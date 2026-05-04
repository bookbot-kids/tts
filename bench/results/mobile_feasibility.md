# Mobile feasibility: ZipVoice and Pocket-TTS vs. Bookbot

## Question
> Can ZipVoice or Pocket-TTS run on Android/iOS in the same way as the
> current Bookbot Flutter plugin (ONNX Runtime, on-device, single Flutter
> package)?

## Short answer
**Not as a drop-in.** Both are technically capable of on-device CPU inference, but reaching that requires a different runtime layer than the existing Bookbot `Opti.kt` / `Opti.swift`. The realistic path for either is **[k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)**, which provides Kotlin, Swift, and Dart bindings for both engines.

## ZipVoice

### What ships in the repo
- `runtime/` contains only `nvidia_triton/` — server-side GPU deployment.
- No `android/`, `ios/`, no Kotlin or Swift.
- `zipvoice/bin/onnx_export.py` exports the model as **3 separate ONNX files** (text encoder + flow-matching decoder run iteratively + Vocos vocoder). INT8 quantization is supported via `--onnx-int8 True`.
- README §"Production Deployment" → "CPU Deployment" explicitly redirects mobile/embedded users to sherpa-onnx (PR #2487).

### What it would cost to reach mobile
1. Add **sherpa-onnx** Android AAR / iOS xcframework dependency.
2. Replace the ONNX Runtime calls in [Opti.kt](../../android/src/main/kotlin/com/tensorspeech/tensorflowtts/module/Opti.kt) and [Opti.swift](../../ios/Classes/Opti.swift) with sherpa-onnx API calls — different I/O contract.
3. Ship 3 model files in `example/android/app/src/main/assets/` and the iOS bundle. Even at INT8, several hundred MB combined.
4. Bundle a default **reference prompt wav** plus its transcript (zero-shot cloning is mandatory; there is no fixed voice).
5. Accept iterative inference (4–8 flow-matching steps per utterance) and design accordingly.

## Pocket-TTS

### What ships in the repo
- README §"Main takeaways": *"Runs on CPU, ~6× real-time on a MacBook Air M4, uses only 2 CPU cores, can run client-side in browser."*
- No `android/`, `ios/`, no Kotlin/Swift code in the repo.
- README "Alternative implementations" lists, in order:
  - [`sherpa-onnx`](https://github.com/k2-fsa/sherpa-onnx) — Kotlin, Swift, **Dart**, plus 9 other languages, runs on Windows/macOS/Linux/Raspberry Pi/Jetson/RK3588.
  - [`pocket-tts-onnx-export`](https://github.com/KevinAHM/pocket-tts-onnx-export) — community ONNX export.
  - [`pocket-tts-mlx`](https://github.com/jishnuvenugopal/pocket-tts-mlx) — Apple Silicon (macOS only, **not iOS**).
  - [`PocketTTS.cpp`](https://github.com/VolgaGerm/PocketTTS.cpp) — single-file ONNX Runtime C++ runtime.
- The pure-PyTorch reference implementation is not realistic for mobile shipping (PyTorch Mobile is large and slow).

### What it would cost to reach mobile
1. Switch the runtime to either sherpa-onnx (recommended) or build against PocketTTS.cpp.
2. Ship the LM + Mimi codec ONNX files (community export).
3. Re-design the Method Channel boundary to support **streaming chunks** — Pocket-TTS yields ~80 ms audio chunks, which doesn't match Bookbot's "one call returns full wav + durations" contract.
4. Pick or pre-bake a default voice (`alba` is the documented default; voice files can be exported to `.safetensors` via `pocket-tts export-voice` for fast cold-start).

## Side-by-side runtime fit

| Axis | Bookbot today | ZipVoice on mobile | Pocket-TTS on mobile |
|---|---|---|---|
| Native runtime | ONNX Runtime (Java / Obj-C) | sherpa-onnx (Kotlin / Swift / Dart) | sherpa-onnx (Kotlin / Swift / Dart) |
| Number of model files | 1 (`convnext-tts-en.onnx`, 71 MB) | 3 (text enc + FM dec + vocoder) | 2 (LM + Mimi codec) |
| Inference shape | single forward | iterative flow-matching (4–8 steps/utterance) | autoregressive token-by-token |
| Voice prompt at inference | not needed (speaker id) | required (ref wav + transcript) | required (or pre-baked safetensors) |
| Languages | EN / ID / SW (one model each) | EN / ZH | EN / FR / DE / PT / IT / ES |
| Streaming output | no | no | yes |
| Sample rate | 44.1 kHz | 24 kHz (Vocos) | 24 kHz (Mimi) |
| INT8 quant available | yes (some assets) | yes (`--onnx-int8 True`) | yes (community export) |
| Per-phoneme timing | **yes (native)** | no | no |
| Mobile demo provided by upstream | n/a (bookbot is the demo) | no | no |

## Implication for the Flutter plugin

If we wanted either engine inside this plugin, the work is roughly:

1. **Add a sherpa-onnx dependency** (Android AAR + iOS xcframework). This replaces the ONNX Runtime mobile dependency we use today.
2. **Replace [Opti.kt](../../android/src/main/kotlin/com/tensorspeech/tensorflowtts/module/Opti.kt) and [Opti.swift](../../ios/Classes/Opti.swift)** with sherpa-onnx calls. The current code is ~80 lines per platform; the rewrite is similar size but against a different API.
3. **Ship the new model files.** Bookbot today: one 71 MB asset. ZipVoice: 3 files, hundreds of MB at FP32. Pocket-TTS: 2 files, ~150–250 MB combined depending on quant.
4. **Re-design the Method Channel boundary** to support either streaming chunks (Pocket-TTS) or multi-step FM (ZipVoice). Neither matches today's "one call returns wav + durations" contract.
5. **Decide what to do about visemes/lip-sync**, since neither model produces per-phoneme timings (see [comparison.md](comparison.md) §"Phoneme timing support"). Either run a forced aligner on the synthesized audio (extra latency + extra binary size) or drop visemes for the new engine.

## TL;DR for the user's two questions

> *"Can they run on mobile device like this Bookbot TTS?"*

Technically yes — both via sherpa-onnx. But it is **not "the same way" as Bookbot**: it requires a new native runtime, new model files, new Method Channel shape, and a replacement for the per-phoneme timing that visemes depend on.

> *"Can replacing their TTS model into Bookbot's `example/android/app/src/main/assets` and run on mobile?"*

**No.** See [Task 6 / Drop-in model-swap section below](#drop-in-model-swap-into-exampleandroidappsrcmainassets) — Bookbot's loader hard-codes the ONNX I/O contract `{x, x_lengths, scales, sids, lids}` → `{wav, durations}`. Neither competitor's exported ONNX matches that contract; the load fails immediately.
