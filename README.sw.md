🌐 [English](README.md) • [Bahasa Indonesia](README.id.md) • **Kiswahili** • [Español](README.es.md)

# TTS

## Programu-jalizi ya Flutter ya Kubadilisha Maandishi Kuwa Sauti (Text-to-Speech)

<p align="center">
    <a href="https://github.com/bookbot-kids/tts/blob/main/LICENSE">
        <img alt="GitHub" src="https://img.shields.io/github/license/bookbot-kids/tts.svg?color=blue">
    </a>
    <a href="https://github.com/bookbot-kids/tts/blob/main/CONTRIBUTING.md">
        <img alt="contributing guidelines" src="https://img.shields.io/badge/contributing-guidelines-brightgreen">
    </a>
</p>

Programu-jalizi ya Flutter ya kubadilisha maandishi kuwa sauti inayofanya kazi kwenye mifumo mingi (Android/iOS) ikitumia miundo maalum ya ONNX Runtime. Maktaba hii hubadilisha mfuatano wa fonimu za IPA (International Phonetic Alphabet) kuwa sauti ya usemi kwa muda wa uchakataji wa karibu papo hapo, ikishadidia lugha mbalimbali zikiwemo Kiingereza, Kiindonesia, Kiswahili, na Kihispania. Pia hutoa data ya muda wa viseme kwa ajili ya uhuishaji wa kulinganisha mwendo wa midomo (lip-sync).

## Vipengele

- Kubadilisha maandishi kuwa sauti kupitia miundo maalum inayotegemea ONNX kwa uchakataji wa ONNX Runtime.
- Ushadidiaji wa lugha nyingi: Kiingereza (na vibadala vya wasemaji vya US/AU/GB), Kiindonesia, Kiswahili, na Kihispania.
- Ulinganishaji wa IPA-kwenda-input ID kwa udhibiti wa kiwango cha fonimu kwenye usanisi wa usemi.
- Utokeaji wa muda wa viseme kwa ajili ya lip-sync na uhuishaji wa mdomo.
- API tofauti za kuzalisha sauti na kuicheza kwa ajili ya udhibiti rahisi wa mtiririko wa sauti.
- Kasi ya usemi, kiwango cha sampuli (sample rate), na idadi ya nyuzi (threads) vinavyoweza kusanidiwa.

## Usakinishaji / Usanidi

