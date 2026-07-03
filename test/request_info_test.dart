import 'package:flutter_test/flutter_test.dart';
import 'package:tts/request_info.dart';
import 'package:tts/tts_configs.dart';

void main() {
  group('RequestInfo', () {
    test('resolves language-specific tokens and serializes channel payload',
        () {
      final request = RequestInfo(
        ['convnext-tts-en.onnx'],
        [42, 43],
        ['A', 'B'],
        'en',
        speed: 0.82,
        speaker: Speaker.gb,
        sampleRate: 24000,
        hopSize: 256,
        requestId: 'request-1',
        singleThread: false,
        playerCompletedDelayed: 150,
        modelVersion: 7,
        logEnabled: false,
        threadCount: 4,
        enableLids: true,
        provider: OrtProvider.xnnpack,
      );

      expect(request.eos, 2);
      expect(request.dot, 12);
      expect(request.space, 3);

      expect(request.toMap(), {
        'models': ['convnext-tts-en.onnx'],
        'inputIds': [42, 43],
        'speed': 0.82,
        'speakerId': 1,
        'sampleRate': 24000,
        'hopSize': 256,
        'requestId': 'request-1',
        'singleThread': false,
        'playerCompletedDelayed': 150,
        'modelVersion': 7,
        'logEnabled': false,
        'threadCount': 4,
        'enableLids': true,
        'provider': 'xnnpack',
      });
    });

    test('constructor rejects unsupported language codes', () {
      expect(
        () => RequestInfo([], [], [], 'fr'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'Unsupported language code: fr',
          ),
        ),
      );
    });
  });
}
