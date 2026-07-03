import 'package:flutter_test/flutter_test.dart';
import 'package:tts/tts_configs.dart';

void main() {
  group('TTSLanguage', () {
    test('resolves every supported code', () {
      expect(TTSLanguage.fromCode('en'), TTSLanguage.en);
      expect(TTSLanguage.fromCode('id'), TTSLanguage.id);
      expect(TTSLanguage.fromCode('sw'), TTSLanguage.sw);
      expect(TTSLanguage.fromCode('es'), TTSLanguage.es);
    });

    test('exposes common special token ids for each language', () {
      for (final language in TTSLanguage.values) {
        expect(language.eos, 2);
        expect(language.space, 3);
        expect(language.dot, 12);
        expect(language.specialInputIds['?'], 15);
      }
    });
  });

  group('Speaker', () {
    test('maps variants to model speaker ids', () {
      expect(Speaker.au.speakerId, 0);
      expect(Speaker.gb.speakerId, 1);
      expect(Speaker.us.speakerId, 2);
      expect(Speaker.id.speakerId, -1);
      expect(Speaker.sw.speakerId, -1);
      expect(Speaker.es.speakerId, -1);
    });
  });

  group('OrtProvider', () {
    test('uses native provider names expected by platform code', () {
      expect(OrtProvider.cpu.nativeName, 'cpu');
      expect(OrtProvider.xnnpack.nativeName, 'xnnpack');
      expect(OrtProvider.nnapi.nativeName, 'nnapi');
    });
  });
}
