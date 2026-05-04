# TTS Comparison Evaluation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a head-to-head benchmark of the current Bookbot TTS plugin vs. **ZipVoice** and **Kyutai Pocket-TTS**, covering five evaluation axes: (1) phoneme-timing output, (2) peak memory, (3) real-time factor (RTF), (4) **mobile feasibility** (Android/iOS), and (5) **drop-in model-swap feasibility** into the existing `example/android/app/src/main/assets/` pipeline.

**Architecture:** A self-contained benchmark harness lives under `bench/`. Each engine is exercised through a thin Python adapter that takes a fixed test corpus, returns audio + (when available) timing metadata, and reports peak RSS and wall-clock RTF. We benchmark on macOS CPU for apples-to-apples numbers; mobile-feasibility findings are documented from upstream code/docs (no on-device benchmark in this plan — see Task 5 caveats).

**Pinned upstream sources** (already cloned by the user):
- ZipVoice: `/Users/ductran/Documents/codes/python/opensource/ZipVoice` — k2-fsa/ZipVoice
- Pocket-TTS: `/Users/ductran/Documents/codes/python/opensource/pocket-tts` — kyutai-labs/pocket-tts

**Tech stack:** Python 3.11, `onnxruntime`, `psutil`, `soundfile`, `pandas`, plus each engine's own deps (PyTorch for both; `piper_phonemize` + `lhotse` for ZipVoice).

---

## Ground truth from upstream (read before writing tasks)

These are not assumptions — they were confirmed by reading the cloned repos. Tasks below are written against these facts.

### Bookbot TTS (current)
- Single ONNX forward pass per utterance. Android plumbing in [android/.../module/Opti.kt](../../../android/src/main/kotlin/com/tensorspeech/tensorflowtts/module/Opti.kt) hard-codes the I/O contract:
  - **Inputs:** `x: int64[1,N]`, `x_lengths: int64[1]`, `scales: float32[3]`, optional `sids: int64[1]`, `lids: int64[1]`.
  - **Outputs:** `wav: float32[1,T]`, `durations: int64[N]`.
- Current English model `convnext-tts-en.onnx` is **~71 MB** (see [example/android/app/src/main/assets/](../../../example/android/app/src/main/assets/)).
- Input is **IPA phonemes** mapped via [example/assets/tts/](../../../example/assets/tts/) CSV. Output `durations` is converted to per-phoneme seconds in [lib/tts.dart](../../../lib/tts.dart) using `hop=512, sr=44100`.
- **Phoneme timing: native, per-phoneme.**

### ZipVoice (k2-fsa/ZipVoice)
- 123M params, flow-matching, **zero-shot voice cloning** — every inference call needs a `--prompt-wav` + `--prompt-text`. There is no fixed "stock voice."
- Tokenizer: **phoneme**-based (`piper_phonemize` espeak backend, or Emilia phone tokenizer). Languages: English + Chinese.
- ONNX export ([zipvoice/bin/onnx_export.py](../../../../python/opensource/ZipVoice/zipvoice/bin/onnx_export.py)) emits **three separate ONNX files**: text encoder, FM decoder (run iteratively `--num-step` times, 4–8), and a Vocos vocoder. INT8 quant supported via `--onnx-int8 True`.
- ONNX inference path: [zipvoice/bin/infer_zipvoice_onnx.py](../../../../python/opensource/ZipVoice/zipvoice/bin/infer_zipvoice_onnx.py). CPU multi-thread via `--num-thread`.
- Per-phoneme timing: **NOT exposed.** The model only computes an aggregate `features_len = ceil(prompt_features_len / prompt_tokens_len * tokens_len / speed)` (see [zipvoice/models/zipvoice.py:290-330](../../../../python/opensource/ZipVoice/zipvoice/models/zipvoice.py)). Per-token dur in `onnx_export.py:139` is `floor(features_len/tokens_len)` — a uniform placeholder, not a learned alignment.
- Mobile path documented by upstream: **k2-fsa/sherpa-onnx** for C++/CPU deployment (README §"Production Deployment"). Sherpa-onnx ships Kotlin, Swift, and Dart bindings.

### Pocket-TTS (kyutai-labs/pocket-tts)
- 100M params, CPU-only PyTorch (≥2.5). Sample rate **24 kHz**. Default voice id **`alba`** (see [pocket_tts/__init__.py](../../../../python/opensource/pocket-tts/pocket_tts/__init__.py) — `DEFAULT_AUDIO_PROMPT = "alba"`). 22 named voices listed in the README.
- Architecture: autoregressive **flow-LM + Mimi neural codec** (two models in [pocket_tts/models/](../../../../python/opensource/pocket-tts/pocket_tts/models/)). Generation is iterative — uses `_run_flow_lm_and_increment_step` per token and `_decode_audio_worker` for the codec; emits ~80ms audio chunks.
- Tokenizer: **SentencePiece subword**, NOT phonemes ([pocket_tts/conditioners/text.py](../../../../python/opensource/pocket-tts/pocket_tts/conditioners/text.py)).
- Public API ([pocket_tts/models/tts_model.py:477](../../../../python/opensource/pocket-tts/pocket_tts/models/tts_model.py)): `generate_audio(state, text) -> torch.Tensor`. **No phoneme/word/timestamp output anywhere in the public API.** RTF is logged internally; alignments are not.
- Voices are KV-cache snapshots from a prompt wav. The 22 named voices are bundled prompt wavs on HuggingFace (`hf://kyutai/tts-voices/...`).
- Mobile path: **no first-party Android/iOS code.** Upstream README points to:
  - **sherpa-onnx** (k2-fsa) — official C++/Kotlin/Swift/Dart deployment.
  - **pocket-tts-onnx-export** (KevinAHM) — community ONNX export.
  - **pocket-tts-mlx** — Apple Silicon (macOS only, not iOS).
  - **PocketTTS.cpp** — single-file ONNX Runtime C++ runtime.

