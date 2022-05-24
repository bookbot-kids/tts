import 'package:flutter_test/flutter_test.dart';
import 'package:tts/tts.dart';
import 'package:tts/tts_platform_interface.dart';
import 'package:tts/tts_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockTtsPlatform with MockPlatformInterfaceMixin implements TtsPlatform {
  @override
  Future<void> initModels(String fastSpeechModel, String melganModel) {
    // TODO: implement initModels
    throw UnimplementedError();
  }

  @override
  Future<void> speakPhoneme(
      String fastSpeechModel, String melganModel, List<String> phonemes,
      {double speed = 1.0}) {
    // TODO: implement speakPhoneme
    throw UnimplementedError();
  }

  @override
  Future<void> speakText(
      String fastSpeechModel, String melganModel, String text,
      {double speed = 1.0}) {
    // TODO: implement speakText
    throw UnimplementedError();
  }
}

void main() {
  final TtsPlatform initialPlatform = TtsPlatform.instance;

  test('$MethodChannelTts is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelTts>());
  });

  test('getPlatformVersion', () async {
    Tts ttsPlugin = Tts();
    MockTtsPlatform fakePlatform = MockTtsPlatform();
    TtsPlatform.instance = fakePlatform;
  });
}
