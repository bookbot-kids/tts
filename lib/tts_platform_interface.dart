import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tts/request_info.dart';

import 'tts_method_channel.dart';

/// Abstract platform interface for TTS native operations.
///
/// This class defines the contract that platform-specific implementations
/// (Android, iOS) must fulfil. It uses [PlatformInterface] to ensure that
/// only verified implementations can replace the default instance.
///
/// The default implementation is [MethodChannelTts], which communicates
/// with native code over a `MethodChannel`.
abstract class TtsPlatform extends PlatformInterface {
  /// Constructs a TtsPlatform.
  TtsPlatform() : super(token: _token);

  /// Verification token to prevent unauthorised platform overrides.
  static final Object _token = Object();

  /// Backing field for the singleton [instance].
  static TtsPlatform _instance = MethodChannelTts();

  /// The default instance of [TtsPlatform] to use.
  ///
  /// Defaults to [MethodChannelTts].
  static TtsPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [TtsPlatform] when
  /// they register themselves.
  static set instance(TtsPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Runs TTS inference and plays the resulting audio.
  ///
  /// Returns a list of per-phoneme durations (in seconds) computed by the
  /// native ONNX model.
  Future<List> speakText(RequestInfo requestInfo) async {
    return await _instance.speakText(requestInfo);
  }

  /// Pre-loads the ONNX model files on the native platform.
  ///
  /// [fastSpeechModel] and [melganModel] are asset file names.
  /// Call this before [speakText] or [generateVoice] to avoid cold-start
  /// latency on the first synthesis call.
  Future<void> initModels(String fastSpeechModel, String melganModel,
      {int version = 1, int threadCount = 1}) async {
    await _instance.initModels(fastSpeechModel, melganModel,
        version: version, threadCount: threadCount);
  }

  /// Runs TTS inference without playing audio.
  ///
  /// The generated audio buffer is cached on the native side and can be
  /// played later with [playVoice]. Returns per-phoneme durations.
  Future<List> generateVoice(RequestInfo requestInfo) async {
    return await _instance.generateVoice(requestInfo);
  }

  /// Plays a previously generated audio buffer identified by
  /// [requestInfo.requestId].
  Future<void> playVoice(RequestInfo requestInfo) async {
    await _instance.playVoice(requestInfo);
  }

  /// Releases native audio buffers and ONNX Runtime resources.
  Future<void> dispose() async {
    await _instance.dispose();
  }
}