### Headline implication for the user's question
> *"Can their TTS model just replace `convnext-tts-en.onnx` in `example/android/app/src/main/assets/` and run on mobile?"*

**No, in either case.** Reasons baked into the upstream code:

| Mismatch axis | Bookbot expects | ZipVoice produces | Pocket-TTS produces |
|---|---|---|---|
| Number of ONNX files | 1 | 3 (text + FM decoder + vocoder) | 0 official; community export = 2 (LM + Mimi) |
| Inference shape | single forward | iterative (4–8 FM steps) | autoregressive token-by-token |
| Input I/O names | `x`, `x_lengths`, `scales`, `sids` | `tokens`, `prompt_tokens`, `prompt_features_len`, `speed` | `text_tokens` + KV-cache state |
| Output I/O names | `wav`, `durations` | latent → vocoder → wav (no `durations`) | streaming codec frames |
| Voice mechanism | speaker id `sids` | requires prompt wav at inference | requires prompt wav (or pre-baked safetensors) |
| Tokenizer | IPA via CSV mapping | espeak phonemes | SentencePiece subwords |

The realistic mobile path for either is **sherpa-onnx** (a separate native runtime swap), not a model-file swap inside the existing `Opti.kt`. Tasks 5 and 6 below produce the evidence in writing.

---

## File Structure

```
bench/
  README.md                       # how to reproduce
  corpus.json                     # fixed test sentences (5 lengths × 1 lang)
  run_bench.py                    # orchestrator: runs each adapter, writes results.csv
  measure.py                      # peak-RSS + wall-clock helpers (subprocess + psutil)
  adapters/
    bookbot_adapter.py            # loads convnext-tts-en.onnx via onnxruntime
    zipvoice_adapter.py           # invokes ZipVoice ONNX inference (CPU)
    pockettts_adapter.py          # invokes pocket_tts.TTSModel (PyTorch CPU)
  voices/
    zipvoice_default.wav          # pinned demo prompt
    zipvoice_default.txt          # transcript of that prompt
  results/
    results.csv                   # one row per (engine, sentence) measurement
    summary.csv                   # aggregated medians/p95
    rtf_vs_length.png             # plot
    comparison.md                 # final write-up
    mobile_feasibility.md         # Tasks 5 & 6 deliverable
```

Each adapter exposes the same Python interface:

```python
def synthesize(text: str, out_wav: str) -> dict:
    """Returns {'audio_seconds': float, 'phoneme_timings': list|None, 'voice_id': str}."""
```

`measure.py` runs each `synthesize` call in a **fresh subprocess** so peak RSS reflects only that engine's footprint (model load + one synthesis), not cumulative imports.

---

## Task 0: Bootstrap benchmark harness

**Files:**
- Create: `bench/README.md`
- Create: `bench/corpus.json`
- Create: `bench/measure.py`
- Create: `bench/run_bench.py`
- Create: `bench/adapters/__init__.py`

- [ ] **Step 1: Create `bench/corpus.json` with 5 fixed English sentences**

```json
{
  "lang": "en",
  "sentences": [
    {"id": "s05",  "text": "Hello world."},
    {"id": "s15",  "text": "The quick brown fox jumps over the lazy dog."},
    {"id": "s30",  "text": "She sells seashells by the seashore, and the shells she sells are surely seashells from the sea."},
    {"id": "s60",  "text": "In the beginning the universe was created. This has made a lot of people very angry and been widely regarded as a bad move. Most of the major problems can be solved if everyone just takes a deep breath."},
    {"id": "s120", "text": "Far out in the uncharted backwaters of the unfashionable end of the western spiral arm of the galaxy lies a small unregarded yellow sun. Orbiting this at a distance of roughly ninety-eight million miles is an utterly insignificant little blue green planet whose ape-descended life forms are so amazingly primitive that they still think digital watches are a pretty neat idea. This planet has, or rather had, a problem, which was this: most of the people on it were unhappy for pretty much of the time."}
  ]
}
```

- [ ] **Step 2: Create `bench/measure.py` — peak RSS + wall-clock harness**

```python
import json, subprocess, sys, time

def run_in_subprocess(adapter_module: str, text: str, out_wav: str) -> dict:
    """Spawn a fresh `python -c` that imports the adapter, synthesizes, prints
    a JSON result. Sample RSS at 50ms intervals via psutil from the parent."""
    import psutil
    code = (
        f"import json, sys; from bench.adapters import {adapter_module} as a; "
        f"r = a.synthesize({text!r}, {out_wav!r}); print('___RESULT___' + json.dumps(r))"
    )
    t0 = time.perf_counter()
    p = subprocess.Popen([sys.executable, "-c", code],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    proc = psutil.Process(p.pid)
    peak_rss = 0
    while p.poll() is None:
        try: peak_rss = max(peak_rss, proc.memory_info().rss)
        except psutil.NoSuchProcess: break
        time.sleep(0.05)
    out, err = p.communicate()
    wall = time.perf_counter() - t0
    if p.returncode != 0:
        raise RuntimeError(f"adapter {adapter_module} failed:\n{err.decode()}")
    line = [l for l in out.decode().splitlines() if l.startswith("___RESULT___")][-1]
    payload = json.loads(line.replace("___RESULT___", ""))
    payload["wall_seconds"] = wall
    payload["peak_rss_mb"] = peak_rss / (1024 * 1024)
    return payload
```

- [ ] **Step 3: Create `bench/run_bench.py` — orchestrator**

