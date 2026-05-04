# Mobile TTS: Memory Optimization + Phoneme Timing for sherpa-onnx Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Pocket-TTS on mobile through sherpa-onnx with two product-essential capabilities the upstream archive doesn't have: (1) ~70 MB smaller on-device footprint via pre-baked voice state, and (2) per-phoneme timing parity with Bookbot's existing visemes/lip-sync.

**Architecture:** Two independent phases against the Bookbot fork of sherpa-onnx and a private branch of pocket-tts.
- **Phase A (memory)** adds a pre-baked voice-state file format. A small C++ tool dumps the LM KV-cache after voice conditioning runs once at build time; sherpa-onnx loads the dump at runtime and skips loading `encoder.onnx` entirely (-72.7 MB on disk, -load-time spike, no quality change since it's bit-identical to the unbaked path).
- **Phase B (phoneme timing)** patches the upstream pocket-tts ONNX export to expose attention weights from a chosen transformer layer, then implements a small C++ aligner inside sherpa-onnx that does monotonic-argmax word alignment and proportional phoneme distribution — a faithful C++ port of `bench/pocket_tts_phoneme_timing.py`. G2P is **caller-supplied** (per-word phoneme list passed in `GenerationConfig`) to avoid bundling espeak-ng inside sherpa.

**Tech Stack:** C++17, ONNX Runtime, ONNX TensorProto serialization (already a sherpa-onnx dep), Dart FFI bindings (`sherpa_onnx` pub package), Python 3.11 + onnxruntime + onnx (for pre-bake CLI and ONNX-export changes), espeak-ng-via-phonemizer for the demo G2P.

**Repos touched:**
- `bookbot-hive/sherpa-onnx` at `/Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx` (Bookbot fork, current branch tracks k2-fsa/master) — most C++ work
- `kyutai-labs/pocket-tts` at `/Users/ductran/Documents/codes/python/opensource/pocket-tts` (clone, will need a `bookbot/attention-output-export` branch) — Phase B export change only
- `bookbot-kids/tts` at `/Users/ductran/Documents/codes/flutter/bookbot/tts` (this repo, current branch `bench/tts-comparison`) — bench app integration + plan doc

**Out of scope:**
- Multi-voice cloning. We pre-bake a fixed set of "stock voices" (~3–5 named voices); user-provided prompt-wav cloning still works through the original (unbaked) code path.
- Streaming-chunk audio output via the new API. Phase B keeps the same `Generate` non-streaming surface; streaming is a separate plan.
- Cross-language bindings beyond Dart. Java/Swift/Kotlin/JS/etc. mirroring is deferred to upstreaming.
- Audio quality MOS / listening tests. Numbers throughout are perf only.
- ZipVoice. Both features are Pocket-TTS-specific; ZipVoice doesn't have an analogous voice-state pre-bake (its encoder takes target text as input, not just prompt) and its attention isn't structured the same way.

**Hardware/test target:** macOS Darwin 25.4.0 / Apple M1 Pro for host build + the existing Android emulator (sdk gphone64 arm64, Android 16, arm64-v8a). The Pixel 8a hardware device the user mentioned in `bench/results/CONCLUSION-android.md` should be the final acceptance target if available.

---

## Why these two things, and not something else

The previous bench round established the problem space. Pocket-TTS via sherpa-onnx on Android already runs sub-real-time (RTF 0.26 long-content) and fits in ~780 MB peak RSS. What's still missing for shipping it Bookbot-style:

1. **On-device size**: 213 MB of model files. The sherpa-onnx int8 archive already int8s `lm_main`/`lm_flow`/`decoder`. The remaining FP32 chunks are `encoder.onnx` (72.7 MB, Mimi audio codec) and `text_conditioner.onnx` (16.4 MB, 1-op embedding). The encoder runs **once per unique reference audio** — sherpa already caches its output by audio hash — so we don't need it after the first call for a given fixed voice. Pre-baking the post-encoder LM state at build time and shipping that lets us drop `encoder.onnx` from the on-device bundle entirely.
2. **Phoneme timing**: visemes/lip-sync depend on per-phoneme timestamps. Bookbot's current ONNX emits a `durations` tensor natively; pocket-tts doesn't. The Python prototype `bench/pocket_tts_phoneme_timing.py` shows attention-monotonic-argmax + proportional phoneme distribution works at PyTorch level. We port that into sherpa-onnx C++.

Static QDQ on the encoder (the alternative memory lever) was the next-biggest option. Pre-baked voice state dominates it on every axis: simpler, no calibration set, no quality risk, bigger savings, and naturally handles Bookbot's fixed-voice product shape.

---

## File Structure

### Phase A — Pre-baked voice state

Files in `bookbot-hive/sherpa-onnx`:

```
sherpa-onnx/csrc/
  offline-tts-pocket-voice-state.h        # NEW. struct PocketVoiceState (header)
  offline-tts-pocket-voice-state.cc       # NEW. Save/Load ONNX TensorProto bundles
  offline-tts-pocket-model-config.h       # MODIFIED. add `std::string voice_state;` field
  offline-tts-pocket-model-config.cc      # MODIFIED. wire voice_state into Register/Validate/ToString
  offline-tts-pocket-impl.h               # MODIFIED. branch in GenerateSingleSentence: if voice_state set, skip encoder/voice-conditioning RunLmMain pair
  offline-tts-pocket-model.cc             # MODIFIED. expose lm_main_state_template setter
  offline-tts-pocket-model.h              # MODIFIED. signature change for setter

bin/
  prebake-pocket-voice.cc                 # NEW. CLI: prompt wav + model dir -> voice_state.bin

CMakeLists.txt                            # MODIFIED. add prebake-pocket-voice executable target
sherpa-onnx/csrc/CMakeLists.txt           # MODIFIED. compile voice-state.cc into sherpa-onnx-core lib
```

Files in `bookbot-kids/tts`:

```
bench/scripts/prebake_pocket_voice.sh     # NEW. wrapper that invokes the prebake binary
bench/voices/alba.voice-state.bin         # NEW. checked in (~6 MB), pre-baked alba voice for the bench
```

Files in `~/.pub-cache/.../sherpa_onnx/lib/src/tts.dart` will be modified upstream once we cut a new sherpa_onnx pub release; for now we override locally via `dependency_overrides` in `bench/flutter_bench/pubspec.yaml`.

### Phase B — Phoneme timing

Files in `kyutai-labs/pocket-tts` (a new branch `bookbot/attention-output-export`):

```
pocket_tts/
  modules/transformer.py                  # MODIFIED. add optional attention_capture hook
  models/tts_model.py                     # MODIFIED. expose attention_layer_index in export config
  bin/onnx_export.py                      # NEW (or MODIFIED). script that re-exports lm_main with attention output
```

Files in `bookbot-hive/sherpa-onnx`:

```
sherpa-onnx/csrc/
  offline-tts-pocket-aligner.h            # NEW. PocketAligner (monotonic argmax + phoneme distribution)
  offline-tts-pocket-aligner.cc           # NEW. impl
  offline-tts-frontend.h                  # MODIFIED. add struct PhonemeTiming { phoneme; word; word_index; start_s; end_s; }
  generated-audio.h                       # MODIFIED. add std::vector<PhonemeTiming> phoneme_timings field
  offline-tts-pocket-model.cc             # MODIFIED. RunLmMain returns attention output; new RunLmMainWithAttention overload
  offline-tts-pocket-model.h              # MODIFIED. signature
  offline-tts-pocket-impl.h               # MODIFIED. wire aligner through GenerateSingleSentence loop
  offline-tts-pocket-model-config.h       # MODIFIED. add `int32_t attention_layer_index = 3;` field
  offline-tts-pocket-model-config.cc      # MODIFIED. Register/ToString
```

C API additions:

```
sherpa-onnx/c-api/c-api.h                 # MODIFIED. SherpaOnnxOfflineTtsPhonemeTiming struct + array on GeneratedAudio
sherpa-onnx/c-api/c-api.cc                # MODIFIED. fill the array, free helper
```

Dart binding (in our local `bench/flutter_bench/`):

```
bench/flutter_bench/lib/sherpa_onnx_overrides/
  generated_audio_with_phonemes.dart      # NEW. extension class wrapping FFI struct
  pocket_tts_with_phonemes.dart           # NEW. thin wrapper over OfflineTts.generate
```

Files in `bookbot-kids/tts`:

```
bench/voices/alba.tokens.txt              # NEW. words+phonemes lookup for the bench corpus (espeak-ng output, frozen)
bench/flutter_bench/lib/main.dart         # MODIFIED. consume PhonemeTiming, log a few entries per row
```

---

# PHASE A — Pre-baked voice state

This phase ships independently and provides the memory win on its own.

---

## Task A0: Set up branches across the three repos

**Files:** none — branch admin only.

- [ ] **Step 1: sherpa-onnx fork — create feature branch**

```bash
cd /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx
git fetch origin
git checkout -b feat/pocket-prebaked-voice-state origin/master
git rev-parse HEAD
```
Expected: clean branch named `feat/pocket-prebaked-voice-state` cut from `bookbot-hive/sherpa-onnx`'s master.

- [ ] **Step 2: this repo — create feature branch**

```bash
cd /Users/ductran/Documents/codes/flutter/bookbot/tts
git checkout -b feat/mobile-tts-prebake-and-phoneme-timing
git rev-parse HEAD
```

- [ ] **Step 3: pocket-tts — leave alone**

Phase A doesn't touch pocket-tts. Skip.

---

## Task A1: Define the voice-state file format

**Files:**
- Create: `sherpa-onnx/csrc/offline-tts-pocket-voice-state.h`

The file format is **a magic header followed by N ONNX TensorProto records, each prefixed with a `uint32` length**. We reuse `Ort::TensorProto` machinery already linked into sherpa to avoid pulling safetensors-cpp.

```
0x00..0x07: magic       = "SHPRPVS\0"  (Sherpa Pocket-Tts Voice State)
0x08..0x0B: version     = uint32_le 1
0x0C..0x0F: tensor_count= uint32_le N
0x10..      N records, each:
              uint32_le name_len
              char[name_len] name (matches the lm_main session input name, e.g. "state_in_layer_0_k")
              uint32_le proto_len
              char[proto_len] serialized ONNX TensorProto bytes
```

- [ ] **Step 1: Write the header file**

```cpp
// sherpa-onnx/csrc/offline-tts-pocket-voice-state.h
#ifndef SHERPA_ONNX_CSRC_OFFLINE_TTS_POCKET_VOICE_STATE_H_
#define SHERPA_ONNX_CSRC_OFFLINE_TTS_POCKET_VOICE_STATE_H_

#include <onnxruntime_cxx_api.h>

#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace sherpa_onnx {

// One pre-baked KV-cache tensor for the lm_main session's `state_in_*` inputs.
struct PocketVoiceStateTensor {
  std::string name;            // input name expected by lm_main session
  std::vector<int64_t> shape;
  std::vector<float> data;     // dtype is always float32 for this model
};

// On-disk and in-memory representation of pre-baked voice state.
//
// File layout (little-endian, packed):
//   magic[8] = "SHPRPVS\0"
//   version: uint32 (currently 1)
//   tensor_count: uint32
//   for each tensor:
//     name_len: uint32
//     name: name_len bytes, UTF-8
//     proto_len: uint32
//     proto: ONNX TensorProto serialized via SerializeToString()
struct PocketVoiceState {
  uint32_t version = 1;
  std::vector<PocketVoiceStateTensor> tensors;

  // Serialize / deserialize. Returns true on success; on failure the
  // *err_msg is filled with a short diagnostic. We do not throw — sherpa-onnx
  // C++ does not use exceptions in user-facing paths.
  bool SaveToFile(const std::string &path, std::string *err_msg) const;
  static bool LoadFromFile(const std::string &path, PocketVoiceState *out,
                           std::string *err_msg);
};

}  // namespace sherpa_onnx

#endif  // SHERPA_ONNX_CSRC_OFFLINE_TTS_POCKET_VOICE_STATE_H_
```

- [ ] **Step 2: Commit**

```bash
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx \
    add sherpa-onnx/csrc/offline-tts-pocket-voice-state.h
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx \
    commit -m "feat(tts): declare PocketVoiceState header"
```

---

## Task A2: Implement save / load

**Files:**
- Create: `sherpa-onnx/csrc/offline-tts-pocket-voice-state.cc`

- [ ] **Step 1: Write the implementation**

```cpp
// sherpa-onnx/csrc/offline-tts-pocket-voice-state.cc
#include "sherpa-onnx/csrc/offline-tts-pocket-voice-state.h"

#include <onnx/onnx_pb.h>

#include <cstring>
#include <fstream>
#include <sstream>

namespace sherpa_onnx {

namespace {

constexpr char kMagic[8] = {'S', 'H', 'P', 'R', 'P', 'V', 'S', '\0'};

bool WriteU32(std::ostream &os, uint32_t v) {
  char b[4] = {static_cast<char>(v & 0xff), static_cast<char>((v >> 8) & 0xff),
               static_cast<char>((v >> 16) & 0xff),
               static_cast<char>((v >> 24) & 0xff)};
  os.write(b, 4);
  return os.good();
}

bool ReadU32(std::istream &is, uint32_t *v) {
  char b[4];
  if (!is.read(b, 4)) return false;
  *v = (static_cast<uint8_t>(b[0])) |
       (static_cast<uint8_t>(b[1]) << 8) |
       (static_cast<uint8_t>(b[2]) << 16) |
       (static_cast<uint8_t>(b[3]) << 24);
  return true;
}

}  // namespace

bool PocketVoiceState::SaveToFile(const std::string &path,
                                  std::string *err_msg) const {
  std::ofstream os(path, std::ios::binary | std::ios::trunc);
  if (!os) {
    *err_msg = "cannot open " + path + " for write";
    return false;
  }
  os.write(kMagic, sizeof(kMagic));
  if (!WriteU32(os, version)) {
    *err_msg = "write version failed";
    return false;
  }
  if (!WriteU32(os, static_cast<uint32_t>(tensors.size()))) {
    *err_msg = "write tensor_count failed";
    return false;
  }
  for (const auto &t : tensors) {
    onnx::TensorProto proto;
    proto.set_name(t.name);
    proto.set_data_type(onnx::TensorProto::FLOAT);
    for (auto d : t.shape) proto.add_dims(d);
    proto.mutable_raw_data()->assign(
        reinterpret_cast<const char *>(t.data.data()),
        t.data.size() * sizeof(float));

    std::string serialized;
    if (!proto.SerializeToString(&serialized)) {
      *err_msg = "TensorProto serialize failed for " + t.name;
      return false;
    }
    if (!WriteU32(os, static_cast<uint32_t>(t.name.size()))) return false;
    os.write(t.name.data(), t.name.size());
    if (!WriteU32(os, static_cast<uint32_t>(serialized.size()))) return false;
    os.write(serialized.data(), serialized.size());
    if (!os.good()) {
      *err_msg = "write failed for tensor " + t.name;
      return false;
    }
  }
  return os.good();
}

bool PocketVoiceState::LoadFromFile(const std::string &path,
                                    PocketVoiceState *out,
                                    std::string *err_msg) {
  std::ifstream is(path, std::ios::binary);
  if (!is) {
    *err_msg = "cannot open " + path + " for read";
    return false;
  }
  char magic[sizeof(kMagic)];
  is.read(magic, sizeof(kMagic));
  if (std::memcmp(magic, kMagic, sizeof(kMagic)) != 0) {
    *err_msg = "bad magic in " + path;
    return false;
  }
  if (!ReadU32(is, &out->version)) {
    *err_msg = "read version failed";
    return false;
  }
  if (out->version != 1) {
    std::ostringstream o;
    o << "unsupported voice-state file version " << out->version;
    *err_msg = o.str();
    return false;
  }
  uint32_t n = 0;
  if (!ReadU32(is, &n)) {
    *err_msg = "read tensor_count failed";
    return false;
  }
  out->tensors.clear();
  out->tensors.reserve(n);
  for (uint32_t i = 0; i < n; ++i) {
    PocketVoiceStateTensor t;
    uint32_t name_len = 0;
    if (!ReadU32(is, &name_len)) {
      *err_msg = "read name_len failed";
      return false;
    }
    t.name.resize(name_len);
    if (name_len && !is.read(t.name.data(), name_len)) {
      *err_msg = "read name failed";
      return false;
    }
    uint32_t proto_len = 0;
    if (!ReadU32(is, &proto_len)) {
      *err_msg = "read proto_len failed";
      return false;
    }
    std::string buf(proto_len, '\0');
    if (proto_len && !is.read(buf.data(), proto_len)) {
      *err_msg = "read proto bytes failed";
      return false;
    }
    onnx::TensorProto proto;
    if (!proto.ParseFromString(buf)) {
      *err_msg = "TensorProto parse failed for " + t.name;
      return false;
    }
    if (proto.data_type() != onnx::TensorProto::FLOAT) {
      *err_msg = "non-float tensor " + t.name + " not supported";
      return false;
    }
    for (int j = 0; j < proto.dims_size(); ++j) {
      t.shape.push_back(proto.dims(j));
    }
    size_t expected = 1;
    for (auto d : t.shape) expected *= static_cast<size_t>(d);
    t.data.resize(expected);
    std::memcpy(t.data.data(), proto.raw_data().data(),
                expected * sizeof(float));
    out->tensors.push_back(std::move(t));
  }
  return true;
}

}  // namespace sherpa_onnx
```

- [ ] **Step 2: Add to sherpa-onnx-core CMakeLists.txt**

Modify `sherpa-onnx/csrc/CMakeLists.txt`. Find the `set(sherpa-onnx-core-srcs ...)` block and append `offline-tts-pocket-voice-state.cc`:

Run:
```bash
grep -n "offline-tts-pocket-model-config.cc" /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx/sherpa-onnx/csrc/CMakeLists.txt
```
Expected: a line number. After that line, insert `offline-tts-pocket-voice-state.cc` so the alphabetical sibling pattern is preserved.

- [ ] **Step 3: Build sherpa-onnx and confirm it still compiles**

```bash
cd /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx
mkdir -p build-host && cd build-host
cmake -DCMAKE_BUILD_TYPE=Release -DSHERPA_ONNX_ENABLE_TTS=ON ..
make -j$(sysctl -n hw.ncpu) sherpa-onnx-core 2>&1 | tail -8
```
Expected: build succeeds with no errors mentioning `offline-tts-pocket-voice-state`.

- [ ] **Step 4: Write a unit test**

Create `sherpa-onnx/csrc/test-offline-tts-pocket-voice-state.cc`:

```cpp
#include "sherpa-onnx/csrc/offline-tts-pocket-voice-state.h"

#include <gtest/gtest.h>

#include <cstdio>
#include <string>

namespace sherpa_onnx {

TEST(PocketVoiceState, RoundTrip) {
  PocketVoiceState s;
  s.version = 1;
  PocketVoiceStateTensor t1{"state_in_layer_0_k",
                            {1, 8, 16},
                            std::vector<float>(8 * 16, 0.5f)};
  PocketVoiceStateTensor t2{"state_in_layer_0_v",
                            {1, 8, 16},
                            std::vector<float>(8 * 16, -0.25f)};
  s.tensors.push_back(t1);
  s.tensors.push_back(t2);

  const std::string path = std::string(testing::TempDir()) + "/vs.bin";
  std::string err;
  ASSERT_TRUE(s.SaveToFile(path, &err)) << err;

  PocketVoiceState loaded;
  ASSERT_TRUE(PocketVoiceState::LoadFromFile(path, &loaded, &err)) << err;
  ASSERT_EQ(loaded.tensors.size(), 2u);
  EXPECT_EQ(loaded.tensors[0].name, "state_in_layer_0_k");
  EXPECT_EQ(loaded.tensors[0].shape, (std::vector<int64_t>{1, 8, 16}));
  EXPECT_EQ(loaded.tensors[1].data[3], -0.25f);
  std::remove(path.c_str());
}

}  // namespace sherpa_onnx
```

Add to the test list in `sherpa-onnx/csrc/CMakeLists.txt`. Sherpa already runs gtest — find any existing `add_executable(test-offline-...)` block and mirror it.

- [ ] **Step 5: Run the test**

```bash
cd /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx/build-host
make -j test-offline-tts-pocket-voice-state
./bin/test-offline-tts-pocket-voice-state
```
Expected: `PocketVoiceState.RoundTrip` PASSED.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx add \
    sherpa-onnx/csrc/offline-tts-pocket-voice-state.cc \
    sherpa-onnx/csrc/test-offline-tts-pocket-voice-state.cc \
    sherpa-onnx/csrc/CMakeLists.txt
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx commit \
    -m "feat(tts): PocketVoiceState save/load with TensorProto records"
```

---

## Task A3: Add `voice_state` to `OfflineTtsPocketModelConfig`

**Files:**
- Modify: `sherpa-onnx/csrc/offline-tts-pocket-model-config.h`
- Modify: `sherpa-onnx/csrc/offline-tts-pocket-model-config.cc`

- [ ] **Step 1: Add field to the header**

Edit `sherpa-onnx/csrc/offline-tts-pocket-model-config.h`. After line 23 (`std::string token_scores_json;`), insert:

```cpp
  // Optional. Path to a pre-baked voice-state .bin produced by
  // bin/prebake-pocket-voice. When set, the encoder ONNX is not loaded
  // and the LM voice-conditioning pass is skipped.
  std::string voice_state;
```

Update the constructor parameter list and member init list to accept `voice_state` after `token_scores_json` with a default of `""`. Also add to `Register`, `Validate`, and `ToString` in the .cc file.

- [ ] **Step 2: Update Register/Validate/ToString**

In `offline-tts-pocket-model-config.cc`, add `po->Register("pocket-voice-state", &voice_state, ...)` next to the other Register calls. Validate: if non-empty, check the file exists. ToString: include the value.

- [ ] **Step 3: Rebuild + smoke**

```bash
cd /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx/build-host
make -j sherpa-onnx-core 2>&1 | tail -5
```
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx add \
    sherpa-onnx/csrc/offline-tts-pocket-model-config.h \
    sherpa-onnx/csrc/offline-tts-pocket-model-config.cc
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx commit \
    -m "feat(tts): voice_state path in OfflineTtsPocketModelConfig"
```

---

## Task A4: Wire the pre-baked path into `GenerateSingleSentence`

**Files:**
- Modify: `sherpa-onnx/csrc/offline-tts-pocket-impl.h` (lines ~233 and ~310-330)
- Modify: `sherpa-onnx/csrc/offline-tts-pocket-model.cc` (loader)
- Modify: `sherpa-onnx/csrc/offline-tts-pocket-model.h` (signature)

The hot logic in `GenerateSingleSentence` currently does (lines 322-330):

```cpp
RunLmMain(View(&empty_seq_tensor), std::move(voice_embedding), lm_main_state);
RunLmMain(std::move(empty_seq_tensor), std::move(text_embedding), lm_main_state);
```

We branch: if `voice_state` was loaded, replace the **first** RunLmMain call with `lm_main_state = LoadedVoiceState()` (which is what the first call's side effect would have been). The encoder pass and `GetVoiceEmbedding` are also skipped (controlled at line ~233).

- [ ] **Step 1: In `OfflineTtsPocketModel`, add voice-state loader**

In `offline-tts-pocket-model.h`, add to the public section of the class:

```cpp
  // Loads a pre-baked voice state and returns it as a PocketLmMainState
  // ready to feed into RunLmMain. Returns empty state on failure.
  PocketLmMainState LoadVoiceStateOrDie(const std::string &path) const;
```

In `offline-tts-pocket-model.cc`, implement:

```cpp
PocketLmMainState OfflineTtsPocketModel::Impl::LoadVoiceStateOrDie(
    const std::string &path) const {
  PocketVoiceState vs;
  std::string err;
  if (!PocketVoiceState::LoadFromFile(path, &vs, &err)) {
    SHERPA_ONNX_LOGE("Failed to load voice state from %s: %s", path.c_str(),
                     err.c_str());
    exit(1);
  }
  PocketLmMainState s;
  s.values.reserve(vs.tensors.size());
  s.input_names = lm_main_state_input_names_;  // already populated at session-init time

  auto memory_info =
      Ort::MemoryInfo::CreateCpu(OrtDeviceAllocator, OrtMemTypeDefault);
  for (auto &t : vs.tensors) {
    Ort::Value v = Ort::Value::CreateTensor<float>(
        memory_info, t.data.data(), t.data.size(), t.shape.data(),
        t.shape.size());
    s.values.push_back(std::move(v));
    // Note: we keep the data buffer alive by stashing it in a parallel vector.
  }
  return s;
}
```

There's a lifetime subtlety: `Ort::Value::CreateTensor` with a raw pointer doesn't copy the data. The vector `t.data` lives in `vs`, which is a local. We need to move the buffers into a member so they outlive the `Ort::Value`. The cleanest fix is to add a parallel `std::vector<std::vector<float>> voice_state_data_` member on `Impl` that owns the buffers, and load the state once at session-init time (in the constructor) rather than per-call.

Replace the above with the constructor-time variant:

```cpp
// In Impl::Init() or constructor body, after lm_main_sess_ is created and
// lm_main_state_input_names_ is populated:
if (!config.model.pocket.voice_state.empty()) {
  PocketVoiceState vs;
  std::string err;
  if (!PocketVoiceState::LoadFromFile(
          config.model.pocket.voice_state, &vs, &err)) {
    SHERPA_ONNX_LOGE("Failed to load voice state: %s", err.c_str());
    exit(1);
  }
  voice_state_data_.reserve(vs.tensors.size());
  for (auto &t : vs.tensors) {
    voice_state_data_.push_back(std::move(t.data));
  }
  voice_state_shapes_.reserve(vs.tensors.size());
  voice_state_names_.reserve(vs.tensors.size());
  for (size_t i = 0; i < vs.tensors.size(); ++i) {
    voice_state_shapes_.push_back(std::move(vs.tensors[i].shape));
    voice_state_names_.push_back(std::move(vs.tensors[i].name));
  }
  has_voice_state_ = true;
}
```

And add a new method:

```cpp
PocketLmMainState OfflineTtsPocketModel::GetPreBakedLmMainState() const {
  return impl_->GetPreBakedLmMainState();
}

PocketLmMainState OfflineTtsPocketModel::Impl::GetPreBakedLmMainState() const {
  PocketLmMainState s;
  s.values.reserve(voice_state_data_.size());
  s.input_names = lm_main_state_input_names_;
  auto memory_info =
      Ort::MemoryInfo::CreateCpu(OrtDeviceAllocator, OrtMemTypeDefault);
  for (size_t i = 0; i < voice_state_data_.size(); ++i) {
    s.values.push_back(Ort::Value::CreateTensor<float>(
        memory_info,
        const_cast<float *>(voice_state_data_[i].data()),
        voice_state_data_[i].size(), voice_state_shapes_[i].data(),
        voice_state_shapes_[i].size()));
  }
  return s;
}

bool OfflineTtsPocketModel::HasVoiceState() const {
  return impl_->has_voice_state_;
}
```

- [ ] **Step 2: Skip encoder load when voice_state is set**

In `OfflineTtsPocketModel::Impl::Init()`, find the block that creates `mimi_encoder_sess_`. Wrap with:

```cpp
if (config.model.pocket.voice_state.empty()) {
  mimi_encoder_sess_ = std::make_unique<Ort::Session>(
      env_, ReadFile(config.model.pocket.encoder).data(),
      ReadFile(config.model.pocket.encoder).size(), session_opts_);
  // ... existing encoder input/output name setup
}
// else: encoder is unused; mimi_encoder_sess_ stays nullptr
```

The text_conditioner_ session must still be loaded (text changes per call).

- [ ] **Step 3: Branch in `GenerateSingleSentence`**

In `offline-tts-pocket-impl.h`, modify the two locations:

Around line 233 (`Ort::Value voice_embedding = GetVoiceEmbedding(gen_config);`), guard:

```cpp
Ort::Value voice_embedding{nullptr};
if (!model_->HasVoiceState()) {
  voice_embedding = GetVoiceEmbedding(gen_config);
  if (!voice_embedding) {
    // ... existing error path
  }
}
```

Around line 310 (`auto lm_main_state = model_->GetLmMainInitState();`), branch:

```cpp
auto lm_main_state = model_->HasVoiceState()
                         ? model_->GetPreBakedLmMainState()
                         : model_->GetLmMainInitState();
```

Around line 322-326 (the `RunLmMain(empty_seq, voice_embedding, ...)` call), wrap:

```cpp
if (!model_->HasVoiceState()) {
  RunLmMain(View(&empty_seq_tensor), std::move(voice_embedding),
            lm_main_state);
}
// text conditioning still runs unconditionally:
RunLmMain(std::move(empty_seq_tensor), std::move(text_embedding),
          lm_main_state);
```

- [ ] **Step 4: Build**

```bash
cd /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx/build-host
make -j sherpa-onnx-core 2>&1 | tail -8
```
Expected: clean build.

- [ ] **Step 5: Commit**

```bash
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx add \
    sherpa-onnx/csrc/offline-tts-pocket-impl.h \
    sherpa-onnx/csrc/offline-tts-pocket-model.h \
    sherpa-onnx/csrc/offline-tts-pocket-model.cc
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx commit \
    -m "feat(tts): branch GenerateSingleSentence on pre-baked voice state"
```

---

## Task A5: `prebake-pocket-voice` CLI

**Files:**
- Create: `bin/prebake-pocket-voice.cc`
- Modify: `CMakeLists.txt` (top-level, add executable target)

The CLI takes the same model config as `offline-tts-pocket-impl`, plus a prompt-wav and output path. It runs encoder + first `RunLmMain` (empty seq, voice embedding) and dumps the resulting `lm_main_state` tensors to a `PocketVoiceState` file.

- [ ] **Step 1: Write the CLI**

```cpp
// bin/prebake-pocket-voice.cc
#include <cstdio>
#include <iostream>
#include <string>
#include <vector>

#include "sherpa-onnx/csrc/offline-tts-pocket-impl.h"
#include "sherpa-onnx/csrc/offline-tts-pocket-voice-state.h"
#include "sherpa-onnx/csrc/parse-options.h"
#include "sherpa-onnx/csrc/wave-reader.h"

int main(int argc, char *argv[]) {
  using namespace sherpa_onnx;
  ParseOptions po(R"(Pre-bake a Pocket-TTS voice state from a prompt wav.

Usage:
  prebake-pocket-voice \
      --pocket-lm-flow=lm_flow.int8.onnx \
      --pocket-lm-main=lm_main.int8.onnx \
      --pocket-encoder=encoder.onnx \
      --pocket-decoder=decoder.int8.onnx \
      --pocket-text-conditioner=text_conditioner.onnx \
      --pocket-vocab-json=vocab.json \
      --pocket-token-scores-json=token_scores.json \
      --prompt-wav=prompt.wav \
      --output=voice_state.bin
)");

  OfflineTtsPocketModelConfig pocket_cfg;
  pocket_cfg.Register(&po);

  std::string prompt_wav;
  std::string output;
  po.Register("prompt-wav", &prompt_wav, "Path to prompt wav (24kHz mono).");
  po.Register("output", &output, "Path to write voice_state.bin");

  po.Read(argc, argv);
  if (prompt_wav.empty() || output.empty() || !pocket_cfg.Validate()) {
    po.PrintUsage();
    return 1;
  }

  // Read prompt wav
  bool is_ok = false;
  int32_t sample_rate = 0;
  std::vector<float> samples = ReadWave(prompt_wav, &sample_rate, &is_ok);
  if (!is_ok) {
    fprintf(stderr, "Failed to read %s\n", prompt_wav.c_str());
    return 1;
  }

  OfflineTtsConfig tts_cfg;
  tts_cfg.model.pocket = pocket_cfg;
  // Important: voice_state must be EMPTY here so encoder is loaded.
  tts_cfg.model.pocket.voice_state.clear();

  OfflineTtsPocketImpl impl(tts_cfg);

  // Run encoder + first RunLmMain. The implementation exposes a helper for
  // exactly this — we add it in this same task.
  PocketVoiceState vs;
  std::string err;
  if (!impl.PreBake(samples, sample_rate, &vs, &err)) {
    fprintf(stderr, "PreBake failed: %s\n", err.c_str());
    return 1;
  }
  if (!vs.SaveToFile(output, &err)) {
    fprintf(stderr, "SaveToFile failed: %s\n", err.c_str());
    return 1;
  }
  fprintf(stderr, "Wrote %s (%zu tensors)\n", output.c_str(), vs.tensors.size());
  return 0;
}
```

- [ ] **Step 2: Add `PreBake` method to `OfflineTtsPocketImpl`**

In `sherpa-onnx/csrc/offline-tts-pocket-impl.h`, add a public method:

```cpp
// Run encoder + first lm_main pass on the given prompt; dump the resulting
// lm_main_state into `out`. Used by bin/prebake-pocket-voice. Returns false
// on failure with diagnostic in *err.
bool PreBake(const std::vector<float> &prompt_audio, int32_t sample_rate,
             PocketVoiceState *out, std::string *err) const {
  GenerationConfig gen;
  gen.reference_audio = prompt_audio;
  gen.reference_sample_rate = sample_rate;

  Ort::Value voice_embedding = GetVoiceEmbedding(gen);
  if (!voice_embedding) {
    *err = "GetVoiceEmbedding returned null";
    return false;
  }

  auto lm_main_state = model_->GetLmMainInitState();

  auto memory_info =
      Ort::MemoryInfo::CreateCpu(OrtDeviceAllocator, OrtMemTypeDefault);
  std::array<int64_t, 3> empty_seq_shape = {1, 0, 32};
  Ort::Value empty_seq_tensor = Ort::Value::CreateTensor<float>(
      memory_info, nullptr, 0, empty_seq_shape.data(), empty_seq_shape.size());

  RunLmMain(View(&empty_seq_tensor), std::move(voice_embedding),
            lm_main_state);

  // Dump lm_main_state into PocketVoiceState
  out->version = 1;
  out->tensors.clear();
  out->tensors.reserve(lm_main_state.values.size());
  for (size_t i = 0; i < lm_main_state.values.size(); ++i) {
    PocketVoiceStateTensor t;
    t.name = lm_main_state.input_names[i];
    auto info = lm_main_state.values[i].GetTensorTypeAndShapeInfo();
    t.shape = info.GetShape();
    size_t n = info.GetElementCount();
    const float *p = lm_main_state.values[i].GetTensorData<float>();
    t.data.assign(p, p + n);
    out->tensors.push_back(std::move(t));
  }
  return true;
}
```

- [ ] **Step 3: Add executable to top-level CMakeLists.txt**

Find an existing `add_executable(...)` block for any `bin/*.cc` (e.g. `offline-tts-pocket`) and mirror it:

```cmake
add_executable(prebake-pocket-voice bin/prebake-pocket-voice.cc)
target_link_libraries(prebake-pocket-voice sherpa-onnx-core)
install(TARGETS prebake-pocket-voice DESTINATION bin)
```

- [ ] **Step 4: Build**

```bash
cd /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx/build-host
cmake -DCMAKE_BUILD_TYPE=Release -DSHERPA_ONNX_ENABLE_TTS=ON ..
make -j prebake-pocket-voice 2>&1 | tail -8
```
Expected: builds.

- [ ] **Step 5: Run end-to-end on the bench's existing model**

```bash
MODEL=/Users/ductran/Documents/codes/flutter/bookbot/tts/bench/sherpa_models/sherpa-onnx-pocket-tts-int8-2026-01-26
./bin/prebake-pocket-voice \
    --pocket-lm-flow=$MODEL/lm_flow.int8.onnx \
    --pocket-lm-main=$MODEL/lm_main.int8.onnx \
    --pocket-encoder=$MODEL/encoder.onnx \
    --pocket-decoder=$MODEL/decoder.int8.onnx \
    --pocket-text-conditioner=$MODEL/text_conditioner.onnx \
    --pocket-vocab-json=$MODEL/vocab.json \
    --pocket-token-scores-json=$MODEL/token_scores.json \
    --prompt-wav=$MODEL/test_wavs/bria.wav \
    --output=/tmp/bria.voice-state.bin
ls -la /tmp/bria.voice-state.bin
```
Expected: file written, size in the 1–10 MB range.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx add \
    bin/prebake-pocket-voice.cc CMakeLists.txt \
    sherpa-onnx/csrc/offline-tts-pocket-impl.h
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx commit \
    -m "feat(tts): prebake-pocket-voice CLI"
```

---

## Task A6: End-to-end host bench — pre-baked vs unbaked

**Files:**
- Create: `bench/scripts/prebake_pocket_voice.sh` (in this repo)
- Create: `bench/voices/bria.voice-state.bin` (in this repo, generated, ~6 MB committed)

- [ ] **Step 1: Wrapper script**

```bash
# bench/scripts/prebake_pocket_voice.sh
#!/usr/bin/env bash
set -euo pipefail
SHERPA=/Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx
MODEL=$(dirname $0)/../sherpa_models/sherpa-onnx-pocket-tts-int8-2026-01-26
OUT=$(dirname $0)/../voices/bria.voice-state.bin

$SHERPA/build-host/bin/prebake-pocket-voice \
    --pocket-lm-flow=$MODEL/lm_flow.int8.onnx \
    --pocket-lm-main=$MODEL/lm_main.int8.onnx \
    --pocket-encoder=$MODEL/encoder.onnx \
    --pocket-decoder=$MODEL/decoder.int8.onnx \
    --pocket-text-conditioner=$MODEL/text_conditioner.onnx \
    --pocket-vocab-json=$MODEL/vocab.json \
    --pocket-token-scores-json=$MODEL/token_scores.json \
    --prompt-wav=$MODEL/test_wavs/bria.wav \
    --output=$OUT

echo "Wrote $OUT ($(du -h $OUT | cut -f1))"
```

```bash
chmod +x bench/scripts/prebake_pocket_voice.sh
./bench/scripts/prebake_pocket_voice.sh
```
Expected: produces `bench/voices/bria.voice-state.bin`.

- [ ] **Step 2: Add a new sherpa adapter that uses pre-baked state**

We need to expose the new field through Python's `sherpa_onnx` package too. For the benchmark the cleanest path is to **not** use Python at all here — instead build a tiny C++ probe that takes the pre-baked voice state and emits one synthesis per sentence with timings. But to keep parity with the existing host bench harness, we'll temporarily test via a local-built `sherpa_onnx` Python wheel from this branch:

```bash
cd /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx
pip install -e python-api-package/  # builds against build-host/
```
Verify:
```bash
python -c "
import sherpa_onnx as so
cfg = so.OfflineTtsPocketModelConfig()
print('has voice_state:', hasattr(cfg, 'voice_state'))
"
```
Expected: `has voice_state: True`. If False, the Python pyi binding hasn't been regenerated — see `python-api-package/sherpa_onnx/lib/_sherpa_onnx.pyi` and add the field manually, or rebuild the pybind11 module.

- [ ] **Step 3: Bench adapter using pre-baked state**

Create `bench/adapters/pockettts_sherpa_prebake_adapter.py`:

```python
"""Pocket-TTS via sherpa-onnx with PRE-BAKED voice state.

Uses the bookbot-hive/sherpa-onnx feature branch which adds
OfflineTtsPocketModelConfig.voice_state. Encoder is not loaded; voice
conditioning is replaced by a one-shot tensor load at session init.
"""
import time
from pathlib import Path
import sherpa_onnx
import soundfile as sf

REPO = Path(__file__).resolve().parents[2]
MODEL_DIR = REPO / "bench" / "sherpa_models" / "sherpa-onnx-pocket-tts-int8-2026-01-26"
VOICE_STATE = REPO / "bench" / "voices" / "bria.voice-state.bin"
DEFAULT_VOICE = "pocket-tts/sherpa-int8/bria@prebaked"


def _build_tts() -> sherpa_onnx.OfflineTts:
    cfg = sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            pocket=sherpa_onnx.OfflineTtsPocketModelConfig(
                lm_flow=str(MODEL_DIR / "lm_flow.int8.onnx"),
                lm_main=str(MODEL_DIR / "lm_main.int8.onnx"),
                encoder="",  # IMPORTANT: empty when voice_state is set
                decoder=str(MODEL_DIR / "decoder.int8.onnx"),
                text_conditioner=str(MODEL_DIR / "text_conditioner.onnx"),
                vocab_json=str(MODEL_DIR / "vocab.json"),
                token_scores_json=str(MODEL_DIR / "token_scores.json"),
                voice_state=str(VOICE_STATE),
            ),
            num_threads=2, debug=False, provider="cpu",
        )
    )
    if not cfg.validate():
        raise RuntimeError("config validation failed")
    return sherpa_onnx.OfflineTts(cfg)


