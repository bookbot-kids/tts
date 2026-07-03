# Home

## Flutter Text-to-Speech Plugin

<p align="center">
    <a href="https://github.com/bookbot-kids/tts/blob/main/LICENSE">
        <img alt="GitHub" src="https://img.shields.io/github/license/bookbot-kids/tts.svg?color=blue">
    </a>
    <a href="https://bookbot-kids.github.io/tts/">
        <img alt="Documentation" src="https://img.shields.io/website/http/bookbot-kids.github.io/tts.svg?down_color=red&down_message=offline&up_message=online">
    </a>
    <a href="https://github.com/bookbot-kids/tts/blob/main/CODE_OF_CONDUCT.md">
        <img alt="Contributor Covenant" src="https://img.shields.io/badge/Contributor%20Covenant-v2.1%20adopted-ff69b4.svg">
    </a>
    <a href="https://github.com/bookbot-kids/tts/blob/main/CONTRIBUTING.md">
        <img alt="contributing guidelines" src="https://img.shields.io/badge/contributing-guidelines-brightgreen">
    </a>
</p>

A cross-platform Android and iOS Flutter text-to-speech plugin using custom
ONNX Runtime models. The library converts IPA phoneme sequences into speech
audio with near-instant inference time, supports multiple languages including
English, Indonesian, Swahili, and Spanish, and returns viseme timing data for
lip-sync animations.

## Features

- Text-to-speech through custom ONNX-based models with ONNX Runtime inference.
- Multi-language support: English with US/AU/GB speaker variants, Indonesian,
  Swahili, and Spanish.
- IPA-to-input ID mapping for phoneme-level control over speech synthesis.
- Viseme timing output for lip-sync and mouth animation.
- Separate voice generation and playback APIs for flexible audio pipeline
  control.
- Configurable speech speed, sample rate, and thread count.

## Installation / Setup

Install the [Flutter SDK](https://docs.flutter.dev/get-started/install), then
add this plugin to your app's `pubspec.yaml`:

```yaml
dependencies:
  tts:
    git:
      url: https://github.com/bookbot-kids/tts.git
```

Place your ONNX model files and IPA mapping CSV files in your app's assets
directory, then register them in your app's `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/tts/en_tts_mapping.csv
    - assets/tts/id_tts_mapping.csv
    - assets/tts/sw_tts_mapping.csv
    - assets/tts/es_tts_mapping.csv
```

### Android

No additional platform-specific setup is required for Android beyond including
the ONNX model files in the app's assets folder.

### iOS

Ensure the ONNX model files are included in your Xcode project's bundle
resources. Add them via **Build Phases > Copy Bundle Resources** in Xcode.

## How to Use

```dart title="main.dart"
import 'package:tts/request_info.dart';
import 'package:tts/tts.dart';

final tts = Tts(threadCount: 1);

await tts.loadIPAsMapping('assets/tts/en_tts_mapping.csv', language: 'en');

final ipas = tts.breakIPA('hɛloʊ wɝld');
final map = tts.search(ipas, language: 'en');
final inputIds = map['inputIds'] as List<int>;
final visemes = map['visemes'] as List<String>;

final request = RequestInfo(
  ['convnext-tts-en.onnx'],
  inputIds,
  visemes,
  'en',
  speaker: Speaker.us,
  speed: 0.82,
);

final output = await tts.speakText(request);
```

The `output` value contains viseme timing data for animation workflows.

For more control, generate voice audio and play it separately:

```dart
final durations = await tts.generateVoice(request);
await tts.playVoice(request);
```

Dispose native resources when the plugin is no longer needed:

```dart
await tts.dispose();
```

## Architecture

This library uses Flutter platform channels to communicate between Dart and
native Android or iOS code.

| Layer | Responsibility |
| --- | --- |
| Flutter | Loads IPA mappings, converts phonemes to input IDs, builds `RequestInfo`, normalizes visemes, and calls native methods through `MethodChannel('tts')`. |
| Platform Channel | Routes `initModels`, `speakText`, `generateVoice`, `playVoice`, and `dispose` calls. |
| Native Android/iOS | Loads ONNX models, runs inference, manages generated audio buffers, and plays PCM audio. |

## Key Technical Details

- ONNX Runtime inference with configurable thread count.
- Default sample rate of 44100 Hz and default hop size of 512.
- PCM Float32 mono audio output.
- Multi-speaker and multi-language model inputs where supported by the model.
- Silent token `_` for pauses and boundaries in viseme timelines.

## File Structure

| Platform | Code | Function |
| --- | --- | --- |
| Flutter | `lib/tts.dart` | Main API class for IPA mapping, phoneme lookup, speech synthesis, and viseme normalization. |
| Flutter | `lib/request_info.dart` | Request configuration for input IDs, model paths, speed, speaker, and language parameters. |
| Flutter | `lib/tts_method_channel.dart` | Method channel implementation for native platform communication. |
| Android | `android/src/main/kotlin/com/bookbot/tts/TtsPlugin.kt` | Flutter plugin entry point for Android. |
| Android | `android/src/main/kotlin/com/tensorspeech/tensorflowtts/tts/TtsManager.kt` | Core TTS manager for model loading, inference dispatch, and playback coordination. |
| iOS | `ios/Classes/SwiftTtsPlugin.swift` | Flutter plugin entry point for iOS. |
| iOS | `ios/Classes/TTS.swift` | Core TTS manager for model loading, inference dispatch, and playback. |

## Helpful Links & Resources

- [Flutter developer documentation](https://docs.flutter.dev/)
- [ONNX Runtime documentation](https://onnxruntime.ai/docs/)
- [Android developer documentation](https://developer.android.com/docs)
- [iOS developer documentation](https://developer.apple.com/documentation/)

## Credits

- [ONNX Runtime](https://github.com/microsoft/onnxruntime)

