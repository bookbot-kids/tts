# On-device TTS Benchmark — Android device (sherpa-onnx)

**Date:** 2026-05-04
**Device:** Android pixel 8a device
**Runtime:** `sherpa_onnx` Flutter pub package v1.13.0 → native `libsherpa-onnx-c-api.so`
**Bench app:** `bench/flutter_bench/` (Flutter, release mode, auto-runs on launch)
**Audience:** anyone deciding whether to ship Pocket-TTS or ZipVoice in a mobile Flutter app

---

## The bottom line

**Both Pocket-TTS and ZipVoice run comfortably on Android** through sherpa-onnx — sub-real-time on long content and fitting in ~780 MB of RAM. The "is it fast enough on a phone?" blocker that gated this question is gone.

What's left is the integration cost: a native plugin rewrite, multi-file model bundle, and a forced-aligner stage to replace the per-phoneme timing the current Bookbot pipeline relies on.

---

## What was measured

Two engines, smallest available INT8 sherpa-onnx variants:

| Engine                             | Archive                                                               | Compressed | On disk |
| ---------------------------------- | --------------------------------------------------------------------- | ---------: | ------: |
| Pocket-TTS (Kyutai)                | `sherpa-onnx-pocket-tts-int8-2026-01-26`                              |    93.8 MB |  213 MB |
| ZipVoice (k2-fsa, distill, 4-step) | `sherpa-onnx-zipvoice-distill-int8-zh-en-emilia` + `vocos_24khz.onnx` |   158.3 MB |  206 MB |

**Test corpus:** 5 fixed English sentences, 12 → 520 chars (`s05`, `s15`, `s30`, `s60`, `s120`)
**Repeats:** 3 per sentence per engine = **30 measurements per engine, 60 total**
**Method:** `OfflineTts` instance rebuilt per call (so each measurement includes a cold model load), `wall_seconds = build_seconds + infer_seconds`. Peak RSS sampled from `/proc/self/status` (`VmHWM`).

How to reproduce: see [bench/flutter_bench/](../flutter_bench/) and [bench/README.md](../README.md).

---

## Headline numbers

### Speed (real-time factor — lower is faster)

`RTF = wall_seconds / audio_seconds`. RTF < 1 means faster than playback.

| Sentence                                | chars | Audio (s) | Pocket-TTS RTF | ZipVoice RTF |
| --------------------------------------- | ----: | --------: | -------------: | -----------: |
| `s05` ("Hello world.")                  |    12 |      ~0.7 |           1.43 |         2.79 |
| `s15` (one short sentence)              |    44 |      ~2.5 |           0.49 |         0.94 |
| `s30` (two sentences)                   |   100 |        ~5 |           0.37 |         0.66 |
| `s60` (paragraph)                       |   220 |       ~10 |       **0.30** |         0.50 |
| `s120` (long paragraph, ~25 s of audio) |   520 |       ~25 |       **0.26** |     **0.36** |

**Read this as:**
- A 25-second paragraph synthesizes in ~6.5 s on Pocket-TTS and ~9 s on ZipVoice — both ~3× faster than playback.
- A 10-second paragraph: ~3 s and ~5 s respectively.
- The "Hello world" / `s05` row is dominated by cold model load (~1–2 s); short utterances will *always* feel slower in this metric than long ones because the model load is amortized over less audio.

### Memory

Peak resident memory across the entire run (VmHWM in `/proc/self/status`):

- **Pocket-TTS: ~778 MB peak**
- **ZipVoice: ~779 MB peak**

Both fit comfortably under the **~1 GB** threshold where iOS aggressively kills foreground apps. Plenty of headroom for the rest of a typical Flutter app.

### Output quality / format

Both engines emit a single `Float32` PCM buffer at the engine's native sample rate (24 kHz). Identical surface — `samples` + `sample_rate` and nothing else.

---

## What sherpa-onnx does NOT give you on either engine

This bench surfaces three things that sherpa-onnx's `OfflineTts.generate(...)` does not return, regardless of engine:

1. **No per-phoneme timing.** ZipVoice never had it; Pocket-TTS uses subword tokens, not phonemes. Verified at `sherpa_onnx/lib/src/tts.dart:612` — the `GeneratedAudio` class has exactly two fields, `Float32List samples` and `int sampleRate`.
2. **No per-word timing.** Same reason — no token-level alignment is plumbed through. Even a "highlight the word as it speaks" UX would need a separate forced-aligner pass.
3. **No streaming chunks.** `generate()` returns the full utterance at once. Pocket-TTS's PyTorch path *does* support streaming via `generate_audio_stream`; sherpa-onnx's binding doesn't expose it. ZipVoice never streamed.

If your app needs any of those, you need a second model on top (forced aligner, e.g. Montreal Forced Aligner or a small whisper-timestamps model) or a different runtime.

---

## Voice / language constraints