def synthesize(text: str, out_wav: str) -> dict:
    tts = _build_tts()
    gen = sherpa_onnx.GenerationConfig()
    # No reference_audio; pre-baked state already encodes it.
    gen.num_steps = 5
    t0 = time.perf_counter()
    audio = tts.generate(text, gen)
    infer_s = time.perf_counter() - t0
    sf.write(str(Path(out_wav).resolve()), audio.samples, audio.sample_rate,
             subtype="PCM_16")
    return {
        "voice_id": DEFAULT_VOICE,
        "audio_seconds": float(len(audio.samples)) / audio.sample_rate,
        "phoneme_timings": None,  # Phase B
        "infer_seconds": infer_s,
    }
```

Add to `bench/run_bench.py` `ENGINES` list.

- [ ] **Step 4: Run the bench against the new adapter**

```bash
source bench/.venv/bin/activate
python -m bench.run_bench --engine pockettts_sherpa_prebake_adapter --repeats 3 --append
python bench/aggregate.py
```
Expected: median RTF within 5% of `pockettts_sherpa_adapter` (the unbaked sherpa path). Median peak RSS noticeably lower (target: ≥ 50 MB lower because the encoder ORT session isn't loaded).

- [ ] **Step 5: Commit results**

```bash
cd /Users/ductran/Documents/codes/flutter/bookbot/tts
git add bench/scripts/prebake_pocket_voice.sh bench/voices/bria.voice-state.bin \
        bench/adapters/pockettts_sherpa_prebake_adapter.py bench/run_bench.py \
        bench/results/results.csv bench/results/summary.csv
