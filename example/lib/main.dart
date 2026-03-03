import 'package:flutter/material.dart';
import 'package:tts_example/tts_controller.dart';

/// Entry point for the TTS example application.
void main() {
  runApp(const MyApp());
}

/// Root widget for the TTS example app.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

/// State for [MyApp] that owns the [TtsController] and text input.
///
/// Uses [ListenableBuilder] to rebuild the UI whenever the controller
/// notifies of state changes (language switch, synthesis result, etc.).
class _MyAppState extends State<MyApp> {
  /// Business-logic controller for TTS operations.
  final _controller = TtsController();

  /// Text field controller, pre-filled with the default English sample text.
  final _textController = TextEditingController()
    ..text = Language.en.defaultText;

  @override
  void dispose() {
    _controller.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('TTS example'),
        ),
        body: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Visibility(
                    visible: _controller.isRunning,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: const CircularProgressIndicator(),
                  ),
                  TextField(
                    controller: _textController,
                  ),
                  RadioGroup<Language>(
                    groupValue: _controller.language,
                    onChanged: (Language? value) {
                      if (value == null) return;
                      _controller.setLanguage(value);
                      _textController.text = value.defaultText;
                    },
                    child: const Column(
                      children: [
                        ListTile(
                          title: Text('en'),
                          leading: Radio<Language>(value: Language.en),
                        ),
                        ListTile(
                          title: Text('id'),
                          leading: Radio<Language>(value: Language.id),
                        ),
                        ListTile(
                          title: Text('sw'),
                          leading: Radio<Language>(value: Language.sw),
                        ),
                      ],
                    ),
                  ),
                  CheckboxListTile(
                    value: _controller.testPerformance,
                    onChanged: (val) {
                      _controller.setTestPerformance(val == true);
                    },
                    title: const Text('Test performance'),
                  ),
                  TextButton(
                    child: const Text('Speak'),
                    onPressed: () {
                      _controller.speak(_textController.text);
                    },
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(_controller.result),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
