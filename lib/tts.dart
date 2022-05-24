import 'package:flutter/services.dart';

import 'tts_platform_interface.dart';

class Tts {
  final _ipa2ArpabetMap = <String, String>{};
  Future<void> speakText(
      String fastSpeechModel, String melganModel, String text,
      {double speed = 1.0}) {
    return TtsPlatform.instance
        .speakText(fastSpeechModel, melganModel, text, speed: speed);
  }

  Future<void> speakPhoneme(
      String fastSpeechModel, String melganModel, List<String> phonemes,
      {double speed = 1.0}) async {
    if (_ipa2ArpabetMap.isEmpty) {
      await _loadMap();
    }

    // convert ipa to ARPABET
    final arpabets =
        phonemes.map((phoneme) => '{${_ipa2ArpabetMap[phoneme]}}').toList();
    return TtsPlatform.instance
        .speakPhoneme(fastSpeechModel, melganModel, arpabets, speed: speed);
  }

  Future<void> initModels(String fastSpeechModel, String melganModel) {
    return TtsPlatform.instance.initModels(fastSpeechModel, melganModel);
  }

  Future<void> _loadMap() async {
    final map = await rootBundle.loadString('assets/phoneme_mapping.txt');
    final lines = map.split('\n');
    for (final line in lines) {
      final parts = line.split(',');
      if (parts.length == 2) {
        _ipa2ArpabetMap[parts[1]] = parts[0];
      }
    }
  }
}
