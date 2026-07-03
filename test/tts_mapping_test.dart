import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts/tts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final assetFixtures = <String, String>{};

  setUp(() {
    assetFixtures.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      final fixture = assetFixtures[key];
      if (fixture == null) {
        return null;
      }

      final bytes = Uint8List.fromList(utf8.encode(fixture));
      return ByteData.view(bytes.buffer);
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('IPA mapping', () {
    test('loads CSV mappings and searches input ids, visemes, and arpabet',
        () async {
      assetFixtures['assets/en_mapping.csv'] = [
        'ipa,arpabet,ids,visemes',
        't,T,10 11,T V',
        'ʃ,SH,12,SH',
        'oʊ,OW,13 14,O W',
      ].join('\n');

      final tts = Tts();
      await tts.loadIPAsMapping('assets/en_mapping.csv', language: 'en');

      expect(tts.allIPAs['en'], {'t', 'ʃ', 'oʊ'});
      expect(tts.mapping['en']!['oʊ']!.inputIds, [13, 14]);
      expect(tts.mapping['en']!['oʊ']!.visemes, ['O', 'W']);

      final result = tts.search(['t', 'missing', 'oʊ'], language: 'en');
      expect(result['inputIds'], [10, 11, 13, 14]);
      expect(result['visemes'], ['T', 'V', 'O', 'W']);
      expect(result['arpabet'], ['T', '', 'OW']);
    });

    test('breakIPA uses greedy tokenization and splits syllables', () {
      final tts = Tts()
        ..allIPAs['en'] = {
          'a',
          'b',
          'c',
          'tʃ',
          'oʊ',
          'aɪr',
        };

      expect(
        tts.breakIPA('tʃoʊ.aɪrb', language: 'en'),
        ['tʃ', 'oʊ', 'aɪr', 'b'],
      );
    });

    test('normalizeIPA preserves stress markers and syllable separators', () {
      final tts = Tts()
        ..allIPAs['en'] = {
          'h',
          'ɛ',
          'loʊ',
          'w',
          'ɝ',
          'ld',
        };

      expect(
        tts.normalizeIPA("ˈhɛloʊ.wɝld", language: 'en'),
        'ˈh ɛ loʊ . w ɝ ld',
      );
    });
  });

  group('character mapping', () {
    test('loads symbol ids from JSON and visemes from CSV', () async {
      assetFixtures['assets/symbols.json'] = json.encode({
        'symbol_to_id': {
          'a': 21,
          'B': 22,
          '?': 23,
        },
      });
      assetFixtures['assets/visemes.csv'] = [
        'symbol,viseme',
        'a,AA',
        'b,BB',
      ].join('\n');

      final tts = Tts();
      await tts.loadCharactersMapping(
        'assets/symbols.json',
        'assets/visemes.csv',
        language: 'id',
      );

      expect(tts.allIPAs['id'], {'a', 'B', '?'});
      expect(tts.search(['a', 'B', '?'], language: 'id'), {
        'inputIds': [21, 22, 23],
        'visemes': ['AA', 'BB', Tts.silent],
        'arpabet': ['a', 'B', '?'],
      });
    });
  });
}
