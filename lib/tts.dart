import 'package:flutter/widgets.dart';
import 'package:tts/mapping.dart';
import 'package:tts/request_info.dart';

import 'tts_platform_interface.dart';

class Tts {
  final int version;
  final int threadCount;
  final ttsMapping = TTSMapping();

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
        requestInfo.inputIds.add(requestInfo.space);
        requestInfo.inputIds.add(requestInfo.dot);
      }

      if (requestInfo.useEos) {
        requestInfo.inputIds.add(requestInfo.eos);
      }
    }

    if (debug) {
      debugPrint('inputIds: ${requestInfo.inputIds}');
      debugPrint('visemes: ${requestInfo.visemes}');
    }

    requestInfo.modelVersion = version;
    requestInfo.threadCount = threadCount;
    final output = await TtsPlatform.instance.speakText(requestInfo);
    if (debug) {
      debugPrint('raw output: $output');
    }
    final result = [];
    var dur = 0.0;
    for (var i = 0; i < output.length; i++) {
      final token = i < requestInfo.visemes.length
          ? requestInfo.visemes[i]
          : TTSMapping.silent;

      result.add({
        'start': dur * requestInfo.hopSize / requestInfo.sampleRate,
        'duration': output[i] * requestInfo.hopSize / requestInfo.sampleRate,
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
            previousViseme != TTSMapping.silent &&
            i != visemes.length - 1) {
          visemes[i]['enabled'] = false;
        }
      }
    }

    return visemes;
  }

  List<String> breakIPA(String ipas, {String language = 'en'}) {
    final allIPAs = ttsMapping.allIPAs[language] ?? {};
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

  String normalizeIPA(String input, {String language = 'en'}) {
    final parts = input.replaceAll(' ', '');
    final result = <String>[];
    final validIPAs = ttsMapping.allIPAs[language] ?? {};
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
