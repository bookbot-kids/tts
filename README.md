# TTS

## Flutter Text-to-Speech Plugin

<p align="center">
    <a href="https://github.com/bookbot-kids/tts/blob/main/LICENSE">
        <img alt="GitHub" src="https://img.shields.io/github/license/bookbot-kids/tts.svg?color=blue">
    </a>
    <a href="https://github.com/bookbot-kids/tts/blob/main/CONTRIBUTING.md">
        <img alt="contributing guidelines" src="https://img.shields.io/badge/contributing-guidelines-brightgreen">
    </a>
</p>

A cross-platform (Android/iOS) Flutter text-to-speech plugin using custom ONNX Runtime models. The library converts IPA (International Phonetic Alphabet) phoneme sequences into speech audio with near-instant inference time, supporting multiple languages including English, Indonesian, and Swahili. It also provides viseme timing data for lip-sync animations.

## Features

- Text-to-speech through custom ONNX-based models with ONNX Runtime inference.
- Multi-language support: English (with US/AU/GB speaker variants), Indonesian, and Swahili.
- IPA-to-input ID mapping for phoneme-level control over speech synthesis.
- Viseme timing output for lip-sync and mouth animation.
- Separate voice generation and playback APIs for flexible audio pipeline control.
- Configurable speech speed, sample rate, and thread count.

## Installation / Setup

