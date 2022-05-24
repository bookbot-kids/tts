import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts/tts_method_channel.dart';

void main() {
  MethodChannelTts platform = MethodChannelTts();
  const MethodChannel channel = MethodChannel('tts');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });
}