```python
import argparse, csv, json
from pathlib import Path
from bench.measure import run_in_subprocess

ENGINES = ["bookbot_adapter", "zipvoice_adapter", "pockettts_adapter"]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", choices=ENGINES + ["all"], default="all")
    ap.add_argument("--repeats", type=int, default=3)
    args = ap.parse_args()

    corpus = json.loads(Path("bench/corpus.json").read_text())
    out_dir = Path("bench/results"); out_dir.mkdir(exist_ok=True)
    rows = []
    engines = ENGINES if args.engine == "all" else [args.engine]
    for eng in engines:
        for s in corpus["sentences"]:
            for r in range(args.repeats):
                wav = out_dir / f"{eng}_{s['id']}_r{r}.wav"
                try:
                    res = run_in_subprocess(eng, s["text"], str(wav))
                    rtf = res["wall_seconds"] / max(res["audio_seconds"], 1e-6)
                    rows.append({"engine": eng, "sentence_id": s["id"], "repeat": r,
                                 "wall_s": res["wall_seconds"], "audio_s": res["audio_seconds"],
                                 "rtf": rtf, "peak_rss_mb": res["peak_rss_mb"],
                                 "voice_id": res.get("voice_id"),
                                 "has_phoneme_timings": res.get("phoneme_timings") is not None})
                except Exception as e:
                    rows.append({"engine": eng, "sentence_id": s["id"], "repeat": r,
                                 "error": str(e)})
    with (out_dir / "results.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=sorted({k for r in rows for k in r}))
        w.writeheader(); w.writerows(rows)

if __name__ == "__main__": main()
```

- [ ] **Step 4: Pin Python env**

```bash
cd /Users/ductran/Documents/codes/flutter/bookbot/tts
python3.11 -m venv bench/.venv
source bench/.venv/bin/activate
pip install onnxruntime psutil soundfile numpy pandas matplotlib tabulate
pip freeze > bench/requirements-base.txt
```
Expected: clean install, no errors.

- [ ] **Step 5: Commit harness skeleton**

```bash
git add bench/ docs/superpowers/plans/2026-05-04-tts-comparison-evaluation.md
git commit -m "chore(bench): add TTS comparison harness skeleton"
```

---

## Task 1: Baseline current Bookbot TTS via direct ONNX

**Files:**
- Create: `bench/adapters/bookbot_adapter.py`
- Reference: [example/android/app/src/main/assets/convnext-tts-en.onnx](../../../example/android/app/src/main/assets/convnext-tts-en.onnx) (~71 MB)
- Reference: [example/assets/tts/](../../../example/assets/tts/) for the IPA mapping CSV
- Reference: [lib/tts.dart](../../../lib/tts.dart) for the `breakIPA`/`search` pipeline being ported to Python
- Reference: [android/.../module/Opti.kt](../../../android/src/main/kotlin/com/tensorspeech/tensorflowtts/module/Opti.kt) for the exact ONNX I/O contract

- [ ] **Step 1: Locate the production ONNX model + IPA mapping**

```bash
find example -name "convnext-tts-en.onnx" -o -name "*tts_mapping*.csv" | sort
```
Expected: `example/android/app/src/main/assets/convnext-tts-en.onnx` and one English mapping CSV. Note the absolute paths in `bench/README.md`.

- [ ] **Step 2: Re-implement Dart `breakIPA` + `search` in Python**

The goal is byte-equivalent input IDs to what the Flutter plugin produces, so ONNX timing reflects production behavior. Read [lib/tts.dart](../../../lib/tts.dart), then port:

```python
# bench/adapters/bookbot_adapter.py
import csv, time
from pathlib import Path
import numpy as np, onnxruntime as ort, soundfile as sf

REPO = Path(__file__).resolve().parents[2]
MODEL_PATH  = REPO / "example/android/app/src/main/assets/convnext-tts-en.onnx"
MAPPING_CSV = REPO / "example/assets/tts/tts_mapping.csv"  # adjust if filename differs
SAMPLE_RATE = 44100
HOP_SIZE    = 512
SPEAKER_ID  = 0           # "us" — default in the example app
SPEED       = 0.82        # default in README
DEFAULT_VOICE = "convnext-tts-en/us"

def _load_mapping():
    table = {}
    with MAPPING_CSV.open() as f:
        for row in csv.DictReader(f):
            table[row["ipa"]] = (int(row["input_id"]), row["viseme"])
    return table

def _text_to_ipa(text: str) -> str:
    # Matches the example app: g2p via phonemizer/espeak.
    from phonemizer import phonemize
    return phonemize(text, language="en-us", backend="espeak", strip=True)

def _break_ipa(ipa: str, table) -> list[str]:
    # Greedy longest-match against mapping keys, mirroring tts.dart's breakIPA.
    keys = sorted(table.keys(), key=len, reverse=True)
    out, i = [], 0
    while i < len(ipa):
        if ipa[i] == " ":
            out.append("_"); i += 1; continue
        for k in keys:
            if ipa.startswith(k, i):
                out.append(k); i += len(k); break
        else:
            i += 1  # skip unknown
    return out

def synthesize(text: str, out_wav: str) -> dict:
    table = _load_mapping()
    ipa = _text_to_ipa(text)
    tokens = _break_ipa(ipa, table)
    input_ids = np.array([[table[t][0] for t in tokens if t in table]], dtype=np.int64)
    visemes   = [table[t][1] for t in tokens if t in table]
    x_lengths = np.array([input_ids.shape[1]], dtype=np.int64)
    scales    = np.array([SPEED, 1.0, 1.0], dtype=np.float32)
    sids      = np.array([SPEAKER_ID], dtype=np.int64)

    sess = ort.InferenceSession(str(MODEL_PATH), providers=["CPUExecutionProvider"])
    inputs = {"x": input_ids, "x_lengths": x_lengths, "scales": scales, "sids": sids}
    t0 = time.perf_counter()
    wav, durations = sess.run(["wav", "durations"], inputs)
    infer_s = time.perf_counter() - t0

    audio = wav.squeeze().astype(np.float32)
    sf.write(out_wav, audio, SAMPLE_RATE)

    sec_per_frame = HOP_SIZE / SAMPLE_RATE
    timings, t = [], 0.0
    for v, d in zip(visemes, durations.squeeze().tolist()):
        dur = float(d) * sec_per_frame
        timings.append({"token": v, "start": t, "duration": dur})
        t += dur

    return {
        "voice_id": DEFAULT_VOICE,
        "audio_seconds": len(audio) / SAMPLE_RATE,
        "phoneme_timings": timings,
        "infer_seconds": infer_s,
    }
```

