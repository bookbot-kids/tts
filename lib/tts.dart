import 'package:csv/csv.dart';
import 'package:csv/csv_settings_autodetection.dart';
import 'package:flutter/services.dart';

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
  static const eos = 95; // end of sentence
  static const dot = 7; // dot (.)
  static const hopSize = 512;
  static const sampleRate = 44100;
  static const silent = '_';

  Future<List> speakText(
    String fastSpeechModel,
    String melganModel,
    List<int> inputIds,
    List<String> visemes, {
    double speed = 1.0,
    int speakerId = 0,
    bool useDot = true,
  }) async {
    if (inputIds.isEmpty) {
      inputIds.add(eos);
    } else {
      if (useDot && inputIds[inputIds.length - 1] != dot) {
        inputIds.add(dot);
      }

      inputIds.add(eos);
    }

    final output = await TtsPlatform.instance.speakText(
        fastSpeechModel, melganModel, inputIds,
        speed: speed, speakerId: speakerId);
    final result = [];
    var dur = 0.0;
    for (var i = 0; i < output.length; i++) {
      final token = i < visemes.length ? visemes[i] : silent;
      result.add({
        'duration': dur * hopSize / sampleRate,
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

  Future<void> loadMapping(String mappingAsset,
      {String language = 'en'}) async {
    // read csv from asset
    final csvData = await rootBundle.loadString(mappingAsset);
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

    final allRows = converter.convert(csvData);
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
}
