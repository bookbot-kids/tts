"""ZipVoice adapter — invokes the upstream `zipvoice.bin.infer_zipvoice` main()
in-process, with torch's MPS/CUDA backends patched off so all engines compare
on CPU. Uses ZipVoice-Distill at num-step=4 (README §3.2 documents this as the
speed-priority configuration; fair vs. Bookbot's single-pass model)."""
import os
import sys
import time
from pathlib import Path

import soundfile as sf

REPO = Path(__file__).resolve().parents[2]
ZV_DIR = Path("/Users/ductran/Documents/codes/python/opensource/ZipVoice")
PROMPT_WAV = REPO / "bench" / "voices" / "zipvoice_default.wav"
PROMPT_TXT = REPO / "bench" / "voices" / "zipvoice_default.txt"
DEFAULT_VOICE = "zipvoice_distill@bookbot_s15_prompt"


def _force_cpu() -> None:
    """Make torch's auto-device picker choose CPU.

    The upstream script auto-selects MPS on Apple Silicon. For an apples-to-
    apples comparison with the CPU-only Bookbot ONNX path, neutralize the
    MPS / CUDA pickers before main() runs.
    """
    import torch  # noqa: WPS433

    torch.backends.mps.is_available = lambda: False
    torch.cuda.is_available = lambda: False


def synthesize(text: str, out_wav: str) -> dict:
    # Make zipvoice importable. Do NOT chdir into ZV_DIR — the harness passes
    # repo-relative output paths and chdir would break them.
    sys.path.insert(0, str(ZV_DIR))
    out_wav = str(Path(out_wav).resolve())
    _force_cpu()

    from zipvoice.bin.infer_zipvoice import main as zv_main  # noqa: WPS433

    sys.argv = [
        "infer_zipvoice",
        "--model-name", "zipvoice_distill",
        "--num-step", "4",
        "--num-thread", "2",
        "--prompt-wav", str(PROMPT_WAV),
        "--prompt-text", PROMPT_TXT.read_text().strip(),
        "--text", text,
        "--res-wav-path", out_wav,
    ]
    t0 = time.perf_counter()
    zv_main()
    infer_s = time.perf_counter() - t0

    audio, sr = sf.read(out_wav)
    return {
        "voice_id": DEFAULT_VOICE,
        "audio_seconds": float(len(audio)) / sr,
        # Phoneme timings: NOT exposed. ZipVoice predicts only an aggregate
        # features_len ratio; per-phoneme alignment requires a forced aligner.
        "phoneme_timings": None,
        "infer_seconds": infer_s,
    }
