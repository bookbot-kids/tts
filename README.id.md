🌐 [English](README.md) • **Bahasa Indonesia** • [Kiswahili](README.sw.md) • [Español](README.es.md)

# TTS

## Plugin Text-to-Speech untuk Flutter

<p align="center">
    <a href="https://github.com/bookbot-kids/tts/blob/main/LICENSE">
        <img alt="GitHub" src="https://img.shields.io/github/license/bookbot-kids/tts.svg?color=blue">
    </a>
    <a href="https://github.com/bookbot-kids/tts/blob/main/CONTRIBUTING.md">
        <img alt="contributing guidelines" src="https://img.shields.io/badge/contributing-guidelines-brightgreen">
    </a>
</p>

Plugin text-to-speech Flutter lintas platform (Android/iOS) yang menggunakan model ONNX Runtime kustom. Library ini mengubah urutan fonem IPA (International Phonetic Alphabet) menjadi audio ucapan dengan waktu inferensi yang nyaris instan, serta mendukung berbagai bahasa termasuk Inggris, Indonesia, Swahili, dan Spanyol. Library ini juga menyediakan data pewaktuan viseme untuk animasi lip-sync.

## Fitur

- Text-to-speech melalui model berbasis ONNX kustom dengan inferensi ONNX Runtime.
- Dukungan multi-bahasa: Inggris (dengan varian penutur US/AU/GB), Indonesia, Swahili, dan Spanyol.
- Pemetaan IPA-ke-input ID untuk kontrol sintesis ucapan pada tingkat fonem.
- Keluaran pewaktuan viseme untuk lip-sync dan animasi gerakan mulut.
- API pembuatan suara dan pemutaran yang terpisah untuk kontrol pipeline audio yang fleksibel.
- Kecepatan ucapan, sample rate, dan jumlah thread yang dapat dikonfigurasi.

## Instalasi / Penyiapan

