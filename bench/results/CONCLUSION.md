# TTS Comparison: Bookbot vs ZipVoice vs Pocket-TTS — Conclusion

**Date:** 2026-05-04
**Author:** benchmark in this repo at `bench/`
**Audience:** anyone deciding whether to keep Bookbot's current TTS or switch

---

## The bottom line

**Keep the current Bookbot TTS.** ZipVoice and Pocket-TTS are impressive research, but for what this app does — read text aloud to kids with synced mouth animation — they would each be a downgrade across the things that matter, and an upgrade only on things this product doesn't need.

You should not swap the model in `example/android/app/src/main/assets/` to either. You also should not invest in switching the runtime layer to host one of them, unless the product's goals change.

---

## Why we ran this

Four questions came in:

1. *Can ZipVoice or Pocket-TTS run on mobile like our current TTS plugin?*
2. *Can we just drop their model file into the app's assets folder and have it work?*
3. *What if we use **sherpa-onnx** (the actual mobile-deployment runtime both upstream READMEs point to)?*
4. *And what do those numbers actually look like running on a real Android device?*

We benchmarked everything three ways — once via each project's research codebase (PyTorch on host CPU), once through sherpa-onnx + INT8 on host CPU, and **once on an Android emulator** (arm64-v8a, the production mobile target) using the smallest available INT8 archives:

- `sherpa-onnx-pocket-tts-int8-2026-01-26` (93.8 MB compressed — the only int8 build available, with mixed int8/fp32 weights)
- `sherpa-onnx-zipvoice-distill-int8-zh-en-emilia` (104.1 MB compressed — distilled, 4-step inference)

We deliberately picked the smallest variants because that is what would actually ship.

---

## What we found

### Speed (real-time factor — lower is faster)

For a typical paragraph (~10 seconds of audio), CPU only:

| Engine | Time to synthesize | Speed vs. playback |
|---|---|---|
| **Bookbot (host)** | ~1.5 s | **~14× faster than real-time** |
| **Pocket-TTS / sherpa-onnx Android** | ~3 s | **~3.8× faster than real-time** |
| Pocket-TTS / sherpa-onnx host | ~3.5 s | ~3.5× faster than real-time |
| **ZipVoice / sherpa-onnx Android** | ~3.5 s | **~2.8× faster than real-time** |
| Pocket-TTS / PyTorch host | ~6 s | ~1.7× faster than real-time |
| ZipVoice / sherpa-onnx host | ~4.5 s | ~2.3× faster than real-time |
| ZipVoice / PyTorch host | ~11 s | slightly slower than real-time |

Bookbot is **~4× faster than Pocket-TTS / sherpa Android** and **~5× faster than ZipVoice / sherpa Android** at this length. The gap widens on longer text and shrinks on short text (where everyone is dominated by model load time).

**The Android sherpa-onnx numbers are the ones to anchor mobile decisions to** — they're what would actually run on a phone. Two surprises in the on-device data:

1. Sherpa-onnx running through the Flutter plugin on the emulator is **1.5–1.8× faster than the same sherpa-onnx code wrapped by Python on the host** — the Flutter ↔ native bridge is leaner than Python's. So "host sherpa-onnx" understates how good these would be on a phone.
2. Both engines on Android peak at roughly **780 MB of resident memory** — comfortably under the 1 GB threshold where iOS starts killing apps.

Even with both surprises, Bookbot still wins on speed by a comfortable margin.

### Memory

Per synthesis, peak resident memory:

| Engine | Peak memory | vs. Bookbot |
|---|---|---|
| **Bookbot (host)** | ~280 MB | 1× |
| **Pocket-TTS / sherpa-onnx Android** | ~780 MB | 2.8× heavier |
| **ZipVoice / sherpa-onnx Android** | ~780 MB | 2.8× heavier |
| Pocket-TTS / sherpa-onnx host | ~840 MB | 3× heavier |
| Pocket-TTS / PyTorch host | ~880 MB | 3× heavier |
| ZipVoice / sherpa-onnx host | ~715 MB median, ~930 MB peak | 2.5–3× heavier |
| ZipVoice / PyTorch host | ~1.3 GB median, peaking 2.5 GB | 5–9× heavier |

On a real phone, both sherpa-onnx engines fit in **~780 MB of resident memory** — comfortably under the 1 GB threshold where iOS starts killing apps. Sherpa + INT8 brings ZipVoice all the way from "scary" (1.3 GB on host PyTorch) to "manageable" on Android. Bookbot is still ~3× lighter, which matters on low-end devices and when other parts of the app are also using memory.

### Mouth animation / lip-sync

This is the one that decides the question.

