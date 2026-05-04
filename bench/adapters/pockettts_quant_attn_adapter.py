"""Pocket-TTS via PyTorch with int8 dynamic quantization on the ATTENTION
projections only (skipping FFN).

The default `quantize=True` quantizes both attention + FFN linears (the
RECOMMENDED_CONFIG = {"attention", "ffn"}). The PR notes that on ARM with
the torch.ao backend, FFN-containing configs hit a per-op dequant penalty
in QNNPACK at batch size 1. This adapter bypasses the public `quantize=True`
flag and calls the lower-level `apply_dynamic_int8(...)` with attention-only
to test whether dropping FFN quantization recovers the speed gap.
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


DEFAULT_VOICE = f"{DEFAULT_AUDIO_PROMPT}+int8dyn-attn"


def synthesize(text: str, out_wav: str) -> dict:
    out_wav = str(Path(out_wav).resolve())
    _force_cpu()

    from pocket_tts import TTSModel  # noqa: WPS433
    from pocket_tts.quantization import apply_dynamic_int8  # noqa: WPS433

    tts = TTSModel.load_model()  # FP32 load
    apply_dynamic_int8(tts.flow_lm, {"attention"})  # quantize attention only

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
        "phoneme_timings": None,
        "infer_seconds": infer_s,
    }