git commit -m "bench: pocket-tts sherpa pre-baked voice state — host CPU measurement"
```

---

## Task A7: Wire pre-baked state through Dart binding + Android bench

**Files:**
- Modify: `bench/flutter_bench/pubspec.yaml` (dependency_overrides)
- Modify: `bench/flutter_bench/lib/main.dart`

The `sherpa_onnx` pub package's Dart class `OfflineTtsPocketModelConfig` doesn't have a `voiceState` field yet. Two paths:
- **Path X (chosen for now)**: clone the pub package, add the field, point to the local clone via `dependency_overrides`. Cheap.
- **Path Y (for upstreaming later)**: send a PR to k2-fsa/sherpa-onnx pub package once Phase A's C++ lands.

- [ ] **Step 1: Clone the Dart pub package locally**

```bash
git clone https://github.com/k2-fsa/sherpa-onnx-dart \
    /Users/ductran/Documents/codes/dart/sherpa-onnx-dart 2>&1 | tail -3
```

If the package isn't a separate repo, it's part of `k2-fsa/sherpa-onnx`'s `flutter/sherpa_onnx/` directory. Find it:

```bash
find /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx -path "*flutter/sherpa_onnx*" -name "tts.dart" | head -2
```
Expected: a path. Use that as the local override.

- [ ] **Step 2: Add `voiceState` to the Dart binding**

Edit the Dart `OfflineTtsPocketModelConfig` class — add a `final String voiceState;` field with default `''`, plumb it through the FFI struct and the `validate()` C call. Mirror what the C side expects.

- [ ] **Step 3: pubspec_overrides in flutter_bench**

```yaml
# bench/flutter_bench/pubspec.yaml — add at top level
dependency_overrides:
  sherpa_onnx:
    path: /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx/flutter/sherpa_onnx