- [ ] **Step 3: Smoke-test**

```bash
brew list espeak >/dev/null 2>&1 || brew install espeak
source bench/.venv/bin/activate
pip install phonemizer
python -c "from bench.adapters import bookbot_adapter as a; print(a.synthesize('Hello world.', '/tmp/bb.wav'))"
afplay /tmp/bb.wav
```
Expected: dict with `audio_seconds > 0`, `len(phoneme_timings) > 0`, audible speech.

- [ ] **Step 4: Run full bench**

```bash
python -m bench.run_bench --engine bookbot_adapter --repeats 3
```
Expected: 5 sentences × 3 repeats = 15 rows in `bench/results/results.csv`.

- [ ] **Step 5: Commit**

```bash
git add bench/adapters/bookbot_adapter.py bench/results/results.csv
git commit -m "bench: baseline current TTS via onnxruntime"
```

---

## Task 2: ZipVoice adapter — phoneme timing, memory, RTF

**Files:**
- Create: `bench/adapters/zipvoice_adapter.py`
- Create: `bench/voices/zipvoice_default.wav` (pinned reference)
- Create: `bench/voices/zipvoice_default.txt` (transcript)
- Reference: `/Users/ductran/Documents/codes/python/opensource/ZipVoice` (cloned repo)

ZipVoice is **zero-shot voice cloning** — there is no fixed "stock voice." The closest stand-in is a fixed reference clip. Use one of the demo prompts shipped with the upstream repo (under `egs/` or `assets/`), or pin a single clip from the project's HuggingFace voice samples. Document the exact file in `bench/README.md`.

- [ ] **Step 1: Pin upstream commit and reference voice**

```bash
ZV=/Users/ductran/Documents/codes/python/opensource/ZipVoice
git -C "$ZV" rev-parse HEAD                # capture into bench/README.md
ls "$ZV/assets" "$ZV/egs" 2>/dev/null      # locate a demo prompt
```

If a demo wav ships, copy it to `bench/voices/zipvoice_default.wav` and write its transcript to `bench/voices/zipvoice_default.txt`. If not, download one prompt from the project's HuggingFace and document the URL+SHA256 in `bench/README.md`.

- [ ] **Step 2: Install ZipVoice deps into the bench venv**

```bash
source bench/.venv/bin/activate
pip install --index-url https://download.pytorch.org/whl/cpu torch torchaudio
pip install -r /Users/ductran/Documents/codes/python/opensource/ZipVoice/requirements.txt
# k2 is optional (training only). Skip on macOS unless prebuilt wheel is available.
```
Expected: install succeeds. If `piper_phonemize` wheel is missing for macOS-arm64, fall back to `--tokenizer espeak` and install `espeak` via brew (already done in Task 1).

- [ ] **Step 3: Run the upstream CLI directly to confirm the recipe**

```bash
cd /Users/ductran/Documents/codes/python/opensource/ZipVoice
PYTHONPATH=. python3 -m zipvoice.bin.infer_zipvoice \
    --model-name zipvoice_distill \
    --prompt-wav /Users/ductran/Documents/codes/flutter/bookbot/tts/bench/voices/zipvoice_default.wav \
    --prompt-text "$(cat /Users/ductran/Documents/codes/flutter/bookbot/tts/bench/voices/zipvoice_default.txt)" \
    --text "Hello world." \
    --res-wav-path /tmp/zv_smoke.wav \
    --num-thread 2
afplay /tmp/zv_smoke.wav
```
Expected: HuggingFace download of the distilled checkpoint on first run, then a wav cloning the prompt's voice.

> Use **`zipvoice_distill`** (8-step) rather than full `zipvoice` for the bench — README §3.2 documents distill as the speed-priority option, with `--num-step 4` an additional toggle. This makes the comparison fair-to-bookbot (Bookbot is a single-pass model). Document this choice in `comparison.md`.

- [ ] **Step 4: Write the adapter as a subprocess shim**

```python
# bench/adapters/zipvoice_adapter.py
import subprocess, time
from pathlib import Path
import soundfile as sf

REPO       = Path(__file__).resolve().parents[2]
ZV_DIR     = Path("/Users/ductran/Documents/codes/python/opensource/ZipVoice")
PROMPT_WAV = REPO / "bench/voices/zipvoice_default.wav"
PROMPT_TXT = REPO / "bench/voices/zipvoice_default.txt"
DEFAULT_VOICE = "zipvoice_distill@demo_prompt"

def synthesize(text: str, out_wav: str) -> dict:
    cmd = [
        "python", "-m", "zipvoice.bin.infer_zipvoice",
        "--model-name", "zipvoice_distill",
        "--num-step", "4",
        "--num-thread", "2",
        "--prompt-wav", str(PROMPT_WAV),
        "--prompt-text", PROMPT_TXT.read_text().strip(),
        "--text", text,
        "--res-wav-path", out_wav,
    ]
    t0 = time.perf_counter()
    subprocess.run(cmd, check=True, cwd=str(ZV_DIR), env={**__import__("os").environ, "PYTHONPATH": str(ZV_DIR)})
    infer_s = time.perf_counter() - t0
    audio, sr = sf.read(out_wav)
    return {
        "voice_id": DEFAULT_VOICE,
        "audio_seconds": len(audio) / sr,
        "phoneme_timings": None,        # see Step 5 — confirmed not exposed
        "infer_seconds": infer_s,
    }
```