- **Bookbot tells you exactly how long each phoneme lasts.** That's how the visemes drive the mouth animation. It's a native model output, not a workaround.
- **ZipVoice doesn't.** It can predict total length only — there's no per-phoneme alignment. You'd have to run a separate forced-aligner on the synthesized audio just to recover what Bookbot already gives you for free. Sherpa-onnx exposes the same ZipVoice model, so it has the same limitation.
- **Pocket-TTS doesn't either.** It uses subword tokens (not phonemes) and the API only returns audio. Same forced-aligner workaround applies, with the extra wrinkle that subwords don't map cleanly back to IPA visemes. Same on PyTorch and sherpa-onnx.

For an app that animates a character's mouth while speaking, this isn't a "nice to have" — it's the load-bearing feature. Switching engines means rebuilding it from scratch.

---

## "Can we just swap the model file?"

No. Tested literally and captured the failure.

The Android plugin's loader expects an ONNX model with very specific input/output names: `x`, `x_lengths`, `scales`, `sids`, `lids` going in; `wav` and `durations` coming out. Both competitors use completely different names — ZipVoice splits its model into 3 files with names like `tokens`, `prompt_tokens`, `text_condition`; Pocket-TTS uses streaming codec frames and KV-cache state.

Renaming a file to `convnext-tts-en.onnx` does not change what's inside. The loader fails immediately with `Required inputs are missing`.

A real swap would mean rewriting the native Android (`Opti.kt`) and iOS (`Opti.swift`) code to match the new engine's interface — not a model swap, a plugin rewrite.

---

## "Can they run on mobile at all?"

Yes — and the **sherpa-onnx** runtime is how. Both upstream projects officially recommend it, and our sherpa-onnx benches show it works (sub-real-time on long content, ~700–840 MB peak memory).

But it is **not "the same way" as Bookbot**. Adopting either engine on mobile would mean:

1. Replacing ONNX Runtime with **sherpa-onnx** in our native code (Kotlin/Swift bindings exist).
2. Shipping multiple model files instead of one (Pocket-TTS: 5 ONNX files, ~213 MB total; ZipVoice: 2 ONNX files + Vocos vocoder, ~206 MB total — both INT8).
3. Redesigning the Flutter ↔ native call boundary (Pocket-TTS streams audio chunks; ZipVoice runs an iterative decoder).
4. Bundling a reference voice clip + transcript (both engines clone from a prompt; there's no fixed voice).
5. Adding a forced aligner to keep visemes working.

Doable. Not small.

---

## Where the others would actually win

Each engine is good at things Bookbot doesn't try to do:

- **Voice cloning from a 3–10 second sample.** ZipVoice's headline feature. If the product wanted user-cloned voices ("read it in dad's voice"), neither Bookbot nor Pocket-TTS can do that.
- **Multilingual coverage with one model.** Pocket-TTS ships English, French, German, Portuguese, Italian, Spanish in one drop-in. Bookbot needs a separate ~71 MB model per language.
- **Streaming-first applications.** Pocket-TTS yields ~80 ms audio chunks, useful if the latency budget for the *first sound* matters more than total throughput.

If a future Bookbot needs any of those, this comparison is worth revisiting.

---

## Recommendation

| For this product, today | Verdict |
|---|---|
| Swap the model file | **No** — the loader rejects it; verified |
| Replace the engine on mobile via sherpa-onnx | **Possible** — but a plugin rewrite + visemes need a forced-aligner replacement |
| Adopt one for a *new* product feature (voice cloning, more languages, streaming) | **Worth a deeper look** when that feature gets prioritized |
| Keep the current TTS | **Yes** — wins on speed, memory, and the lip-sync we already ship |

---

## Where to dig deeper

- Full benchmark numbers and methodology: [comparison.md](comparison.md)
- Mobile feasibility + the drop-in failure reproduction: [mobile_feasibility.md](mobile_feasibility.md)
- Raw per-run measurements: [results.csv](results.csv) (70 rows: 5 engines × 5 sentences × 2–3 repeats)
- Plots: [rtf_vs_length.png](rtf_vs_length.png), [rss_vs_length.png](rss_vs_length.png)
- Reproduce: [bench/README.md](../README.md)

---

## Caveats worth knowing

- All numbers are CPU-only on a MacBook (Apple M1 Pro, 32 GB). Real phones will be slower in absolute terms, but the *ratios* between engines are the part we care about.
- Bookbot here was exercised through Python `onnxruntime`, not the actual Flutter plugin. That strips the Method Channel + AudioTrack overhead — fair vs. the other Python engines, but slightly understates real on-device latency.
- We did not measure **audio quality**. ZipVoice and Pocket-TTS are likely more natural-sounding to an adult ear than Bookbot's small ConvNext model. For a kids' reading app the trade-off may still favor Bookbot, but a listening test is the next step if quality is in scope.
- ZipVoice was run with the *fast* configuration in both runtimes (`distill`, 4 steps). The default 16-step `zipvoice` would be roughly 2× slower than reported here.
- Sherpa-onnx models are INT8-quantized; PyTorch models are FP32. Some of the speed/memory gap between the two ZipVoice rows comes from quantization.