```

```bash
cd bench/flutter_bench
flutter pub get
```

- [ ] **Step 4: Push voice-state file to emulator**

```bash
adb push bench/voices/bria.voice-state.bin /data/local/tmp/bench/voices/
```

- [ ] **Step 5: Update flutter_bench main.dart to set `voiceState`**

In `_buildPocket()`, set:

```dart
voiceState: '/data/local/tmp/bench/voices/bria.voice-state.bin',
encoder: '',  // unused when voice_state is set
```

Also add a `pockettts_sherpa_prebake_android` engine row to the bench loop.

- [ ] **Step 6: Build and rerun on emulator**

```bash
cd bench/flutter_bench
flutter build apk --release 2>&1 | tail -3
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am force-stop com.bookbot.flutter_bench
adb shell monkey -p com.bookbot.flutter_bench -c android.intent.category.LAUNCHER 1 2>&1 | tail -1
```
Stream logcat for `___ROW___` and `___DONE___` markers (use Monitor with `grep -E "BENCH|ROW|DONE"`).

- [ ] **Step 7: Pull results, aggregate, commit**

```bash
adb pull /storage/emulated/0/Android/data/com.bookbot.flutter_bench/files/results_android.csv \
    bench/results/results_android_prebake.csv
python -c "
import csv
prebake = list(csv.DictReader(open('bench/results/results_android_prebake.csv')))
print(f'rows: {len(prebake)}')
import statistics
for eng in sorted(set(r['engine'] for r in prebake)):
    rss = [float(r['peak_rss_mb']) for r in prebake if r['engine']==eng]
    rtf = [float(r['rtf']) for r in prebake if r['engine']==eng]
    print(f'{eng}: median_rtf={statistics.median(rtf):.3f} median_peak={statistics.median(rss):.0f}MB')
