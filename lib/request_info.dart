import 'package:tts/tts_configs.dart';

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

  /// End-of-sequence token ID, resolved from [TTSLanguage.eos].
  int eos;

  /// Dot (period) token ID, resolved from [TTSLanguage.dot].
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

  /// Space token ID, resolved from [TTSLanguage.space].
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
    final resolvedLanguage = TTSLanguage.fromCode(language);
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
