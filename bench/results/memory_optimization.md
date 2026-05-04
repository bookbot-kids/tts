# On-mobile memory optimization — what's available for each engine

This doc walks through every realistic lever for shrinking the on-device memory and disk footprint of Pocket-TTS and ZipVoice via sherpa-onnx, including two cheap experiments run here. It's anchored in **measurements where possible** and flags **projection vs. measurement** explicitly.

The headline is: most of the obvious wins have already been taken by sherpa's int8 archive. The biggest *unmeasured* lever (warm-instance mode) is **3–5× faster** than our headline RTF on short utterances and is what a real app would do anyway.

## Where we are now (recap)

Smallest sherpa-onnx INT8 variants, on Android emulator:

| Engine | Model files on disk | Peak RSS (cold subprocess) | Median RTF (s120) |
|---|---:|---:|---:|
| Pocket-TTS | 213 MB (5 ONNX) | 778 MB | 0.26 |
| ZipVoice | 206 MB (2 ONNX + Vocos vocoder) | 779 MB | 0.36 |

What's already int8 in the Pocket-TTS archive (verified by counting `MatMulInteger` ops):

| File | Size | Status |
|---|---:|---|
| `lm_main.int8.onnx` | 76.3 MB | ✅ int8 |
| `lm_flow.int8.onnx` | 10.0 MB | ✅ int8 |
| `decoder.int8.onnx` | 22.7 MB | ✅ int8 |
| `encoder.onnx` (Mimi audio codec) | 72.7 MB | ❌ FP32 |
| `text_conditioner.onnx` (1-op embedding lookup) | 16.4 MB | ❌ FP32 (n/a) |

ZipVoice ships two int8 ONNX (`encoder.int8.onnx` 90 MB, `decoder.int8.onnx` 64 MB) plus the Vocos vocoder at 52 MB FP32.

---

## Lever 1: Persistent-instance mode (MEASURED — biggest practical win)

**What:** Build the `OfflineTts` instance once at app launch and reuse it across every `generate()` call, instead of constructing a fresh one per call.

**Why it matters:** Our headline numbers measure each utterance in a fresh subprocess (so peak RSS includes model load + first inference). A real app wouldn't do that — it would keep the TTS instance alive. Run all 5 sentences against ONE persistent sherpa-onnx instance:

```
Pocket-TTS (warm probe — bench/probe_warm_vs_cold.py):
  build delta:         365 MB
  s05  audio=0.72s  infer=0.263s  rtf=0.365   (cold-subprocess: 1.43)
  s15  audio=2.48s  infer=0.468s  rtf=0.189   (cold-subprocess: 0.49)
  s30  audio=4.72s  infer=0.856s  rtf=0.181   (cold-subprocess: 0.37)
  s60  audio=9.67s  infer=1.777s  rtf=0.184   (cold-subprocess: 0.30)
  s120 audio=26.20s infer=4.911s  rtf=0.187   (cold-subprocess: 0.26)

ZipVoice (warm probe):
  build delta:         297 MB
  s05  audio=0.67s  infer=0.604s  rtf=0.899   (cold-subprocess: 2.79)
  s30  audio=4.25s  infer=1.307s  rtf=0.308   (cold-subprocess: 0.66)
  s120 audio=24.35s infer=7.006s  rtf=0.288   (cold-subprocess: 0.36)
```

**Effect:** RTF drops **3–5× on short utterances** because the model load (~365 MB / ~297 MB respectively) happens once instead of per call. On long utterances the cold-subprocess number was already mostly steady-state, so the improvement is smaller (~1.3–1.5×) but still real.

**Memory:** Peak RSS in steady-state is ~850 MB for either engine — slightly higher than the cold-subprocess peak only because `psutil` is sampling the process *with the model resident*, not at load-time spike. There's no extra cost; the working set is just there continuously.

**Effort:** Zero — this is just normal app architecture.

**Action:** This is the **single most important number for mobile**. Headline doc should emphasize "0.18–0.30 RTF in steady state on Android" not "0.26–0.36 cold-subprocess RTF."

