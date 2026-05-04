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

Two questions came in:

1. *Can ZipVoice or Pocket-TTS run on mobile like our current TTS plugin?*
2. *Can we just drop their model file into the app's assets folder and have it work?*

We benchmarked all three engines on the same machine, same sentences, same CPU, and read each project's source code to answer the mobile/drop-in questions properly.

---

## What we found

### Speed (real-time factor — lower is faster)

For a typical paragraph (~10 seconds of audio):

- **Bookbot finishes in ~1.5 seconds.** Roughly 6× faster than playback.
- **Pocket-TTS finishes in ~6 seconds.** About 1.7× faster than playback.
- **ZipVoice finishes in ~11 seconds.** Slightly slower than playback.

Bookbot is **3× faster than Pocket-TTS** and **6× faster than ZipVoice** at this length. The gap widens on longer text and shrinks on very short text (where everyone is dominated by model load time).

### Memory

Per synthesis, peak resident memory on the test machine:

- **Bookbot: ~280 MB**
- **Pocket-TTS: ~880 MB** (3× heavier)
- **ZipVoice: 1.3 GB median, peaking 2.5 GB** on long input (5–9× heavier)

That difference matters on phones, where 1.3 GB+ is dangerously close to where iOS will kill the app.

### Mouth animation / lip-sync

This is the one that decides the question.

- **Bookbot tells you exactly how long each phoneme lasts.** That's how the visemes drive the mouth animation. It's a native model output, not a workaround.
- **ZipVoice doesn't.** It can predict total length only — there's no per-phoneme alignment. You'd have to run a separate forced-aligner on the synthesized audio just to recover what Bookbot already gives you for free.
- **Pocket-TTS doesn't either.** It uses subword tokens (not phonemes) and the API only returns audio. Same forced-aligner workaround applies, with the extra wrinkle that subwords don't map cleanly back to IPA visemes.

For an app that animates a character's mouth while speaking, this isn't a "nice to have" — it's the load-bearing feature. Switching engines means rebuilding it from scratch.

---

## "Can we just swap the model file?"

No. Tested literally and captured the failure.

The Android plugin's loader expects an ONNX model with very specific input/output names: `x`, `x_lengths`, `scales`, `sids`, `lids` going in; `wav` and `durations` coming out. Both competitors use completely different names — ZipVoice splits its model into 3 files with names like `tokens`, `prompt_tokens`, `text_condition`; Pocket-TTS uses streaming codec frames and KV-cache state.

Renaming a file to `convnext-tts-en.onnx` does not change what's inside. The loader fails immediately with `Required inputs are missing`.

A real swap would mean rewriting the native Android (`Opti.kt`) and iOS (`Opti.swift`) code to match the new engine's interface — not a model swap, a plugin rewrite.

---

## "Can they run on mobile at all?"

Yes, but not the same way.

Neither project ships first-party Android or iOS code. Both upstream READMEs point to **`sherpa-onnx`** (k2-fsa) for mobile deployment — a separate native runtime with Kotlin/Swift/Dart bindings.

Adopting either engine on mobile would mean:

1. Replacing ONNX Runtime with `sherpa-onnx` in our native code.
2. Shipping multiple model files instead of one (~hundreds of MB even at INT8).
3. Redesigning the Flutter <-> native call boundary (Pocket-TTS streams; ZipVoice runs iteratively).
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
| Replace the engine on mobile | **No** — would need plugin rewrite + lose visemes |
| Adopt one for a *new* product feature (voice cloning, more languages, streaming) | **Worth a deeper look** when that feature gets prioritized |
| Keep the current TTS | **Yes** — wins on speed, memory, and the lip-sync we already ship |

---

## Where to dig deeper

- Full benchmark numbers and methodology: [comparison.md](comparison.md)
- Mobile feasibility + the drop-in failure reproduction: [mobile_feasibility.md](mobile_feasibility.md)
- Raw per-run measurements: [results.csv](results.csv) (40 rows, 5 sentences × 2–3 repeats × 3 engines)
- Plots: [rtf_vs_length.png](rtf_vs_length.png), [rss_vs_length.png](rss_vs_length.png)
- Reproduce: [bench/README.md](../README.md)

---

## Caveats worth knowing

- All numbers are CPU-only on a MacBook (Apple M1 Pro, 32 GB). Real phones will be slower in absolute terms, but the *ratios* between engines are the part we care about.
- Bookbot here was exercised through Python `onnxruntime`, not the actual Flutter plugin. That strips the Method Channel + AudioTrack overhead — fair vs. the other Python engines, but slightly understates real on-device latency.
- We did not measure **audio quality**. ZipVoice and Pocket-TTS are likely more natural-sounding to an adult ear than Bookbot's small ConvNext model. For a kids' reading app the trade-off may still favor Bookbot, but a listening test is the next step if quality is in scope.
- ZipVoice was run with the *fast* configuration (`zipvoice_distill --num-step 4`). The default 16-step `zipvoice` would be roughly 2× slower than reported here.
