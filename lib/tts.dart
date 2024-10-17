import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:csv/csv_settings_autodetection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
  final int version;
  final int threadCount;

  Tts({
    this.version = 1,
    this.threadCount = 1,
  });

  Future<List> speakText(
    RequestInfo requestInfo, {
    bool cleanUpVisemes = true,
    double minDurationInSecond = 0.05,
    bool debug = false,
  }) async {
    if (requestInfo.inputIds.isEmpty) {
      if (requestInfo.useEos) {
        requestInfo.inputIds.add(requestInfo.eos);
      }
    } else {
      if (requestInfo.useDot &&
          requestInfo.inputIds[requestInfo.inputIds.length - 1] !=
              requestInfo.dot) {
        requestInfo.inputIds.add(requestInfo.dot);
      }

      if (requestInfo.useEos) {
        requestInfo.inputIds.add(requestInfo.eos);
      }
    }

    if (debug || requestInfo.logEnabled) {
      // ignore: avoid_print
      print('inputIds: ${requestInfo.inputIds}');
    }

    requestInfo.modelVersion = version;
    requestInfo.threadCount = threadCount;
    final output = await TtsPlatform.instance.speakText(requestInfo);
    final result = [];
    var dur = 0.0;
    for (var i = 0; i < output.length; i++) {
      final token =
          i < requestInfo.visemes.length ? requestInfo.visemes[i] : silent;

      result.add({
        'start': dur,
        'duration': output[i],
        'token': token,
        'enabled': true,
      });
      dur += output[i];
    }

    return cleanUpVisemes
        ? normalizeVisemes(
            result,
            minDurationInSecond: minDurationInSecond,
            useEos: requestInfo.useEos,
          )
        : result;
  }

  Future<void> playVoice(RequestInfo requestInfo) async {
    requestInfo.modelVersion = version;
    requestInfo.threadCount = threadCount;
    await TtsPlatform.instance.playVoice(requestInfo);
  }

  Future<List> generateVoice(
    RequestInfo requestInfo, {
    bool cleanUpVisemes = true,
    double minDurationInSecond = 0.05,
  }) async {
    if (requestInfo.inputIds.isEmpty) {
      if (requestInfo.useEos) {
        requestInfo.inputIds.add(requestInfo.eos);
      }
    } else {
      if (requestInfo.useDot &&
          requestInfo.inputIds[requestInfo.inputIds.length - 1] !=
              requestInfo.dot) {
        requestInfo.inputIds.add(requestInfo.dot);
      }

      if (requestInfo.useEos) {
        requestInfo.inputIds.add(requestInfo.eos);
      }
    }

    requestInfo.modelVersion = version;
    requestInfo.threadCount = threadCount;
    final output = await TtsPlatform.instance.generateVoice(requestInfo);
    final result = [];
    var dur = 0.0;
    for (var i = 0; i < output.length; i++) {
      final token =
          i < requestInfo.visemes.length ? requestInfo.visemes[i] : silent;
      result.add({
        'start': dur,
        'duration': output[i],
        'token': token,
        'enabled': true,
      });
      dur += output[i];
    }

    return cleanUpVisemes
        ? normalizeVisemes(
            result,
            minDurationInSecond: minDurationInSecond,
            useEos: requestInfo.useEos,
          )
        : result;
  }

  /// Disable visemes that are too short by `enabled` key
  List normalizeVisemes(
    List visemes, {
    double minDurationInSecond = 0.05,
    bool useEos = true,
  }) {
    // ignore the last eos by length - 2
    final length = visemes.length - (useEos ? 2 : 1);
    for (var i = length; i >= 0; i--) {
      double duration = visemes[i]['duration'];
      // disable duration less than min
      if (i - 1 >= 0) {
        String previousViseme = visemes[i - 1]['token'];
        if (duration < minDurationInSecond &&
            previousViseme != silent &&
            i != visemes.length - 1) {
          visemes[i]['enabled'] = false;
        }
      }
    }

    return visemes;
  }

  List<String> breakIPA(String ipas, {String language = 'en'}) {
    final allIPAs = this.allIPAs[language] ?? {};
    final result = <String>[];
    for (final ipa in ipas.split('.')) {
      final characters = ipa.characters.toList();
      final length = characters.length;
      for (var i = 0; i < length; i++) {
        // 3 letters ipa
        if (i < length - 2) {
          final combine =
              '${characters[i]}${characters[i + 1]}${characters[i + 2]}';
          if (allIPAs.contains(combine)) {
            result.add(combine);
            i += 2;
            continue;
          }
        }

        // 2 letters ipa
        if (i < length - 1) {
          final combine = '${characters[i]}${characters[i + 1]}';
          if (allIPAs.contains(combine)) {
            result.add(combine);
            i++;
          } else {
            result.add(characters[i]);
          }
        } else {
          result.add(characters[i]);
        }
      }
    }

    return result;
  }

  Future<void> initModels(
    String fastSpeechModel,
    String melganModel,
  ) {
    return TtsPlatform.instance.initModels(fastSpeechModel, melganModel,
        version: version, threadCount: threadCount);
  }

  /// Search inputIds & visemes in mapping
  /// return a map with inputIds, visemes keys
  Map<String, dynamic> search(List<String> ipas, {String language = 'en'}) {
    final map = mapping.putIfAbsent(language, () => {});
    final inputIds = <int>[];
    final visemes = <String>[];
    final arpabets = <String>[];
    for (final ipa in ipas) {
      inputIds.addAll(map[ipa]?.inputIds ?? []);
      visemes.addAll(map[ipa]?.visemes ?? []);
      arpabets.add(map[ipa]?.arpabet ?? '');
    }

    return {
      'inputIds': inputIds,
      'visemes': visemes,
      'arpabet': arpabets,
    };
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

  Future<void> loadIPAsMapping(String mappingAsset,
      {String language = 'en'}) async {
    final allRows = await readCSV(mappingAsset);
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

      map[symbol] = MappingData(symbol, symbol, [id], [vimes]);
    });

    allIPAs[language] = map.keys.toSet();
  }

  String normalizeIPA(String input, {String language = 'en'}) {
    final parts = input.replaceAll(' ', '');
    final result = <String>[];
    final validIPAs = allIPAs[language] ?? {};
    for (final part in parts.split('.')) {
      final characters = part.characters.toList();
      final length = characters.length;
      final list = <String>[];
      for (var i = 0; i < length; i++) {
        // 3 letters ipa
        if (i < length - 2) {
          final combine =
              '${characters[i]}${characters[i + 1]}${characters[i + 2]}';
          if (validIPAs.contains(combine)) {
            list.add(combine);
            i += 2;
            continue;
          }
        }

        // 2 letters ipa
        if (i < length - 1) {
          final combine = '${characters[i]}${characters[i + 1]}';
          if (validIPAs.contains(combine)) {
            list.add(combine);
            i++;
          } else {
            list.add(characters[i]);
          }
        } else {
          list.add(characters[i]);
        }
      }

      if (list.isNotEmpty) {
        var str = '';
        for (final item in list) {
          if (item == 'ˈ' || item == "'") {
            str += item;
          } else {
            str += '$item ';
          }
        }

        result.add(str.trim());
      }
    }

    return result.join(' . ');
  }

  Future<void> dispose() async {
    await TtsPlatform.instance.dispose();
  }
}
