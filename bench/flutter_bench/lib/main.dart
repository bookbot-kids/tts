// On-device sherpa-onnx TTS benchmark for Android emulator.
//
// Reads:  /data/local/tmp/bench/...  (assets pushed via adb push)
// Writes: <app external files dir>/results_android.csv
// Logs:   one JSON line per measurement via stdout (logcat tag flutter).
//
// Engines benchmarked (smallest sherpa-onnx variants):
//   - sherpa-onnx-pocket-tts-int8-2026-01-26          (93.8 MB compressed)
//   - sherpa-onnx-zipvoice-distill-int8-zh-en-emilia  (104.1 MB compressed)
//
// Bookbot is not run on-device here; its perf is already known from the
// production app, and this run focuses on validating the sherpa-onnx
// mobile path the upstream READMEs recommend.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

const benchRoot = '/data/local/tmp/bench';
const corpusJson = '$benchRoot/corpus.json';

const pocketDir = '$benchRoot/sherpa_models/sherpa-onnx-pocket-tts-int8-2026-01-26';
const zipvoiceDir = '$benchRoot/sherpa_models/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia';
const vocoderPath = '$benchRoot/sherpa_models/vocos_24khz.onnx';

const pocketRefWav = '$pocketDir/test_wavs/bria.wav';
const zipvoiceRefWav = '$benchRoot/voices/zipvoice_default.wav';
const zipvoiceRefTxtPath = '$benchRoot/voices/zipvoice_default.txt';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Required by the sherpa_onnx Flutter package before any TTS object is built.
  so.initBindings();
  runApp(const MaterialApp(home: BenchHome()));
}

class BenchHome extends StatefulWidget {
  const BenchHome({super.key});
  @override
  State<BenchHome> createState() => _BenchHomeState();
}

class _BenchHomeState extends State<BenchHome> {
  final _log = <String>[];
  bool _running = false;
  String _status = 'Idle';

