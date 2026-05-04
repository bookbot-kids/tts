# TTS Comparison Benchmark

Head-to-head benchmark of the current Bookbot TTS plugin vs. ZipVoice and
Kyutai Pocket-TTS on five axes: phoneme timing, peak memory, real-time factor
(RTF), mobile feasibility, and drop-in model-swap feasibility.

## Layout

| Path | Purpose |
|---|---|
| `corpus.json` | 5 fixed English sentences spanning 12–520 chars |
| `measure.py` | peak-RSS + wall-clock harness (subprocess + psutil) |
| `run_bench.py` | orchestrator — `python -m bench.run_bench --engine <…>` |
| `adapters/bookbot_adapter.py` | loads `convnext-tts-en.onnx` via onnxruntime |
| `adapters/zipvoice_adapter.py` | shells out to `zipvoice.bin.infer_zipvoice` |
| `adapters/pockettts_adapter.py` | uses `pocket_tts.TTSModel` Python API |
| `voices/zipvoice_default.wav` | pinned reference prompt for ZipVoice cloning |
| `results/results.csv` | one row per (engine, sentence, repeat) |
| `results/comparison.md` | final write-up |
| `results/mobile_feasibility.md` | mobile + model-swap analysis |

## Reproduce

```bash
# 1. Bench-only deps (light)
python3.11 -m venv bench/.venv
source bench/.venv/bin/activate
pip install onnxruntime psutil soundfile numpy pandas matplotlib tabulate phonemizer
brew install espeak

# 2. ZipVoice + Pocket-TTS deps (heavy — adds PyTorch CPU + transformers + lhotse)
pip install --index-url https://download.pytorch.org/whl/cpu torch torchaudio
pip install -r /Users/ductran/Documents/codes/python/opensource/ZipVoice/requirements.txt
pip install -e /Users/ductran/Documents/codes/python/opensource/pocket-tts

# 3. Run
python -m bench.run_bench --engine bookbot_adapter --repeats 3
python -m bench.run_bench --engine zipvoice_adapter --repeats 3 --append
python -m bench.run_bench --engine pockettts_adapter --repeats 3 --append
python bench/aggregate.py
```

## Pinned upstream sources

Filled in as each adapter is added.

| Project | Path | Commit SHA |
|---|---|---|
| ZipVoice | `/Users/ductran/Documents/codes/python/opensource/ZipVoice` | TBD |
| Pocket-TTS | `/Users/ductran/Documents/codes/python/opensource/pocket-tts` | TBD |

## Notes

- Each `synthesize` call runs in a fresh subprocess so peak RSS reflects only
  one engine's footprint, not cumulative imports. This means **cold start
  dominates short sentences** — first repeat of `s05` is mostly model load.
- Bookbot is exercised through `onnxruntime` Python rather than via Flutter,
  so the comparison is apples-to-apples (same machine, same runtime kind).
  This strips Flutter platform-channel + AudioTrack/AVAudioEngine overhead;
  documented as a caveat in `results/comparison.md`.
- Quality (MOS) is **not** measured. RTF and memory only.
