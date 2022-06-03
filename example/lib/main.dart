// ignore_for_file: avoid_print

import 'dart:io';
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

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _ttsPlugin = Tts();
  bool _isRunning = false;
  // 'hello world'    'h ə l oʊ   w ɝ r l d'     '53 20 64 70 91 45 64 37'
  static const _defaultText = 'library aback ables';
  final _textController = TextEditingController()..text = _defaultText;
  var _result = '';
  late Database _db;
  late StoreRef _storeRef;

  @override
  void initState() {
    super.initState();
    init();
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
    setState(() {
      _isRunning = true;
      _result = '';
    });

    try {
      final startTime = DateTime.now().millisecondsSinceEpoch;
      final text = _textController.text;
      final words = text
          .split(' ')
          .map((e) => e.trim())
          .where((element) => element.isNotEmpty)
          .toList();

      List<int> inputIds = [];
      List<String> visemes = [];

      List wordIPAs = []; // ipa for each word
      List wirdInputIds = []; // input id for each word
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

      final output = await _ttsPlugin.speakText(
        RequestInfo(
            'fastspeech2_quant.tflite', 'mbmelgan.tflite', inputIds, visemes,
            speed: 1),
      );
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
    await _ttsPlugin.loadMapping('assets/tts_mapping.csv');

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
