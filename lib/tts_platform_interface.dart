import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'tts_method_channel.dart';

abstract class TtsPlatform extends PlatformInterface {
  /// Constructs a TtsPlatform.
  TtsPlatform() : super(token: _token);

  static final Object _token = Object();

  static TtsPlatform _instance = MethodChannelTts();

  /// The default instance of [TtsPlatform] to use.
  ///
  /// Defaults to [MethodChannelTts].
  static TtsPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [TtsPlatform] when
  /// they register themselves.
  static set instance(TtsPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> speakText(
      String fastSpeechModel, String melganModel, String text,
      {double speed = 1.0}) async {
    await _instance.speakText(fastSpeechModel, melganModel, text, speed: speed);
  }

  Future<void> speakPhoneme(
      String fastSpeechModel, String melganModel, List<String> phonemes,
      {double speed = 1.0}) async {
    await _instance.speakPhoneme(fastSpeechModel, melganModel, phonemes,
        speed: speed);
  }

  Future<void> initModels(String fastSpeechModel, String melganModel) async {
    await _instance.initModels(fastSpeechModel, melganModel);
  }
}