- Install [Flutter SDK](https://docs.flutter.dev/get-started/install).
- Add this plugin to your `pubspec.yaml`:

```yaml
dependencies:
  tts:
    git:
      url: https://github.com/bookbot-kids/tts.git
```

- Place your ONNX model files (e.g. `convnext-tts-en.onnx`) and IPA mapping CSV files in your app's assets directory.
- Register the assets in your app's `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/tts/en_tts_mapping.csv
    - assets/tts/id_tts_mapping.csv
    - assets/tts/sw_tts_mapping.csv
```

### Android

No additional platform-specific setup is required for Android beyond including the ONNX model files in the `assets` folder.

### iOS

Ensure the ONNX model files are included in your Xcode project's bundle resources. Add them via **Build Phases > Copy Bundle Resources** in Xcode.

## How to Use

### Flutter Sample App

Run the example app under `example/` to see the plugin in action. Select a language, enter text, and press **Speak** to hear the synthesised output.

```dart title="main.dart"
import 'package:tts/tts.dart';
import 'package:tts/request_info.dart';

final tts = Tts(threadCount: 1); // (1)

// Load IPA-to-input ID mapping for a language
await tts.loadIPAsMapping('assets/tts/en_tts_mapping.csv', language: 'en'); // (2)

// Convert IPA phonemes to input IDs and visemes
final ipas = tts.breakIPA('hɛloʊ wɝld'); // (3)
final map = tts.search(ipas, language: 'en'); // (4)
final inputIds = map['inputIds'] as List<int>;
final visemes = map['visemes'] as List<String>;

// Build request and synthesise speech
final request = RequestInfo(
  ['convnext-tts-en.onnx'], // (5)
  inputIds,
  visemes,
  'en',
  speaker: Speaker.us,
  speed: 0.82,
); // (6)

final output = await tts.speakText(request); // (7)
// output contains viseme timing data: [{start, duration, token, enabled}, ...]
```

1. Create a `Tts` instance with desired thread count.
2. Load the IPA mapping CSV for the target language.
3. Break an IPA string into individual phoneme tokens.
4. Search the mapping to get `inputIds` (model input) and `visemes` (lip-sync tokens).
5. Specify the ONNX model file name.
6. Configure the request with language, speaker, speed, and other parameters.
7. `speakText` runs inference and plays audio, returning viseme timing data.

### Generate and Play Separately

For more control, you can separate voice generation from playback:

```dart
// Generate voice audio (returns viseme timing without playing)
final durations = await tts.generateVoice(request);

// Play the generated audio buffer
await tts.playVoice(request);
```

### Dispose

```dart
await tts.dispose();
```

## Architecture

This library uses **Flutter Platform Channels** to enable communication between Dart (Flutter) and native code (Android/iOS). The architecture follows a three-layer design:

### 1. Flutter Layer (Dart)

The Flutter layer provides a high-level API through the `Tts` class, which handles:

- IPA mapping loading and phoneme lookup
- Input ID and viseme preparation
- Viseme normalization and timing cleanup
- Communication with native platforms via `MethodChannel('tts')`

```dart
// Flutter sends command to native platform
await methodChannel.invokeMethod('speakText', requestInfo.toMap());

// Other supported methods: initModels, generateVoice, playVoice, dispose
```

### 2. Platform Channel Bridge

The method channel acts as a bridge between Flutter and native code:

| Method | Purpose |
|--------|---------|
| `initModels` | Load ONNX model files into memory |
| `speakText` | Run inference and play audio, return viseme durations |
| `generateVoice` | Run inference only, cache audio buffer, return viseme durations |
| `playVoice` | Play a previously generated audio buffer |
| `dispose` | Release audio buffers and resources |

### 3. Native Layer (Android/iOS)

#### Android Implementation (Kotlin)

The Android native code handles:

1. **Model Management**: Copies ONNX models from assets to internal storage and loads them with ONNX Runtime.
2. **ONNX Inference**: Runs the TTS model via `Opti` processor with input tensors (phoneme IDs, speed, speaker ID).
3. **Audio Playback**: Uses `TtsBufferPlayer` with `AudioTrack` for PCM audio playback.
4. **Task Management**: Uses thread pools for concurrent inference and audio playback tasks.

```kotlin
// Android: Handling method calls from Flutter
override fun onMethodCall(call: MethodCall, result: Result) {
    when(call.method) {
        "initModels" -> { /* Load ONNX models */ }
        "speakText" -> { /* Run inference + play audio */ }
        "generateVoice" -> { /* Run inference, cache buffer */ }
        "playVoice" -> { /* Play cached audio buffer */ }
        "dispose" -> { /* Clean up resources */ }
    }
}
```

#### iOS Implementation (Swift)

The iOS native code handles:

1. **Model Loading**: Loads ONNX models via `ORTSession` with configurable thread count.
2. **ONNX Inference**: Runs the TTS model via `Opti` processor using ONNX Runtime Objective-C API.
3. **Audio Playback**: Uses `AVAudioEngine` and `AVAudioPlayerNode` for PCM audio playback.
4. **Task Queuing**: Uses `OperationQueue` for sequential inference and audio playback tasks.

```swift
// iOS: Handling method calls from Flutter
public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initModels": /* Load ONNX models */
    case "speakText": /* Run inference + play audio */
    case "generateVoice": /* Run inference, cache buffer */
    case "playVoice": /* Play cached audio buffer */
    case "dispose": /* Clean up resources */
    }
}
```

### TTS Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App (Dart)                        │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  1. Load IPA mapping CSV                                  │  │
│  │  2. Convert word → IPA → inputIds + visemes               │  │
│  │  3. Build RequestInfo with model, speed, speaker          │  │
│  │  4. Call tts.speakText(request)                           │  │
│  └───────────────────────┬───────────────────────────────────┘  │
└────────────────────────────┼─────────────────────────────────────┘
                             │ Method Channel ('tts')
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Native Platform (Android/iOS)                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  1. Load ONNX model (if not already loaded)               │  │
│  │  2. Create input tensors:                                 │  │
│  │     • x: phoneme input IDs [1, seq_len]                   │  │
│  │     • x_lengths: sequence length [1]                      │  │
│  │     • scales: [speed, 1.0, 1.0]                           │  │
│  │     • sids: speaker ID (optional)                         │  │
│  │     • lids: language ID (optional)                        │  │
│  │  3. Run ONNX Runtime inference                            │  │
│  │  4. Extract wav audio + duration outputs                  │  │
│  └───────────────────────┬───────────────────────────────────┘  │
│                          │                                       │
│  ┌───────────────────────▼───────────────────────────────────┐  │
│  │  Audio Playback:                                          │  │
│  │  • Android: AudioTrack with PCM Float32                   │  │
│  │  • iOS: AVAudioEngine + AVAudioPlayerNode                 │  │
│  └───────────────────────┬───────────────────────────────────┘  │
│                          │ Method Channel Result                 │
└────────────────────────────┼─────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Flutter App (Dart)                            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Receive viseme durations (seconds per phoneme)           │  │
│  │  Normalize visemes and build lip-sync timeline            │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Technical Details

1. **ONNX Runtime Inference**:
   - Uses ONNX Runtime for cross-platform model inference
   - Configurable thread count for intra-op parallelism
   - Supports multi-speaker models via speaker ID input
   - Supports multi-language models via language ID input

2. **Audio Processing**:
   - Default sample rate: 44100 Hz
   - Default hop size: 512
   - Output format: PCM Float32 mono audio
   - Duration per phoneme computed as: `frame_count * hop_size / sample_rate`

3. **Viseme System**:
   - Maps phonemes to visual mouth shapes for lip-sync animation
   - Short-duration visemes (< 50ms by default) can be disabled via normalization
   - Silent token `_` used for pauses and boundaries

4. **Thread Safety**:
   - Android: Uses thread pools with single-threaded executors for sequential task processing
   - iOS: Uses `OperationQueue` with max concurrent operation count of 1
   - Both platforms support task cancellation for interrupted speech requests

## File Structure

| Platform | Code | Function |
|----------|------|----------|
| Flutter | [`tts.dart`](lib/tts.dart) | Main API class: IPA mapping, phoneme lookup, speech synthesis, viseme normalization. |
| Flutter | [`request_info.dart`](lib/request_info.dart) | Request configuration: input IDs, model paths, speed, speaker, language parameters. |
| Flutter | [`tts_platform_interface.dart`](lib/tts_platform_interface.dart) | Platform interface for method channel abstraction. |
| Flutter | [`tts_method_channel.dart`](lib/tts_method_channel.dart) | Method channel implementation for native platform communication. |
| Android | [`TtsPlugin.kt`](android/src/main/kotlin/com/bookbot/tts/TtsPlugin.kt) | Flutter plugin entry point for Android. Routes method calls to `TtsManager`. |
| Android | [`TtsManager.kt`](android/src/main/kotlin/com/tensorspeech/tensorflowtts/tts/TtsManager.kt) | Core TTS manager: model loading, inference dispatch, audio playback coordination. |
| Android | [`Opti.kt`](android/src/main/kotlin/com/tensorspeech/tensorflowtts/module/Opti.kt) | ONNX Runtime inference wrapper for Android. |
| iOS | [`SwiftTtsPlugin.swift`](ios/Classes/SwiftTtsPlugin.swift) | Flutter plugin entry point for iOS. Routes method calls to `TTS`. |
| iOS | [`TTS.swift`](ios/Classes/TTS.swift) | Core TTS manager: model loading, inference dispatch, audio playback with AVAudioEngine. |
| iOS | [`Opti.swift`](ios/Classes/Opti.swift) | ONNX Runtime inference wrapper for iOS. |
| iOS | [`BaseProcessor.swift`](ios/Classes/BaseProcessor.swift) | Base class for ONNX session management on iOS. |

## Helpful Links & Resources

- [Flutter developer documentation](https://docs.flutter.dev/)
- [ONNX Runtime documentation](https://onnxruntime.ai/docs/)
- [Android developer documentation](https://developer.android.com/docs)
- [iOS/MacOS developer documentation](https://developer.apple.com/documentation/)

## Credits

[ONNX Runtime](https://github.com/microsoft/onnxruntime)
