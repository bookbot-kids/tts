// Basic smoke test for the TTS example app.
//
// Verifies that the app builds and renders its core UI: the title, the
// language selector options, and the Speak action.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_example/main.dart';

void main() {
  testWidgets('Renders the TTS example UI', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // App title and primary action are present.
    expect(find.text('TTS example'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Speak'), findsOneWidget);

    // All four supported languages are offered as options.
    for (final code in ['en', 'id', 'sw', 'es']) {
      expect(find.text(code), findsOneWidget);
    }
  });
}
