import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:csv/csv_settings_autodetection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:tts/request_info.dart';

import 'tts_platform_interface.dart';

/// Holds the mapping between an IPA phoneme and its corresponding model
/// input IDs, ARPAbet representation, and viseme tokens.
class MappingData {
  /// The IPA phoneme symbol (e.g. 'ɛ', 'oʊ').
  final String ipa;

  /// The ARPAbet equivalent of the IPA phoneme (e.g. 'EH', 'OW').
  final String arpabet;

  /// Numeric token IDs that the ONNX model expects as input for this phoneme.
  final List<int> inputIds;

  /// Visual mouth-shape tokens used for lip-sync animation.
  final List<String> visemes;

  MappingData(this.ipa, this.arpabet, this.inputIds, this.visemes);
}

/// Main text-to-speech class that handles IPA mapping, phoneme lookup,
/// speech synthesis via ONNX models, and viseme timing.
///
/// Usage:
/// 1. Create an instance: `final tts = Tts(threadCount: 1);`
/// 2. Load IPA mappings: `await tts.loadIPAsMapping('mapping.csv', language: 'en');`
/// 3. Convert phonemes to input IDs: `final map = tts.search(ipas, language: 'en');`
/// 4. Synthesise speech: `final output = await tts.speakText(request);`
class Tts {
  /// Per-language map of IPA symbol to its [MappingData] (input IDs + visemes).
  Map<String, Map<String, MappingData>> mapping = {};

  /// Per-language set of all known IPA symbols, used for multi-character
  /// phoneme tokenisation in [breakIPA] and [normalizeIPA].
  Map<String, Set<String>> allIPAs = {};

  /// The token used to represent silence or pauses in the viseme timeline.
  static const silent = '_';

  /// Model version passed to the native platform for model selection.
  final int version;

  /// Number of threads for ONNX Runtime intra-op parallelism.
  final int threadCount;

  Tts({
    this.version = 1,
    this.threadCount = 1,
  });

  /// Runs TTS inference and plays the generated audio.
  ///
  /// Appends EOS/dot tokens to [requestInfo.inputIds] if configured, then
  /// delegates to the native platform. Returns a list of viseme timing maps,
  /// each containing `start`, `duration`, `token`, and `enabled` keys.
  ///
  /// If [cleanUpVisemes] is true (default), visemes shorter than
  /// [minDurationInSecond] are marked as disabled.
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

  /// Plays a previously generated audio buffer identified by
  /// [requestInfo.requestId].
  Future<void> playVoice(RequestInfo requestInfo) async {
    requestInfo.modelVersion = version;
    requestInfo.threadCount = threadCount;
    await TtsPlatform.instance.playVoice(requestInfo);
  }

  /// Runs TTS inference without playing audio. The generated audio buffer
  /// is cached on the native side and can be played later with [playVoice].
  ///
  /// Returns viseme timing data in the same format as [speakText].
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

  /// Disables visemes that are too short by setting `enabled` to false.
  ///
  /// Iterates backwards through [visemes] and marks any entry with a duration
  /// below [minDurationInSecond] as disabled, unless it is the first or last
  /// entry, or the previous viseme is silent.
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

  /// Tokenises an IPA string into individual phoneme symbols.
  ///
  /// Uses greedy matching (3-char, then 2-char, then 1-char) against the
  /// known IPA set for [language]. Syllable boundaries (`.`) are used as
  /// split points.
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

  /// Pre-loads ONNX models on the native platform.
  ///
  /// Call this before [speakText] or [generateVoice] to avoid cold-start
  /// latency on the first synthesis call.
  Future<void> initModels(
    String fastSpeechModel,
    String melganModel,
  ) {
    return TtsPlatform.instance.initModels(fastSpeechModel, melganModel,
        version: version, threadCount: threadCount);
  }

  /// Looks up a list of IPA phonemes in the loaded mapping and returns
  /// a map with `inputIds` (List<int>), `visemes` (List<String>), and
  /// `arpabet` (List<String>) keys.
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

  /// Reads and parses a CSV file from Flutter assets.
  ///
  /// Auto-detects field delimiters (`,` or `;`) and returns rows as
  /// a list of lists with elements of type [E].
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

  /// Loads an IPA-to-input-ID mapping from a CSV asset file.
  ///
  /// The CSV is expected to have columns: IPA, ARPAbet, input IDs (space-
  /// separated), and visemes (space-separated). The first row is skipped
  /// as a header. After loading, [allIPAs] is updated with the known
  /// phoneme set for [language].
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

  /// Loads a character-based mapping from a JSON symbol-to-ID file and a
  /// viseme CSV file. Used for languages that map individual characters
  /// (rather than IPA phonemes) directly to model input IDs.
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

  /// Normalises an IPA string by tokenising multi-character phonemes and
  /// inserting spaces between them. Syllable boundaries (`.`) are preserved
  /// as ` . ` separators. Stress markers (`ˈ`, `'`) are kept attached to
  /// the following phoneme without a trailing space.
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

  /// Releases native audio buffers and resources.
  Future<void> dispose() async {
    await TtsPlatform.instance.dispose();
  }
}
