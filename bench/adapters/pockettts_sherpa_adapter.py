"""Pocket-TTS via sherpa-onnx (the actual mobile-deployment runtime).

Model: sherpa-onnx-pocket-tts-int8-2026-01-26 (INT8 quant, ~213 MB on disk).
Reference: https://k2-fsa.github.io/sherpa/onnx/tts/pocket.html
"""
import time
from pathlib import Path

import librosa
import sherpa_onnx
import soundfile as sf

REPO = Path(__file__).resolve().parents[2]
MODEL_DIR = REPO / "bench" / "sherpa_models" / "sherpa-onnx-pocket-tts-int8-2026-01-26"
REF_WAV = MODEL_DIR / "test_wavs" / "bria.wav"  # bundled English reference
DEFAULT_VOICE = "pocket-tts/sherpa-int8/bria"


def _build_tts() -> sherpa_onnx.OfflineTts:
    cfg = sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            pocket=sherpa_onnx.OfflineTtsPocketModelConfig(
                lm_flow=str(MODEL_DIR / "lm_flow.int8.onnx"),
                lm_main=str(MODEL_DIR / "lm_main.int8.onnx"),
                encoder=str(MODEL_DIR / "encoder.onnx"),
                decoder=str(MODEL_DIR / "decoder.int8.onnx"),
                text_conditioner=str(MODEL_DIR / "text_conditioner.onnx"),
                vocab_json=str(MODEL_DIR / "vocab.json"),
                token_scores_json=str(MODEL_DIR / "token_scores.json"),
            ),
            debug=False,
            num_threads=2,
            provider="cpu",
        )
    )
    if not cfg.validate():
        raise RuntimeError("OfflineTts config validation failed")
    return sherpa_onnx.OfflineTts(cfg)


def synthesize(text: str, out_wav: str) -> dict:
    tts = _build_tts()
    ref_audio, ref_sr = librosa.load(str(REF_WAV), sr=tts.sample_rate)

    gen = sherpa_onnx.GenerationConfig()
    gen.reference_audio = ref_audio
    gen.reference_sample_rate = ref_sr
    gen.num_steps = 5  # matches the upstream Python example default

    t0 = time.perf_counter()
    audio = tts.generate(text, gen)
    infer_s = time.perf_counter() - t0

    if len(audio.samples) == 0:
        raise RuntimeError("sherpa-onnx returned empty audio")

    sf.write(str(Path(out_wav).resolve()), audio.samples, audio.sample_rate, subtype="PCM_16")

    return {
        "voice_id": DEFAULT_VOICE,
        "audio_seconds": float(len(audio.samples)) / audio.sample_rate,
        "phoneme_timings": None,  # sherpa-onnx OfflineTts surfaces no token alignment
        "infer_seconds": infer_s,
    }