"
```
Expected: pre-baked engine row shows peak RSS ~50–80 MB lower than the non-pre-baked sherpa Android row (778 MB → ~700 MB). RTF approximately equal.

```bash
git add bench/flutter_bench/lib/main.dart bench/flutter_bench/pubspec.yaml \
        bench/results/results_android_prebake.csv
git commit -m "bench: pocket-tts pre-baked voice state on Android emulator"
```

---

## Task A8: Phase A writeup

**Files:**
- Modify: `bench/results/CONCLUSION-android.md` (add a new section)
- Create: `bench/results/PHASE-A-RESULTS.md`

- [ ] **Step 1: Write up findings**

Use this skeleton for `bench/results/PHASE-A-RESULTS.md`:

```markdown
# Phase A — Pre-baked voice state — Results

**Goal:** Drop encoder.onnx from the on-device runtime by shipping a pre-baked
LM-state .bin generated at build time.

## Headline

| Metric | Before (sherpa int8) | After (sherpa int8 + prebake) | Delta |
|---|---:|---:|---:|
| On-disk model bundle | 213 MB | TBD MB (≤ 141 MB if encoder.onnx + test_wavs/ omitted) | −72 MB |
| Cold-start time on emulator | TBD | TBD | TBD |
| Peak RSS (Android) | 778 MB | TBD | TBD |
| Median RTF (Android, s120) | 0.26 | TBD | within ±5% |

## Reproduction

[exact commands from this plan, copy-pasted]

## Caveats

- One pre-baked file is one fixed voice. To support multiple voices, ship
  one .voice-state.bin per voice (~6 MB each); the runtime path doesn't
  change.
- The sherpa-onnx voice_embedding cache is now redundant (encoder never
  runs). Could simplify the impl by dropping the cache when voice_state
  is set; out of scope for this phase.
```

Fill in the TBDs from Task A7's output.

- [ ] **Step 2: Final commit**

```bash
git add bench/results/PHASE-A-RESULTS.md bench/results/CONCLUSION-android.md
git commit -m "bench: Phase A pre-baked voice state writeup"
```

---

# PHASE B — Phoneme timing

This phase is independent of Phase A. If you're tight on time, ship A first, B can land in a follow-up release.

---

## Task B0: Branches in the second repo

- [ ] **Step 1: pocket-tts feature branch**

```bash
cd /Users/ductran/Documents/codes/python/opensource/pocket-tts
git checkout -b bookbot/attention-output-export origin/main
```

- [ ] **Step 2: sherpa-onnx feature branch (continue from Phase A or fresh)**

If Phase A landed:
```bash
cd /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx
git checkout -b feat/pocket-phoneme-timing feat/pocket-prebaked-voice-state
```

If running B independently:
```bash
git checkout -b feat/pocket-phoneme-timing origin/master
```

---

## Task B1: Patch pocket-tts ONNX export to emit attention weights

**Files in pocket-tts:**
- Modify: `pocket_tts/modules/transformer.py`
- Modify: `pocket_tts/models/tts_model.py`
- Create or modify: `pocket_tts/bin/onnx_export.py`

The Python prototype `bench/pocket_tts_phoneme_timing.py` monkey-patches `StreamingMultiheadAttention.forward` to record `weights[..., text_start:text_end].mean(dim=heads)`. We can't monkey-patch in ONNX — we modify the forward to *return* attention weights when a layer matches the configured layer index.

- [ ] **Step 1: Read the existing forward**

```bash
grep -n "class StreamingMultiheadAttention\|def forward" \
    /Users/ductran/Documents/codes/python/opensource/pocket-tts/pocket_tts/modules/transformer.py | head -10
