# TTS Comparison: Bookbot vs. ZipVoice vs. Pocket-TTS

**Date:** 2026-05-04
**Hardware (host):** macOS Darwin 25.4.0, Apple M1 Pro, 32 GB RAM
**Hardware (mobile):** Android emulator (sdk gphone64 arm64, Android 16, arm64-v8a) on the same M1 Pro host
**Test corpus:** 5 English sentences (12–520 chars), 2–3 repeats each
**Seven runtimes compared:**

1. **Bookbot** — production ONNX via `onnxruntime` (host CPU)
2. **Pocket-TTS / PyTorch** — upstream `pocket_tts.TTSModel` Python API (host CPU)
3. **Pocket-TTS / sherpa-onnx host** — INT8 ONNX through k2-fsa's runtime in Python (host CPU)
4. **Pocket-TTS / sherpa-onnx Android** — INT8 ONNX through the `sherpa_onnx` Flutter plugin **on the Android emulator**
5. **ZipVoice / PyTorch** — upstream `zipvoice.bin.infer_zipvoice` distill, 4-step (host CPU)
6. **ZipVoice / sherpa-onnx host** — INT8 ONNX + Vocos in Python (host CPU)
7. **ZipVoice / sherpa-onnx Android** — INT8 ONNX + Vocos via the `sherpa_onnx` Flutter plugin **on the Android emulator**

Smallest available variants used for both engines: `sherpa-onnx-pocket-tts-int8-2026-01-26` (93.8 MB compressed) and `sherpa-onnx-zipvoice-distill-int8-zh-en-emilia` (104.1 MB compressed).

## Headline table

| Engine | Default voice | Phoneme timing | Median RTF | p95 RTF | Median peak RSS | Max peak RSS |
|---|---|---|---:|---:|---:|---:|
| **Bookbot TTS** (host) | `convnext-tts-en/us` | **YES** (per-phoneme, native) | **0.35** | 2.63 | **280 MB** | 321 MB |
| **Pocket-TTS / sherpa-onnx Android** | `bria` | NO | **0.37** | 1.53 | 778 MB | 779 MB |
| Pocket-TTS / sherpa-onnx host | `bria` | NO | 0.67 | 3.76 | 843 MB | 887 MB |
| **ZipVoice / sherpa-onnx Android** | demo prompt clone | NO | **0.66** | 2.83 | 779 MB | 779 MB |
| Pocket-TTS / PyTorch host | `alba` | NO | 0.91 | 3.31 | 881 MB | 934 MB |
| ZipVoice / sherpa-onnx host | demo prompt clone | NO | 1.00 | 5.45 | 715 MB | 933 MB |
| ZipVoice / PyTorch host (distill 4-step) | demo prompt clone | NO | 2.27 | 14.80 | 1294 MB | 2518 MB |

`RTF = wall_seconds / audio_seconds`. Lower is faster. RTF < 1 is faster than real-time.

p95 RTF is dominated by cold-start of the shortest utterance (`s05` = "Hello world"). Each measurement runs in a fresh subprocess, so p95 reflects "first utterance after launch", not steady-state.

See [rtf_vs_length.png](rtf_vs_length.png) and [rss_vs_length.png](rss_vs_length.png) for the per-engine curves.

## RTF by sentence length (medians)

| Sentence id | chars | Bookbot host | Pocket-TTS sherpa **Android** | Pocket-TTS sherpa host | Pocket-TTS PyTorch | ZipVoice sherpa **Android** | ZipVoice sherpa host | ZipVoice PyTorch |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| s05 | 12 | 2.37 | 1.43 | 3.59 | 3.26 | 2.79 | 5.14 | 14.75 |
| s15 | 44 | 0.58 | 0.49 | 1.13 | 1.44 | 0.94 | 1.64 | 3.84 |
| s30 | 100 | 0.35 | 0.37 | 0.67 | 0.91 | 0.66 | 1.00 | 2.27 |
| s60 | 220 | 0.16 | 0.30 | 0.41 | 0.59 | 0.50 | 0.65 | 1.08 |
| s120 | 520 | **0.07** | **0.26** | 0.29 | 0.37 | **0.36** | 0.43 | 1.18 |

At long-sentence steady state (s120):
- **Bookbot ≈ 14× real-time** (host)
- **Pocket-TTS / sherpa-onnx Android ≈ 3.8× real-time** — only 3.5× slower than Bookbot
- **ZipVoice / sherpa-onnx Android ≈ 2.8× real-time** — only 5× slower than Bookbot

