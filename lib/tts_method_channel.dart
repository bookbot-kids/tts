import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tts_platform_interface.dart';

/// An implementation of [TtsPlatform] that uses method channels.
class MethodChannelTts extends TtsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('tts');

  @override
  Future<List> speakText(
      String fastSpeechModel, String melganModel, List<int> inputIds,
      {double speed = 1.0, int speakerId = 0}) async {
    return await methodChannel.invokeMethod('speakText', {
      'fastSpeechModel': fastSpeechModel,
      'melganModel': melganModel,
      'inputIds': inputIds,
      'speed': speed,
      'speakerId': speakerId,
    });
  }

  @override
  Future<void> initModels(String fastSpeechModel, String melganModel) async {
    await methodChannel.invokeMethod('initModels', {
      'fastSpeechModel': fastSpeechModel,
      'melganModel': melganModel,
    });
  }
}
