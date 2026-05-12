"""
Streaming, phoneme-level timing for Kyutai Pocket TTS.

Builds on pocket_tts_word_timing.py. Yields tagged events as audio is
generated:

    ('audio',   torch.Tensor)            -- a chunk of PCM audio (24 kHz)
    ('phoneme', PhonemeTiming)           -- emitted when a phoneme begins

Design
------
Pocket TTS's frame rate is 12.5 Hz (one latent / 80 ms). That is the FLOOR on
localisation: we cannot say more about *when* a phoneme is happening than the
frame the model was on while emitting it. Inside a single SentencePiece token
the model gives us no further signal -- a token like "▁Hello" produces a
plateau of attention with no phoneme-internal structure. Phoneme timing
therefore has two parts:

  1. Word-level frame range, from attention monotonic-argmax (same as the
     batch version, but updated incrementally as frames arrive).
  2. Within a word, redistribute its phoneme list across the word's frames
     proportionally, with a minimum of 1 frame (80 ms) per phoneme.

When num_phonemes > num_frames_in_word the proportional layout produces
overlapping events -- consecutive phonemes share frames -- so that every
phoneme still has the requested 80 ms minimum span.

A phoneme's timestamps are absolute (seconds from the start of the
generated audio) so the UI can sync against the audio playhead. Phoneme
events for word *w* are emitted as soon as alignment moves to word *w+1*
(i.e. one-word lookahead). For typical 200-500 ms words at faster-than-
real-time generation, the events arrive comfortably ahead of their audio.

G2P
---
Pluggable. Pass a callable ``g2p(words: list[str]) -> list[list[str]]`` that
returns one phoneme list per word, in order. Recommended: ``phonemizer`` with
the espeak-ng backend (covers English, Spanish, Indonesian, isiZulu,
isiXhosa, etc. -- relevant for Bookbot's deployment languages).

    from phonemizer import phonemize
    def g2p(words):
        return [phonemize(w, language="en-us", backend="espeak", strip=True).split()
                for w in words]

For ARPAbet English-only quick tests, ``g2p_en`` works:

    import g2p_en
    _g = g2p_en.G2p()
    def g2p(words):
        # filter out spaces / stress digits as needed
        return [[p for p in _g(w) if p.strip()] for w in words]
"""

from __future__ import annotations

import math
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Callable, Iterator

import torch
import torch.nn.functional as F

from pocket_tts import TTSModel
from pocket_tts.modules.transformer import (
    StreamingMultiheadAttention,
    _build_attention_mask,
)

# Reuse the layout helper from the batch version. Keeping it here as a copy
# so this file is self-contained; if you have both files, delete this and
# import from pocket_tts_word_timing.
_SP_SPACE = "\u2581"


@dataclass
class TextLayout:
    tokens: list[str]
    token_to_word: list[int]
    words: list[str]


def layout_text(model: TTSModel, text: str) -> TextLayout:
    sp = model.flow_lm.conditioner.tokenizer.sp
    pieces: list[str] = sp.encode(text, out_type=str)
    token_to_word: list[int] = []
    words: list[str] = []
    cur = -1
    for p in pieces:
        starts_word = p.startswith(_SP_SPACE)
        body = p.lstrip(_SP_SPACE)
        if starts_word and any(c.isalnum() for c in body):
            cur += 1
            words.append(body)
            token_to_word.append(cur)
        elif starts_word:
            token_to_word.append(-1)
        else:
            if any(c.isalnum() for c in body) and cur >= 0:
                words[cur] += body
            token_to_word.append(cur)
    return TextLayout(tokens=pieces, token_to_word=token_to_word, words=words)


# --- Recorder --------------------------------------------------------------

class _Recorder:
    """One-producer / one-consumer attention buffer.

    Producer: pocket-tts generation thread (calls into the patched attn forward).
    Consumer: the generator returned by generate_stream_with_phoneme_timings,
              running in the caller's thread.

    Cross-thread sharing is via list append + index read. CPython's GIL makes
    these safe for our single-producer/single-consumer pattern; len() is the
    only synchronisation we need (we read frames at indices < len_seen).
    """
    def __init__(self) -> None:
        self.enabled = False
        self.target_layer: StreamingMultiheadAttention | None = None
        self.text_start = 0
        self.text_end = 0
        self.frames: list[torch.Tensor] = []

    def reset(self, target_layer, text_start: int, text_end: int) -> None:
        self.target_layer = target_layer
        self.text_start = text_start
        self.text_end = text_end
        self.frames = []

    @contextmanager
    def recording(self):
        self.enabled = True
        try:
            yield
        finally:
            self.enabled = False


