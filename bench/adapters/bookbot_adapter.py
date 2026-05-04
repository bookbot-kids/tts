"""Bookbot TTS adapter: loads convnext-tts-en.onnx via onnxruntime.

Mirrors the production Dart pipeline (lib/tts.dart, example/lib/tts_controller.dart):
- Text -> IPA via espeak (phonemizer). The production app uses a word DB
  for known words and only falls back to a phonemizer for unknowns; using
  espeak everywhere here is a fidelity caveat documented in the bench README.
- IPA tokenized greedily (3-char -> 2-char -> 1-char) against the mapping
  set, splitting on '.' first — exact port of Tts.breakIPA.
- Each IPA may map to MULTIPLE input IDs and visemes (space-separated in
  the CSV); we flatten the same way Tts.search does.
- EOS token is appended (Parameters.enEos = 2), matching useEos=true default.
- Speaker = us = 2, speed = 0.82 (English defaults from tts_controller.dart).
"""
import csv
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
import soundfile as sf

REPO = Path(__file__).resolve().parents[2]
MODEL_PATH = REPO / "example" / "android" / "app" / "src" / "main" / "assets" / "convnext-tts-en.onnx"
MAPPING_CSV = REPO / "example" / "assets" / "tts" / "en_tts_mapping.csv"

SAMPLE_RATE = 44100
HOP_SIZE = 512
SPEAKER_ID = 2          # Speaker.us in lib/request_info.dart
LANGUAGE_ID = 0         # the shipped convnext-tts-en.onnx requires `lids`
SPEED = 0.82            # Language.en.defaultSpeed in example/lib/tts_controller.dart
EOS_ID = 2              # Parameters.enEos
DOT_ID = 12             # Parameters.specialInputIds['en']['.']
SPACE_ID = 3            # Parameters.specialInputIds['en'][' ']
DEFAULT_VOICE = "convnext-tts-en/us"


def _load_mapping():
    """Returns (mapping, all_ipas).

    mapping: dict[str ipa] -> dict{'input_ids': list[int], 'visemes': list[str]}
    all_ipas: set[str] of every known IPA (used for greedy tokenization).
    """
    mapping: dict[str, dict] = {}
    with MAPPING_CSV.open(encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        next(reader)  # header: IPA, Arpabet, Input ids, visemes, Notes
        for row in reader:
            if len(row) < 4:
                continue
            ipa, _arpa, ids_str, vis_str = row[0], row[1], row[2], row[3]
            if not ipa:
                continue
            ids = [int(s) for s in ids_str.split() if s.strip()]
            vis = [v for v in vis_str.split() if v.strip()]
            mapping[ipa] = {"input_ids": ids, "visemes": vis}
    return mapping, set(mapping.keys())


def _text_to_ipa(text: str) -> str:
    """Convert English text to IPA via espeak.

    The production plugin uses a word lookup DB first; this is a fidelity
    caveat (different input IDs may result), but the count of phonemes —
    which dominates RTF — is in the same ballpark.
    """
    from phonemizer import phonemize
    return phonemize(text, language="en-us", backend="espeak", strip=True)


def _break_ipa(ipas: str, all_ipas: set[str]) -> list[str]:
    """Exact port of Tts.breakIPA (lib/tts.dart): split on '.', then within
    each segment, greedy 3-char then 2-char then 1-char match against the
    known IPA set."""
    result: list[str] = []
    for segment in ipas.split("."):
        chars = list(segment)
        n = len(chars)
        i = 0
        while i < n:
            if i < n - 2:
                trio = chars[i] + chars[i + 1] + chars[i + 2]
                if trio in all_ipas:
                    result.append(trio)
                    i += 3
                    continue
            if i < n - 1:
                pair = chars[i] + chars[i + 1]
                if pair in all_ipas:
                    result.append(pair)
                    i += 2
                    continue
            result.append(chars[i])
            i += 1
    return result


def _search(tokens: list[str], mapping: dict) -> tuple[list[int], list[str]]:
    """Port of Tts.search: flatten each IPA's input_ids and visemes."""
    input_ids: list[int] = []
    visemes: list[str] = []
    for tok in tokens:
        entry = mapping.get(tok)
        if entry is None:
            continue
        input_ids.extend(entry["input_ids"])
        visemes.extend(entry["visemes"])
    return input_ids, visemes


def synthesize(text: str, out_wav: str) -> dict:
    mapping, all_ipas = _load_mapping()
    ipa = _text_to_ipa(text)
    tokens = _break_ipa(ipa, all_ipas)
    input_ids, visemes = _search(tokens, mapping)
    # Append EOS, matching useEos=true default in lib/tts.dart speakText.
    input_ids.append(EOS_ID)

    if not input_ids:
        raise RuntimeError(f"empty input_ids for text={text!r} ipa={ipa!r}")

    x = np.array([input_ids], dtype=np.int64)
    x_lengths = np.array([x.shape[1]], dtype=np.int64)
    scales = np.array([SPEED, 1.0, 1.0], dtype=np.float32)
    sids = np.array([SPEAKER_ID], dtype=np.int64)
    lids = np.array([LANGUAGE_ID], dtype=np.int64)

    sess = ort.InferenceSession(str(MODEL_PATH), providers=["CPUExecutionProvider"])
    inputs = {
        "x": x,
        "x_lengths": x_lengths,
        "scales": scales,
        "sids": sids,
        "lids": lids,
    }
    t0 = time.perf_counter()
    wav, durations = sess.run(["wav", "durations"], inputs)
    infer_s = time.perf_counter() - t0

    audio = wav.squeeze().astype(np.float32)
    sf.write(out_wav, audio, SAMPLE_RATE)

    sec_per_frame = HOP_SIZE / SAMPLE_RATE
    timings: list[dict] = []
    t = 0.0
    durations_list = durations.squeeze().tolist()
    if isinstance(durations_list, (int, float)):
        durations_list = [durations_list]
    for i, d in enumerate(durations_list):
        token = visemes[i] if i < len(visemes) else "_"
        dur_s = float(d) * sec_per_frame
        timings.append({"token": token, "start": t, "duration": dur_s})
        t += dur_s

    return {
        "voice_id": DEFAULT_VOICE,
        "audio_seconds": float(len(audio)) / SAMPLE_RATE,
        "phoneme_timings": timings,
        "infer_seconds": infer_s,
    }