  @override
  void initState() {
    super.initState();
    // Auto-run on launch so the bench can be triggered with `adb shell am start`
    // alone, without needing UI tapping.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 1), _run);
    });
  }

  void _addLog(String line) {
    // ignore: avoid_print
    print('BENCH $line');
    setState(() {
      _log.add(line);
      if (_log.length > 200) _log.removeAt(0);
    });
  }

  /// Reads /proc/self/status and returns (VmRSS, VmHWM) in MB.
  /// VmHWM is the peak resident size since process start.
  (double, double) _procStatus() {
    try {
      final lines = File('/proc/self/status').readAsLinesSync();
      double parse(String key) {
        final l = lines.firstWhere((x) => x.startsWith(key), orElse: () => '');
        if (l.isEmpty) return 0.0;
        final parts = l.split(RegExp(r'\s+'));
        final kb = double.tryParse(parts[1]) ?? 0.0;
        return kb / 1024.0;
      }
      return (parse('VmRSS:'), parse('VmHWM:'));
    } catch (_) {
      return (0.0, 0.0);
    }
  }

  Future<List<Map<String, Object?>>> _runEngine({
    required String engine,
    required so.OfflineTts Function() build,
    required so.OfflineTtsGenerationConfig Function() makeGen,
    required List<Map<String, Object?>> sentences,
    required int repeats,
    required String voiceId,
  }) async {
    final rows = <Map<String, Object?>>[];
    for (final s in sentences) {
      final id = s['id'] as String;
      final text = s['text'] as String;
      for (var r = 0; r < repeats; r++) {
        _addLog('[$engine] $id r$r start');
        so.OfflineTts? tts;
        try {
          final tBuild0 = DateTime.now();
          tts = build();
          final buildMs = DateTime.now().difference(tBuild0).inMilliseconds;

          final gen = makeGen();
          final tInfer0 = DateTime.now();
          final audio = tts.generateWithConfig(text: text, config: gen);
          final inferMs = DateTime.now().difference(tInfer0).inMilliseconds;

          final (rss, hwm) = _procStatus();
          final audioSec = audio.samples.length / audio.sampleRate;
          final wallSec = (buildMs + inferMs) / 1000.0;
          final inferSec = inferMs / 1000.0;
          final rtf = wallSec / (audioSec == 0 ? 1e-6 : audioSec);

          final row = <String, Object?>{
            'engine': engine,
            'sentence_id': id,
            'repeat': r,
            'wall_s': wallSec,
            'infer_s': inferSec,
            'audio_s': audioSec,
            'rtf': rtf,
            'rss_mb': rss,
            'peak_rss_mb': hwm,
            'voice_id': voiceId,
            'has_phoneme_timings': false,
          };
          rows.add(row);
          _addLog('___ROW___${jsonEncode(row)}');
        } catch (e, st) {
          final row = <String, Object?>{
            'engine': engine,
            'sentence_id': id,
            'repeat': r,
            'error': '$e',
          };
          rows.add(row);
          _addLog('___ROW___${jsonEncode(row)}');
          _addLog('error: $e\n$st');
        } finally {
          tts?.free();
        }
      }
    }
    return rows;
  }

  so.OfflineTts _buildPocket() {
    final cfg = so.OfflineTtsConfig(
      model: so.OfflineTtsModelConfig(
        pocket: so.OfflineTtsPocketModelConfig(
          lmFlow: '$pocketDir/lm_flow.int8.onnx',
          lmMain: '$pocketDir/lm_main.int8.onnx',
          encoder: '$pocketDir/encoder.onnx',
          decoder: '$pocketDir/decoder.int8.onnx',
          textConditioner: '$pocketDir/text_conditioner.onnx',
          vocabJson: '$pocketDir/vocab.json',
          tokenScoresJson: '$pocketDir/token_scores.json',
        ),
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      ),
    );
    return so.OfflineTts(cfg);
  }

  so.OfflineTtsGenerationConfig _genPocket() {
    final wave = so.readWave(pocketRefWav);
    return so.OfflineTtsGenerationConfig(
      sid: 0,
      speed: 1.0,
      referenceAudio: wave.samples,
      referenceSampleRate: wave.sampleRate,
      extra: {'max_reference_audio_len': 12, 'num_steps': 5},
    );
  }

  so.OfflineTts _buildZipvoice() {
    final cfg = so.OfflineTtsConfig(
      model: so.OfflineTtsModelConfig(
        zipvoice: so.OfflineTtsZipVoiceModelConfig(
          tokens: '$zipvoiceDir/tokens.txt',
          encoder: '$zipvoiceDir/encoder.int8.onnx',
          decoder: '$zipvoiceDir/decoder.int8.onnx',
          vocoder: vocoderPath,
          dataDir: '$zipvoiceDir/espeak-ng-data',
          lexicon: '$zipvoiceDir/lexicon.txt',
        ),
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      ),
    );
    return so.OfflineTts(cfg);
  }

  so.OfflineTtsGenerationConfig _genZipvoice() {
    final wave = so.readWave(zipvoiceRefWav);
    final refText = File(zipvoiceRefTxtPath).readAsStringSync().trim();
    return so.OfflineTtsGenerationConfig(
      speed: 1.0,
      referenceAudio: wave.samples,
      referenceSampleRate: wave.sampleRate,
      referenceText: refText,
      numSteps: 4,
      extra: {'min_char_in_sentence': 30},
    );
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Loading corpus';
      _log.clear();
    });
    _addLog('reading $corpusJson');
    final corpusFile = File(corpusJson);
    if (!corpusFile.existsSync()) {
      _addLog('FATAL: corpus.json not found at $corpusJson');
      setState(() => _running = false);
      return;
    }
    final corpus = jsonDecode(corpusFile.readAsStringSync()) as Map<String, dynamic>;
    final sentences = (corpus['sentences'] as List).cast<Map<String, Object?>>();

    final rows = <Map<String, Object?>>[];

    setState(() => _status = 'Pocket-TTS sherpa');
    rows.addAll(await _runEngine(
      engine: 'pockettts_sherpa_android',
      build: _buildPocket,
      makeGen: _genPocket,
      sentences: sentences,
      repeats: 3,
      voiceId: 'pocket-tts/sherpa-int8/bria',
    ));

    setState(() => _status = 'ZipVoice sherpa');
    rows.addAll(await _runEngine(
      engine: 'zipvoice_sherpa_android',
      build: _buildZipvoice,
      makeGen: _genZipvoice,
      sentences: sentences,
      repeats: 3,
      voiceId: 'zipvoice/sherpa-int8-distill@bookbot_s15_prompt',
    ));

    final fields = <String>{};
    for (final r in rows) {
      fields.addAll(r.keys.cast<String>());
    }
    final keys = fields.toList()..sort();
    final out = StringBuffer();
    out.writeln(keys.join(','));
    for (final r in rows) {
      out.writeln(keys.map((k) {
        final v = r[k];
        if (v == null) return '';
        final s = v.toString();
        if (s.contains(',') || s.contains('"')) {
          return '"${s.replaceAll('"', '""')}"';
        }
        return s;
      }).join(','));
    }
    final extDir = await getExternalStorageDirectory();
    final outPath = '${extDir?.path ?? '/sdcard'}/results_android.csv';
    File(outPath).writeAsStringSync(out.toString());
    _addLog('___DONE___ wrote ${rows.length} rows -> $outPath');
    setState(() {
      _running = false;
      _status = 'Done — ${rows.length} rows';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TTS Bench (sherpa-onnx)')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              ElevatedButton(
                onPressed: _running ? null : _run,
                child: const Text('Run benchmark'),
              ),
              const SizedBox(width: 12),
              Text(_status),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  _log.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