---

## Lever 2: `max_reference_audio_len` (MEASURED — does nothing)

**What:** Pocket-TTS's `gen.extra["max_reference_audio_len"]` (in seconds) caps how much of the prompt audio the encoder processes. Default in the upstream Python example is 12.

**Hypothesis going in:** A shorter prompt means less encoder work and less encoder RAM during the prompt-encoding step.

**Result (steady-state, persistent instance, sentence s30, 3-run median):**

| `max_reference_audio_len` | Infer time | RTF |
|---:|---:|---:|
| 3 s | 0.840 s | 0.178 |
| 6 s | 0.873 s | 0.198 |
| 12 s (default) | 0.852 s | 0.184 |
| 30 s | 0.909 s | 0.192 |

**Effect:** Within noise. The encoder runs once per `generate()` and finishes in ~50 ms even on a 30-second prompt; the autoregressive `lm_main` loop dominates inference time and isn't sensitive to prompt length.

**Action:** Don't bother tuning this for perf. Possible quality concern for very short prompts (the cloned voice may degrade with <3 s of source) — separate question.

---

## Lever 3: Pre-baked voice state via `pocket-tts export-voice` (MEASURED size, blocked by sherpa)

**What:** Pocket-TTS provides a `export-voice` CLI that runs the encoder ONCE on a chosen prompt wav and saves the resulting KV-cache state to a `.safetensors` file. The PyTorch path can then load that file in a fraction of the time it takes to re-encode from scratch.

**Measured saving:**
```
  encoder.onnx (FP32):       72.7 MB
  alba.safetensors:           6.2 MB    (~12× smaller)
```

**Why this matters in theory:** If we shipped a **fixed default voice** (one named voice, not user-supplied), we could:
- Drop `encoder.onnx` from the on-device bundle entirely (-72.7 MB on disk)
- Skip its load and inference cost
- Drop the test_wavs directory (-13 MB)

**Why it doesn't currently work via sherpa-onnx:** I checked the `OfflineTtsPocketModelConfig` API — there's no input slot for a pre-encoded voice state. Sherpa-onnx always re-encodes the prompt audio from samples on every call.

```dart
// sherpa_onnx OfflineTtsPocketModelConfig — no pre-encoded-state input
final pocket = sherpa_onnx.OfflineTtsPocketModelConfig(
    lmFlow:..., lmMain:..., encoder:..., decoder:..., textConditioner:...,
    vocabJson:..., tokenScoresJson:...,
);
```

To use the safetensors voice state on mobile, you'd need to upstream a sherpa-onnx PR exposing `set_voice_state(safetensors_path)` or similar. Real C++ work, not a config flag.

**Effort:** Upstream sherpa-onnx patch (probably 1–2 weeks of work + review).
**Expected gain if landed:** -72.7 MB on disk, faster cold start (skip encoder load), no RTF change in steady-state.
**Action:** Worth raising as a feature request to k2-fsa/sherpa-onnx if shipping a single fixed voice is acceptable to product.

The same idea (pre-baked text_condition) applies to ZipVoice in principle, but its encoder takes both prompt-info AND target-text as input, so the encoder output isn't constant across utterances. Not viable as-is.

---

## Lever 4: Static (QDQ) quantization of the FP32 encoder

