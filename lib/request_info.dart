/// Default audio and token parameters for TTS models across languages.
class Parameters {
  /// Default audio sample rate in Hz.
  static const defaultSampleRate = 44100;

  /// Default hop size (frame shift) in samples, used to convert
  /// duration frames to seconds: `duration_sec = frames * hopSize / sampleRate`.
  static const defaultHopSize = 512;
}

/// Languages supported by the TTS models.
///
/// Each variant carries its [code] (the string used across the public API,
/// e.g. `'en'`) and resolves its model token IDs via [eos] and
/// [specialInputIds]. Both are implemented with exhaustive `switch`
/// statements over this enum, so adding a new language causes a compile-time
/// error until every token mapping is provided — there is no silent fallback.
enum Language {
  /// English.
  en('en'),

  /// Indonesian.
  id('id'),

  /// Swahili.
  sw('sw'),

  /// Spanish.
  es('es');

  /// Language code used in the public API (e.g. `'en'`).
  final String code;

  const Language(this.code);

  /// Resolves a [Language] from its [code], throwing if unsupported.
  static Language fromCode(String code) => Language.values.firstWhere(
        (language) => language.code == code,
        orElse: () => throw ArgumentError('Unsupported language code: $code'),
      );

  /// End-of-sequence token ID for this language.
  int get eos {
    switch (this) {
      case Language.en:
      case Language.id:
      case Language.sw:
      case Language.es:
        return 2;
    }
  }

  /// Maps punctuation/special characters to their model input IDs.
  Map<String, int> get specialInputIds {
    switch (this) {
      case Language.en:
      case Language.id:
      case Language.sw:
      case Language.es:
        return const {
          '!': 4,
          ',': 10,
          '.': 12,
          ':': 13,
          ';': 14,
          '?': 15,
          ' ': 3,
        };
    }
  }

  /// Dot (period) token ID for this language.
  int get dot => specialInputIds['.']!;

  /// Space token ID for this language.
  int get space => specialInputIds[' ']!;
}

/// ONNX Runtime execution provider used for inference.
///
/// Currently only honoured on Android; iOS always uses its default provider.
enum OrtProvider {
  /// Default ONNX Runtime CPU execution provider (most compatible).
  cpu('cpu'),

  /// XNNPACK EP — typically fastest on ARM with multi-threading.
  xnnpack('xnnpack'),

  /// Android NNAPI EP — may fail on unsupported ops (e.g. GATHER rank mismatch).
  nnapi('nnapi');

  /// Native-side identifier sent over the method channel.
  final String nativeName;

  const OrtProvider(this.nativeName);
}

/// Speaker variants for multi-speaker TTS models.
///
/// The [speakerId] is passed to the ONNX model's `sids` input tensor.
/// A value of -1 indicates no speaker ID (single-speaker model).
enum Speaker {
  /// US English speaker.
  us(2),

  /// Australian English speaker.
  au(0),

  /// British English speaker.
  gb(1),

  /// Indonesian (single-speaker, no speaker ID).
  id(-1),

  /// Swahili (single-speaker, no speaker ID).
  sw(-1),

  /// Spanish (single-speaker, no speaker ID).
  es(-1);

  /// Numeric ID passed to the model. -1 means speaker ID is omitted.
  final int speakerId;

  const Speaker(this.speakerId);
}

/// Encapsulates all parameters needed for a single TTS synthesis request.
///
/// Passed from Dart to native platform via [toMap]. The constructor
/// automatically resolves language-specific EOS, dot, and space token IDs
/// from [Parameters].
class RequestInfo {
  /// ONNX model file names (e.g. `['convnext-tts-en.onnx']`).
  final List<String> models;

  /// Phoneme token IDs to feed to the model's `x` input tensor.
  final List<int> inputIds;

  /// Viseme tokens corresponding to each input ID, for lip-sync output.
  final List<String> visemes;

  /// Speech speed ratio. Values < 1.0 produce slower speech.
  double speed;

  /// Speaker variant for multi-speaker models.
  Speaker speaker;

  /// Whether to append a dot (period) token at the end of input IDs.
  bool useDot;

  /// Audio sample rate in Hz.
  int sampleRate;

  /// Hop size for duration-to-seconds conversion.
  int hopSize;

  /// End-of-sequence token ID, resolved from [Language.eos].
  int eos;

  /// Dot (period) token ID, resolved from [Language.dot].
  int dot;

  /// Unique identifier for this request, used for generate/play separation.
  String requestId;

  /// If true, cancels any previously running task before starting this one.
  bool singleThread;

  /// Whether to append an EOS token to input IDs.
  bool useEos;

  /// Model version passed to the native platform.
  int modelVersion;

  /// Enables debug logging on the native side.
  bool logEnabled;

  /// Number of threads for ONNX Runtime intra-op parallelism.
  int threadCount;

  /// Whether to append a space token at the end of input IDs.
  bool useEndSpace;

  /// Language code (e.g. 'en', 'id', 'sw').
  final String language;

  /// Space token ID, resolved from [Language.space].
  int space;

  /// Whether to include language ID (`lids`) input tensor.
  bool enableLids;

  /// Delay in milliseconds before notifying playback completion.
  int playerCompletedDelayed;

  /// ONNX Runtime execution provider. Android-only; iOS ignores this.
  OrtProvider provider;

  RequestInfo(
    this.models,
    this.inputIds,
    this.visemes,
    this.language, {
    this.speed = 1.0,
    this.speaker = Speaker.us,
    this.useDot = false,
    this.sampleRate = Parameters.defaultSampleRate,
    this.hopSize = Parameters.defaultHopSize,
    this.eos = 0,
    this.dot = 0,
    this.requestId = '',
    this.singleThread = true,
    this.playerCompletedDelayed = 0,
    this.useEos = true,
    this.modelVersion = 1,
    this.logEnabled = true,
    this.threadCount = 1,
    this.useEndSpace = false,
    this.space = 0,
    this.enableLids = false,
    this.provider = OrtProvider.cpu,
  }) {
    final resolvedLanguage = Language.fromCode(language);
    eos = resolvedLanguage.eos;
    dot = resolvedLanguage.dot;
    space = resolvedLanguage.space;
  }

  /// Serialises this request to a map for passing over the method channel.
  Map toMap() => {
        'models': models,
        'inputIds': inputIds,
        'speed': speed,
        'speakerId': speaker.speakerId,
        'sampleRate': sampleRate,
        'hopSize': hopSize,
        'requestId': requestId,
        'singleThread': singleThread,
        'playerCompletedDelayed': playerCompletedDelayed,
        'modelVersion': modelVersion,
        'logEnabled': logEnabled,
        'threadCount': threadCount,
        'enableLids': enableLids,
        'provider': provider.nativeName,
      };
}
