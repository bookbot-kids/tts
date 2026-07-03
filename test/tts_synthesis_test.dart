import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tts/request_info.dart';
import 'package:tts/tts.dart';
import 'package:tts/tts_method_channel.dart';
import 'package:tts/tts_platform_interface.dart';

class RecordingTtsPlatform
    with MockPlatformInterfaceMixin
    implements TtsPlatform {
  RequestInfo? spokenRequest;
  RequestInfo? generatedRequest;
  RequestInfo? playedRequest;
  var disposed = false;
  final spokenDurations = <num>[];
  final generatedDurations = <num>[];
  String? fastSpeechModel;
  String? melganModel;
  int? initVersion;
  int? initThreadCount;

  @override
  Future<void> initModels(
    String fastSpeechModel,
    String melganModel, {
    int version = 1,
    int threadCount = 1,
  }) async {
    this.fastSpeechModel = fastSpeechModel;
    this.melganModel = melganModel;
    initVersion = version;
    initThreadCount = threadCount;
  }

  @override
  Future<List> speakText(RequestInfo requestInfo) async {
    spokenRequest = requestInfo;
    return spokenDurations;
  }

  @override
  Future<List> generateVoice(RequestInfo requestInfo) async {
    generatedRequest = requestInfo;
    return generatedDurations;
  }

  @override
  Future<List> playVoice(RequestInfo requestInfo) async {
    playedRequest = requestInfo;
    return [];
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  late RecordingTtsPlatform platform;

  setUp(() {
    platform = RecordingTtsPlatform();
    TtsPlatform.instance = platform;
  });

  tearDown(() {
    TtsPlatform.instance = MethodChannelTts();
  });

  group('Tts synthesis requests', () {
    test(
        'speakText appends dot and EOS, sets runtime options, and maps timings',
        () async {
      platform.spokenDurations.addAll([0.1, 0.2, 0.3, 0.4]);
      final request = RequestInfo(
        ['model.onnx'],
        [100, 101],
        ['A', 'B'],
        'en',
        useDot: true,
        logEnabled: false,
      );
      final tts = Tts(version: 9, threadCount: 3);

      final result = await tts.speakText(request, cleanUpVisemes: false);

      expect(platform.spokenRequest, same(request));
      expect(request.inputIds, [100, 101, request.dot, request.eos]);
      expect(request.modelVersion, 9);
      expect(request.threadCount, 3);
      expect(result, [
        {'start': 0.0, 'duration': 0.1, 'token': 'A', 'enabled': true},
        {'start': 0.1, 'duration': 0.2, 'token': 'B', 'enabled': true},
        {
          'start': 0.30000000000000004,
          'duration': 0.3,
          'token': '_',
          'enabled': true
        },
        {
          'start': 0.6000000000000001,
          'duration': 0.4,
          'token': '_',
          'enabled': true
        },
      ]);
    });

    test('speakText appends EOS for empty input when configured', () async {
      platform.spokenDurations.add(0.25);
      final request =
          RequestInfo(['model.onnx'], [], [], 'en', logEnabled: false);

      final result = await Tts().speakText(request, cleanUpVisemes: false);

      expect(request.inputIds, [request.eos]);
      expect(result.single, {
        'start': 0.0,
        'duration': 0.25,
        'token': '_',
        'enabled': true,
      });
    });

    test('speakText appends dot without EOS when only EOS is disabled',
        () async {
      platform.spokenDurations.addAll([0.1]);
      final request = RequestInfo(
        ['model.onnx'],
        [100],
        ['A'],
        'en',
        useDot: true,
        useEos: false,
        logEnabled: false,
      );

      await Tts().speakText(request, cleanUpVisemes: false);

      expect(request.inputIds, [100, request.dot]);
    });

    test('generateVoice mirrors speakText without playback', () async {
      platform.generatedDurations.addAll([0.1, 0.2]);
      final request =
          RequestInfo(['model.onnx'], [100], ['A'], 'en', logEnabled: false);
      final tts = Tts(version: 5, threadCount: 2);

      final result = await tts.generateVoice(request, cleanUpVisemes: false);

      expect(platform.generatedRequest, same(request));
      expect(platform.spokenRequest, isNull);
      expect(request.inputIds, [100, request.eos]);
      expect(request.modelVersion, 5);
      expect(request.threadCount, 2);
      expect(result, [
        {'start': 0.0, 'duration': 0.1, 'token': 'A', 'enabled': true},
        {'start': 0.1, 'duration': 0.2, 'token': '_', 'enabled': true},
      ]);
    });

    test('short non-silent visemes are disabled during cleanup', () async {
      platform.spokenDurations.addAll([0.1, 0.02, 0.3]);
      final request = RequestInfo(['model.onnx'], [100], ['A', 'B'], 'en',
          logEnabled: false);

      final result = await Tts().speakText(
        request,
        cleanUpVisemes: true,
        minDurationInSecond: 0.05,
      );

      expect(result[0]['enabled'], isTrue);
      expect(result[1]['enabled'], isFalse);
      expect(result[2]['enabled'], isTrue);
    });

    test('playVoice, initModels, and dispose delegate to platform', () async {
      final tts = Tts(version: 6, threadCount: 4);
      final request = RequestInfo(['model.onnx'], [1], ['A'], 'en');

      await tts.initModels('fast.onnx', 'melgan.onnx');
      await tts.playVoice(request);
      await tts.dispose();

      expect(platform.fastSpeechModel, 'fast.onnx');
      expect(platform.melganModel, 'melgan.onnx');
      expect(platform.initVersion, 6);
      expect(platform.initThreadCount, 4);
      expect(platform.playedRequest, same(request));
      expect(request.modelVersion, 6);
      expect(request.threadCount, 4);
      expect(platform.disposed, isTrue);
    });
  });

  group('normalizeVisemes', () {
    test('keeps short viseme enabled when previous token is silent', () {
      final visemes = [
        {'start': 0.0, 'duration': 0.1, 'token': '_', 'enabled': true},
        {'start': 0.1, 'duration': 0.02, 'token': 'A', 'enabled': true},
        {'start': 0.12, 'duration': 0.1, 'token': 'B', 'enabled': true},
      ];

      final normalized = Tts().normalizeVisemes(
        visemes,
        minDurationInSecond: 0.05,
        useEos: false,
      );

      expect(normalized[1]['enabled'], isTrue);
    });
  });
}
