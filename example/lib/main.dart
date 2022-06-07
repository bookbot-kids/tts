// ignore_for_file: avoid_print

import 'dart:io';
import 'package:csv/csv.dart';
import 'package:csv/csv_settings_autodetection.dart';
import 'package:duration/duration.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';
import 'package:tts/request_info.dart';
import 'package:tts/tts.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

enum Langage { en, id }

class _MyAppState extends State<MyApp> {
  final _ttsPlugin = Tts();
  bool _isRunning = false;
  // 'hello world'    'h ə l oʊ   w ɝ r l d'     '53 20 64 70 91 45 64 37'
  static const _defaultEnText = 'library aback ables';
  static const _defaultIdText = 'halo, apa kabar?';
  final _textController = TextEditingController()..text = _defaultEnText;
  var _result = '';
  late Database _db;
  late StoreRef _storeRef;
  Langage? _language = Langage.en;
  Future? initTask;

  @override
  void initState() {
    super.initState();
    initTask = init();
  }

  Future<void> _updateWordDb() async {
    await initTask;
    // read csv
    final csvData = await rootBundle.loadString('assets/words.csv');
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
    final newWords = [];
    allRows.skip(1).forEach((row) {
      // inuse
      if ('true' == row[9]?.toString().toLowerCase() ||
          'true' == row[10]?.toString().toLowerCase()) {
        final item = [];

        for (var i = 0; i < row.length; i++) {
          item.add(row[i]);
        }
        newWords.add(item);
      }
    });
    final finder = Finder(
        filter: Filter.or([
      Filter.equals('inUse', true),
      Filter.equals('pluralInUse', true),
    ]));

    var records = await _storeRef.find(_db, finder: finder);
    await _db.transaction((db) async {
      for (final requeryRecord in records) {
        final data = requeryRecord.value;
        final id = data['id'] as String;
        final csvRow = newWords.firstWhereOrNull((element) => element[0] == id);
        if (csvRow == null) {
          continue;
        }

        final updateRecord = _storeRef.record(id);
        await updateRecord.update(db, {
          'syllable': csvRow[3],
          'syllablePlural': csvRow[4],
          'ukipa': csvRow[5],
          'usipa': csvRow[6],
          'ukipaPlural': csvRow[7],
          'usipaPlural': csvRow[8],
        });
        print('update word $id');
      }
    });

    // remove unused
    records = await _storeRef.find(_db,
        finder: Finder(
            filter: Filter.and([
          Filter.notEquals('inUse', true),
          Filter.notEquals('pluralInUse', true),
        ])));
    await _db.transaction((db) async {
      for (final requeryRecord in records) {
        final data = requeryRecord.value;
        final id = data['id'] as String;
        final findingRecord = _storeRef.record(id);
        final deleteResult = await findingRecord.delete(db);
        print('remove word $id $deleteResult');
      }
    });

    await _db.close();
    print('done');
  }

  Future<List<String>> _findIPA(String word) async {
    final finder = Finder(
        filter: Filter.or(
            [Filter.equals('word', word), Filter.equals('plural', word)]));
    final record = await _storeRef.findFirst(_db, finder: finder);
    final value = record?.value;
    if (value == null) {
      return [];
    }

    final isPlural = value['plural'] == word;

    final ipas = (isPlural ? value['usipaPlural'] : value['usipa']) ?? '';
    return ipas.split('.');
  }

  List<String> ipaCharacters(Set<String> allIPAs, List ipas) {
    final result = <String>[];
    for (String ipa in ipas) {
      var characters = ipa.characters.toList();
      for (var i = 0; i < characters.length; i += 2) {
        if (i < characters.length - 1) {
          final combine = '${characters[i]}${characters[i + 1]}';
          if (allIPAs.contains(combine)) {
            result.add(combine);
          } else {
            result.add(characters[i]);
            result.add(characters[i + 1]);
          }
        } else {
          result.add(characters[i]);
        }
      }
    }

    return result;
  }