- [ ] **Step 5: Confirm phoneme-timing answer in writing**

This finding came out of the upstream-code read but must be stated explicitly in the deliverable. Add to `bench/results/comparison.md` under "Phoneme timing support":

> **ZipVoice: NO native per-phoneme timing.** The model predicts only an *aggregate* feature length: `features_len = ceil(prompt_features_len / prompt_tokens_len * tokens_len / speed)` ([zipvoice/models/zipvoice.py:323-325](../../../../python/opensource/ZipVoice/zipvoice/models/zipvoice.py)). The per-token duration in `onnx_export.py:139` is `floor(features_len / tokens_len)` — a uniform placeholder, not a learned alignment. To recover per-phoneme timestamps, run a forced aligner (e.g. Montreal Forced Aligner or `whisper-timestamped`) on the synthesized audio. This is a post-hoc workaround, not a native capability.

- [ ] **Step 6: Run the bench**

```bash
python -m bench.run_bench --engine zipvoice_adapter --repeats 3
```
Expected: 15 rows added to `results.csv`. First run downloads the checkpoint (slow) — discard it from RTF measurements by warming up once before measured runs (the harness does this implicitly: cold-start model load happens inside the subprocess, so Repeat 0 will be slower than 1–2; the median absorbs it).

- [ ] **Step 7: Commit**

```bash
git add bench/adapters/zipvoice_adapter.py bench/voices/ bench/results/results.csv
git commit -m "bench: add ZipVoice adapter and measurements"
```

---

## Task 3: Pocket-TTS adapter — phoneme timing, memory, RTF

**Files:**
- Create: `bench/adapters/pockettts_adapter.py`
- Reference: `/Users/ductran/Documents/codes/python/opensource/pocket-tts` (cloned repo)

- [ ] **Step 1: Pin upstream commit**

```bash
PT=/Users/ductran/Documents/codes/python/opensource/pocket-tts
git -C "$PT" rev-parse HEAD                # capture into bench/README.md
```

- [ ] **Step 2: Install pocket-tts into the bench venv**

```bash
source bench/.venv/bin/activate
pip install -e /Users/ductran/Documents/codes/python/opensource/pocket-tts
```
Expected: editable install succeeds. Verify:
```bash
python -c "from pocket_tts import TTSModel; print('ok')"
```

- [ ] **Step 3: Smoke-test the upstream CLI**

```bash
pocket-tts generate --voice alba --text "Hello world." --output /tmp/pt_smoke.wav
afplay /tmp/pt_smoke.wav
```
Expected: a wav file in `alba`'s voice. First run downloads weights from HuggingFace.

- [ ] **Step 4: Write the adapter using the documented Python API**

The README's documented pattern (`README.md:115-128`):

```python
# bench/adapters/pockettts_adapter.py
import time, scipy.io.wavfile, numpy as np
from pocket_tts import TTSModel
from pocket_tts import DEFAULT_AUDIO_PROMPT  # = "alba"

DEFAULT_VOICE = DEFAULT_AUDIO_PROMPT

def synthesize(text: str, out_wav: str) -> dict:
    tts = TTSModel.load_model()                          # default = english model
    voice_state = tts.get_state_for_audio_prompt(DEFAULT_VOICE)
    t0 = time.perf_counter()
    audio = tts.generate_audio(voice_state, text)        # 1D torch tensor, PCM
    infer_s = time.perf_counter() - t0
    sr = tts.sample_rate                                 # 24000
    scipy.io.wavfile.write(out_wav, sr, audio.numpy().astype(np.float32))
    return {
        "voice_id": DEFAULT_VOICE,
        "audio_seconds": int(audio.shape[-1]) / sr,
        "phoneme_timings": None,        # see Step 5 — confirmed not exposed
        "infer_seconds": infer_s,
    }
```

- [ ] **Step 5: Confirm phoneme-timing answer in writing**

Add to `bench/results/comparison.md`:

> **Pocket-TTS: NO phoneme/word timing in the public API.** The tokenizer is SentencePiece subword ([pocket_tts/conditioners/text.py](../../../../python/opensource/pocket-tts/pocket_tts/conditioners/text.py)), not phonemes. `TTSModel.generate_audio` returns a 1D audio tensor only ([pocket_tts/models/tts_model.py:477-542](../../../../python/opensource/pocket-tts/pocket_tts/models/tts_model.py)); `generate_audio_stream` yields audio chunks but no token alignment. Internal RTF is logged but no per-token times are surfaced. Workaround: run forced alignment on the output, same as ZipVoice.

- [ ] **Step 6: Run the bench**

```bash
python -m bench.run_bench --engine pockettts_adapter --repeats 3
```
Expected: 15 more rows in `results.csv`.

- [ ] **Step 7: Commit**

```bash
git add bench/adapters/pockettts_adapter.py bench/results/results.csv
git commit -m "bench: add pocket-tts adapter and measurements"
```

---

## Task 4: Aggregate, compare, and write up

**Files:**
- Create: `bench/aggregate.py`
- Create: `bench/results/comparison.md`

