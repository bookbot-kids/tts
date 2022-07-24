import 'package:flutter_test/flutter_test.dart';
import 'package:tts/request_info.dart';
import 'package:tts/tts.dart';
import 'package:tts/tts_platform_interface.dart';
import 'package:tts/tts_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockTtsPlatform with MockPlatformInterfaceMixin implements TtsPlatform {
  @override
  Future<void> initModels(String fastSpeechModel, String melganModel,
      {int version = 1}) {
    throw UnimplementedError();
  }

  @override
  Future<List> speakText(RequestInfo requestInfo) {
    throw UnimplementedError();
  }

  @override
  Future<List> generateVoice(RequestInfo requestInfo) {
    throw UnimplementedError();
  }

  @override
  Future<List> playVoice(RequestInfo requestInfo) {
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
