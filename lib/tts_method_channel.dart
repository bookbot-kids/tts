import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tts_platform_interface.dart';

/// An implementation of [TtsPlatform] that uses method channels.
class MethodChannelTts extends TtsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('tts');

  @override
  Future<void> speakText(
      String fastSpeechModel, String melganModel, String text,
      {double speed = 1.0}) async {
    await methodChannel.invokeMethod('speakText', {
      'fastSpeechModel': fastSpeechModel,
      'melganModel': melganModel,
      'text': text,
      'speed': speed
    });
  }

  @override
  Future<void> speakPhoneme(
      String fastSpeechModel, String melganModel, List<String> phonemes,
      {double speed = 1.0}) async {
    await methodChannel.invokeMethod('speakText', {
      'fastSpeechModel': fastSpeechModel,
      'melganModel': melganModel,
      'text': phonemes.join(' '),
      'speed': speed
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