## Sherpa-onnx on real Android vs. host Python

The Android emulator numbers (Pocket-TTS Android vs. Pocket-TTS sherpa host, ZipVoice Android vs. ZipVoice sherpa host) all run the **same** INT8 ONNX models through the **same** sherpa-onnx C++ runtime — the difference is the binding layer (Flutter/native vs. Python wrapper) and the host environment (Android arm64 vs. macOS arm64). Running on the emulator is consistently **1.5–2× faster** than the host Python path:

| Engine | Host RTF | Android RTF | Android speedup |
|---|---:|---:|---:|
| Pocket-TTS / sherpa-onnx | 0.67 | 0.37 | **1.8×** |
| ZipVoice / sherpa-onnx | 1.00 | 0.66 | **1.5×** |

Two reasons:
1. The Flutter plugin uses the native `libsherpa-onnx-c-api.so` directly through dart:ffi, with no Python interpreter or numpy boxing in the hot path.
2. The emulator's arm64-v8a runs natively on Apple Silicon (HVF), so it isn't slowed down by translation.

The Android emulator is therefore a *closer* proxy to a real arm64 phone than the host Python bench. The Android numbers above are the ones to anchor mobile decisions to.

## What sherpa-onnx changes (PyTorch → sherpa)

Switching from the research PyTorch path to the production sherpa-onnx + INT8 path (host CPU comparison):

- **Pocket-TTS:** ~25% faster on long content (0.37 → 0.29 RTF). Memory roughly the same. The PyTorch implementation is already efficient on CPU, so sherpa adds modest gains.
- **ZipVoice:** ~2.7× faster on long content (1.18 → 0.43 RTF), and **~2× lighter on memory** (1.3 GB → 715 MB median; 2.5 GB → 933 MB peak). This is a much bigger win because PyTorch ZipVoice was carrying flow-matching activations + a heavy Vocos vocoder; sherpa runs the INT8 ONNX directly with a separate vocoder ONNX.

Adding the **Android** layer on top closes another 1.5–1.8×.

In short: **sherpa-onnx on Android is the right comparison for mobile**, and it materially closes the gap with Bookbot. Bookbot is still ~4× faster than Pocket-TTS / sherpa Android and ~5× faster than ZipVoice / sherpa Android on long content, with ~2.8× lower memory — but both competitors are now safely in the "fits on a phone" range (peak ~780 MB, RTF < 0.5).

## Phoneme and word timing support

- **Bookbot: native, per-phoneme.** The ONNX model returns a `durations` int64 tensor (frames per phoneme). [lib/tts.dart](../../lib/tts.dart) converts it to per-token seconds at `hop=512, sr=44100`. This is what drives the viseme/lip-sync output the rest of the app relies on.
- **ZipVoice (all runtimes): no.** The flow-matching model only predicts an aggregate feature length; per-token alignment is uniform `floor(features_len / tokens_len)`, not learned. The sherpa-onnx C API's `GeneratedAudio` struct exposes only `samples` and `sample_rate` — no word or phoneme timestamps. To recover per-phoneme timestamps you would have to run a forced aligner on the synthesized audio.
- **Pocket-TTS (all runtimes): no.** Tokenizer is SentencePiece subword (not phonemes), and `tts.generate()` returns only audio — no token alignment in PyTorch, in sherpa-onnx host Python, or in the sherpa-onnx Flutter binding. Same forced-aligner workaround applies, with the extra wrinkle that subwords don't map cleanly back to IPA visemes.

**Word timing specifically:** also no. Sherpa-onnx's `GeneratedAudio` (Dart `class GeneratedAudio { Float32List samples; int sampleRate; }` — see `sherpa_onnx/lib/src/tts.dart:612`; same shape in Python's `sherpa_onnx.lib._sherpa_onnx.GeneratedAudio`) does not surface any per-word or per-token timestamp array. The C API call site has no out-parameter for alignment either. So even a "word-level highlight as it speaks" UI would need a forced-aligner pass on top.

This is the single most important axis for Bookbot's current product: visemes/lip-sync depend on per-phoneme timing. Either competitor would need a forced-aligner stage *and* a re-mapping from word-level timestamps back to IPA visemes.

## Memory

Cold-start measurement (one fresh subprocess per call) so peak RSS reflects model load + one synthesis:

