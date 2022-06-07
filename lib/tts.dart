import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:csv/csv_settings_autodetection.dart';
import 'package:flutter/services.dart';
import 'package:tts/request_info.dart';

import 'tts_platform_interface.dart';

class MappingData {
  final String ipa;
  final String arpabet;
  final List<int> inputIds;
  final List<String> visemes;

  MappingData(this.ipa, this.arpabet, this.inputIds, this.visemes);
}

class Tts {
  Map<String, Map<String, MappingData>> mapping = {};
  Map<String, Set<String>> allIPAs = {};
  static const silent = '_';

  Future<List> speakText(RequestInfo requestInfo) async {
    if (requestInfo.inputIds.isEmpty) {
      requestInfo.inputIds.add(requestInfo.eos);
    } else {
      if (requestInfo.useDot &&
          requestInfo.inputIds[requestInfo.inputIds.length - 1] !=
              requestInfo.dot) {
        requestInfo.inputIds.add(requestInfo.dot);
      }

      requestInfo.inputIds.add(requestInfo.eos);
    }

    final output = await TtsPlatform.instance.speakText(requestInfo);
    final result = [];
    var dur = 0.0;
    for (var i = 0; i < output.length; i++) {
      final token =
          i < requestInfo.visemes.length ? requestInfo.visemes[i] : silent;
      result.add({
        'duration': dur * requestInfo.hopSize / requestInfo.sampleRate,
        'token': token,
      });
      dur += output[i];
    }
    return result;
  }

  Future<void> initModels(String fastSpeechModel, String melganModel) {
    return TtsPlatform.instance.initModels(fastSpeechModel, melganModel);
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

  Future<List<List<E>>> _readCSV<E extends dynamic>(String assetPath) async {
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

  Future<void> loadIPAsMapping(String mappingAsset,
      {String language = 'en'}) async {
    final allRows = await _readCSV(mappingAsset);
    allRows.skip(1).forEach((row) {
      final map = mapping.putIfAbsent(language, () => {});
      String ipa = row[0];
      String arpabet = row[1];
      String ids = row[2];
      String visemes = row[3];
      map[ipa] = MappingData(
          ipa,
          arpabet,
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
    final visemeRows = (await _readCSV(visemePaths)).skip(1).toList();
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

      map[symbol] = MappingData(symbol, symbol, [id], [vimes]);
    });

    allIPAs[language] = map.keys.toSet();
  }
}
