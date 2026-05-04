"""Pocket-TTS via the upstream PyTorch path WITH int8 dynamic quantization.

This exercises kyutai-labs/pocket-tts PR #147 (merged into main 2026-03-24),
which adds `TTSModel.load_model(quantize=True)`. The PR uses
`torch.ao.quantization.quantize_dynamic` (or torchao when available) on the
attention + FFN nn.Linear layers in the FlowLM transformer; the Mimi codec
stays FP32 (it's conv-based, dynamic_quantize doesn't target convs).

PR-reported impact: ~48% runtime memory reduction, ~16-27% speedup, WER
delta in noise band. This adapter measures whether those gains hold up
against our 5-sentence corpus.
"""
import time
from pathlib import Path

import numpy as np
import scipy.io.wavfile

from pocket_tts.default_parameters import DEFAULT_AUDIO_PROMPT


def _force_cpu() -> None:
    import torch  # noqa: WPS433

    torch.backends.mps.is_available = lambda: False
    torch.cuda.is_available = lambda: False


DEFAULT_VOICE = f"{DEFAULT_AUDIO_PROMPT}+int8dyn"


def synthesize(text: str, out_wav: str) -> dict:
    out_wav = str(Path(out_wav).resolve())
    _force_cpu()

    from pocket_tts import TTSModel  # noqa: WPS433

    tts = TTSModel.load_model(quantize=True)  # PR #147 toggle
    voice_state = tts.get_state_for_audio_prompt(DEFAULT_AUDIO_PROMPT)

    t0 = time.perf_counter()
    audio = tts.generate_audio(voice_state, text)
    infer_s = time.perf_counter() - t0

    sr = tts.sample_rate
    audio_np = audio.detach().cpu().numpy().astype(np.float32)
    scipy.io.wavfile.write(out_wav, sr, audio_np)

    return {
        "voice_id": DEFAULT_VOICE,
        "audio_seconds": float(audio_np.shape[-1]) / sr,
        # Quantization is internal and does not change the public output
        # surface — still no per-token alignment in `generate_audio`.
        "phoneme_timings": None,
        "infer_seconds": infer_s,
    }