- [ ] **Step 1: Write `bench/aggregate.py`**

```python
import pandas as pd, matplotlib.pyplot as plt
from pathlib import Path

df = pd.read_csv("bench/results/results.csv")
if "error" in df.columns:
    df = df[df["error"].isna()]

g = df.groupby("engine").agg(
    median_rtf=("rtf", "median"),
    p95_rtf=("rtf", lambda s: s.quantile(0.95)),
    median_peak_mb=("peak_rss_mb", "median"),
    has_phoneme_timings=("has_phoneme_timings", "any"),
).reset_index()
print(g.to_markdown(index=False))
g.to_csv("bench/results/summary.csv", index=False)

length_map = {"s05": 12, "s15": 44, "s30": 100, "s60": 220, "s120": 520}
df["chars"] = df["sentence_id"].map(length_map)
fig, ax = plt.subplots()
for eng, sub in df.groupby("engine"):
    series = sub.groupby("chars")["rtf"].median()
    ax.plot(series.index, series.values, marker="o", label=eng)
ax.axhline(1.0, ls="--", color="gray", label="real-time")
ax.set(xlabel="characters", ylabel="RTF (CPU)", title="RTF vs sentence length")
ax.legend()
fig.savefig("bench/results/rtf_vs_length.png", dpi=150, bbox_inches="tight")
```

Run:
```bash
python bench/aggregate.py
```
Expected: a 3-row markdown table printed to stdout, `summary.csv` and `rtf_vs_length.png` written.

- [ ] **Step 2: Write `bench/results/comparison.md` from the template below**

Replace every `__` placeholder with the actual number from `summary.csv`.

```markdown
# TTS Comparison: Bookbot vs. ZipVoice vs. Pocket-TTS

**Date:** 2026-05-04
**Hardware:** macOS Darwin 25.4.0, <CPU model>, <RAM> GB
**Test corpus:** 5 English sentences (5–500+ chars), 3 repeats each.

## Headline table

| Engine        | Default voice            | Phoneme timing | Median RTF (CPU) | p95 RTF | Median peak RSS |
|---------------|--------------------------|----------------|------------------|---------|-----------------|
| Bookbot TTS   | convnext-tts-en (us)     | YES (per-phoneme, native) | __ | __ | __ MB |
| ZipVoice-distill (4-step) | demo prompt  | NO (aggregate-length only; needs forced aligner) | __ | __ | __ MB |
| Pocket-TTS    | alba                     | NO (subword tokenizer; no alignment in API) | __ | __ | __ MB |

RTF = wall_seconds / audio_seconds. Lower is faster. < 1.0 is real-time.

## Phoneme timing support
- **Bookbot:** native — model returns a `durations` tensor (frames per phoneme), converted at hop=512, sr=44100. This is the contract that drives [lib/tts.dart](../../../lib/tts.dart) viseme/lip-sync output.
- **ZipVoice:** <paste finding from Task 2 Step 5>
- **Pocket-TTS:** <paste finding from Task 3 Step 5>

## Memory
<one paragraph: who's lightest, who's heaviest, by how much, and why
(e.g. PyTorch runtime vs. ONNX runtime vs. native).>

## Real-time factor
<one paragraph + reference to bench/results/rtf_vs_length.png>

## Caveats
- Bookbot exercised through `onnxruntime` Python, not via Flutter — strips
  platform-channel + AudioTrack/AVAudioEngine overhead.
- ZipVoice is zero-shot voice-cloning; "default voice" = the demo prompt
  bundled with the upstream repo at SHA <…>. Distill+4-step chosen to make the
  RTF comparison fair (Bookbot is single-pass).
- Pocket-TTS measured with default voice `alba` and the english model.
- All three on CPU. GPU is irrelevant for Bookbot (single-pass small model)
  and for Pocket-TTS (upstream README §"unsupported features" notes no GPU
  speedup observed).

## Recommendation
<2–4 sentences: which to keep, which to consider, on which axes, and what
would change the answer (mobile deployment, voice cloning need, phoneme
timing requirement for visemes/lip-sync).>
```

- [ ] **Step 3: Commit**

```bash
git add bench/aggregate.py bench/results/
git commit -m "bench: aggregate results and write comparison report"
```

---

## Task 5: Mobile feasibility — can either run on Android/iOS like Bookbot?

This task is **a written analysis**, not a benchmark. It answers the user's first question.

**Files:**
- Create: `bench/results/mobile_feasibility.md`

- [ ] **Step 1: Inspect upstream mobile/runtime evidence**

Run these checks and capture outputs:

```bash
# ZipVoice — official mobile path?
ls /Users/ductran/Documents/codes/python/opensource/ZipVoice/runtime
grep -rn -i "android\|ios\|mobile\|sherpa" /Users/ductran/Documents/codes/python/opensource/ZipVoice/README.md

# Pocket-TTS — official mobile path?
ls /Users/ductran/Documents/codes/python/opensource/pocket-tts | grep -iE "android|ios|mobile|kotlin|swift"
grep -n -iE "android|ios|mobile|sherpa|kotlin|swift|dart" /Users/ductran/Documents/codes/python/opensource/pocket-tts/README.md
```

Expected findings (already confirmed during plan-writing — the task records them as evidence):
- **ZipVoice** has only `runtime/nvidia_triton/` — server-GPU only. README §"CPU Deployment" points to k2-fsa/sherpa-onnx for C++ on CPU. **No first-party Android or iOS code in the repo.**
- **Pocket-TTS** ships no Android/iOS code. README "Alternative implementations" lists sherpa-onnx (Kotlin/Swift/Dart bindings), pocket-tts-mlx (macOS-only), pocket-tts-csharp, PocketTTS.cpp, and several WebAssembly ports.

