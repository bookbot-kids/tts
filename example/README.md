# TTS Example

A demo Flutter app that demonstrates how to use the `tts` plugin for multi-language text-to-speech synthesis.

## Features

- Select between English, Indonesian, and Swahili languages.
- Enter text and press **Speak** to hear synthesised speech.
- Displays IPA phonemes, input IDs, viseme durations, and execution time.
- Performance benchmarking mode for measuring inference times.

## Setup

1. Install [Flutter SDK](https://docs.flutter.dev/get-started/install).
2. Run `flutter pub get` in this directory.
3. Launch an Android emulator or iOS simulator (or connect a real device).
4. Run the app:

```bash
flutter run
```

## Assets

The example app requires the following assets:

- **IPA mapping files** (`assets/tts/`): CSV files mapping IPA phonemes to model input IDs and visemes for each language.
- **Word database** (`assets/WordUniversal.json`): JSON file containing word-to-IPA mappings for all supported languages.
- **ONNX models** (Android: `android/app/src/main/assets/`, iOS: bundle resources): Pre-trained TTS models per language (e.g. `convnext-tts-en.onnx`).

## Usage

1. Select a language (en / id / sw) using the radio buttons.
2. Edit the text field with your desired input.
3. Press **Speak** to run TTS inference and play the audio.
4. View the output showing IPA, input IDs, viseme durations, and total execution time.
