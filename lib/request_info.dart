/// Default audio and token parameters for TTS models across languages.
class Parameters {
  /// Default audio sample rate in Hz.
  static const defaultSampleRate = 44100;

  /// Default hop size (frame shift) in samples, used to convert
  /// duration frames to seconds: `duration_sec = frames * hopSize / sampleRate`.
  static const defaultHopSize = 512;

  /// End-of-sequence token IDs per language.
  static const enEos = 2;
  static const idEos = 2;
  static const swEos = 2;

  /// Maps language code to its EOS input ID.
  static const eosInputIds = <String, int>{
    'en': enEos,
    'sw': swEos,
    'id': idEos,
  };

  /// Maps language code to a map of punctuation/special characters to their
  /// model input IDs.
  static const specialInputIds = <String, Map<String, int>>{
    'en': {
      '!': 4,
      ',': 10,
      '.': 12,
      ':': 13,
      ';': 14,
      '?': 15,
      ' ': 3,
    },
    'id': {
      '!': 4,
      ',': 10,
      '.': 12,
      ':': 13,
      ';': 14,
      '?': 15,
      ' ': 3,
    },
    'sw': {
      '!': 4,
      ',': 10,
      '.': 12,
      ':': 13,
      ';': 14,
      '?': 15,
      ' ': 3,
    },
  };
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
  sw(-1);

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

  /// End-of-sequence token ID, resolved from [Parameters.eosInputIds].
  int eos;

  /// Dot (period) token ID, resolved from [Parameters.specialInputIds].
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

  /// Space token ID, resolved from [Parameters.specialInputIds].
  int space;

  /// Whether to include language ID (`lids`) input tensor.
  bool enableLids;

  /// Delay in milliseconds before notifying playback completion.
  int playerCompletedDelayed;

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
  }) {
    eos = Parameters.eosInputIds[language]!;
    dot = Parameters.specialInputIds[language]!['.']!;
    space = Parameters.specialInputIds[language]![' ']!;
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
        'enableLids': enableLids
      };
}