_recorder = _Recorder()
_orig_forward = StreamingMultiheadAttention.forward


def _patched_forward(self, query: torch.Tensor, model_state):
    if not _recorder.enabled or self is not _recorder.target_layer:
        return _orig_forward(self, query, model_state)

    state = None if model_state is None else self.get_state(model_state)
    projected = self.in_proj(query)
    b, t, _ = projected.shape
    d = self.dim_per_head
    packed = projected.view(b, t, 3, self.num_heads, d)
    q, k, v = torch.unbind(packed, dim=2)
    rope_offset = self._cache_backend.rope_offset(state, b, q.device)
    q, k = self.rope(q, k, offset=rope_offset)
    q = q.transpose(1, 2)

    k_attn, v_attn, pos_k, offset = self._cache_backend.append_and_get(k, v, state)
    pos_q = offset.view(-1, 1) + torch.arange(t, device=q.device, dtype=torch.long).view(1, -1)
    attn_mask = _build_attention_mask(pos_q, pos_k, self.context)

    scale = 1.0 / math.sqrt(d)
    scores = torch.matmul(q, k_attn.transpose(-2, -1)) * scale
    scores = scores.masked_fill(~attn_mask, float("-inf"))
    weights = F.softmax(scores, dim=-1)

    if t == 1:
        ts, te = _recorder.text_start, _recorder.text_end
        if te > ts and te <= weights.shape[-1]:
            row = weights[0, :, 0, ts:te].mean(dim=0).detach().cpu()
            _recorder.frames.append(row)

    out = torch.matmul(weights, v_attn).transpose(1, 2)
    bb, tt, hh, dd = out.shape
    return self.out_proj(out.reshape(bb, tt, hh * dd))


StreamingMultiheadAttention.forward = _patched_forward


# --- Phoneme distribution -------------------------------------------------

@dataclass
class PhonemeTiming:
    phoneme: str
    word: str
    word_index: int
    start_s: float
    end_s: float


def _distribute_phonemes(
    phonemes: list[str],
    word: str,
    word_idx: int,
    start_frame: int,
    end_frame: int,         # exclusive
    frame_dur: float = 0.080,
) -> list[PhonemeTiming]:
    """Lay out phonemes across [start_frame, end_frame) with min 1 frame each.

    If len(phonemes) > (end_frame - start_frame), consecutive phonemes overlap
    so that each still spans >= 1 frame (== 80 ms). If len(phonemes) == 0,
    returns an empty list (e.g. punctuation-only "words" never reach here
    because we filter them out upstream).
    """
    K = len(phonemes)
    if K == 0:
        return []
    n_frames = max(1, end_frame - start_frame)
    out: list[PhonemeTiming] = []
    for i, p in enumerate(phonemes):
        s_f = start_frame + round(i * n_frames / K)
        e_f = start_frame + round((i + 1) * n_frames / K)
        if e_f <= s_f:                      # enforce 80 ms minimum
            e_f = s_f + 1
        out.append(PhonemeTiming(
            phoneme=p,
            word=word,
            word_index=word_idx,
            start_s=s_f * frame_dur,
            end_s=e_f * frame_dur,
        ))
    return out


# --- Streaming generator --------------------------------------------------

G2pFn = Callable[[list[str]], list[list[str]]]