  Future<void> _speak() async {
    await initTask;
    setState(() {
      _isRunning = true;
      _result = '';
    });

    try {
      final startTime = DateTime.now().millisecondsSinceEpoch;
      final text = _textController.text;

      List<int> inputIds = [];
      List<String> visemes = [];

      List wordIPAs = []; // ipa for each word
      List wirdInputIds = []; // input id for each word
      RequestInfo request;
      if (_language == Langage.en) {
        final words = text
            .split(' ')
            .map((e) => e.trim())
            .where((element) => element.isNotEmpty)
            .toList();
        final allAvailableIPAs = _ttsPlugin.allIPAs['en']!;
        for (final word in words) {
          final ipa = await _findIPA(word);
          final characters = ipaCharacters(allAvailableIPAs, ipa);
          wordIPAs.add(characters);
          final map = _ttsPlugin.search(characters);
          inputIds.addAll(map['inputIds'] as List<int>);
          visemes.addAll(map['visemes'] as List<String>);
          wirdInputIds.add(map['inputIds']);
        }

        request = RequestInfo(
            'fastspeech2_quant.tflite', 'mbmelgan.tflite', inputIds, visemes);
      } else {
        final characters = text.characters.toList();
        final map = _ttsPlugin.search(characters, language: 'id');
        inputIds.addAll(map['inputIds'] as List<int>);
        visemes.addAll(map['visemes'] as List<String>);
        wordIPAs.add(characters);
        wirdInputIds.add(map['inputIds']);

        request = IdRequestInfo(
          'id_fastspeech2_quant.tflite',
          'id_mbmelgan.tflite',
          inputIds,
          visemes,
        );
      }

      final output = await _ttsPlugin.speakText(request);
      setState(() {
        _result += '''
IPA:
${wordIPAs.join('; ')}

InputIds:
${wirdInputIds.join('; ')}

''';
      });

      final totalTime = DateTime.now().millisecondsSinceEpoch - startTime;
      // ignore: avoid_print
      print('output: $output');
      setState(() {
        _result +=
            'Duration:\n ${output.join('\n')}\n\nExecute in ${printDuration(
          Duration(milliseconds: totalTime),
          tersity: DurationTersity.millisecond,
          abbreviated: false,
        )}';
      });
    } on PlatformException {
      // ignore: avoid_print
      print('Failed to run TTS');
    }

    setState(() {
      _isRunning = false;
    });
  }

  Future<void> init() async {
    await _ttsPlugin.loadCsvMapping('assets/tts_mapping.csv');
    await _ttsPlugin.loadJsonMapping('assets/id_processor.json',
        language: 'id');

    // copy word db into storage
    Directory appDocDir = await getApplicationDocumentsDirectory();

    final assetContent = await rootBundle.load('assets/Word.db');
    final dbFile = File(p.join(appDocDir.path, 'Word.db'));
    if (!await dbFile.exists()) {
      final bytes = assetContent.buffer
          .asUint8List(assetContent.offsetInBytes, assetContent.lengthInBytes);
      await dbFile.writeAsBytes(bytes);
    }

    _db = await databaseFactoryIo.openDatabase(dbFile.path);
    _storeRef = StoreRef.main();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('TTS example'),
        ),
        body: Center(
            child: Column(
          children: [
            Visibility(
              visible: _isRunning,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: const CircularProgressIndicator(),
            ),
            TextField(
              controller: _textController,
            ),
            ListTile(
              title: const Text('en'),
              leading: Radio<Langage>(
                value: Langage.en,
                groupValue: _language,
                onChanged: (Langage? value) {
                  setState(() {
                    _language = value;
                    _textController.text = _defaultEnText;
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('id'),
              leading: Radio<Langage>(
                value: Langage.id,
                groupValue: _language,
                onChanged: (Langage? value) {
                  setState(() {
                    _language = value;
                    _textController.text = _defaultIdText;
                  });
                },
              ),
            ),
            TextButton(
              child: const Text('Speak'),
              onPressed: () {
                _speak();
              },
            ),
            Expanded(
                child: SingleChildScrollView(
              child: Text(_result),
            ))
          ],
        )),
      ),
    );
  }
}