- Pasang [Flutter SDK](https://docs.flutter.dev/get-started/install).
- Tambahkan plugin ini ke `pubspec.yaml` Anda:

```yaml
dependencies:
  tts:
    git:
      url: https://github.com/bookbot-kids/tts.git
```

- Letakkan berkas model ONNX Anda (mis. `convnext-tts-en.onnx`) dan berkas CSV pemetaan IPA di direktori assets aplikasi Anda.
- Daftarkan assets tersebut di `pubspec.yaml` aplikasi Anda:

```yaml
flutter:
  assets:
    - assets/tts/en_tts_mapping.csv
    - assets/tts/id_tts_mapping.csv
    - assets/tts/sw_tts_mapping.csv
    - assets/tts/es_tts_mapping.csv
```

### Android

Tidak diperlukan penyiapan khusus platform tambahan untuk Android selain menyertakan berkas model ONNX di dalam folder `assets`.

### iOS

Pastikan berkas model ONNX disertakan dalam bundle resources proyek Xcode Anda. Tambahkan melalui **Build Phases > Copy Bundle Resources** di Xcode.

## Cara Penggunaan

### Aplikasi Contoh Flutter

Jalankan aplikasi contoh di bawah `example/` untuk melihat plugin ini bekerja. Pilih sebuah bahasa, masukkan teks, lalu tekan **Speak** untuk mendengar keluaran yang disintesis.

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

1. Buat instance `Tts` dengan jumlah thread yang diinginkan.
2. Muat CSV pemetaan IPA untuk bahasa target.
3. Pecah string IPA menjadi token fonem individual.
4. Telusuri pemetaan untuk memperoleh `inputIds` (input model) dan `visemes` (token lip-sync).
5. Tentukan nama berkas model ONNX.
6. Konfigurasikan request dengan bahasa, penutur, kecepatan, dan parameter lainnya.
7. `speakText` menjalankan inferensi dan memutar audio, lalu mengembalikan data pewaktuan viseme.

### Membuat dan Memutar Secara Terpisah

Untuk kontrol yang lebih besar, Anda dapat memisahkan pembuatan suara dari pemutaran:

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

## Arsitektur

Library ini menggunakan **Flutter Platform Channels** untuk memungkinkan komunikasi antara Dart (Flutter) dan kode native (Android/iOS). Arsitekturnya mengikuti desain tiga lapis:

### 1. Lapisan Flutter (Dart)

Lapisan Flutter menyediakan API tingkat tinggi melalui kelas `Tts`, yang menangani:

- Pemuatan pemetaan IPA dan pencarian fonem
- Penyiapan input ID dan viseme
- Normalisasi viseme dan pembersihan pewaktuan
- Komunikasi dengan platform native melalui `MethodChannel('tts')`

```dart
// Flutter sends command to native platform
await methodChannel.invokeMethod('speakText', requestInfo.toMap());

// Other supported methods: initModels, generateVoice, playVoice, dispose
```

### 2. Jembatan Platform Channel

Method channel berperan sebagai jembatan antara Flutter dan kode native:

| Method | Fungsi |
|--------|--------|
| `initModels` | Memuat berkas model ONNX ke dalam memori |
| `speakText` | Menjalankan inferensi dan memutar audio, mengembalikan durasi viseme |
| `generateVoice` | Hanya menjalankan inferensi, menyimpan buffer audio di cache, mengembalikan durasi viseme |
| `playVoice` | Memutar buffer audio yang telah dibuat sebelumnya |
| `dispose` | Melepaskan buffer audio dan sumber daya |

### 3. Lapisan Native (Android/iOS)

#### Implementasi Android (Kotlin)

Kode native Android menangani:

1. **Manajemen Model**: Menyalin model ONNX dari assets ke penyimpanan internal dan memuatnya dengan ONNX Runtime.
2. **Inferensi ONNX**: Menjalankan model TTS melalui prosesor `Opti` dengan tensor input (ID fonem, kecepatan, ID penutur).
3. **Pemutaran Audio**: Menggunakan `TtsBufferPlayer` dengan `AudioTrack` untuk pemutaran audio PCM.
4. **Manajemen Tugas**: Menggunakan thread pool untuk tugas inferensi dan pemutaran audio secara bersamaan.

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

#### Implementasi iOS (Swift)

Kode native iOS menangani:

1. **Pemuatan Model**: Memuat model ONNX melalui `ORTSession` dengan jumlah thread yang dapat dikonfigurasi.
2. **Inferensi ONNX**: Menjalankan model TTS melalui prosesor `Opti` menggunakan ONNX Runtime Objective-C API.
3. **Pemutaran Audio**: Menggunakan `AVAudioEngine` dan `AVAudioPlayerNode` untuk pemutaran audio PCM.
4. **Antrean Tugas**: Menggunakan `OperationQueue` untuk tugas inferensi dan pemutaran audio secara berurutan.

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

### Alur Pipeline TTS

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

### Detail Teknis Utama

1. **Inferensi ONNX Runtime**:
   - Menggunakan ONNX Runtime untuk inferensi model lintas platform
   - Jumlah thread yang dapat dikonfigurasi untuk paralelisme intra-op
   - Mendukung model multi-penutur melalui input ID penutur
   - Mendukung model multi-bahasa melalui input ID bahasa

2. **Pemrosesan Audio**:
   - Sample rate default: 44100 Hz
   - Hop size default: 512
   - Format keluaran: audio mono PCM Float32
   - Durasi per fonem dihitung sebagai: `frame_count * hop_size / sample_rate`

3. **Sistem Viseme**:
   - Memetakan fonem ke bentuk mulut visual untuk animasi lip-sync
   - Viseme berdurasi singkat (< 50ms secara default) dapat dinonaktifkan melalui normalisasi
   - Token hening `_` digunakan untuk jeda dan batas

4. **Keamanan Thread**:
   - Android: Menggunakan thread pool dengan executor single-thread untuk pemrosesan tugas secara berurutan
   - iOS: Menggunakan `OperationQueue` dengan jumlah operasi bersamaan maksimum 1
   - Kedua platform mendukung pembatalan tugas untuk permintaan ucapan yang terinterupsi

## Struktur Berkas

| Platform | Kode | Fungsi |
|----------|------|--------|
| Flutter | [`tts.dart`](lib/tts.dart) | Kelas API utama: pemetaan IPA, pencarian fonem, sintesis ucapan, normalisasi viseme. |
| Flutter | [`request_info.dart`](lib/request_info.dart) | Konfigurasi request: input ID, jalur model, kecepatan, penutur, parameter bahasa. |
| Flutter | [`tts_platform_interface.dart`](lib/tts_platform_interface.dart) | Antarmuka platform untuk abstraksi method channel. |
| Flutter | [`tts_method_channel.dart`](lib/tts_method_channel.dart) | Implementasi method channel untuk komunikasi dengan platform native. |
| Android | [`TtsPlugin.kt`](android/src/main/kotlin/com/bookbot/tts/TtsPlugin.kt) | Titik masuk plugin Flutter untuk Android. Meneruskan pemanggilan method ke `TtsManager`. |
| Android | [`TtsManager.kt`](android/src/main/kotlin/com/tensorspeech/tensorflowtts/tts/TtsManager.kt) | Manajer TTS inti: pemuatan model, dispatch inferensi, koordinasi pemutaran audio. |
| Android | [`Opti.kt`](android/src/main/kotlin/com/tensorspeech/tensorflowtts/module/Opti.kt) | Pembungkus inferensi ONNX Runtime untuk Android. |
| iOS | [`SwiftTtsPlugin.swift`](ios/Classes/SwiftTtsPlugin.swift) | Titik masuk plugin Flutter untuk iOS. Meneruskan pemanggilan method ke `TTS`. |
| iOS | [`TTS.swift`](ios/Classes/TTS.swift) | Manajer TTS inti: pemuatan model, dispatch inferensi, pemutaran audio dengan AVAudioEngine. |
| iOS | [`Opti.swift`](ios/Classes/Opti.swift) | Pembungkus inferensi ONNX Runtime untuk iOS. |
| iOS | [`BaseProcessor.swift`](ios/Classes/BaseProcessor.swift) | Kelas dasar untuk manajemen sesi ONNX pada iOS. |

## Tautan & Sumber Daya yang Bermanfaat

- [Dokumentasi developer Flutter](https://docs.flutter.dev/)
- [Dokumentasi ONNX Runtime](https://onnxruntime.ai/docs/)
- [Dokumentasi developer Android](https://developer.android.com/docs)
- [Dokumentasi developer iOS/MacOS](https://developer.apple.com/documentation/)

## Kredit

[ONNX Runtime](https://github.com/microsoft/onnxruntime)