- **Bookbot ~280 MB** — onnxruntime + a 71 MB single ONNX model.
- **Pocket-TTS / sherpa-onnx ~843 MB** — sherpa-onnx + 5 ONNX files totaling ~213 MB on disk. The archive is **mixed-precision int8**, not full int8 (consistent with upstream's open issue on int8 support): `lm_main.int8.onnx`, `lm_flow.int8.onnx`, `decoder.int8.onnx` are quantized; `encoder.onnx` (Mimi audio codec for prompt encoding) and `text_conditioner.onnx` are FP32. There is no smaller variant available upstream.
- **Pocket-TTS / PyTorch ~881 MB** — full PyTorch + 100 M-param flow-LM + Mimi codec.
- **ZipVoice / sherpa-onnx ~715 MB median, ~933 MB peak** — sherpa-onnx + 2 INT8 ONNX files + Vocos vocoder ONNX (~206 MB on disk total).
- **ZipVoice / PyTorch ~1.3 GB median, peaking 2.5 GB** — full PyTorch + 123 M-param model + Vocos.

Bookbot is **2.5–3×** lighter than either competitor's sherpa path, **4–9×** lighter than the PyTorch paths.

## Real-time factor

Beyond the cold-start range (sentences ≥ s30, ≥ 100 chars), **on the production sherpa-onnx path**:
- Bookbot is **3–14× faster than real-time** depending on length.
- Pocket-TTS / sherpa is **1.1–3.5× faster than real-time**.
- ZipVoice / sherpa-onnx is **roughly real-time on s30 and 1.5–2.3× faster than real-time on long content**.

Mobile-side numbers will be slower in absolute terms, but the *ratios* between engines should hold roughly.

## Caveats

- **Bookbot path is stripped of Flutter overhead.** The comparison runs the same ONNX file via Python `onnxruntime`, so it does not include the platform-channel + AudioTrack/AVAudioEngine cost the real plugin pays. This makes the inference numbers fair vs. the other Python engines but slightly understates Bookbot's end-to-end latency on a real device.
- **Bookbot text-to-IPA uses espeak.** The production app uses a bundled word DB first, falling back to a phonemizer for unknowns. Espeak everywhere here may produce a slightly different phoneme count, but length and RTF land in the same ballpark.
- **ZipVoice is zero-shot voice cloning, not a fixed voice.** The PyTorch and sherpa-onnx ZipVoice rows both clone the **same** target voice (the Bookbot s15 output, `bench/voices/zipvoice_default.wav`) so the two ZipVoice rows compare on equal footing.
- **Pocket-TTS sherpa uses voice `bria` (bundled with the sherpa archive); Pocket-TTS PyTorch uses voice `alba`.** Both are from the upstream voice catalog. Voice choice has minimal impact on RTF or memory.
- **All sherpa-onnx models are INT8 quant.** Upstream provides only INT8 weights for these. PyTorch rows are FP32. INT8 explains a chunk of the speed/memory gap between sherpa and PyTorch.
- **All on CPU.** GPU/MPS would help ZipVoice and Pocket-TTS some; Bookbot is CPU-only by design.
- **Cold start dominates short sentences.** Each measurement loads the model fresh. That reflects "first utterance after launch", not warm steady-state.
- **Quality (MOS / naturalness) was not measured.**

## Recommendation

If the product still needs **per-phoneme timing for visemes/lip-sync**, **mobile-friendly memory**, and **single-pass low-latency inference**, Bookbot is the clear keeper. Even on the production sherpa-onnx path, both competitors lose 3–6× on long-content speed and 2.5–3× on memory, plus they do not produce per-phoneme alignment.

The sherpa-onnx numbers do change the picture in one important way: they show that **migrating to either engine on mobile is technically practical** (sub-real-time on long content, sub-1 GB memory), so the blocker is no longer "it's too slow" but "the plugin needs a rewrite and visemes need a forced-aligner replacement."

Where the others would *win*:
- **Voice quality and zero-shot cloning** — ZipVoice's main proposition. If the product wanted to add user-cloned voices, no engine in this comparison can replace it short-term.
- **Multilingual coverage with one model** — Pocket-TTS supports EN/FR/DE/PT/IT/ES out of the box; Bookbot needs a separate ~71 MB model per language.
- **Streaming-first applications** — Pocket-TTS yields audio chunks at ~80 ms granularity; Bookbot returns the whole utterance.

For the current Bookbot product (kid-facing reading app with lip-sync), neither competitor is a drop-in. See [mobile_feasibility.md](mobile_feasibility.md) for the deeper "could we even put one of these on Android/iOS instead of the current ONNX model?" question; the short answer is "not without rewriting the native runtime layer."