- [ ] **Step 2: Compare runtime fit against Bookbot's plumbing**

Bookbot today on Android: ONNX Runtime Android, single-pass forward, raw `AudioTrack`. iOS: ONNX Runtime Objective-C, `AVAudioEngine`. See [android/.../module/Opti.kt](../../../android/src/main/kotlin/com/tensorspeech/tensorflowtts/module/Opti.kt) and [ios/Classes/Opti.swift](../../../ios/Classes/Opti.swift).

Score each engine on the runtime axes:

| Axis | Bookbot today | ZipVoice on mobile | Pocket-TTS on mobile |
|---|---|---|---|
| Native runtime | ONNX Runtime (Java/Obj-C) | sherpa-onnx (Kotlin/Swift) – community/upstream-blessed | sherpa-onnx (Kotlin/Swift/Dart) – upstream-blessed |
| Number of model files | 1 | 3 (text enc + FM dec + vocoder) | 2 (LM + Mimi codec) |
| Inference shape | single forward | iterative FM (4–8 steps/utterance) | autoregressive token-by-token |
| Per-utterance compute | ~71 MB params, 1 pass | 123M params × N steps | 100M params × T tokens |
| INT8 mobile-quant available | already quant in some assets | yes (`--onnx-int8 True`) | yes (community export, KevinAHM) |
| Voice prompt at inference | not needed | required (ref wav) | required (or pre-baked safetensors via `export_voice`) |
| Languages | EN/ID/SW | EN/ZH | EN/FR/DE/PT/IT/ES |
| Sample rate out | 44.1 kHz | 24 kHz (Vocos) | 24 kHz (Mimi) |

- [ ] **Step 3: Write `bench/results/mobile_feasibility.md`**

```markdown
# Mobile feasibility: ZipVoice and Pocket-TTS vs. Bookbot

## Question
Can ZipVoice or Pocket-TTS run on Android/iOS in the same way as the current
Bookbot Flutter plugin (ONNX Runtime, on-device, single Flutter package)?

## Short answer
**Not as a drop-in.** Both are technically capable of on-device CPU inference,
but reaching that requires a different runtime layer than the existing
Bookbot `Opti.kt` / `Opti.swift`. The realistic path for either is
[k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx), which provides
Kotlin, Swift, and Dart bindings for both engines.

## Findings

### ZipVoice
- No first-party Android/iOS code in the repo. `runtime/` contains only
  `nvidia_triton/` (server GPU).
- README §"CPU Deployment" explicitly redirects mobile/embedded users to
  sherpa-onnx (PR #2487).
- ONNX export available (`zipvoice/bin/onnx_export.py`), produces three
  separate ONNX files plus optional INT8 quant. Sherpa-onnx wraps these.
- Practical mobile deployment cost: replace ONNX Runtime usage with
  sherpa-onnx, ship 3 model files (~hundreds of MB at FP32, less at INT8),
  bundle a default reference prompt wav, and accept iterative inference
  (4–8 FM steps).

### Pocket-TTS
- README "Main takeaways": "Runs on CPU, ~6× real-time on a MacBook Air M4,
  uses only 2 CPU cores, can run client-side in browser."
- No first-party Android/iOS code. README "Alternative implementations" lists
  sherpa-onnx (Kotlin/Swift/Dart), PocketTTS.cpp, candle/WebAssembly ports.
- Pure-PyTorch reference implementation is not realistic for mobile shipping
  (PyTorch Mobile is large and slow). Use community ONNX export
  (KevinAHM/pocket-tts-onnx-export) or sherpa-onnx.
- Practical mobile cost: replace ONNX Runtime usage with sherpa-onnx, ship
  the LM + Mimi codec, accept autoregressive streaming (different audio
  pipeline than Bookbot's pre-buffered AudioTrack).

## Implication for the Flutter plugin
If we want either engine inside this plugin, the work is:
1. Add a sherpa-onnx Android AAR / iOS xcframework dependency.
2. Replace the `Opti.kt` / `Opti.swift` ONNX Runtime calls with sherpa-onnx
   API calls (different I/O contract — see Task 6).
3. Ship the new model files in `example/android/app/src/main/assets/` and the
   iOS bundle.
4. Re-design the `MethodChannel` boundary to support streaming chunks
   (Pocket-TTS) or multi-step FM (ZipVoice), neither of which match the
   current "one call returns wav + durations" contract.
5. Decide what to do about visemes/lip-sync, since neither model produces
   per-phoneme timings (see Tasks 2/3).
```

- [ ] **Step 4: Commit**

```bash
git add bench/results/mobile_feasibility.md
git commit -m "bench: document mobile feasibility for ZipVoice and pocket-tts"
```

---

## Task 6: Drop-in model-swap test — replace `convnext-tts-en.onnx` and run the example app

This task answers the user's second question literally and produces evidence either way. It is a **negative-result demonstration** — the expected outcome is failure, but the failure mode is the deliverable.

**Files:**
- Append findings to: `bench/results/mobile_feasibility.md` (new section "Drop-in model swap")

- [ ] **Step 1: Export ZipVoice to ONNX**

```bash
source bench/.venv/bin/activate
cd /Users/ductran/Documents/codes/python/opensource/ZipVoice
python -m zipvoice.bin.onnx_export --model-name zipvoice_distill --onnx-model-dir /tmp/zv_onnx
ls -la /tmp/zv_onnx
```
Expected: 3 ONNX files (text encoder, FM decoder, vocoder) totaling >100 MB.

- [ ] **Step 2: Inspect ZipVoice ONNX I/O against Bookbot's contract**