|                               | Pocket-TTS / sherpa                                     | ZipVoice / sherpa                                              |
| ----------------------------- | ------------------------------------------------------- | -------------------------------------------------------------- |
| Default voice                 | `bria` (bundled in archive)                             | none — zero-shot, must supply a 3–10 s prompt wav + transcript |
| Other voices                  | 22 named voices listed in upstream README               | any wav clip, cloned at inference                              |
| Languages (this archive)      | English (multilingual model exists in non-int8 archive) | Chinese + English                                              |
| Voice prompt at inference     | required                                                | required                                                       |
| Inference shape               | autoregressive token-by-token + Mimi codec              | iterative flow-matching (4 steps) + Vocos vocoder              |
| Number of model files to ship | 5 ONNX (mixed int8/FP32)                                | 2 ONNX + 1 vocoder                                             |

Pocket-TTS is the lighter integration: one fixed voice ID, no prompt-wav management. ZipVoice always needs a paired (prompt-wav, prompt-text) bundle.

---

## What about Bookbot for context?

The current Bookbot Flutter plugin runs an FP32 `convnext-tts-en.onnx` (~71 MB) via ONNX Runtime mobile, in a single forward pass, and **emits per-phoneme `durations` natively** — that's how the existing visemes/lip-sync work. Detailed cross-engine perf and memory comparison lives in [comparison.md](comparison.md); for this doc the relevant takeaway is:

- Bookbot is faster (RTF ~0.07 on long content vs Pocket-TTS 0.26 / ZipVoice 0.36) and lighter (~280 MB vs ~780 MB peak).
- Bookbot is the only one of the three that gives you per-phoneme timestamps for free.
- Either competitor on mobile would be a different shape of plugin: new native bindings, multiple model files, prompt-wav handling, no native phoneme timing.

---

## What it would cost to ship one of these

If we decided to swap an existing Bookbot screen to one of these (Pocket-TTS being the lighter lift):

1. Add `sherpa_onnx: ^1.13.0` (Flutter pub package). Note: it conflicts with the current Bookbot plugin's bundled ONNX Runtime — both ship `libonnxruntime.so` for arm64-v8a, and Gradle refuses to merge them. Either drop the Bookbot plugin from that build, exclude one of the conflicting AARs in `android/app/build.gradle`, or fork sherpa-onnx Android to use the same onnxruntime version.
2. Bundle the ~213 MB (Pocket-TTS) or ~206 MB (ZipVoice + vocoder) of model files. Either bake them into the APK (will push it past Play Store's APK-only 200 MB limit — needs an App Bundle) or download on first launch.
3. Pre-bake voice state — for Pocket-TTS, `pocket-tts export-voice` produces a small `.safetensors` for fast cold start; for ZipVoice, ship a default prompt wav + transcript.
4. Replace the per-phoneme timing path that drives visemes today. Either add a forced-aligner stage on the synthesized audio (extra latency, extra binary size) or rebuild the lip-sync to use word-level / time-coded approximations.
5. Initialize sherpa-onnx once per app launch (`sherpa_onnx.initBindings()` in `main()` before any `OfflineTts` is constructed).

**One concrete pitfall we hit during this bench**: the sherpa-onnx Flutter package requires `initBindings()` to be called explicitly before any `OfflineTts` instance is built. Without it every call fails with `Exception: Please initialize sherpa-onnx first` — and that error is not in the upstream README's quickstart. Worth noting in any plugin we build on top.

---

## Recommendation

| Question                                         | Answer                                                                                                                                                                                                                                                       |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Is sherpa-onnx fast enough for mobile?           | **Yes** — RTF 0.26–0.36 on long content, peak 780 MB.                                                                                                                                                                                                        |
| Is the smallest available variant good enough?   | **Yes** — Pocket-TTS int8 archive is the only build, and it works fine. ZipVoice distill+4-step is the speed-priority config and matches Bookbot's single-pass shape better than the 16-step default.                                                        |
| Does either give us word or phoneme timing?      | **No** — verified across Dart and Python bindings.                                                                                                                                                                                                           |
| Should we adopt one *today* in place of Bookbot? | **No** — Bookbot is faster, lighter, and ships native phoneme timing. The cost of switching is real (plugin rewrite + aligner + bigger binary) and the benefit (better voices, voice cloning, more languages) is not currently load-bearing for the product. |
| When is it worth revisiting?                     | When the product needs voice cloning, or multilingual coverage with one model, or naturalness levels Bookbot can't reach. Then the integration cost stops being a "no" and becomes "what's the budget?".                                                     |

---

## Reproducibility

- Bench app: [bench/flutter_bench/lib/main.dart](../flutter_bench/lib/main.dart). Auto-runs on launch.
- Models pushed via adb to `/data/local/tmp/bench/sherpa_models/` (~420 MB) before launch.
- Raw measurements: [results_android.csv](results_android.csv) (30 rows: 2 engines × 5 sentences × 3 repeats).
- Merged into [results.csv](results.csv) for cross-runtime comparison.
- Build: `flutter build apk --release` from `bench/flutter_bench/` (134 MB APK including the sherpa-onnx ARM64 native libs).
