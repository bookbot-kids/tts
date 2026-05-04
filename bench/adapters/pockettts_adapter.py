"""Pocket-TTS adapter — uses the documented Python API
(pocket_tts.TTSModel.load_model + get_state_for_audio_prompt + generate_audio)
with the default voice 'alba'. Forces CPU device for an apples-to-apples
comparison; pocket-tts is CPU-only by design (README §"Main takeaways"),
but PyTorch may auto-select MPS — patch it off the same way the ZipVoice
adapter does."""
import time
from pathlib import Path

import numpy as np
import scipy.io.wavfile

from pocket_tts.default_parameters import DEFAULT_AUDIO_PROMPT


def _force_cpu() -> None:
    import torch  # noqa: WPS433

    torch.backends.mps.is_available = lambda: False
    torch.cuda.is_available = lambda: False


DEFAULT_VOICE = DEFAULT_AUDIO_PROMPT  # = "alba"


def synthesize(text: str, out_wav: str) -> dict:
    out_wav = str(Path(out_wav).resolve())
    _force_cpu()

    from pocket_tts import TTSModel  # noqa: WPS433

    tts = TTSModel.load_model()
    voice_state = tts.get_state_for_audio_prompt(DEFAULT_VOICE)

    t0 = time.perf_counter()
    audio = tts.generate_audio(voice_state, text)
    infer_s = time.perf_counter() - t0

    sr = tts.sample_rate
    audio_np = audio.detach().cpu().numpy().astype(np.float32)
    scipy.io.wavfile.write(out_wav, sr, audio_np)

    return {
        "voice_id": DEFAULT_VOICE,
        "audio_seconds": float(audio_np.shape[-1]) / sr,
        # Phoneme timings: NOT exposed. Pocket-TTS uses SentencePiece subwords
        # and generate_audio returns only a 1D audio tensor.
        "phoneme_timings": None,
        "infer_seconds": infer_s,
    }
