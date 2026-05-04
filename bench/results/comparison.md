# TTS Comparison: Bookbot vs. ZipVoice vs. Pocket-TTS

**Date:** 2026-05-04
**Hardware:** macOS Darwin 25.4.0, Apple M1 Pro, 32 GB RAM
**Test corpus:** 5 English sentences (12–520 chars), 2–3 repeats each
**All engines run on CPU.** ZipVoice/Pocket-TTS auto-pick MPS by default;
this bench patches `torch.backends.mps.is_available` off so the comparison
is apples-to-apples with the CPU-only Bookbot ONNX path.

## Headline table

| Engine | Default voice | Phoneme timing | Median RTF | p95 RTF | Median peak RSS | Max peak RSS |
|---|---|---|---:|---:|---:|---:|
| **Bookbot TTS** | `convnext-tts-en/us` | **YES** (per-phoneme, native) | **0.35** | 2.63 | **280 MB** | 321 MB |
| Pocket-TTS | `alba` | NO (subword tokenizer; no alignment) | 0.91 | 3.31 | 881 MB | 934 MB |
| ZipVoice-Distill (4-step) | demo prompt clone | NO (aggregate-length only) | 2.27 | 14.80 | 1294 MB | 2518 MB |

`RTF = wall_seconds / audio_seconds`. Lower is faster. RTF < 1 is faster than real-time.

p95 RTF is dominated by the cold-start of the shortest utterance (`s05` = "Hello world"). Each measurement runs in a fresh subprocess, so p95 reflects "first utterance after launch", not steady-state.

See [rtf_vs_length.png](rtf_vs_length.png) and [rss_vs_length.png](rss_vs_length.png) for the per-engine curves.

## RTF by sentence length (medians)

| Sentence id | chars | Bookbot | Pocket-TTS | ZipVoice |
|---|---:|---:|---:|---:|
| s05 | 12 | 2.39 | 3.26 | 14.75 |
| s15 | 44 | 0.60 | 1.44 | 3.84 |
| s30 | 100 | 0.37 | 0.91 | 2.27 |
| s60 | 220 | 0.17 | 0.58 | 1.08 |
| s120 | 520 | 0.076 | 0.36 | 1.17 |

At long-sentence steady state (s120):
- **Bookbot ≈ 13× real-time**
- Pocket-TTS ≈ 2.7× real-time
- ZipVoice ≈ 0.85× real-time (i.e. *slower* than playback)

## Phoneme timing support

- **Bookbot: native, per-phoneme.** The ONNX model returns a `durations` int64 tensor (frames per phoneme). [lib/tts.dart](../../lib/tts.dart) converts it to per-token seconds at `hop=512, sr=44100`. This is what drives the viseme/lip-sync output the rest of the app relies on.
- **ZipVoice: no.** The flow-matching model only predicts an aggregate feature length: `features_len = ceil(prompt_features_len / prompt_tokens_len * tokens_len / speed)` ([zipvoice/models/zipvoice.py:323-325](../../../python/opensource/ZipVoice/zipvoice/models/zipvoice.py)). The "per-token duration" used in `onnx_export.py:139` is `floor(features_len / tokens_len)` — uniform, not a learned alignment. To recover per-phoneme timestamps you would have to run a forced aligner (Montreal Forced Aligner, `whisper-timestamped`, etc.) on the synthesized audio. This is a post-hoc workaround, not a native capability.
- **Pocket-TTS: no.** Tokenizer is SentencePiece subword ([pocket_tts/conditioners/text.py](../../../python/opensource/pocket-tts/pocket_tts/conditioners/text.py)), not phonemes. The public API ([pocket_tts/models/tts_model.py:477](../../../python/opensource/pocket-tts/pocket_tts/models/tts_model.py)) returns audio only — `generate_audio` and `generate_audio_stream` yield audio tensors, no token alignment. Same forced-aligner workaround applies.

