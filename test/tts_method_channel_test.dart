import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts/request_info.dart';
import 'package:tts/tts_configs.dart';
import 'package:tts/tts_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tts');
  late MethodChannelTts platform;
  late List<MethodCall> calls;

  setUp(() {
    platform = MethodChannelTts();
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      calls.add(methodCall);
      switch (methodCall.method) {
        case 'speakText':
        case 'generateVoice':
          return [0.1, 0.2];
        case 'initModels':
        case 'playVoice':
        case 'dispose':
          return null;
        default:
          fail('Unexpected method call: ${methodCall.method}');
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('initModels sends model names and runtime options', () async {
    await platform.initModels('fast.onnx', 'melgan.onnx',
        version: 3, threadCount: 4);

    expect(calls.single.method, 'initModels');
    expect(calls.single.arguments, {
      'fastSpeechModel': 'fast.onnx',
      'melganModel': 'melgan.onnx',
      'version': 3,
      'logEnabled': true,
      'threadCount': 4,
    });
  });

  test('speakText invokes native method with serialized request', () async {
    final request = RequestInfo(
      ['model.onnx'],
      [1, 2],
      ['A', 'B'],
      'en',
      speaker: Speaker.us,
      provider: OrtProvider.nnapi,
    );

    final result = await platform.speakText(request);

    expect(result, [0.1, 0.2]);
    expect(calls.single.method, 'speakText');
    expect(calls.single.arguments, request.toMap());
  });

  test('generateVoice invokes native method with serialized request', () async {
    final request = RequestInfo(['model.onnx'], [1], ['A'], 'en');

    final result = await platform.generateVoice(request);

    expect(result, [0.1, 0.2]);
    expect(calls.single.method, 'generateVoice');
    expect(calls.single.arguments, request.toMap());
  });

  test('playVoice invokes native method with serialized request', () async {
    final request = RequestInfo(
      ['model.onnx'],
      [1],
      ['A'],
      'en',
      requestId: 'request-1',
    );

    await platform.playVoice(request);

    expect(calls.single.method, 'playVoice');
    expect(calls.single.arguments, request.toMap());
  });

  test('dispose invokes native dispose', () async {
    await platform.dispose();

    expect(calls.single.method, 'dispose');
    expect(calls.single.arguments, isNull);
  });
}