- Sakinisha [Flutter SDK](https://docs.flutter.dev/get-started/install).
- Ongeza programu-jalizi hii kwenye `pubspec.yaml` yako:

```yaml
dependencies:
  tts:
    git:
      url: https://github.com/bookbot-kids/tts.git
```

- Weka faili zako za miundo ya ONNX (k.m. `convnext-tts-en.onnx`) na faili za CSV za ulinganishaji wa IPA katika saraka ya assets ya programu yako.
- Sajili assets katika `pubspec.yaml` ya programu yako:

```yaml
flutter:
  assets:
    - assets/tts/en_tts_mapping.csv
    - assets/tts/id_tts_mapping.csv
    - assets/tts/sw_tts_mapping.csv
    - assets/tts/es_tts_mapping.csv
```

### Android

Hakuna usanidi wa ziada mahususi kwa jukwaa unaohitajika kwa Android zaidi ya kujumuisha faili za miundo ya ONNX katika folda ya `assets`.

### iOS

Hakikisha faili za miundo ya ONNX zimejumuishwa katika rasilimali za kifurushi (bundle resources) za mradi wako wa Xcode. Ziongeze kupitia **Build Phases > Copy Bundle Resources** katika Xcode.

## Jinsi ya Kutumia

### Programu ya Mfano ya Flutter

Endesha programu ya mfano iliyo chini ya `example/` ili kuona programu-jalizi ikifanya kazi. Chagua lugha, ingiza maandishi, na bonyeza **Speak** ili kusikia matokeo ya usanisi.

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

1. Unda mfano (instance) wa `Tts` ukiwa na idadi ya nyuzi unayotaka.
2. Pakia faili ya CSV ya ulinganishaji wa IPA kwa lugha lengwa.
3. Gawanya mfuatano wa IPA kuwa tokeni za fonimu binafsi.
4. Tafuta katika ulinganishaji ili kupata `inputIds` (input ya muundo) na `visemes` (tokeni za lip-sync).
5. Bainisha jina la faili la muundo wa ONNX.
6. Sanidi ombi kwa lugha, msemaji, kasi, na vigezo vingine.
7. `speakText` huendesha uchakataji na kucheza sauti, ikirudisha data ya muda wa viseme.

### Kuzalisha na Kucheza Kwa Kutenganisha

Kwa udhibiti zaidi, unaweza kutenganisha uzalishaji wa sauti na uchezaji:

```dart
// Generate voice audio (returns viseme timing without playing)
final durations = await tts.generateVoice(request);

// Play the generated audio buffer
await tts.playVoice(request);
```

### Kuondoa (Dispose)

```dart
await tts.dispose();
```

## Usanifu (Architecture)

Maktaba hii hutumia **Flutter Platform Channels** ili kuwezesha mawasiliano kati ya Dart (Flutter) na msimbo asilia (Android/iOS). Usanifu unafuata muundo wa tabaka tatu:

### 1. Tabaka la Flutter (Dart)

Tabaka la Flutter hutoa API ya kiwango cha juu kupitia darasa la `Tts`, ambalo hushughulikia:

- Upakiaji wa ulinganishaji wa IPA na utafutaji wa fonimu
- Uandaaji wa input ID na viseme
- Usawazishaji wa viseme na usafishaji wa muda
- Mawasiliano na mifumo asilia kupitia `MethodChannel('tts')`

```dart
// Flutter sends command to native platform
await methodChannel.invokeMethod('speakText', requestInfo.toMap());

// Other supported methods: initModels, generateVoice, playVoice, dispose
```

### 2. Daraja la Platform Channel

Method channel hufanya kazi kama daraja kati ya Flutter na msimbo asilia:

| Mbinu | Kusudi |
|--------|---------|
| `initModels` | Pakia faili za miundo ya ONNX kwenye kumbukumbu |
| `speakText` | Endesha uchakataji na ucheze sauti, rudisha muda wa viseme |
| `generateVoice` | Endesha uchakataji pekee, hifadhi buffer ya sauti, rudisha muda wa viseme |
| `playVoice` | Cheza buffer ya sauti iliyozalishwa awali |
| `dispose` | Toa buffer za sauti na rasilimali |

### 3. Tabaka Asilia (Android/iOS)

#### Utekelezaji wa Android (Kotlin)

Msimbo asilia wa Android hushughulikia:

1. **Usimamizi wa Miundo**: Hunakili miundo ya ONNX kutoka assets kwenda hifadhi ya ndani na huipakia kwa ONNX Runtime.
2. **Uchakataji wa ONNX**: Huendesha muundo wa TTS kupitia kichakataji cha `Opti` ukiwa na input tensors (vitambulisho vya fonimu, kasi, kitambulisho cha msemaji).
3. **Uchezaji wa Sauti**: Hutumia `TtsBufferPlayer` pamoja na `AudioTrack` kwa uchezaji wa sauti ya PCM.
4. **Usimamizi wa Kazi**: Hutumia thread pools kwa kazi za uchakataji na uchezaji wa sauti zinazoendeshwa kwa wakati mmoja.

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

#### Utekelezaji wa iOS (Swift)

Msimbo asilia wa iOS hushughulikia:

1. **Upakiaji wa Miundo**: Hupakia miundo ya ONNX kupitia `ORTSession` ikiwa na idadi ya nyuzi inayoweza kusanidiwa.
2. **Uchakataji wa ONNX**: Huendesha muundo wa TTS kupitia kichakataji cha `Opti` ukitumia API ya Objective-C ya ONNX Runtime.
3. **Uchezaji wa Sauti**: Hutumia `AVAudioEngine` na `AVAudioPlayerNode` kwa uchezaji wa sauti ya PCM.
4. **Upangaji wa Kazi kwenye Foleni**: Hutumia `OperationQueue` kwa kazi za uchakataji na uchezaji wa sauti zinazofuatana.

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

### Mtiririko wa Pipeline ya TTS

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

### Maelezo Muhimu ya Kiufundi

1. **Uchakataji wa ONNX Runtime**:
   - Hutumia ONNX Runtime kwa uchakataji wa miundo kwenye mifumo mbalimbali
   - Idadi ya nyuzi inayoweza kusanidiwa kwa usawe wa intra-op (intra-op parallelism)
   - Hushadidia miundo ya wasemaji wengi kupitia input ya kitambulisho cha msemaji
   - Hushadidia miundo ya lugha nyingi kupitia input ya kitambulisho cha lugha

2. **Uchakataji wa Sauti**:
   - Kiwango cha sampuli chaguo-msingi: 44100 Hz
   - Ukubwa wa hop chaguo-msingi: 512
   - Muundo wa matokeo: sauti ya PCM Float32 ya mono
   - Muda kwa kila fonimu hukokotolewa kama: `frame_count * hop_size / sample_rate`

3. **Mfumo wa Viseme**:
   - Hulinganisha fonimu na maumbo ya kuona ya mdomo kwa ajili ya uhuishaji wa lip-sync
   - Viseme za muda mfupi (< 50ms kwa chaguo-msingi) zinaweza kuzimwa kupitia usawazishaji
   - Tokeni ya kimya `_` hutumika kwa vituo na mipaka

4. **Usalama wa Nyuzi (Thread Safety)**:
   - Android: Hutumia thread pools zenye watekelezaji wa nyuzi-moja kwa uchakataji wa kazi zinazofuatana
   - iOS: Hutumia `OperationQueue` yenye idadi ya juu ya operesheni sambamba ya 1
   - Mifumo yote miwili hushadidia ughairi wa kazi kwa maombi ya usemi yaliyokatizwa

## Muundo wa Faili

| Jukwaa | Msimbo | Kazi |
|----------|------|----------|
| Flutter | [`tts.dart`](lib/tts.dart) | Darasa kuu la API: ulinganishaji wa IPA, utafutaji wa fonimu, usanisi wa usemi, usawazishaji wa viseme. |
| Flutter | [`request_info.dart`](lib/request_info.dart) | Usanidi wa ombi: input IDs, njia za miundo, kasi, msemaji, vigezo vya lugha. |
| Flutter | [`tts_platform_interface.dart`](lib/tts_platform_interface.dart) | Kiolesura cha jukwaa kwa uondoaji wa method channel. |
| Flutter | [`tts_method_channel.dart`](lib/tts_method_channel.dart) | Utekelezaji wa method channel kwa mawasiliano na jukwaa asilia. |
| Android | [`TtsPlugin.kt`](android/src/main/kotlin/com/bookbot/tts/TtsPlugin.kt) | Lango la kuingilia la programu-jalizi ya Flutter kwa Android. Huelekeza method calls kwenda `TtsManager`. |
| Android | [`TtsManager.kt`](android/src/main/kotlin/com/tensorspeech/tensorflowtts/tts/TtsManager.kt) | Msimamizi mkuu wa TTS: upakiaji wa miundo, usambazaji wa uchakataji, uratibu wa uchezaji wa sauti. |
| Android | [`Opti.kt`](android/src/main/kotlin/com/tensorspeech/tensorflowtts/module/Opti.kt) | Kifunika cha uchakataji cha ONNX Runtime kwa Android. |
| iOS | [`SwiftTtsPlugin.swift`](ios/Classes/SwiftTtsPlugin.swift) | Lango la kuingilia la programu-jalizi ya Flutter kwa iOS. Huelekeza method calls kwenda `TTS`. |
| iOS | [`TTS.swift`](ios/Classes/TTS.swift) | Msimamizi mkuu wa TTS: upakiaji wa miundo, usambazaji wa uchakataji, uchezaji wa sauti kwa AVAudioEngine. |
| iOS | [`Opti.swift`](ios/Classes/Opti.swift) | Kifunika cha uchakataji cha ONNX Runtime kwa iOS. |
| iOS | [`BaseProcessor.swift`](ios/Classes/BaseProcessor.swift) | Darasa msingi kwa usimamizi wa session ya ONNX kwenye iOS. |

## Viungo na Rasilimali za Kusaidia

- [Nyaraka za wasanidi wa Flutter](https://docs.flutter.dev/)
- [Nyaraka za ONNX Runtime](https://onnxruntime.ai/docs/)
- [Nyaraka za wasanidi wa Android](https://developer.android.com/docs)
- [Nyaraka za wasanidi wa iOS/MacOS](https://developer.apple.com/documentation/)

## Shukrani

[ONNX Runtime](https://github.com/microsoft/onnxruntime)