This is the single most important axis for Bookbot's current product: visemes/lip-sync depend on per-phoneme timing. Either competitor would need a forced-aligner stage *and* a re-mapping from word-level timestamps back to IPA phonemes.

## Memory

Cold-start measurement (one fresh subprocess per call) so peak RSS reflects model load + one synthesis:

- **Bookbot ~280 MB** — onnxruntime + a 71 MB single ONNX model.
- **Pocket-TTS ~881 MB** — PyTorch + 100 M-param flow-LM + Mimi codec.
- **ZipVoice ~1.3 GB median, peaking 2.5 GB on the longest sentence** — PyTorch + 123 M-param model + Vocos vocoder, plus the iterative flow-matching activations growing with sequence length.

Bookbot is roughly **3×** lighter than Pocket-TTS and **5–9×** lighter than ZipVoice in resident memory.

## Real-time factor

Beyond the cold-start range (sentences ≥ s30, ≥ 100 chars):
- Bookbot is **2–13× faster than real-time** depending on length.
- Pocket-TTS is **0.9–2.7× faster than real-time** — broadly matches the "~6× real-time on M4" claim in the upstream README; we measured 2.7× on M1 Pro.
- ZipVoice-Distill at 4 steps is **~real-time** on long content and slower on short. Going to `--num-step 8` (the upstream default) would roughly double these numbers.

## Caveats

- **Bookbot path is stripped of Flutter overhead.** The comparison runs the same ONNX file via Python `onnxruntime`, so it does not include the platform-channel + AudioTrack/AVAudioEngine cost the real plugin pays. This makes the inference numbers fair vs. the other Python engines but slightly understates Bookbot's end-to-end latency on a real device.
- **Bookbot text-to-IPA uses espeak.** The production app uses a bundled word DB first, falling back to a phonemizer for unknowns. Espeak everywhere here may produce a slightly different phoneme count, but length and RTF land in the same ballpark.
- **ZipVoice is zero-shot voice cloning, not a fixed voice.** The "default" used here is `bench/voices/zipvoice_default.wav`, which is the Bookbot s15 output — so ZipVoice clones the same target voice as Bookbot. ZipVoice upstream commit pinned at `2f7326f`, model `zipvoice_distill@HF main`.
- **ZipVoice was run with distill + 4 steps** (README §3.2 documents this as the speed-priority configuration, fairer vs. Bookbot's single-pass model). The full `zipvoice` model with default 16 steps would be ~2× slower than these numbers.
- **Pocket-TTS used the default English model and voice `alba`.** Upstream commit pinned at `de010ea`.
- **All on CPU.** GPU/MPS would help ZipVoice and Pocket-TTS some; Bookbot is CPU-only by design.
- **Cold start dominates short sentences.** Each measurement loads the model fresh. That reflects "first utterance after launch", not warm steady-state. A warm-RTF rerun with persistent processes is a sensible follow-up but was out of scope here.
- **Quality (MOS / naturalness) was not measured.** The comparison is performance + capability only.

## Recommendation

If the product still needs **per-phoneme timing for visemes/lip-sync**, **mobile-friendly memory**, and **single-pass low-latency inference**, Bookbot is the clear keeper. Both competitors lose on all three quantitative axes by 2–9× and on the timing axis lose qualitatively (no native alignment).

Where the others would *win*:
- **Voice quality and zero-shot cloning** — ZipVoice's main proposition. If the product wanted to add user-cloned voices, no engine in this comparison can replace it short-term.
- **Multilingual coverage with one model** — Pocket-TTS supports EN/FR/DE/PT/IT/ES out of the box; Bookbot needs a separate ~71 MB model per language.
- **Streaming-first applications** — Pocket-TTS yields audio chunks at ~80 ms granularity; Bookbot returns the whole utterance.

For the current Bookbot product (kid-facing reading app with lip-sync), neither competitor is a drop-in. Tasks 5 and 6 explore the deeper "could we even put one of these on Android/iOS instead of the current ONNX model?" question; the short answer is "not without rewriting the native runtime layer."