```

- [ ] **Step 2: Add an attention-weight output**

Modify `StreamingMultiheadAttention.forward` to additionally take `record_attention: bool = False` and, when True, also return `weights` (the post-softmax tensor before matmul with v). Make the change minimal: keep the default behavior identical so non-export callers see no change.

```python
# In transformer.py StreamingMultiheadAttention.forward, after computing
# `weights = F.softmax(scores, dim=-1)`:
self._last_attention = weights if self._record_attention else None
# ...rest of forward unchanged
```

Add an `_record_attention: bool = False` class attribute and a setter `set_record_attention(self, on: bool)`.

- [ ] **Step 3: Add an `attention_capture_layer_index` to the FlowLM transformer**

In `pocket_tts/models/tts_model.py`, expose a config option `attention_layer_index` (default 3, matching the bench prototype) and a method on `TTSModel` that toggles the recording on the chosen layer.

- [ ] **Step 4: Modify the ONNX export**

Find the existing `onnx_export.py` (or equivalent — there isn't a first-party export script in upstream pocket-tts, so you'll create one). The script should:

1. Load FP32 PyTorch model.
2. Wrap the `lm_main` forward to also output attention weights at layer 3 (shape `[batch, time, num_heads, kv_seq_len]` or `[batch, time, kv_seq_len]` after mean-over-heads, matching the prototype).
3. Run `torch.onnx.export` with the new output named `attn_layer_3`.

```python
# pocket_tts/bin/onnx_export_with_attention.py — new file
import argparse
import torch
from pathlib import Path
from pocket_tts import TTSModel

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--layer-index", type=int, default=3)
    args = p.parse_args()

    model = TTSModel.load_model()
    model.eval()
    target_layer = model.flow_lm.transformer.layers[args.layer_index].self_attn
    target_layer._record_attention = True

    # Build a thin wrapper module that forwards lm_main inputs and returns
    # (conditioning, eos_logit, attn_weights).
    class LmMainWithAttention(torch.nn.Module):
        def __init__(self, base, layer):
            super().__init__()
            self.base = base
            self.layer = layer
        def forward(self, seq, embedding, *kv_cache_inputs):
            cond, eos = self.base(seq, embedding, *kv_cache_inputs)
            attn = self.layer._last_attention  # [B, T, H, S]
            attn = attn.mean(dim=2)            # mean over heads -> [B, T, S]
            return cond, eos, attn

    wrapped = LmMainWithAttention(model.flow_lm, target_layer)
    # ... build dummy inputs matching the original lm_main forward signature
    # ... call torch.onnx.export(wrapped, dummy_inputs, args.out, ...)
    # ... output_names must include 'attn_layer_3'
    print(f"Exported to {args.out}")

if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run the export**

```bash
cd /Users/ductran/Documents/codes/python/opensource/pocket-tts
source /Users/ductran/Documents/codes/flutter/bookbot/tts/bench/.venv/bin/activate
python -m pocket_tts.bin.onnx_export_with_attention \
    --out /tmp/lm_main_with_attn.onnx
ls -la /tmp/lm_main_with_attn.onnx
```
Expected: ONNX file ~30–80 MB (FP32 reference, INT8 quant in a follow-up step). Verify outputs:
```bash
python -c "
import onnx
m = onnx.load('/tmp/lm_main_with_attn.onnx')
print([o.name for o in m.graph.output])
"
```
Expected: includes `'attn_layer_3'`.

- [ ] **Step 6: Quantize the new lm_main**

Apply the same `quantize_dynamic` recipe sherpa-onnx used for the existing `lm_main.int8.onnx`:

```python
from onnxruntime.quantization import quantize_dynamic, QuantType
quantize_dynamic("/tmp/lm_main_with_attn.onnx",
                 "/tmp/lm_main.int8.with_attn.onnx",
                 weight_type=QuantType.QInt8)
```
Verify outputs are unchanged (still includes `attn_layer_3`).

- [ ] **Step 7: Verify Python parity with the bench prototype**

Run a short script that loads the new ONNX, generates one utterance, captures `attn_layer_3` per frame, and compares the values to the monkey-patched prototype's output for the same input. Should match to within float-quantization noise.

- [ ] **Step 8: Commit pocket-tts work**

```bash
cd /Users/ductran/Documents/codes/python/opensource/pocket-tts
git add pocket_tts/modules/transformer.py pocket_tts/models/tts_model.py \
        pocket_tts/bin/onnx_export_with_attention.py
git commit -m "feat: ONNX export variant with attention weights output"
```

---

## Task B2: `PocketAligner` — C++ port of the prototype

**Files in sherpa-onnx:**
- Create: `sherpa-onnx/csrc/offline-tts-pocket-aligner.h`
- Create: `sherpa-onnx/csrc/offline-tts-pocket-aligner.cc`

The aligner has zero Pocket-TTS-specific knowledge; it only sees attention curves and a token-to-word map. This file is testable in isolation.

- [ ] **Step 1: Header**

```cpp
// sherpa-onnx/csrc/offline-tts-pocket-aligner.h
#ifndef SHERPA_ONNX_CSRC_OFFLINE_TTS_POCKET_ALIGNER_H_
#define SHERPA_ONNX_CSRC_OFFLINE_TTS_POCKET_ALIGNER_H_

#include <string>
#include <vector>

#include "sherpa-onnx/csrc/offline-tts-frontend.h"  // PhonemeTiming

namespace sherpa_onnx {

struct PocketAlignerConfig {
  int32_t text_start = 0;     // first text-token index in attention seq dim
  int32_t text_end = 0;       // exclusive
  std::vector<int32_t> token_to_word;     // length text_end - text_start
  std::vector<std::string> words;
  std::vector<std::vector<std::string>> word_phonemes;  // [num_words][num_phonemes]
  float frame_dur = 0.080f;   // pocket-tts frame rate is 12.5 Hz
};

class PocketAligner {
 public:
  explicit PocketAligner(PocketAlignerConfig cfg);

  // Feed one frame's attention row over the text tokens.
  // attn_row.size() must equal text_end - text_start.
  // Returns any phoneme events that fired this frame (zero or more).
  std::vector<PhonemeTiming> Step(const std::vector<float> &attn_row);

  // Call once at end-of-utterance to flush remaining phonemes.
  std::vector<PhonemeTiming> Flush();

 private:
  PocketAlignerConfig cfg_;
  int32_t cur_frame_ = 0;
  int32_t cur_word_ = -1;
  int32_t cur_word_first_frame_ = 0;
  int32_t cur_token_ = 0;
};

}  // namespace sherpa_onnx

#endif  // SHERPA_ONNX_CSRC_OFFLINE_TTS_POCKET_ALIGNER_H_
```

- [ ] **Step 2: Implementation — port `_drain_frames` + `_distribute_phonemes`**

```cpp
// sherpa-onnx/csrc/offline-tts-pocket-aligner.cc
#include "sherpa-onnx/csrc/offline-tts-pocket-aligner.h"

#include <algorithm>
#include <cmath>

namespace sherpa_onnx {

PocketAligner::PocketAligner(PocketAlignerConfig cfg) : cfg_(std::move(cfg)) {}

namespace {
std::vector<PhonemeTiming> DistributePhonemes(
    const std::vector<std::string> &phonemes, const std::string &word,
    int32_t word_idx, int32_t start_frame, int32_t end_frame, float dur) {
  std::vector<PhonemeTiming> out;
  if (phonemes.empty()) return out;
  int32_t n_frames = std::max(1, end_frame - start_frame);
  int32_t K = static_cast<int32_t>(phonemes.size());
  out.reserve(K);
  for (int32_t i = 0; i < K; ++i) {
    int32_t s_f = start_frame + static_cast<int32_t>(std::round(
                                    1.0 * i * n_frames / K));
    int32_t e_f = start_frame + static_cast<int32_t>(std::round(
                                    1.0 * (i + 1) * n_frames / K));
    if (e_f <= s_f) e_f = s_f + 1;  // 80 ms minimum
    out.push_back(PhonemeTiming{phonemes[i], word, word_idx,
                                s_f * dur, e_f * dur});
  }
  return out;
}
}  // namespace

std::vector<PhonemeTiming> PocketAligner::Step(
    const std::vector<float> &attn_row) {
  std::vector<PhonemeTiming> events;
  // Monotonic argmax: peak can only stay or move right.
  int32_t local_argmax = cur_token_;
  float best = -std::numeric_limits<float>::infinity();
  for (int32_t i = cur_token_;
       i < static_cast<int32_t>(attn_row.size()); ++i) {
    if (attn_row[i] > best) {
      best = attn_row[i];
      local_argmax = i;
    }
  }
  cur_token_ = local_argmax;
  int32_t tok_word = cfg_.token_to_word[cur_token_];
  if (tok_word >= 0 && tok_word != cur_word_) {
    if (cur_word_ >= 0) {
      auto evs = DistributePhonemes(
          cfg_.word_phonemes[cur_word_], cfg_.words[cur_word_], cur_word_,
          cur_word_first_frame_, cur_frame_, cfg_.frame_dur);
      events.insert(events.end(), evs.begin(), evs.end());
    }
    cur_word_ = tok_word;
    cur_word_first_frame_ = cur_frame_;
  }
  cur_frame_ += 1;
  return events;
}

std::vector<PhonemeTiming> PocketAligner::Flush() {
  std::vector<PhonemeTiming> events;
  if (cur_word_ >= 0) {
    auto evs = DistributePhonemes(
        cfg_.word_phonemes[cur_word_], cfg_.words[cur_word_], cur_word_,
        cur_word_first_frame_, cur_frame_, cfg_.frame_dur);
    events.insert(events.end(), evs.begin(), evs.end());
  }
  return events;
}

}  // namespace sherpa_onnx
```

