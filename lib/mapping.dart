import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:csv/csv_settings_autodetection.dart';
import 'package:flutter/services.dart';
import 'package:tts/request_info.dart';
import 'package:tuple/tuple.dart';

class MappingData {
  final String ipa;
  final List<int> inputIds;
  final List<String> visemes;

  MappingData(this.ipa, this.inputIds, this.visemes);
}

class TTSMapping {
  static const silent = '_';
  Map<String, Set<String>> allIPAs = {};
  Map<String, Map<String, MappingData>> mapping = {};

  Future<void> loadIPAsMapping(String mappingAsset,
      {String language = 'en'}) async {
    final allRows = await readCSV(mappingAsset);
    allRows.skip(1).forEach((row) {
      final map = mapping.putIfAbsent(language, () => {});
      String ipa = row[0];
      String ids = row[2];
      String visemes = row[3];
      map[ipa] = MappingData(
          ipa,
          ids
              .split(' ')
              .where((element) => element.trim().isNotEmpty)
              .map((id) => int.parse(id.trim()))
              .toList(),
          visemes
              .split(' ')
              .where((element) => element.trim().isNotEmpty)
              .toList());
    });

    final map = mapping.putIfAbsent(language, () => {});
    allIPAs[language] = map.keys.toSet();
  }

  Future<void> loadCharactersMapping(String jsonPath, String visemePaths,
      {String language = 'id'}) async {
    final jsonData = json.decode(await rootBundle.loadString(jsonPath));
    final visemeRows = (await readCSV(visemePaths)).skip(1).toList();
    final symboyToId = jsonData['symbol_to_id'] as Map;
    final map = mapping.putIfAbsent(language, () => {});
    symboyToId.forEach((symbol, id) {
      var vimes = silent;
      for (var row in visemeRows) {
        if (row[0] == symbol.toString().toLowerCase()) {
          vimes = row[1];
          break;
        }
      }

      map[symbol] = MappingData(symbol, [id], [vimes]);
    });

    allIPAs[language] = map.keys.toSet();
  }

  Future<List<List<E>>> readCSV<E extends dynamic>(String assetPath) async {
    final csvData = await rootBundle.loadString(assetPath);
    var detector = const FirstOccurrenceSettingsDetector(
        fieldDelimiters: [',', ';'],
        textDelimiters: ['"'],
        textEndDelimiters: ['"'],
        eols: ['\r\n', '\n']);
    var converter = CsvToListConverter(
      csvSettingsDetector: detector,
      shouldParseNumbers: false,
      allowInvalid: true,
    );

    final rows = converter.convert<E>(csvData);
    return rows;
  }

  /// Search inputIds & visemes in mapping
  /// return a map with inputIds, visemes keys
  Map<String, dynamic> search(List<String> ipas, {String language = 'en'}) {
    final map = mapping.putIfAbsent(language, () => {});
    final inputIds = <int>[];
    final visemes = <String>[];
    for (final ipa in ipas) {
      inputIds.addAll(map[ipa]?.inputIds ?? []);
      visemes.addAll(map[ipa]?.visemes ?? []);
    }

    return {
      'inputIds': inputIds,
      'visemes': visemes,
    };
  }

  Tuple2<List<int>, List<String>> insertInput(
    List<int> inputIds,
    List<String> visemes,
    String language, {
    bool insertEos = true,
    bool insertBos = true,
    bool insertSpace = false,
  }) {
    final map = mapping.putIfAbsent(language, () => {});
    if (insertBos) {
      // insert bos
      inputIds.insert(0, Parameters.intersperse); // 0
      inputIds.insert(0, Parameters.bosInputIds[language]!); // bos

      visemes.insert(0, '-'); // silent
      final bos = map['^']?.visemes.first;
      visemes.insert(0, bos!);
    }

    if (insertEos) {
      inputIds.insert(inputIds.length, Parameters.intersperse); // -
      inputIds.insert(
          inputIds.length, Parameters.eosInputIds[language]!); // eos

      // insert silent
      visemes.insert(visemes.length, '-');

      // insert eos
      final eos = map['\$']?.visemes.first;
      visemes.insert(visemes.length, eos!);
    }

    if (insertSpace) {
      // insert pad, space, pad at the end
      inputIds.insert(inputIds.length, Parameters.intersperse);
      inputIds.insert(
          inputIds.length, Parameters.specialInputIds[language]![' ']!);
      inputIds.insert(inputIds.length, Parameters.intersperse);

      visemes.insert(visemes.length, '-');
      visemes.insert(visemes.length, '-');
      visemes.insert(visemes.length, '-');
    }

    return Tuple2(inputIds, visemes);
  }

  Map<String, dynamic> generateInput(List<String> ipas,
      {String language = 'en', bool normalizeSentence = false}) {
    if (normalizeSentence) {
      // Add ^ in start and $ at end,
      ipas
        ..insert(0, '^')
        ..insert(ipas.length, '\$');
    }

    //after each phoneme, we need to “intersperse” padding _ token
    for (int i = ipas.length - 1; i > 0; i--) {
      ipas.insert(i, '_');
    }
    // Finally map them into the IDs
    return search(ipas, language: language);
  }
}
