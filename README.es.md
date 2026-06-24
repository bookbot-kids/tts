🌐 [English](README.md) • [Bahasa Indonesia](README.id.md) • [Kiswahili](README.sw.md) • **Español**

# TTS

## Plugin de Texto a Voz para Flutter

<p align="center">
    <a href="https://github.com/bookbot-kids/tts/blob/main/LICENSE">
        <img alt="GitHub" src="https://img.shields.io/github/license/bookbot-kids/tts.svg?color=blue">
    </a>
    <a href="https://github.com/bookbot-kids/tts/blob/main/CONTRIBUTING.md">
        <img alt="contributing guidelines" src="https://img.shields.io/badge/contributing-guidelines-brightgreen">
    </a>
</p>

Un plugin de texto a voz para Flutter multiplataforma (Android/iOS) que utiliza modelos personalizados de ONNX Runtime. La librería convierte secuencias de fonemas IPA (Alfabeto Fonético Internacional) en audio de voz con un tiempo de inferencia casi instantáneo, con soporte para múltiples idiomas, incluyendo inglés, indonesio, suajili y español. También proporciona datos de temporización de visemas para animaciones de sincronización labial.

## Características

- Texto a voz mediante modelos personalizados basados en ONNX con inferencia de ONNX Runtime.
- Soporte multi-idioma: inglés (con variantes de locutor US/AU/GB), indonesio, suajili y español.
- Mapeo de IPA a IDs de entrada para un control a nivel de fonema de la síntesis de voz.
- Salida de temporización de visemas para sincronización labial y animación de la boca.
- APIs separadas de generación y reproducción de voz para un control flexible de la canalización de audio.
- Velocidad de habla, frecuencia de muestreo y número de hilos configurables.

## Instalación / Configuración

