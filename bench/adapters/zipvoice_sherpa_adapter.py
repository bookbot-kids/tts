"""ZipVoice via sherpa-onnx (the actual mobile-deployment runtime).

Model: sherpa-onnx-zipvoice-distill-int8-zh-en-emilia + vocos_24khz.onnx
(INT8 quant, ~154 MB + 52 MB vocoder).
Reference: https://k2-fsa.github.io/sherpa/onnx/tts/zipvoice.html

The reference prompt reuses bench/voices/zipvoice_default.wav so the
sherpa-onnx ZipVoice clones the same target voice as the PyTorch ZipVoice
run did — keeping the two ZipVoice rows directly comparable.
"""
import time
from pathlib import Path

import librosa
import sherpa_onnx
import soundfile as sf

REPO = Path(__file__).resolve().parents[2]
MODEL_DIR = REPO / "bench" / "sherpa_models" / "sherpa-onnx-zipvoice-distill-int8-zh-en-emilia"
VOCODER_PATH = REPO / "bench" / "sherpa_models" / "vocos_24khz.onnx"
REF_WAV = REPO / "bench" / "voices" / "zipvoice_default.wav"
REF_TXT = REPO / "bench" / "voices" / "zipvoice_default.txt"
DEFAULT_VOICE = "zipvoice/sherpa-int8-distill@bookbot_s15_prompt"


def _build_tts() -> sherpa_onnx.OfflineTts:
    cfg = sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            zipvoice=sherpa_onnx.OfflineTtsZipvoiceModelConfig(
                tokens=str(MODEL_DIR / "tokens.txt"),
                encoder=str(MODEL_DIR / "encoder.int8.onnx"),
                decoder=str(MODEL_DIR / "decoder.int8.onnx"),
                data_dir=str(MODEL_DIR / "espeak-ng-data"),
                lexicon=str(MODEL_DIR / "lexicon.txt"),
                vocoder=str(VOCODER_PATH),
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
    ref_audio, ref_sr = librosa.load(str(REF_WAV), sr=None)
    ref_text = REF_TXT.read_text().strip()

    gen = sherpa_onnx.GenerationConfig()
    gen.reference_audio = ref_audio
    gen.reference_sample_rate = ref_sr
    gen.reference_text = ref_text
    gen.num_steps = 4  # matches the PyTorch ZipVoice bench config (distill, 4 steps)
    gen.extra["min_char_in_sentence"] = "30"

    t0 = time.perf_counter()
    audio = tts.generate(text, gen)
    infer_s = time.perf_counter() - t0

    if len(audio.samples) == 0:
        raise RuntimeError("sherpa-onnx returned empty audio")

    sf.write(str(Path(out_wav).resolve()), audio.samples, audio.sample_rate, subtype="PCM_16")

    return {
        "voice_id": DEFAULT_VOICE,
        "audio_seconds": float(len(audio.samples)) / audio.sample_rate,
        "phoneme_timings": None,
        "infer_seconds": infer_s,
    }