def generate_stream_with_phoneme_timings(
    model: TTSModel,
    voice_state: dict,
    text: str,
    g2p: G2pFn,
    *,
    layer_index: int = 3,
    frame_dur: float = 0.080,
) -> Iterator[tuple[str, object]]:
    """Real-time generator yielding ('audio', tensor) and ('phoneme', PhonemeTiming).

    Phoneme events are emitted with one-word lookahead: as soon as alignment
    moves to word w+1, we know the frame range of word w and emit all of its
    phoneme events at once (each with absolute timestamps). Audio chunks are
    yielded as they become available from pocket-tts's internal mimi decoder.

    Order of yields between audio and phoneme events is roughly causal but
    depends on the relative pace of pocket-tts's generation vs decoder
    threads. The UI should treat phoneme timestamps as absolute and not
    assume any audio chunk and phoneme event yielded together correspond
    to the same wall-clock moment.
    """
    layout = layout_text(model, text)
    if not layout.words:
        # Nothing alignable; just stream audio.
        for chunk in model.generate_audio_stream(voice_state, text):
            yield ("audio", chunk)
        return

    word_phonemes = g2p(layout.words)
    assert len(word_phonemes) == len(layout.words), (
        f"g2p returned {len(word_phonemes)} phoneme lists for {len(layout.words)} words"
    )

    target_layer = model.flow_lm.transformer.layers[layer_index].self_attn
    layer_state = target_layer.get_state(voice_state)
    voice_end = int(layer_state["offset"].view(-1)[0].item())
    text_start = voice_end
    text_end = voice_end + len(layout.tokens)

    _recorder.reset(target_layer=target_layer, text_start=text_start, text_end=text_end)

    # Streaming alignment state
    consumed = 0                 # frames already processed in this generator
    cur_word = -1                # word index currently being attended to
    cur_word_first_frame = -1    # frame index where cur_word began
    cur_token = 0                # monotonic argmax pointer (in token space)
    emitted: set[int] = set()

    def _drain_frames(upto: int) -> list[PhonemeTiming]:
        """Process recorder.frames[consumed:upto], return phoneme events to emit."""
        nonlocal consumed, cur_word, cur_word_first_frame, cur_token
        events: list[PhonemeTiming] = []
        for f in range(consumed, upto):
            attn = _recorder.frames[f]
            # Monotonic argmax: peak can only stay or move right.
            local = int(torch.argmax(attn[cur_token:]).item()) + cur_token
            cur_token = local
            tok_word = layout.token_to_word[cur_token]
            if tok_word < 0:
                continue                     # punctuation / non-word token
            if tok_word != cur_word:
                # We've left the previous word; emit its phonemes.
                if cur_word >= 0 and cur_word not in emitted:
                    events.extend(_distribute_phonemes(
                        phonemes=word_phonemes[cur_word],
                        word=layout.words[cur_word],
                        word_idx=cur_word,
                        start_frame=cur_word_first_frame,
                        end_frame=f,
                        frame_dur=frame_dur,
                    ))
                    emitted.add(cur_word)
                cur_word = tok_word
                cur_word_first_frame = f
        consumed = upto
        return events

    with _recorder.recording():
        for chunk in model.generate_audio_stream(voice_state, text):
            # Snapshot how many frames are visible RIGHT NOW.
            available = len(_recorder.frames)
            for ev in _drain_frames(available):
                yield ("phoneme", ev)
            yield ("audio", chunk)

    # Final flush: drain any frames the recorder captured after the last chunk,
    # then emit phonemes for the final word.
    available = len(_recorder.frames)
    for ev in _drain_frames(available):
        yield ("phoneme", ev)
    if cur_word >= 0 and cur_word not in emitted:
        for ev in _distribute_phonemes(
            phonemes=word_phonemes[cur_word],
            word=layout.words[cur_word],
            word_idx=cur_word,
            start_frame=cur_word_first_frame,
            end_frame=len(_recorder.frames),
            frame_dur=frame_dur,
        ):
            yield ("phoneme", ev)


# --- Demo -----------------------------------------------------------------

if __name__ == "__main__":
    # Example with phonemizer / espeak-ng. Install with:
    #   pip install phonemizer
    #   apt-get install espeak-ng     (or brew install espeak-ng on mac)
    from phonemizer import phonemize  # type: ignore

    def g2p(words: list[str]) -> list[list[str]]:
        # phonemize per-word so we keep alignment with our word list.
        out = []
        for w in words:
            ph = phonemize(w, language="en-us", backend="espeak",
                           strip=True, with_stress=False)
            # phonemizer returns IPA as a single space-separated string per word
            out.append(ph.split())
        return out

    model = TTSModel.load_model()
    voice_state = model.get_state_for_audio_prompt("alba")

    audio_chunks: list[torch.Tensor] = []
    for kind, payload in generate_stream_with_phoneme_timings(
        model, voice_state,
        "Hello world, this is a test of Pocket TTS phoneme timing.",
        g2p=g2p,
        layer_index=3,
    ):
        if kind == "audio":
            audio_chunks.append(payload)               # type: ignore[arg-type]
        else:  # phoneme
            ev: PhonemeTiming = payload                # type: ignore[assignment]
            print(f"{ev.start_s:6.2f}s -> {ev.end_s:6.2f}s  "
                  f"/{ev.phoneme}/  in {ev.word!r}")

    import scipy.io.wavfile
    full = torch.cat(audio_chunks, dim=0)
    scipy.io.wavfile.write("out.wav", model.sample_rate, full.numpy())
