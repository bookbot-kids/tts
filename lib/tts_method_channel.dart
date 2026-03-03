import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tts/request_info.dart';

import 'tts_platform_interface.dart';

/// Method-channel implementation of [TtsPlatform].
///
/// Communicates with native Android (Kotlin) and iOS (Swift) code over
/// the `'tts'` [MethodChannel]. Each method serialises [RequestInfo] via
/// [RequestInfo.toMap] and receives native results as platform primitives.
class MethodChannelTts extends TtsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('tts');

  /// Invokes the native `speakText` method to run ONNX inference and play
  /// the resulting audio. Returns a list of per-phoneme durations (seconds).
  @override
  Future<List> speakText(RequestInfo requestInfo) async {
    return await methodChannel.invokeMethod('speakText', requestInfo.toMap());
  }

  /// Invokes the native `initModels` method to pre-load ONNX model files.
  ///
  /// [fastSpeechModel] and [melganModel] are asset file names that the
  /// native side copies from Flutter assets to internal storage (if needed)
  /// and loads into an ONNX Runtime session.
  @override
  Future<void> initModels(String fastSpeechModel, String melganModel,
      {int version = 1, int threadCount = 1}) async {
    await methodChannel.invokeMethod('initModels', {
      'fastSpeechModel': fastSpeechModel,
      'melganModel': melganModel,
      'version': version,
      'logEnabled': true,
      'threadCount': threadCount
    });
  }

  /// Invokes the native `playVoice` method to play a previously cached
  /// audio buffer identified by [RequestInfo.requestId].
  @override
  Future<void> playVoice(RequestInfo requestInfo) async {
    await methodChannel.invokeMethod('playVoice', requestInfo.toMap());
  }

  /// Invokes the native `generateVoice` method to run ONNX inference
  /// without playing audio. The audio buffer is cached for later playback
  /// via [playVoice]. Returns per-phoneme durations (seconds).
  @override
  Future<List> generateVoice(RequestInfo requestInfo) async {
    return await methodChannel.invokeMethod(
        'generateVoice', requestInfo.toMap());
  }

  /// Invokes the native `dispose` method to release audio buffers and
  /// ONNX Runtime resources.
  @override
  Future<void> dispose() async {
    await methodChannel.invokeMethod('dispose');
  }
}
