import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:tts/tts.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

enum TTSMode { text, phoneme }

class _MyAppState extends State<MyApp> {
  final _ttsPlugin = Tts();
  bool _isRunning = false;
  final _textController = TextEditingController();
  var _mode = TTSMode.text;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> _speak() async {
    setState(() {
      _isRunning = true;
    });

    try {
      if (_mode == TTSMode.text) {
        await _ttsPlugin.speakText(
            'fastspeech2_quant.tflite', 'mbmelgan.tflite', _textController.text,
            speed: 0.6);
      } else {
        await _ttsPlugin.speakPhoneme('fastspeech2_quant.tflite',
            'mbmelgan.tflite', _textController.text.split(','));
      }
    } on PlatformException {
      // ignore: avoid_print
      print('Failed to run TTS');
    }

    setState(() {
      _isRunning = false;
    });
  }

  Future<void> initPlatformState() async {}

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
                visible: _isRunning, child: const CircularProgressIndicator()),
            ListTile(
              title: const Text('Text'),
              leading: Radio<TTSMode>(
                value: TTSMode.text,
                groupValue: _mode,
                onChanged: (TTSMode? value) {
                  if (value != null) {
                    setState(() {
                      _mode = value;
                    });
                  }
                },
              ),
            ),
            ListTile(
              title: const Text('Phoneme'),
              leading: Radio<TTSMode>(
                value: TTSMode.phoneme,
                groupValue: _mode,
                onChanged: (TTSMode? value) {
                  if (value != null) {
                    setState(() {
                      _mode = value;
                    });
                  }
                },
              ),
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
          ],
        )),
      ),
    );
  }
}