- [ ] **Step 3: Add `PhonemeTiming` to the frontend header**

In `sherpa-onnx/csrc/offline-tts-frontend.h`, near the top (or wherever `GeneratedAudio` is declared):

```cpp
struct PhonemeTiming {
  std::string phoneme;
  std::string word;
  int32_t word_index = -1;
  float start_s = 0.0f;
  float end_s = 0.0f;
};
```

Add to `GeneratedAudio` (in `generated-audio.h`):

```cpp
std::vector<PhonemeTiming> phoneme_timings;
```

- [ ] **Step 4: Test the aligner against the Python prototype**

Create `sherpa-onnx/csrc/test-offline-tts-pocket-aligner.cc`:

```cpp
#include "sherpa-onnx/csrc/offline-tts-pocket-aligner.h"

#include <gtest/gtest.h>

namespace sherpa_onnx {

TEST(PocketAligner, SingleWordOnePhoneme) {
  PocketAlignerConfig cfg;
  cfg.text_start = 0;
  cfg.text_end = 2;  // tokens 0..1 are word 0
  cfg.token_to_word = {0, 0};
  cfg.words = {"hi"};
  cfg.word_phonemes = {{"h", "aɪ"}};
  cfg.frame_dur = 0.080f;
  PocketAligner a(cfg);
  // 4 frames pointing at token 0, then EOS.
  for (int i = 0; i < 4; ++i) {
    auto evs = a.Step({1.0f, 0.0f});
    EXPECT_TRUE(evs.empty());
  }
  auto flush = a.Flush();
  ASSERT_EQ(flush.size(), 2u);
  EXPECT_EQ(flush[0].phoneme, "h");
  EXPECT_FLOAT_EQ(flush[0].start_s, 0.0f);
  EXPECT_NEAR(flush[1].end_s, 4 * 0.080f, 1e-6);
}

TEST(PocketAligner, AdvancesAcrossWords) {
  PocketAlignerConfig cfg;
  cfg.text_start = 0;
  cfg.text_end = 2;  // token 0 -> word 0, token 1 -> word 1
  cfg.token_to_word = {0, 1};
  cfg.words = {"hi", "yo"};
  cfg.word_phonemes = {{"h"}, {"y"}};
  cfg.frame_dur = 0.080f;
  PocketAligner a(cfg);
  // 2 frames on word 0 token, then 2 frames on word 1 token
  a.Step({1.0f, 0.0f});                       // word 0 first sees frame 0
  a.Step({1.0f, 0.0f});
  auto evs = a.Step({0.0f, 1.0f});            // moves to word 1
  ASSERT_EQ(evs.size(), 1u);                  // word 0 emitted
  EXPECT_EQ(evs[0].word, "hi");
  EXPECT_FLOAT_EQ(evs[0].start_s, 0.0f);
  EXPECT_NEAR(evs[0].end_s, 2 * 0.080f, 1e-6);
}

}  // namespace sherpa_onnx
```

- [ ] **Step 5: Build + run tests**

```bash
cd /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx/build-host
make -j test-offline-tts-pocket-aligner
./bin/test-offline-tts-pocket-aligner
```
Expected: both tests PASS.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx add \
    sherpa-onnx/csrc/offline-tts-pocket-aligner.h \
    sherpa-onnx/csrc/offline-tts-pocket-aligner.cc \
    sherpa-onnx/csrc/test-offline-tts-pocket-aligner.cc \
    sherpa-onnx/csrc/offline-tts-frontend.h \
    sherpa-onnx/csrc/generated-audio.h \
    sherpa-onnx/csrc/CMakeLists.txt
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx commit \
    -m "feat(tts): PocketAligner — monotonic argmax + phoneme distribution"
```

---

## Task B3: Plumb attention output through `RunLmMain`

**Files in sherpa-onnx:**
- Modify: `sherpa-onnx/csrc/offline-tts-pocket-model.h`
- Modify: `sherpa-onnx/csrc/offline-tts-pocket-model.cc`
- Modify: `sherpa-onnx/csrc/offline-tts-pocket-impl.h`

`RunLmMain` currently returns `std::tuple<Ort::Value, Ort::Value, PocketLmMainState>` (conditioning, eos_logit, state). The new ONNX exposes a third tensor (`attn_layer_3`). We extend the tuple to 4 elements.

- [ ] **Step 1: Detect at session-init whether attention output exists**

In `OfflineTtsPocketModel::Impl::Init()`, after fetching `lm_main_output_names_`:

```cpp
has_attention_output_ = std::find(
    lm_main_output_names_.begin(), lm_main_output_names_.end(),
    std::string("attn_layer_3")) != lm_main_output_names_.end();
```

- [ ] **Step 2: Extend RunLmMain tuple**

Change return type to `std::tuple<Ort::Value, Ort::Value, PocketLmMainState, Ort::Value>`. The fourth element is the attention tensor or `Ort::Value{nullptr}` if the model doesn't have it.

- [ ] **Step 3: Update callers in `offline-tts-pocket-impl.h`**

The existing two-call destructure at lines ~324 and ~329 (voice / text conditioning) discards return values — no change needed beyond syntax. The hot loop at line ~368:

```cpp
Ort::Value attn{nullptr};
std::tie(conditioning, eos_logit, lm_main_state, attn) = RunLmMain(
    std::move(cur_tensor), View(&empty_text_tensor), lm_main_state);
```

- [ ] **Step 4: Build**

```bash
cd /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx/build-host
make -j sherpa-onnx-core 2>&1 | tail -8
```
Expected: clean build.

- [ ] **Step 5: Commit**

```bash
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx add \
    sherpa-onnx/csrc/offline-tts-pocket-model.h \
    sherpa-onnx/csrc/offline-tts-pocket-model.cc \
    sherpa-onnx/csrc/offline-tts-pocket-impl.h
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx commit \
    -m "feat(tts): plumb attn_layer_3 through RunLmMain"
```

---

## Task B4: Wire aligner into `GenerateSingleSentence`

**Files in sherpa-onnx:**
- Modify: `sherpa-onnx/csrc/offline-tts-pocket-impl.h`
- Modify: `sherpa-onnx/csrc/offline-tts-frontend.h` (extend GenerationConfig)

Caller passes per-word phoneme lists in `GenerationConfig`. Aligner is invoked per generation step.

- [ ] **Step 1: Extend `GenerationConfig`**

Add:

```cpp
// Optional. If non-empty, the runtime aligns generated frames to these
// per-word phoneme lists and returns per-phoneme timings in
// GeneratedAudio.phoneme_timings. Phoneme strings are opaque (caller
// chooses IPA / ARPAbet / etc.). The model must have been exported with
// attention output enabled or this is a no-op.
std::vector<std::string> phoneme_words;                    // length = num words
std::vector<std::vector<std::string>> phoneme_per_word;    // [num_words][num_phonemes]
std::vector<int32_t> phoneme_token_to_word;                // length = num text tokens
```

- [ ] **Step 2: Build aligner config in GenerateSingleSentence**

After `GetTextEmbedding(text)` and the text-conditioning RunLmMain, before the generation loop:

```cpp
std::unique_ptr<PocketAligner> aligner;
if (model_->HasAttentionOutput() && !gen_config.phoneme_words.empty()) {
  PocketAlignerConfig cfg;
  cfg.text_start = 0;  // attn_layer_3 indexes from text start by construction
  cfg.text_end = static_cast<int32_t>(gen_config.phoneme_token_to_word.size());
  cfg.token_to_word = gen_config.phoneme_token_to_word;
  cfg.words = gen_config.phoneme_words;
  cfg.word_phonemes = gen_config.phoneme_per_word;
  cfg.frame_dur = 0.080f;
  aligner = std::make_unique<PocketAligner>(std::move(cfg));
}
```

- [ ] **Step 3: Per-step aligner feed**

Inside the `for (int32_t step = 0; step < max_frames; ++step)` loop, after the `RunLmMain` call:

```cpp
if (aligner && attn) {
  // attn shape is [1, 1, T_text]. Copy that 1-D slice into a vector<float>.
  auto attn_info = attn.GetTensorTypeAndShapeInfo();
  auto attn_shape = attn_info.GetShape();   // [1, 1, T_text]
  size_t t_text = static_cast<size_t>(attn_shape.back());
  std::vector<float> row(t_text);
  std::memcpy(row.data(), attn.GetTensorData<float>(), t_text * sizeof(float));
  auto evs = aligner->Step(row);
  // accumulate into a member vector for return
  for (auto &e : evs) result_phoneme_timings.push_back(std::move(e));
}
```

After the loop ends:

```cpp
if (aligner) {
  auto evs = aligner->Flush();
  for (auto &e : evs) result_phoneme_timings.push_back(std::move(e));
}
ans.phoneme_timings = std::move(result_phoneme_timings);
```

- [ ] **Step 4: Build + smoke**

```bash
cd /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx/build-host
make -j sherpa-onnx-core 2>&1 | tail -5
```
Expected: clean build.

- [ ] **Step 5: Commit**

```bash
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx add \
    sherpa-onnx/csrc/offline-tts-frontend.h \
    sherpa-onnx/csrc/offline-tts-pocket-impl.h
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx commit \
    -m "feat(tts): wire PocketAligner into pocket-tts inference loop"
```

---

## Task B5: C API

**Files in sherpa-onnx:**
- Modify: `sherpa-onnx/c-api/c-api.h`
- Modify: `sherpa-onnx/c-api/c-api.cc`

- [ ] **Step 1: Add C struct and array to `GeneratedAudio`**

```c
typedef struct SherpaOnnxOfflineTtsPhonemeTiming {
  const char *phoneme;
  const char *word;
  int32_t word_index;
  float start_s;
  float end_s;
} SherpaOnnxOfflineTtsPhonemeTiming;

