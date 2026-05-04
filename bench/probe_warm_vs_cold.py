"""Diagnostic: how much of the on-device peak RSS is cold-start spike
vs. steady-state working set? Run all 5 sentences against ONE persistent
sherpa-onnx instance, sample peak RSS after each call.

Run from repo root:  python -m bench.probe_warm_vs_cold
"""
import json
import time
from pathlib import Path

import numpy as np
import onnxruntime  # noqa: F401  (loaded by sherpa under the hood)
import psutil
import sherpa_onnx
import soundfile as sf

REPO = Path(__file__).resolve().parents[1]
BENCH = REPO / "bench"

POCKET = BENCH / "sherpa_models" / "sherpa-onnx-pocket-tts-int8-2026-01-26"
ZIPVOICE = BENCH / "sherpa_models" / "sherpa-onnx-zipvoice-distill-int8-zh-en-emilia"
VOCODER = BENCH / "sherpa_models" / "vocos_24khz.onnx"
ZV_PROMPT = BENCH / "voices" / "zipvoice_default.wav"
ZV_PROMPT_TXT = BENCH / "voices" / "zipvoice_default.txt"


def rss_mb() -> float:
    return psutil.Process().memory_info().rss / (1024 * 1024)


def hwm_mb() -> float:
    """Process peak RSS since start (VmHWM on Linux/Android, equivalent on Mac)."""
    try:
        for line in Path("/proc/self/status").read_text().splitlines():
            if line.startswith("VmHWM:"):
                return float(line.split()[1]) / 1024
    except Exception:
        pass
    # macOS fallback: psutil rusage maxrss is in bytes on Linux but kB on macOS,
    # and ru_maxrss reflects peak. Just use rss_mb as a floor.
    return rss_mb()


def probe_pocket(corpus):
    cfg = sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            pocket=sherpa_onnx.OfflineTtsPocketModelConfig(
                lm_flow=str(POCKET / "lm_flow.int8.onnx"),
                lm_main=str(POCKET / "lm_main.int8.onnx"),
                encoder=str(POCKET / "encoder.onnx"),
                decoder=str(POCKET / "decoder.int8.onnx"),
                text_conditioner=str(POCKET / "text_conditioner.onnx"),
                vocab_json=str(POCKET / "vocab.json"),
                token_scores_json=str(POCKET / "token_scores.json"),
            ),
            num_threads=2, debug=False, provider="cpu",
        )
    )
    print(f"\nPocket-TTS: building TTS ...  rss before={rss_mb():.0f} MB")
    rss_before_build = rss_mb()
    tts = sherpa_onnx.OfflineTts(cfg)
    rss_after_build = rss_mb()
    print(f"  after build:                     rss={rss_after_build:.0f} MB  (delta {rss_after_build-rss_before_build:.0f} MB)")

    import librosa
    ref, sr = librosa.load(str(POCKET / "test_wavs" / "bria.wav"), sr=tts.sample_rate)
    print(f"  ref audio: {len(ref)/sr:.2f}s, sr={sr}")

    rows = []
    for s in corpus:
        gen = sherpa_onnx.GenerationConfig()
        gen.reference_audio = ref
        gen.reference_sample_rate = sr
        gen.num_steps = 5
        t0 = time.perf_counter()
        audio = tts.generate(s["text"], gen)
        infer = time.perf_counter() - t0
        rss = rss_mb()
        peak = hwm_mb()
        audio_s = len(audio.samples) / audio.sample_rate
        rtf = infer / audio_s
        rows.append({"sid": s["id"], "audio_s": audio_s, "infer_s": infer,
                     "rtf": rtf, "rss_mb": rss, "peak_mb": peak})
        print(f"  {s['id']}: audio={audio_s:.2f}s infer={infer:.3f}s rtf={rtf:.3f}  rss={rss:.0f} peak={peak:.0f}")
    return rows


def probe_zipvoice(corpus):
    cfg = sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            zipvoice=sherpa_onnx.OfflineTtsZipvoiceModelConfig(
                tokens=str(ZIPVOICE / "tokens.txt"),
                encoder=str(ZIPVOICE / "encoder.int8.onnx"),
                decoder=str(ZIPVOICE / "decoder.int8.onnx"),
                data_dir=str(ZIPVOICE / "espeak-ng-data"),
                lexicon=str(ZIPVOICE / "lexicon.txt"),
                vocoder=str(VOCODER),
            ),
            num_threads=2, debug=False, provider="cpu",
        )
    )
    print(f"\nZipVoice: building TTS ...  rss before={rss_mb():.0f} MB")
    rss_before_build = rss_mb()
    tts = sherpa_onnx.OfflineTts(cfg)
    rss_after_build = rss_mb()
    print(f"  after build:                     rss={rss_after_build:.0f} MB  (delta {rss_after_build-rss_before_build:.0f} MB)")

    import librosa
    ref, sr = librosa.load(str(ZV_PROMPT), sr=None)
    ref_text = ZV_PROMPT_TXT.read_text().strip()

    rows = []
    for s in corpus:
        gen = sherpa_onnx.GenerationConfig()
        gen.reference_audio = ref
        gen.reference_sample_rate = sr
        gen.reference_text = ref_text
        gen.num_steps = 4
        gen.extra["min_char_in_sentence"] = "30"
        t0 = time.perf_counter()
        audio = tts.generate(s["text"], gen)
        infer = time.perf_counter() - t0
        rss = rss_mb()
        peak = hwm_mb()
        audio_s = len(audio.samples) / audio.sample_rate
        rtf = infer / audio_s
        rows.append({"sid": s["id"], "audio_s": audio_s, "infer_s": infer,
                     "rtf": rtf, "rss_mb": rss, "peak_mb": peak})
        print(f"  {s['id']}: audio={audio_s:.2f}s infer={infer:.3f}s rtf={rtf:.3f}  rss={rss:.0f} peak={peak:.0f}")
    return rows


def main():
    corpus = json.loads((BENCH / "corpus.json").read_text())["sentences"]
    p = probe_pocket(corpus)
    z = probe_zipvoice(corpus)
    out = {"pocket": p, "zipvoice": z}
    (BENCH / "results" / "warm_probe.json").write_text(json.dumps(out, indent=2))
    print("\nwrote bench/results/warm_probe.json")


if __name__ == "__main__":
    main()
