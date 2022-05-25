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

class _MyAppState extends State<MyApp> {
  final _ttsPlugin = Tts();
  bool _isRunning = false;
  final _textController = TextEditingController()
    ..text = '53 20 64 70 91 45 64 37'; // hello world

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
      final output = await _ttsPlugin.speakText(
          'fastspeech2_quant.tflite',
          'mbmelgan.tflite',
          _textController.text
              .split(' ')
              .map((e) => int.parse(e.trim()))
              .toList(),
          speed: 1);
      // ignore: avoid_print
      print('output: $output');
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