- Instala el [Flutter SDK](https://docs.flutter.dev/get-started/install).
- Añade este plugin a tu `pubspec.yaml`:

```yaml
dependencies:
  tts:
    git:
      url: https://github.com/bookbot-kids/tts.git
```

- Coloca tus archivos de modelo ONNX (p. ej. `convnext-tts-en.onnx`) y los archivos CSV de mapeo de IPA en el directorio de assets de tu aplicación.
- Registra los assets en el `pubspec.yaml` de tu aplicación:

```yaml
flutter:
  assets:
    - assets/tts/en_tts_mapping.csv
    - assets/tts/id_tts_mapping.csv
    - assets/tts/sw_tts_mapping.csv
    - assets/tts/es_tts_mapping.csv
```

### Android

No se requiere ninguna configuración adicional específica de la plataforma para Android más allá de incluir los archivos de modelo ONNX en la carpeta `assets`.

### iOS

Asegúrate de que los archivos de modelo ONNX estén incluidos en los recursos del bundle de tu proyecto de Xcode. Agrégalos mediante **Build Phases > Copy Bundle Resources** en Xcode.

## Cómo Usar

### Aplicación de Ejemplo en Flutter

Ejecuta la aplicación de ejemplo en `example/` para ver el plugin en acción. Selecciona un idioma, introduce un texto y presiona **Speak** para escuchar la salida sintetizada.

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

1. Crea una instancia de `Tts` con el número de hilos deseado.
2. Carga el CSV de mapeo de IPA para el idioma objetivo.
3. Divide una cadena IPA en tokens de fonema individuales.
4. Consulta el mapeo para obtener `inputIds` (entrada del modelo) y `visemes` (tokens de sincronización labial).
5. Especifica el nombre del archivo de modelo ONNX.
6. Configura la petición con el idioma, el locutor, la velocidad y otros parámetros.
7. `speakText` ejecuta la inferencia y reproduce el audio, devolviendo los datos de temporización de visemas.

### Generar y Reproducir por Separado

Para un mayor control, puedes separar la generación de voz de la reproducción:

```dart
// Generate voice audio (returns viseme timing without playing)
final durations = await tts.generateVoice(request);

// Play the generated audio buffer
await tts.playVoice(request);
```

### Liberar Recursos

```dart
await tts.dispose();
```

## Arquitectura

Esta librería utiliza **Flutter Platform Channels** para habilitar la comunicación entre Dart (Flutter) y el código nativo (Android/iOS). La arquitectura sigue un diseño de tres capas:

### 1. Capa de Flutter (Dart)

La capa de Flutter proporciona una API de alto nivel a través de la clase `Tts`, que se encarga de:

- La carga del mapeo de IPA y la búsqueda de fonemas
- La preparación de IDs de entrada y visemas
- La normalización de visemas y el ajuste de la temporización
- La comunicación con las plataformas nativas a través de `MethodChannel('tts')`

```dart
// Flutter sends command to native platform
await methodChannel.invokeMethod('speakText', requestInfo.toMap());

// Other supported methods: initModels, generateVoice, playVoice, dispose
```

### 2. Puente del Platform Channel

El method channel actúa como un puente entre Flutter y el código nativo:

| Método | Propósito |
|--------|-----------|
| `initModels` | Carga los archivos de modelo ONNX en memoria |
| `speakText` | Ejecuta la inferencia y reproduce el audio, devuelve las duraciones de los visemas |
| `generateVoice` | Ejecuta solo la inferencia, almacena en caché el búfer de audio, devuelve las duraciones de los visemas |
| `playVoice` | Reproduce un búfer de audio generado previamente |
| `dispose` | Libera los búferes de audio y los recursos |

### 3. Capa Nativa (Android/iOS)

#### Implementación en Android (Kotlin)

El código nativo de Android se encarga de:

1. **Gestión de Modelos**: Copia los modelos ONNX desde los assets al almacenamiento interno y los carga con ONNX Runtime.
2. **Inferencia ONNX**: Ejecuta el modelo de TTS mediante el procesador `Opti` con tensores de entrada (IDs de fonemas, velocidad, ID de locutor).
3. **Reproducción de Audio**: Utiliza `TtsBufferPlayer` con `AudioTrack` para la reproducción de audio PCM.
4. **Gestión de Tareas**: Utiliza pools de hilos para tareas concurrentes de inferencia y reproducción de audio.

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

#### Implementación en iOS (Swift)

El código nativo de iOS se encarga de:

1. **Carga de Modelos**: Carga los modelos ONNX mediante `ORTSession` con un número de hilos configurable.
2. **Inferencia ONNX**: Ejecuta el modelo de TTS mediante el procesador `Opti` usando la API de Objective-C de ONNX Runtime.
3. **Reproducción de Audio**: Utiliza `AVAudioEngine` y `AVAudioPlayerNode` para la reproducción de audio PCM.
4. **Encolado de Tareas**: Utiliza `OperationQueue` para tareas secuenciales de inferencia y reproducción de audio.

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

### Flujo de la Canalización de TTS

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

### Detalles Técnicos Clave

1. **Inferencia con ONNX Runtime**:
   - Utiliza ONNX Runtime para la inferencia de modelos multiplataforma
   - Número de hilos configurable para el paralelismo intra-op
   - Admite modelos multi-locutor mediante la entrada de ID de locutor
   - Admite modelos multi-idioma mediante la entrada de ID de idioma

2. **Procesamiento de Audio**:
   - Frecuencia de muestreo por defecto: 44100 Hz
   - Tamaño de salto (hop size) por defecto: 512
   - Formato de salida: audio mono PCM Float32
   - La duración por fonema se calcula como: `frame_count * hop_size / sample_rate`

3. **Sistema de Visemas**:
   - Mapea los fonemas a formas visuales de la boca para la animación de sincronización labial
   - Los visemas de corta duración (< 50ms por defecto) pueden desactivarse mediante la normalización
   - El token silencioso `_` se utiliza para pausas y límites

4. **Seguridad entre Hilos**:
   - Android: Utiliza pools de hilos con ejecutores de un solo hilo para el procesamiento secuencial de tareas
   - iOS: Utiliza `OperationQueue` con un número máximo de operaciones concurrentes de 1
   - Ambas plataformas admiten la cancelación de tareas para peticiones de voz interrumpidas

## Estructura de Archivos

| Plataforma | Código | Función |
|----------|------|----------|
| Flutter | [`tts.dart`](lib/tts.dart) | Clase principal de la API: mapeo de IPA, búsqueda de fonemas, síntesis de voz, normalización de visemas. |
| Flutter | [`request_info.dart`](lib/request_info.dart) | Configuración de la petición: IDs de entrada, rutas de modelos, velocidad, locutor, parámetros de idioma. |
| Flutter | [`tts_platform_interface.dart`](lib/tts_platform_interface.dart) | Interfaz de plataforma para la abstracción del method channel. |
| Flutter | [`tts_method_channel.dart`](lib/tts_method_channel.dart) | Implementación del method channel para la comunicación con la plataforma nativa. |
| Android | [`TtsPlugin.kt`](android/src/main/kotlin/com/bookbot/tts/TtsPlugin.kt) | Punto de entrada del plugin de Flutter para Android. Enruta las llamadas de método a `TtsManager`. |
| Android | [`TtsManager.kt`](android/src/main/kotlin/com/tensorspeech/tensorflowtts/tts/TtsManager.kt) | Gestor principal de TTS: carga de modelos, despacho de inferencia, coordinación de la reproducción de audio. |
| Android | [`Opti.kt`](android/src/main/kotlin/com/tensorspeech/tensorflowtts/module/Opti.kt) | Envoltorio de inferencia de ONNX Runtime para Android. |
| iOS | [`SwiftTtsPlugin.swift`](ios/Classes/SwiftTtsPlugin.swift) | Punto de entrada del plugin de Flutter para iOS. Enruta las llamadas de método a `TTS`. |
| iOS | [`TTS.swift`](ios/Classes/TTS.swift) | Gestor principal de TTS: carga de modelos, despacho de inferencia, reproducción de audio con AVAudioEngine. |
| iOS | [`Opti.swift`](ios/Classes/Opti.swift) | Envoltorio de inferencia de ONNX Runtime para iOS. |
| iOS | [`BaseProcessor.swift`](ios/Classes/BaseProcessor.swift) | Clase base para la gestión de sesiones ONNX en iOS. |

## Enlaces y Recursos Útiles

- [Documentación para desarrolladores de Flutter](https://docs.flutter.dev/)
- [Documentación de ONNX Runtime](https://onnxruntime.ai/docs/)
- [Documentación para desarrolladores de Android](https://developer.android.com/docs)
- [Documentación para desarrolladores de iOS/MacOS](https://developer.apple.com/documentation/)

## Créditos

[ONNX Runtime](https://github.com/microsoft/onnxruntime)