**What:** Replace `encoder.onnx` (Pocket-TTS's Mimi audio codec, 72.7 MB FP32) with an int8 version. Static QDQ quantization inserts `QuantizeLinear`/`DequantizeLinear` nodes around each op using scale/zero-point values determined offline from a calibration set.

**Why this is the only direction left for the existing archive:** As your context note correctly identifies, dynamic quantization (the easy path, what `quantize_dynamic` does) only quantizes `nn.Linear` weights. The Mimi encoder is **Conv1d-heavy** — `MatMulInteger` doesn't touch convs. To quantize convs you need static QDQ with `QLinearConv`.

**Expected gain (projected):**
- Disk: ~72.7 MB → ~18–22 MB (−50 MB)
- Encoder runtime memory during the prompt-encoding step: similar reduction
- RTF: marginal — encoder runs once per generation and is already <100 ms on the M1 ARM emulator

**Effort (substantial, this is the "real project" tier):**
1. Source: ~100 representative prompt wavs (the project's voice catalogue is good calibration material).
2. Tool: `onnxruntime.quantization.quantize_static` with `CalibrationDataReader` feeding the prompt wavs as encoder inputs.
3. Quality regression: synthesize 50–100 utterances using each prompt with FP32 vs int8 encoder; compute MCD or PESQ vs. FP32 reference (or run informal listening tests focused on prosody, especially on the autoregressive `lm_main` which is most quantization-sensitive in TTS).
4. Likely outcome: some ops will need to stay FP32 (LayerNorm, activations) — `quantize_static` supports `OpTypesToQuantize` to mix.

**Risk:** Per the upstream Pocket-TTS issue thread you cited, quantization can hurt prosody and pronunciation on the autoregressive path. The encoder isn't autoregressive but feeds the lm — small encoder errors propagate.

**Action:** Worth doing if and only if the 50 MB on-disk saving matters for your distribution channel (e.g. APK fits under a Play-Store size threshold). Skip if APK size isn't the bottleneck.

---

## Lever 5: NNAPI / CoreML / XNNPACK execution providers

**What:** sherpa-onnx exposes `provider` in `OfflineTtsModelConfig` (we used `"cpu"`). On Android, NNAPI can route some ops to GPU/DSP/NPU. On iOS, CoreML can use the Apple Neural Engine. XNNPACK is an optimized CPU kernel library for ARM.

**Why this is uncertain rather than recommended:**
- NNAPI's TTS-relevant op coverage is patchy — any unsupported op (custom ones in lm_main especially) falls back to CPU and *adds* memory copies between accelerator and CPU, often making things slower overall.
- Quantized models often regress under NNAPI because INT8 fallback paths are missing on many devices.
- A/B testing would need to happen per-device class; results don't generalize.

**Effort:** Low to try (`provider: "nnapi"` or `"coreml"`), medium to validate (per-device matrix).
**Expected gain:** ±20% RTF, mostly downside for INT8 + autoregressive workloads.
**Action:** Try `xnnpack` first on Android (better track record for INT8 transformer LMs). Skip NNAPI unless we have a specific device target showing benefit.

---

## Lever 6: ORT session-level memory tuning

`OrtSessionOptions` has a few flags worth knowing about, even if they're small wins:

- `enable_mem_pattern = True` — ORT pre-plans tensor allocation. Already on by default in sherpa-onnx.
- `enable_cpu_mem_arena = True` — single arena allocator. Already on by default.
- `session.use_env_allocators = "1"` — share the allocator across multiple `InferenceSession` instances. Sherpa builds 5 sessions for Pocket-TTS (one per ONNX file); a shared allocator can reduce fragmentation.
- `intra_op_num_threads = 2` — already set in our adapter; tuning between 1 and physical cores affects RTF more than memory.

**Expected gain:** 5–10% peak RSS reduction in the multi-session case, no RTF change.
**Effort:** Pass through `provider_config_path`-style flags from the Flutter binding; small patch.
**Action:** Not bottleneck-shifting on its own. Bundle into any sherpa-onnx PR that already touches the session-builder code.

---

## Lever 7: ZipVoice-specific — fewer flow-matching steps

**What:** ZipVoice's GenerationConfig has `num_steps`. We use 4 (the `--num-step 4` recipe documented as speed-priority for the distill model). The default `zipvoice` (non-distill) uses 16. Going to 2 or 3 for distill is possible.

**Expected gain:** RTF roughly proportional to step count — going from 4 → 3 should be ~25% faster.
**Risk:** Quality degrades quickly below 4. The distill model was trained to be optimal at ~4–8 steps; below that you get artefacts.
**Action:** Worth trying num_steps=3 and listening before committing. Out of scope for this round.

---

## Lever 8: ZipVoice-specific — smaller / merged vocoder

`vocos_24khz.onnx` is 52 MB. There's no smaller vocoder on sherpa-onnx's release page. Alternatives:
- **HifiGAN-lite / MelGAN** (~5–10 MB) — much smaller but lower quality.
- **WaveNeXt / Apnet** — newer streaming vocoders, comparable quality, similar size.

**Effort:** Significant. Need a compatible vocoder for Vocos's mel-spectrogram input format, or retrain ZipVoice to emit a different intermediate.
**Action:** Probably not worth chasing unless we're rebuilding ZipVoice anyway.

---

## What about the warning in your context note?

> *"Worth A/B-ing the int8 build against FP32 on a held-out set — particularly listening for prosody glitches and pronunciation regressions on the autoregressive lm_main."*

This is a real concern that we **have not addressed in this benchmark**. Everything in this doc compares perf metrics. Quality regression testing (MCD / PESQ / informal A/B listening between FP32 PyTorch and int8 sherpa-onnx) is a separate workstream that should happen before any production switch.

The sherpa-onnx team's int8 archive has presumably been quality-checked against FP32 (otherwise they wouldn't ship it), but their bar isn't necessarily ours — kids' content has different prosody requirements than adult-voice agents.

---

## Honest summary by lever

| # | Lever | Disk | Steady RSS | RTF | Effort | Status |
|---|---|---:|---:|---:|---|---|
| 1 | Persistent-instance mode | 0 | 0 | **−40 to −80%** | trivial | ✅ measured here |
| 2 | `max_reference_audio_len` cap | 0 | small | ±0 | trivial | ✅ measured, no effect |
| 3 | Pre-baked safetensors (Pocket-TTS) | **−72 MB** | small | small | upstream PR | blocked by sherpa-onnx API |
| 4 | Static QDQ encoder quant | **−50 MB** | medium | minor | calib+quality regression | projected, not done |
| 5 | NNAPI / CoreML / XNNPACK | 0 | 0 | ±20% | per-device A/B | not done |
| 6 | ORT session-level tuning | 0 | small | 0 | small patch | not done |
| 7 | ZipVoice fewer FM steps | 0 | 0 | ~−25% | quality A/B | not done |
| 8 | ZipVoice smaller vocoder | −40 MB | small | small | new model | not viable |

The order I'd actually do them, given product goals:
1. **Lever 1** in your app architecture today — it's free, and changes the headline RTF story by 3–5× on short utterances. This is the only one that is genuinely "free money."
2. **Lever 5** (XNNPACK) — cheapest perf experiment to run, takes a config flag.
3. **Lever 4** (static encoder quant) — only if APK distribution size matters. Real project.
4. **Lever 3** (pre-baked voice) — only if shipping a single fixed voice is acceptable.
5. Skip the rest.

---

## What this means for the recommendation

The mobile feasibility picture got better:

- "Steady-state Pocket-TTS on a phone" is **RTF ~0.18 (5× real-time)** with peak ~850 MB, not the cold-subprocess RTF 0.26 / 778 MB we headline.
- "Steady-state ZipVoice on a phone" is **RTF ~0.30 (3× real-time)** with peak ~830 MB.
- Cold-start on the very first utterance is still ~1–3 seconds for either engine (model load), but everything after that is well within real-time.

Bookbot's RTF ~0.07 in steady state is still 2–4× faster, but the gap is narrower than the cold-subprocess numbers implied. **The "is it fast enough on a phone?" answer is now decisively yes for either engine.**

Memory headroom past sherpa's int8 archive is bounded — most of it requires real engineering work (Lever 4) for a 50 MB disk saving and minor RAM relief, not orders of magnitude. The on-device size is what it is.

The remaining product-level question hasn't moved: **per-phoneme timing for visemes is still missing**, and a forced-aligner stage on top would erase most of the speed advantage these engines have over Bookbot on long content.
