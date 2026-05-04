# Pocket-TTS PR #147 dynamic int8 — measured, didn't help

**TL;DR:** We tried Pocket-TTS's official int8 dynamic quantization (PR #147, merged into upstream main 2026-03-24) on host CPU. It was **slower and heavier** than unquantized PyTorch in our setup. The PR's reported 27%/16% speedup and 48% memory reduction did not reproduce on macOS arm64 with our cold-start measurement methodology.

The mobile-deployment story is unchanged: **sherpa-onnx is still the right path**, and its mixed-precision int8 archive is still the smallest ship-able variant.

## What we measured

We added two PyTorch adapters that exercise PR #147:

- `pockettts_quant_adapter.py` — `TTSModel.load_model(quantize=True)`, the public flag, which quantizes both attention + FFN linears (the PR's `RECOMMENDED_CONFIG = {"attention", "ffn"}`).
- `pockettts_quant_attn_adapter.py` — calls `apply_dynamic_int8(flow_lm, {"attention"})` directly, skipping FFN. The PR explicitly notes ARM has a per-op dequant penalty in QNNPACK with FFN; we tested whether dropping FFN recovers the gap.

Both were run with `torchao` 0.17.0 installed (the faster of the two backends per PR description) — confirmed via `pocket_tts.quantization._get_backend()` returning `"torchao"`.

## Results (host CPU, M1 Pro, 5 sentences × 3 repeats each, fresh subprocess per call)

| Variant | Median RTF | p95 RTF | Median peak RSS | vs. unquantized |
|---|---:|---:|---:|---|
| Unquantized PyTorch (`pockettts_adapter`) | **0.91** | 3.31 | **881 MB** | baseline |
| Quant `attention+ffn` (`quantize=True`) | 1.02 | 4.07 | 946 MB | 12% slower, 7% heavier |
| Quant `attention`-only | 1.00 | 3.99 | 886 MB | 10% slower, ~same memory |
| Pocket-TTS sherpa-onnx host | 0.67 | 3.76 | 843 MB | 27% faster, 4% lighter |
| Pocket-TTS sherpa-onnx **Android** | **0.37** | 1.53 | **778 MB** | 59% faster, 12% lighter |

## Why the PR's numbers didn't reproduce

Three reasons, in descending order of impact:

1. **`torchao` C++ extensions are not loaded** in our environment. `hasattr(torchao, "_C")` is `False` on the macOS-arm64 pip wheel (`torchao 0.17.0`). Pocket-TTS's `_get_backend()` still picks `"torchao"` (the gating condition is `hasattr(torchao, "_C") or not _SKIPPED_CPP_EXTENSIONS`, and the latter defaults to False), so it routes through torchao's pure-Python `quantize_(model, Int8DynamicActivationInt8WeightConfig())` — slower than the C++ kernels the PR was benchmarked against. The PR's "~16% ARM speedup" is specifically the **torchao with C extensions** path; without them you fall off the cliff.

2. **The PR's 48% memory reduction is steady-state, ours is peak-during-load.** Each of our measurements runs in a fresh subprocess and starts cold, so peak RSS includes the FP32 → int8 conversion transition (FP32 weights are still resident while int8 versions are being created). The smaller int8 weights only matter once that transition is done — but our bench measures the whole "first inference after launch" experience, which is also what mobile users actually feel. Steady-state memory is genuinely smaller; cold-start peak is not.

3. **The PR's reported ~27% speedup is x86-specific** ("~27% faster (4.04x vs. 3.17x real-time speed factor)" in the PR's own benchmark table is x86; the ARM numbers were 5.36x vs ?? with the torchao backend, and the PR explicitly flags QNNPACK regressions on ARM). MKL/oneDNN on x86 has solid int8 paths; the ARM equivalents lag.

## What this means for mobile

- The sherpa-onnx int8 archive **already** quantizes the parts that matter (lm_main, lm_flow, decoder) and **already** ships smaller and faster than the FP32 PyTorch path. PR #147 is effectively a parallel attempt at the same thing through a different runtime; on x86 it competes, on ARM without torchao C extensions it loses.
- Running the upstream PyTorch model on Android would mean shipping PyTorch Mobile (not feasible) or routing through ONNX/sherpa anyway — at which point you'd want the sherpa team's existing int8 archive, not PR #147's PyTorch-only quantization.
- The realistic memory headroom past the sherpa-onnx archive would come from quantizing the **encoder** (Mimi audio codec, currently FP32 in the sherpa archive), not from re-quantizing what's already int8. That's a static QDQ job with calibration data — substantially more work than a CLI flag — and would likely cost audio quality, which is why the sherpa team didn't do it.

## Bottom line on the question "can we do dynamic or static quantization to get memory improvement?"

- **Dynamic** (PR #147): tried, **does not help us** on macOS arm64 cold-start. May help on x86 servers or on real Android devices with a torchao build that has working C extensions — neither matches our deployment target.
- **Static / QDQ**: would target the FP32 encoder in the sherpa archive (the only remaining FP32 component worth quantizing). Requires a calibration set of ~100 representative prompt wavs, a regression script comparing FP32 vs int8 audio quality (PESQ/MCD or informal listening), and acceptance that some ops stay FP. This is a real project, not a CLI flag, and the gain is bounded — encoder is 72.7 MB on disk, runs once per generation, so the wins are mostly download size, not inference speed.

The sensible next step for shrinking on-device size further is **not** more quantization — it's deciding whether to ship a single voice's pre-baked KV-cache safetensors (Pocket-TTS's `export-voice` output) instead of the full encoder pipeline. That can collapse the per-voice cost by an order of magnitude without touching weights. Out of scope for this benchmark.
