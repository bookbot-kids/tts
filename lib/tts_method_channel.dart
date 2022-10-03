import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tts/request_info.dart';

import 'tts_platform_interface.dart';

/// An implementation of [TtsPlatform] that uses method channels.
class MethodChannelTts extends TtsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('tts');

  @override
  Future<List> speakText(RequestInfo requestInfo) async {
    return await methodChannel.invokeMethod('speakText', {
      'fastSpeechModel': requestInfo.fastSpeechModel,
      'melganModel': requestInfo.melganModel,
      'inputIds': requestInfo.inputIds,
      'speed': requestInfo.speed,
      'speakerId': requestInfo.speakerId,
      'sampleRate': requestInfo.sampleRate,
      'hopSize': requestInfo.hopSize,
      'requestId': requestInfo.requestId,
      'singleThread': requestInfo.singleThread,
      'playerCompletedDelayed': requestInfo.playerCompletedDelayed,
      'modelVersion': requestInfo.modelVersion,
    });
  }

  @override
  Future<void> initModels(String fastSpeechModel, String melganModel,
      {int version = 1}) async {
    await methodChannel.invokeMethod('initModels', {
      'fastSpeechModel': fastSpeechModel,
      'melganModel': melganModel,
      'version': version
    });
  }

  @override
  Future<void> playVoice(RequestInfo requestInfo) async {
    await methodChannel.invokeMethod('playVoice', {
      'fastSpeechModel': requestInfo.fastSpeechModel,
      'melganModel': requestInfo.melganModel,
      'inputIds': requestInfo.inputIds,
      'speed': requestInfo.speed,
      'speakerId': requestInfo.speakerId,
      'sampleRate': requestInfo.sampleRate,
      'hopSize': requestInfo.hopSize,
      'requestId': requestInfo.requestId,
      'singleThread': requestInfo.singleThread,
      'playerCompletedDelayed': requestInfo.playerCompletedDelayed,
      'modelVersion': requestInfo.modelVersion,
    });
  }

  @override
  Future<List> generateVoice(RequestInfo requestInfo) async {
    return await methodChannel.invokeMethod('generateVoice', {
      'fastSpeechModel': requestInfo.fastSpeechModel,
      'melganModel': requestInfo.melganModel,
      'inputIds': requestInfo.inputIds,
      'speed': requestInfo.speed,
      'speakerId': requestInfo.speakerId,
      'sampleRate': requestInfo.sampleRate,
      'hopSize': requestInfo.hopSize,
      'requestId': requestInfo.requestId,
      'singleThread': requestInfo.singleThread,
      'playerCompletedDelayed': requestInfo.playerCompletedDelayed,
      'modelVersion': requestInfo.modelVersion,
    });
  }
}
