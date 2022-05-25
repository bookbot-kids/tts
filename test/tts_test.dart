import 'package:flutter_test/flutter_test.dart';
import 'package:tts/tts.dart';
import 'package:tts/tts_platform_interface.dart';
import 'package:tts/tts_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockTtsPlatform with MockPlatformInterfaceMixin implements TtsPlatform {
  @override
  Future<void> initModels(String fastSpeechModel, String melganModel) {
    throw UnimplementedError();
  }

  @override
  Future<List> speakText(
      String fastSpeechModel, String melganModel, List<int> inputIds,
      {double speed = 1.0, int speakerId = 0}) {
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