```bash
python - <<'PY'
import onnx
for fn in ["/tmp/zv_onnx/fm_decoder.onnx", "/tmp/zv_onnx/text_encoder.onnx", "/tmp/zv_onnx/vocos.onnx"]:
    m = onnx.load(fn)
    print("\n==", fn)
    print(" inputs:",  [(i.name, [d.dim_value or d.dim_param for d in i.type.tensor_type.shape.dim]) for i in m.graph.input])
    print(" outputs:", [(o.name, [d.dim_value or d.dim_param for d in o.type.tensor_type.shape.dim]) for o in m.graph.output])
PY
```
Expected: I/O names like `tokens`, `prompt_tokens`, `prompt_features_len`, `speed`, `noise`, `t`, … — none of which match Bookbot's `x` / `x_lengths` / `scales` / `sids`.

- [ ] **Step 3: Demonstrate the drop-in fails**

Don't actually overwrite the production model. Make a copy of the example app's asset folder and try the swap there:

```bash
cp -R example/android/app/src/main/assets /tmp/assets_swap
rm /tmp/assets_swap/convnext-tts-en.onnx
cp /tmp/zv_onnx/fm_decoder.onnx /tmp/assets_swap/convnext-tts-en.onnx   # rename trick
ls -la /tmp/assets_swap/convnext-tts-en.onnx
```

Then run a tiny Kotlin-equivalent loader from Python that mimics `Opti.kt`:

```python
import numpy as np, onnxruntime as ort
sess = ort.InferenceSession("/tmp/assets_swap/convnext-tts-en.onnx",
                            providers=["CPUExecutionProvider"])
try:
    sess.run(["wav", "durations"], {
        "x": np.array([[1,2,3,4,5]], dtype=np.int64),
        "x_lengths": np.array([5], dtype=np.int64),
        "scales": np.array([1.0,1.0,1.0], dtype=np.float32),
        "sids": np.array([0], dtype=np.int64),
    })
except Exception as e:
    print("EXPECTED FAILURE:", type(e).__name__, str(e)[:200])
```
Expected: `InvalidArgument` — input names don't match. Capture the exact error.

- [ ] **Step 4: Repeat for Pocket-TTS via the community ONNX export**

```bash
git clone https://github.com/KevinAHM/pocket-tts-onnx-export /tmp/pt_onnx_export
# Follow that repo's README to produce ONNX files. Do not bother running them
# through Bookbot's loader — by Step 2 we already know the I/O won't match
# (Pocket-TTS is autoregressive, two-model, with KV-cache state inputs).
```
Capture the file list and the I/O of one of the models, same shape as Step 2.

- [ ] **Step 5: Append the drop-in section to `mobile_feasibility.md`**

```markdown
## Drop-in model swap into `example/android/app/src/main/assets/`

**Result: NOT POSSIBLE without rewriting `Opti.kt` / `Opti.swift`.**

### Evidence
- Bookbot's loader expects ONNX inputs `{x, x_lengths, scales, sids?, lids?}`
  and outputs `{wav, durations}` (see [android/.../module/Opti.kt:30-78](../../../android/src/main/kotlin/com/tensorspeech/tensorflowtts/module/Opti.kt)).
- ZipVoice's exported ONNX uses inputs `{tokens, prompt_tokens, prompt_features_len, speed}`
  on the text encoder and `{noise, t, text_condition, ...}` on the FM decoder
  — confirmed by `onnx.load` inspection in Task 6 Step 2.
- Pocket-TTS has no official ONNX export; the community export
  (KevinAHM/pocket-tts-onnx-export) emits two models that take SentencePiece
  IDs and KV-cache tensors, not a flat phoneme ID array.

Renaming a file to `convnext-tts-en.onnx` does not change its I/O graph.
Loading any of these via the existing `Opti.kt` raises
`InvalidArgument: Got invalid input names`.

### What would actually be needed
A model swap into the *plugin* (not just the assets folder) requires:
1. New native loader code (or sherpa-onnx integration) that knows the new
   I/O shape and runs N-step / autoregressive inference.
2. New Dart-side request shape — prompt wav + reference text for ZipVoice,
   voice-state safetensors for Pocket-TTS.
3. New Method Channel methods for streaming output (Pocket-TTS).
4. Replacement for the `durations` output that drives visemes — either a
   forced aligner or a different lip-sync strategy.
```

- [ ] **Step 6: Commit**

```bash
git add bench/results/mobile_feasibility.md
git commit -m "bench: prove model-swap drop-in fails and document why"
```

---

## Self-review checklist

- [ ] All three engines exercised on the same corpus, same machine, same repeat count.
- [ ] Default/standard voice for each engine is documented by name and (for ZipVoice) pinned by file + upstream commit SHA.
- [ ] Phoneme-timing finding is explicit per engine (yes-native / yes-forced / no), not hand-waved — statements anchored to specific source-file lines.
- [ ] Peak RSS is measured in a fresh subprocess per call, not cumulative.
- [ ] Mobile feasibility is documented in writing with evidence from upstream READMEs and `runtime/` folders.
- [ ] Drop-in model swap is **demonstrated** to fail (Task 6 captures the actual ONNX runtime error), not just asserted.

## Known limitations

- **Cold-start dominates short sentences.** Each subprocess loads the model from scratch — that reflects "first utterance after launch", not steady-state. Add a Task 7 later for warm RTF inside one process if needed.
- **Quality not measured.** Faster + smaller is meaningless if the audio is worse. A follow-up MOS or A/B listening test is required before any production switch.
- **Mobile reality differs.** Tasks 1–4 run on macOS CPU. Bookbot's deployment target is mobile ARM with ONNX Runtime. To validate ZipVoice/pocket-tts on real hardware, build a sherpa-onnx-based Android demo in a follow-up — out of scope here.