// Extend SherpaOnnxGeneratedAudio:
//   const SherpaOnnxOfflineTtsPhonemeTiming *phoneme_timings;
//   int32_t num_phoneme_timings;
```

- [ ] **Step 2: Allocate / free**

In `c-api.cc`, fill the array in `SherpaOnnxOfflineTtsGenerateImpl` and add it to the existing destroy function.

- [ ] **Step 3: Build + commit**

```bash
make -j sherpa-onnx-c-api 2>&1 | tail -5
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx add \
    sherpa-onnx/c-api/c-api.h sherpa-onnx/c-api/c-api.cc
git -C /Users/ductran/Documents/codes/ml/bookbot/sherpa-onnx commit \
    -m "feat(tts): C API for phoneme timings"
```

---

## Task B6: Dart binding (local override only)

**Files in `sherpa_onnx` Dart pub package** (local override path discovered in Phase A Task A7):
- Modify: `lib/src/tts.dart` (extend GeneratedAudio class + GenerationConfig)
- Modify: `lib/src/sherpa_onnx_bindings.dart` (FFI struct mapping)

- [ ] **Step 1: Extend Dart `GeneratedAudio`**

```dart
class PhonemeTiming {
  final String phoneme;
  final String word;
  final int wordIndex;
  final double startS;
  final double endS;

  PhonemeTiming({
    required this.phoneme,
    required this.word,
    required this.wordIndex,
    required this.startS,
    required this.endS,
  });
}

class GeneratedAudio {
  GeneratedAudio({
    required this.samples,
    required this.sampleRate,
    this.phonemeTimings = const [],
  });
  final Float32List samples;
  final int sampleRate;
  final List<PhonemeTiming> phonemeTimings;
}
```

- [ ] **Step 2: Read C struct array via FFI**

In the existing `OfflineTts.generateWithConfig` body, after copying samples, walk `result.phoneme_timings[0..num_phoneme_timings)` and build the Dart list. Then call the destroy helper.

- [ ] **Step 3: Add fields to GenerationConfig**

```dart
class OfflineTtsGenerationConfig {
  // ...
  List<String> phonemeWords = const [];
  List<List<String>> phonemePerWord = const [];
  List<int> phonemeTokenToWord = const [];
}
```

Plumb them through the FFI struct.

- [ ] **Step 4: Commit**

In whichever local copy of the Dart package you're using (the one referenced by `dependency_overrides`).

---

## Task B7: G2P + token-to-word data for the bench

**Files in this repo:**
- Create: `bench/voices/alba.tokens.txt`
- Create: `bench/scripts/precompute_phoneme_layout.py`

The aligner needs `token_to_word` (mapping each text token in attention space to its word). That's the SentencePiece tokenization of the input text plus a word-segmentation step. Doing this on-device requires SentencePiece (already linked into sherpa for pocket-tts text_conditioner) plus a G2P. To stay fast and avoid bundling espeak-ng, we precompute `token_to_word + per-word phonemes` *for the bench corpus* in Python and ship them as a JSON sidecar.

- [ ] **Step 1: Generate token + phoneme layout**

```python
# bench/scripts/precompute_phoneme_layout.py
import json, sys
from pathlib import Path
from phonemizer import phonemize
from sentencepiece import SentencePieceProcessor

REPO = Path(__file__).resolve().parents[2]
CORPUS = REPO / "bench" / "corpus.json"
TOKENIZER = REPO / "bench" / "sherpa_models" / "sherpa-onnx-pocket-tts-int8-2026-01-26"
SP_MODEL = "..."  # path inside the model archive; check pocket_tts/conditioners/text.py

def main():
    sp = SentencePieceProcessor(model_file=str(SP_MODEL))
    corpus = json.loads(CORPUS.read_text())
    out = []
    for s in corpus["sentences"]:
        text = s["text"]
        pieces = sp.encode(text, out_type=str)
        # layout_text logic from pocket_tts_phoneme_timing.py — port verbatim
        token_to_word = []
        words = []
        cur = -1
        for p in pieces:
            starts_word = p.startswith("▁")
            body = p.lstrip("▁")
            if starts_word and any(c.isalnum() for c in body):
                cur += 1
                words.append(body)
                token_to_word.append(cur)
            elif starts_word:
                token_to_word.append(-1)
            else:
                if any(c.isalnum() for c in body) and cur >= 0:
                    words[cur] += body
                token_to_word.append(cur)
        per_word = [phonemize(w, language="en-us", backend="espeak",
                              strip=True, with_stress=False).split()
                    for w in words]
        out.append({"id": s["id"], "tokens": pieces, "token_to_word": token_to_word,
                    "words": words, "phonemes": per_word})
    (REPO / "bench" / "voices" / "alba.tokens.json").write_text(
        json.dumps(out, indent=2))

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Commit the precomputed file**

```bash
python bench/scripts/precompute_phoneme_layout.py
git add bench/scripts/precompute_phoneme_layout.py bench/voices/alba.tokens.json
git commit -m "bench: precomputed phoneme layout for the test corpus"
```

---

## Task B8: Update flutter_bench to use phoneme timing

**Files:**
- Modify: `bench/flutter_bench/lib/main.dart`

- [ ] **Step 1: Load the precomputed JSON at startup**

```dart
final layout = jsonDecode(
  File('/data/local/tmp/bench/voices/alba.tokens.json').readAsStringSync(),
) as List;
```

- [ ] **Step 2: For each sentence, pass the layout into `GenerationConfig`**

```dart
final entry = layout.firstWhere((e) => e['id'] == s['id']);
gen.phonemeWords = (entry['words'] as List).cast<String>();
gen.phonemePerWord = (entry['phonemes'] as List).map(
    (l) => (l as List).cast<String>()).toList();
gen.phonemeTokenToWord = (entry['token_to_word'] as List).cast<int>();
```

- [ ] **Step 3: Log the first 3 phoneme timings per row**

```dart
final timings = audio.phonemeTimings;
final preview = timings.take(3).map(
    (p) => '${p.phoneme}@${p.startS.toStringAsFixed(2)}s').join(',');
row['phoneme_timings_preview'] = preview;
row['has_phoneme_timings'] = timings.isNotEmpty;
```

- [ ] **Step 4: Push the layout file to the emulator**

```bash
adb push bench/voices/alba.tokens.json /data/local/tmp/bench/voices/
```

- [ ] **Step 5: Build + run**

Same flow as Task A7 step 6. Expected: log lines now show non-empty `phoneme_timings_preview`, and `has_phoneme_timings` is true.

- [ ] **Step 6: Commit**

```bash
git add bench/flutter_bench/lib/main.dart
git commit -m "bench: consume PhonemeTiming on Android"
```

---

## Task B9: Phase B writeup

**Files:**
- Create: `bench/results/PHASE-B-RESULTS.md`

- [ ] **Step 1: Write up findings**

```markdown
# Phase B — Phoneme timing — Results

## Headline

| Metric | Value |
|---|---|
| Per-phoneme timing produced on Android emulator? | yes / no |
| Avg phoneme events per sentence (s60) | TBD |
| Aligner overhead RTF | TBD (target: < 1% of total) |
| End-to-end RTF impact | TBD |
| Spot check: 5 phoneme timestamps within 80ms of audio? | yes / no |

## Reproduction

[exact commands]

## Caveats

- 12.5 Hz frame rate is the floor on temporal precision: every phoneme
  start/end is quantized to the nearest 80 ms.
- Within a single SentencePiece token the model gives no further signal;
  multi-phoneme tokens use proportional layout, not learned alignment.
- G2P is caller-supplied. The bench precomputes per-word IPA via espeak-ng;
  production callers must supply equivalent data.
```

- [ ] **Step 2: Commit**

```bash
git add bench/results/PHASE-B-RESULTS.md
git commit -m "bench: Phase B phoneme timing writeup"
```

---

## Self-review checklist

After all tasks complete:

- [ ] sherpa-onnx fork builds cleanly with both phases applied (`make -j sherpa-onnx-core`).
- [ ] Both unit tests pass (`test-offline-tts-pocket-voice-state`, `test-offline-tts-pocket-aligner`).
- [ ] `prebake-pocket-voice` produces a file that the runtime can load.
- [ ] Android emulator bench shows: pre-baked peak RSS ≥ 50 MB lower than non-pre-baked; phoneme_timings populated; RTF within ±5% of baseline.
- [ ] Both result writeups (PHASE-A-RESULTS.md, PHASE-B-RESULTS.md) have all TBDs filled in.
- [ ] No unused includes, no commented-out experimental code in committed files.

## Known limitations

- **Multilingual phoneme timing**: the patched ONNX export is English-pinned (layer 3 chosen empirically for the english model). Other language models may need a different `attention_layer_index` — exposed as a config field in B3 step 1 but not validated end-to-end across languages.
- **Voice variety post-prebake**: shipping multiple voices means shipping multiple .voice-state.bin files. ~6 MB each is acceptable for 3–5 stock voices; not a path for user-cloned voices.
- **Upstream PR cost**: Bookbot fork only. Each upstream-PR step would add 1–2 weeks of cross-language binding + review tax. Out of scope.
- **No audio-quality regression test in this plan.** Fast manual A/B listening between baked and non-baked outputs is recommended before shipping; bit-identical output isn't *guaranteed* because numerical paths differ slightly when state is loaded from disk vs built in-process (rounding in TensorProto serialize/deserialize).

---

## Execution suggestion

Phase A first, end-to-end including the Android bench. Land that, ship if it gives enough product value on its own. Then Phase B. Each phase is 4–6 days of focused work for one engineer; the polyglot binding tax (deferred here) doubles that on upstream PRs.

If both phases land, the `bench/flutter_bench/` app demonstrates a phoneme-timing-capable, ~70 MB smaller, sub-real-time on-device Pocket-TTS — close enough to Bookbot's existing capabilities to make a serious replacement-or-augmentation decision possible.
