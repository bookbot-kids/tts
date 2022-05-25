import 'package:csv/csv.dart';
import 'package:csv/csv_settings_autodetection.dart';
import 'package:flutter/services.dart';

import 'tts_platform_interface.dart';

class Tts {
  Map<String, Map<String, List<int>>> ipa2InputIds = {};
  static const eos = 95;
  static const dot = 7;

  Future<List> speakText(
    String fastSpeechModel,
    String melganModel,
    List<int> inputIds, {
    double speed = 1.0,
    int speakerId = 0,
    bool useDot = true,
  }) {
    if (inputIds.isEmpty) {
      inputIds.add(eos);
    } else {
      if (useDot && inputIds[inputIds.length - 1] != dot) {
        inputIds.add(dot);
      }

      inputIds.add(eos);
    }

    return TtsPlatform.instance.speakText(
        fastSpeechModel, melganModel, inputIds,
        speed: speed, speakerId: speakerId);
  }

  Future<void> initModels(String fastSpeechModel, String melganModel) {
    return TtsPlatform.instance.initModels(fastSpeechModel, melganModel);
  }

  List<int> searchInputIds(String ipa, {String language = 'en'}) {
    final map = ipa2InputIds.putIfAbsent(language, () => {});
    return map[ipa] ?? [];
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
      final map = ipa2InputIds.putIfAbsent(language, () => {});
      String ids = row[2];
      map[row[0]] = ids
          .split(' ')
          .where((element) => element.trim().isNotEmpty)
          .map((id) => int.parse(id.trim()))
          .toList();
    });
  }
}
