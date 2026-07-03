import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tts/request_info.dart';
import 'package:tts/tts_method_channel.dart';
import 'package:tts/tts_platform_interface.dart';

class MockTtsPlatform with MockPlatformInterfaceMixin implements TtsPlatform {
  @override
  Future<void> initModels(
    String fastSpeechModel,
    String melganModel, {
    int version = 1,
    int threadCount = 1,
  }) async {}

  @override
  Future<List> speakText(RequestInfo requestInfo) async => [];

  @override
  Future<List> generateVoice(RequestInfo requestInfo) async => [];

  @override
  Future<List> playVoice(RequestInfo requestInfo) async => [];

  @override
  Future<void> dispose() async {}
}

class InvalidTtsPlatform implements TtsPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(() {
    TtsPlatform.instance = MethodChannelTts();
  });

  test('MethodChannelTts is the default platform instance', () {
    expect(TtsPlatform.instance, isInstanceOf<MethodChannelTts>());
  });

  test('allows verified mock platform implementations in tests', () {
    final fakePlatform = MockTtsPlatform();

    TtsPlatform.instance = fakePlatform;

    expect(TtsPlatform.instance, same(fakePlatform));
  });

  test('rejects unverified platform implementations', () {
    expect(
      () => TtsPlatform.instance = InvalidTtsPlatform(),
      throwsA(isA<AssertionError>()),
    );
  });
}
