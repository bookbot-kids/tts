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
import 'package:uuid/uuid.dart';

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
  static const _defaultEnText =
      'library aback ables hello world may then them single they she go do it love me so much join us';
  static const _defaultIdText =
      'Saat kamu mengetuk kamu akan secara otomatis mengubah halaman ketika kamu selesai kecuali kamu perlu membaca ulang kata-kata yang kamu anggap sulit';
  final _textController = TextEditingController()..text = _defaultEnText;
  var _result = '';
  late Database _db;
  late StoreRef _storeRef;
  Langage? _language = Langage.en;
  Future? initTask;
  static final spaceRegEx = RegExp(r'[\t\n\r\s]');
  static final curlyTagRegex = RegExp(r'\{.*?\}');
  static final nonAlphaUnicodeWithContractedRegEx = RegExp(
      '[^a-zA-Z-\'\d\u0041-\u005A\u0061-\u007A\u00AA\u00B5\u00BA\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02C1\u02C6-\u02D1\u02E0-\u02E4\u02EC\u02EE\u0370-\u0374\u0376\u0377\u037A-\u037D\u0386\u0388-\u038A\u038C\u038E-\u03A1\u03A3-\u03F5\u03F7-\u0481\u048A-\u0527\u0531-\u0556\u0559\u0561-\u0587\u05D0-\u05EA\u05F0-\u05F2\u0620-\u064A\u066E\u066F\u0671-\u06D3\u06D5\u06E5\u06E6\u06EE\u06EF\u06FA-\u06FC\u06FF\u0710\u0712-\u072F\u074D-\u07A5\u07B1\u07CA-\u07EA\u07F4\u07F5\u07FA\u0800-\u0815\u081A\u0824\u0828\u0840-\u0858\u08A0\u08A2-\u08AC\u0904-\u0939\u093D\u0950\u0958-\u0961\u0971-\u0977\u0979-\u097F\u0985-\u098C\u098F\u0990\u0993-\u09A8\u09AA-\u09B0\u09B2\u09B6-\u09B9\u09BD\u09CE\u09DC\u09DD\u09DF-\u09E1\u09F0\u09F1\u0A05-\u0A0A\u0A0F\u0A10\u0A13-\u0A28\u0A2A-\u0A30\u0A32\u0A33\u0A35\u0A36\u0A38\u0A39\u0A59-\u0A5C\u0A5E\u0A72-\u0A74\u0A85-\u0A8D\u0A8F-\u0A91\u0A93-\u0AA8\u0AAA-\u0AB0\u0AB2\u0AB3\u0AB5-\u0AB9\u0ABD\u0AD0\u0AE0\u0AE1\u0B05-\u0B0C\u0B0F\u0B10\u0B13-\u0B28\u0B2A-\u0B30\u0B32\u0B33\u0B35-\u0B39\u0B3D\u0B5C\u0B5D\u0B5F-\u0B61\u0B71\u0B83\u0B85-\u0B8A\u0B8E-\u0B90\u0B92-\u0B95\u0B99\u0B9A\u0B9C\u0B9E\u0B9F\u0BA3\u0BA4\u0BA8-\u0BAA\u0BAE-\u0BB9\u0BD0\u0C05-\u0C0C\u0C0E-\u0C10\u0C12-\u0C28\u0C2A-\u0C33\u0C35-\u0C39\u0C3D\u0C58\u0C59\u0C60\u0C61\u0C85-\u0C8C\u0C8E-\u0C90\u0C92-\u0CA8\u0CAA-\u0CB3\u0CB5-\u0CB9\u0CBD\u0CDE\u0CE0\u0CE1\u0CF1\u0CF2\u0D05-\u0D0C\u0D0E-\u0D10\u0D12-\u0D3A\u0D3D\u0D4E\u0D60\u0D61\u0D7A-\u0D7F\u0D85-\u0D96\u0D9A-\u0DB1\u0DB3-\u0DBB\u0DBD\u0DC0-\u0DC6\u0E01-\u0E30\u0E32\u0E33\u0E40-\u0E46\u0E81\u0E82\u0E84\u0E87\u0E88\u0E8A\u0E8D\u0E94-\u0E97\u0E99-\u0E9F\u0EA1-\u0EA3\u0EA5\u0EA7\u0EAA\u0EAB\u0EAD-\u0EB0\u0EB2\u0EB3\u0EBD\u0EC0-\u0EC4\u0EC6\u0EDC-\u0EDF\u0F00\u0F40-\u0F47\u0F49-\u0F6C\u0F88-\u0F8C\u1000-\u102A\u103F\u1050-\u1055\u105A-\u105D\u1061\u1065\u1066\u106E-\u1070\u1075-\u1081\u108E\u10A0-\u10C5\u10C7\u10CD\u10D0-\u10FA\u10FC-\u1248\u124A-\u124D\u1250-\u1256\u1258\u125A-\u125D\u1260-\u1288\u128A-\u128D\u1290-\u12B0\u12B2-\u12B5\u12B8-\u12BE\u12C0\u12C2-\u12C5\u12C8-\u12D6\u12D8-\u1310\u1312-\u1315\u1318-\u135A\u1380-\u138F\u13A0-\u13F4\u1401-\u166C\u166F-\u167F\u1681-\u169A\u16A0-\u16EA\u1700-\u170C\u170E-\u1711\u1720-\u1731\u1740-\u1751\u1760-\u176C\u176E-\u1770\u1780-\u17B3\u17D7\u17DC\u1820-\u1877\u1880-\u18A8\u18AA\u18B0-\u18F5\u1900-\u191C\u1950-\u196D\u1970-\u1974\u1980-\u19AB\u19C1-\u19C7\u1A00-\u1A16\u1A20-\u1A54\u1AA7\u1B05-\u1B33\u1B45-\u1B4B\u1B83-\u1BA0\u1BAE\u1BAF\u1BBA-\u1BE5\u1C00-\u1C23\u1C4D-\u1C4F\u1C5A-\u1C7D\u1CE9-\u1CEC\u1CEE-\u1CF1\u1CF5\u1CF6\u1D00-\u1DBF\u1E00-\u1F15\u1F18-\u1F1D\u1F20-\u1F45\u1F48-\u1F4D\u1F50-\u1F57\u1F59\u1F5B\u1F5D\u1F5F-\u1F7D\u1F80-\u1FB4\u1FB6-\u1FBC\u1FBE\u1FC2-\u1FC4\u1FC6-\u1FCC\u1FD0-\u1FD3\u1FD6-\u1FDB\u1FE0-\u1FEC\u1FF2-\u1FF4\u1FF6-\u1FFC\u2071\u207F\u2090-\u209C\u2102\u2107\u210A-\u2113\u2115\u2119-\u211D\u2124\u2126\u2128\u212A-\u212D\u212F-\u2139\u213C-\u213F\u2145-\u2149\u214E\u2183\u2184\u2C00-\u2C2E\u2C30-\u2C5E\u2C60-\u2CE4\u2CEB-\u2CEE\u2CF2\u2CF3\u2D00-\u2D25\u2D27\u2D2D\u2D30-\u2D67\u2D6F\u2D80-\u2D96\u2DA0-\u2DA6\u2DA8-\u2DAE\u2DB0-\u2DB6\u2DB8-\u2DBE\u2DC0-\u2DC6\u2DC8-\u2DCE\u2DD0-\u2DD6\u2DD8-\u2DDE\u2E2F\u3005\u3006\u3031-\u3035\u303B\u303C\u3041-\u3096\u309D-\u309F\u30A1-\u30FA\u30FC-\u30FF\u3105-\u312D\u3131-\u318E\u31A0-\u31BA\u31F0-\u31FF\u3400-\u4DB5\u4E00-\u9FCC\uA000-\uA48C\uA4D0-\uA4FD\uA500-\uA60C\uA610-\uA61F\uA62A\uA62B\uA640-\uA66E\uA67F-\uA697\uA6A0-\uA6E5\uA717-\uA71F\uA722-\uA788\uA78B-\uA78E\uA790-\uA793\uA7A0-\uA7AA\uA7F8-\uA801\uA803-\uA805\uA807-\uA80A\uA80C-\uA822\uA840-\uA873\uA882-\uA8B3\uA8F2-\uA8F7\uA8FB\uA90A-\uA925\uA930-\uA946\uA960-\uA97C\uA984-\uA9B2\uA9CF\uAA00-\uAA28\uAA40-\uAA42\uAA44-\uAA4B\uAA60-\uAA76\uAA7A\uAA80-\uAAAF\uAAB1\uAAB5\uAAB6\uAAB9-\uAABD\uAAC0\uAAC2\uAADB-\uAADD\uAAE0-\uAAEA\uAAF2-\uAAF4\uAB01-\uAB06\uAB09-\uAB0E\uAB11-\uAB16\uAB20-\uAB26\uAB28-\uAB2E\uABC0-\uABE2\uAC00-\uD7A3\uD7B0-\uD7C6\uD7CB-\uD7FB\uF900-\uFA6D\uFA70-\uFAD9\uFB00-\uFB06\uFB13-\uFB17\uFB1D\uFB1F-\uFB28\uFB2A-\uFB36\uFB38-\uFB3C\uFB3E\uFB40\uFB41\uFB43\uFB44\uFB46-\uFBB1\uFBD3-\uFD3D\uFD50-\uFD8F\uFD92-\uFDC7\uFDF0-\uFDFB\uFE70-\uFE74\uFE76-\uFEFC\uFF21-\uFF3A\uFF41-\uFF5A\uFF66-\uFFBE\uFFC2-\uFFC7\uFFCA-\uFFCF\uFFD2-\uFFD7\uFFDA-\uFFDC]',
      caseSensitive: false,
      unicode: true);
  @override
  void initState() {
    super.initState();
    initTask = init();
  }

  List getBISyllables(String word) {
    if (word.isNotEmpty != true) return [];
    const consonant = 'kh|n[yg]|sy|[bcdfghjklmnpqrstvwxyz]';
    const vowel =
        'a(?:[iu](?!(?:$consonant)+\\b))?|o(?:i(?!(?:$consonant)+\\b))?|[aeiou]';
    final regex = RegExp(
        '(?:$consonant)*(?:$vowel)(?:(?:$consonant)*(?=[^a-zA-Z]|\$)|(?=($consonant))\\1(?=(?:$consonant)))?',
        caseSensitive: false);

    Iterable matches = regex.allMatches(word);

    var out = [];
    for (Match m in matches) {
      out.add(m[0]);
    }
    return out;
  }

  Future<void> _exportWords() async {
    Directory appDocDir = await getApplicationDocumentsDirectory();
    final assetContent = await rootBundle.load('assets/WordUniversal.db');
    final dbFile = File(p.join(appDocDir.path, 'WordUniversal.db'));
    if (!await dbFile.exists()) {
      final bytes = assetContent.buffer
          .asUint8List(assetContent.offsetInBytes, assetContent.lengthInBytes);
      await dbFile.writeAsBytes(bytes);
    }

    final exportDb = await databaseFactoryIo.openDatabase(dbFile.path);
    final storeRef = StoreRef.main();
    final allWords = await storeRef.find(exportDb, finder: Finder());
    List<List<dynamic>> enRows = [];
    enRows.add([
      'id',
      'word',
      'inUse',
      'validated',
      'language',
      'ipa',
      'syllable',
      'level'
    ]);

    List<List<dynamic>> biRows = [];
    biRows.add([
      'id',
      'word',
      'inUse',
      'validated',
      'language',
      'ipa',
      'syllable',
      'level'
    ]);

    List<List<dynamic>> enEmptyRows = [];
    enEmptyRows.add([
      'id',
      'word',
      'inUse',
      'validated',
      'language',
      'ipa',
      'syllable',
      'level'
    ]);

    List<List<dynamic>> biEmptyRows = [];
    biEmptyRows.add([
      'id',
      'word',
      'inUse',
      'validated',
      'language',
      'ipa',
      'syllable',
      'level'
    ]);

    for (final record in allWords) {
      if (record['deletedAt'] != null) {
        continue;
      }

      String id = record['id'] as String;
      String word = record['word'] as String;
      bool inUse = record['inUse'] as bool;
      bool validated = record['validated'] as bool;
      String language = record['language'] as String;
      String ipa = record['ipa'] as String;
      String syllable = record['syllable'] as String;
      int level = record['level'] as int;

      print('word $id');
      if (ipa.isEmpty) {
        print('word $word has empty ipa');
        if (language == 'id') {
          final rows = [
            id,
            word,
            inUse,
            validated,
            language,
            ipa,
            syllable,
            level
          ];
          biEmptyRows.add(rows);
        } else if (language == 'en') {
          final rows = [
            id,
            word,
            inUse,
            validated,
            language,
            ipa,
            syllable,
            level
          ];
          enEmptyRows.add(rows);
        }
        continue;
      }

      final normalize = ipa.replaceAll('ˈ', '').replaceAll(' ', '');
      if (normalize.length > 2) {
        print('word $word invalid');
        continue;
      }

      if (language == 'id') {
        final rows = [
          id,
          word,
          inUse,
          validated,
          language,
          ipa,
          syllable,
          level
        ];
        biRows.add(rows);
      } else if (language == 'en') {
        final rows = [
          id,
          word,
          inUse,
          validated,
          language,
          ipa,
          syllable,
          level
        ];
        enRows.add(rows);
      } else {
        throw Exception('wrong language');
      }
    }

    Directory dir = await getTemporaryDirectory();
    final biFile = File(p.join(dir.path, 'bi_words.csv'));
    await biFile.writeAsString(const ListToCsvConverter().convert(biRows));

    final enFile = File(p.join(dir.path, 'en_words.csv'));
    await enFile.writeAsString(const ListToCsvConverter().convert(enRows));

    final biEnmptyFile = File(p.join(dir.path, 'bi_empty_words.csv'));
    await biEnmptyFile
        .writeAsString(const ListToCsvConverter().convert(biEmptyRows));

    final enEmptyFile = File(p.join(dir.path, 'en_empty_words.csv'));
    await enEmptyFile
        .writeAsString(const ListToCsvConverter().convert(enEmptyRows));
    print('done');
  }

  Future<void> _exportBIWords() async {
    Directory appDocDir = await getApplicationDocumentsDirectory();

    final assetContent = await rootBundle.load('assets/WordIndonesia.db');
    final dbFile = File(p.join(appDocDir.path, 'WordIndonesia.db'));
    if (!await dbFile.exists()) {
      final bytes = assetContent.buffer
          .asUint8List(assetContent.offsetInBytes, assetContent.lengthInBytes);
      await dbFile.writeAsBytes(bytes);
    }

    final db = await databaseFactoryIo.openDatabase(dbFile.path);
    final store = StoreRef.main();
    final allWords = await store.find(db);
    List<List<dynamic>> rows = [];
    List<dynamic> row = [];
    row.add("id");
    row.add("word");
    row.add("plural");
    row.add("syllable");
    row.add("syllablePlural");

    rows.add(row);
    for (var i = 0; i < allWords.length; i++) {
      final item = allWords[i].value;
      if (item == null) continue;
      List<dynamic> row = [];
      final id = item['id'];
      String word = item['word'] ?? '';
      String plural = item['plural'] ?? '';
      String syllable = item['syllable'] ?? '';
      if (syllable.isEmpty) {
        syllable = getBISyllables(word).join('.');
      }

      String syllablePlural = item['syllablePlural'] ?? '';
      if (syllablePlural.isEmpty) {
        syllablePlural = getBISyllables(plural).join('.');
      }

      row.add(id);
      row.add(word);
      row.add(plural);
      row.add(syllable);
      row.add(syllablePlural);
      rows.add(row);

      print('Listing word $word ($i)');
    }

    Directory dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'bi_words.csv'));
    String csv = const ListToCsvConverter().convert(rows);
    await file.writeAsString(csv);
    print('done');
  }

  Future<void> _importCsvToWordUniversal() async {
    await initTask;
    Directory appDocDir = await getApplicationDocumentsDirectory();
    // copy word.db
    final assetContent = await rootBundle.load('assets/Word.db');
    final dbFile = File(p.join(appDocDir.path, 'Word.db'));
    if (!await dbFile.exists()) {
      final bytes = assetContent.buffer
          .asUint8List(assetContent.offsetInBytes, assetContent.lengthInBytes);
      await dbFile.writeAsBytes(bytes);
    }

    // copy WordIndonesia.db
    final assetContent2 = await rootBundle.load('assets/WordIndonesia.db');
    final dbFile2 = File(p.join(appDocDir.path, 'WordIndonesia.db'));
    if (!await dbFile2.exists()) {
      final bytes = assetContent2.buffer.asUint8List(
          assetContent2.offsetInBytes, assetContent2.lengthInBytes);
      await dbFile2.writeAsBytes(bytes);
    }

    final wordDb = await databaseFactoryIo.openDatabase(dbFile.path);
    final wordIndonesiaDb = await databaseFactoryIo.openDatabase(dbFile2.path);

    var csvRows = await _ttsPlugin.readCSV('assets/gruut_syllables.csv');

    final exportDbFile = File(p.join(appDocDir.path, 'WordUniversal.db'));
    final exportDb = await databaseFactoryIo.openDatabase(exportDbFile.path);
    final storeRef = StoreRef.main();
    csvRows = csvRows.skip(1).toList();
    const uuid = Uuid();
    await exportDb.transaction((transaction) async {
      // copy english words
      for (final row in csvRows) {
        final word = row[0];
        final syllable = row[1];
        final ipa = row[3];
        final search = await storeRef.find(wordDb,
            finder: Finder(
              filter: Filter.equals('word', word),
            ));
        if (search.isEmpty) {
          var id = uuid.v4();
          await storeRef.record(id).put(transaction, {
            'id': id,
            'word': word,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
            '_status': 'synced',
            'inUse': true,
            'validated': false,
            'language': 'en',
            'ipa': ipa,
            'syllable': syllable,
            'level': 0
          });
        } else {
          final existingWord = search.first.value;
          var id = existingWord['id'];
          var syllable = existingWord['syllable'] ?? '';
          var inUse = existingWord['inUse'] ?? false;
          var level = existingWord['level'] ?? 0;
          await storeRef.record(id).put(transaction, {
            'id': id,
            'word': word,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
            '_status': 'synced',
            'inUse': inUse,
            'validated': false,
            'language': 'en',
            'ipa': ipa,
            'syllable': syllable,
            'level': level
          });
        }

        print('Listing english word $word');
      }

      // copy indonesian words
      final allIdWords = await storeRef.find(wordIndonesiaDb, finder: Finder());
      for (final record in allIdWords) {
        var existingWord = record.value;
        var word = existingWord['word'] ?? '';
        var inUse = existingWord['inUse'] ?? false;
        if (!inUse || word.isEmpty) continue;
        var id = existingWord['id'];
        var syllable = existingWord['syllable'] ?? '';

        var level = existingWord['level'] ?? 0;
        var ipa = existingWord['ipa'] ?? '';

        await storeRef.record(id).put(transaction, {
          'id': id,
          'word': word,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
          '_status': 'synced',
          'inUse': inUse,
          'validated': false,
          'language': 'id',
          'ipa': ipa,
          'syllable': syllable,
          'level': level
        });

        print('Listing id word $word');
      }
    });

    print('done');
  }

  Future<void> _importCsv() async {
    await initTask;
    var csvRows = await _ttsPlugin.readCSV('assets/words_arpa.csv');
    Directory appDocDir = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(appDocDir.path, 'WordInfo.db'));
    final db = await databaseFactoryIo.openDatabase(dbFile.path);
    final storeRef = StoreRef.main();
    csvRows = csvRows.skip(1).toList();
    await db.transaction((transaction) async {
      for (final row in csvRows) {
        final id = row[0];
        final word = row[1];
        final plural = row[2];
        final cmuarpaInputIds = _parseList<int>(row[3]);
        final cmuarpaPluralInputIds = _parseList<int>(row[4]);
        final cmuarpaVisemes = _parseList<String>(row[5]);
        final cmuarpaPluralVisemes = _parseList<String>(row[6]);
        await storeRef.record(id).put(transaction, {
          'id': id,
          'word': word,
          'plural': plural,
          'cmuarpaInputIds': cmuarpaInputIds,
          'cmuarpaPluralInputIds': cmuarpaPluralInputIds,
          'cmuarpaVisemes': cmuarpaVisemes,
          'cmuarpaPluralVisemes': cmuarpaPluralVisemes,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
          '_status': 'synced',
        });
      }
    });

    print('done');
  }

  Future<void> _exportCsv() async {
    await initTask;
    final allWords = await _storeRef.find(_db);
    print('there are ${allWords.length} words');

    List<List<dynamic>> rows = [];
    List<dynamic> row = [];
    row.add("id");
    row.add("word");
    row.add("plural");
    row.add("syllable");
    row.add("syllablePlural");
    row.add("ukipa");
    row.add("usipa");
    row.add("ukipaPlural");
    row.add("usipaPlural");
    row.add("inUse");
    row.add("pluralInUse");

    rows.add(row);
    for (var i = 0; i < allWords.length; i++) {
      final item = allWords[i].value;
      if (item == null) continue;
      List<dynamic> row = [];
      final id = item['id'];
      final word = item['word'] ?? '';
      final plural = item['plural'] ?? '';
      final syllable = item['syllable'] ?? '';
      final syllablePlural = item['syllablePlural'] ?? '';
      final ukipa = item['ukipa'] ?? '';
      final usipa = item['usipa'] ?? '';
      final ukipaPlural = item['ukipaPlural'] ?? '';
      final usipaPlural = item['usipaPlural'] ?? '';
      final inUse = item['inUse'] ?? false;
      final pluralInUse = item['pluralInUse'] ?? false;

      row.add(id);
      row.add(word);
      row.add(plural);
      row.add(syllable);
      row.add(syllablePlural);
      row.add(ukipa);
      row.add(usipa);
      row.add(ukipaPlural);
      row.add(usipaPlural);
      row.add(inUse);
      row.add(pluralInUse);
      rows.add(row);

      print('Listing word $word ($i)');
    }

    Directory dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'words.csv'));
    String csv = const ListToCsvConverter().convert(rows);
    await file.writeAsString(csv);
    print('done');
  }

  Future<void> _mapping() async {
    await initTask;
    final finder = Finder();
    var records = await _storeRef.find(_db, finder: finder);
    List<List<dynamic>> rows = [];
    List row = [
      'id',
      'word',
      'plural',
      'ukIPA',
      'pluralIPA',
      'ukARPA',
      'ukPluralARPA',
      'inUse',
      'pluralInUse'
    ];
    rows.add(row);
    for (final record in records) {
      List row = [];
      final data = record.value;
      final id = data['id'] ?? '';
      final word = data['word'] ?? '';
      final pluaral = data['plural'] ?? '';
      final ukipa = data['ukipa'] ?? '';
      final ukipaPlural = data['ukipaPlural'] ?? '';
      final inUse = data['inUse'] ?? false;
      final pluralInuse = data['pluralInUse'] ?? false;
      final ukChars = _ttsPlugin.breakIPA(ukipa, language: 'en');
      final ukPluralChars = _ttsPlugin.breakIPA(ukipaPlural, language: 'en');
      final ukInfo = _ttsPlugin.search(ukChars, language: 'en');
      final ukPluralInfo = _ttsPlugin.search(ukPluralChars, language: 'en');

      row.add(id);
      row.add(word);
      row.add(pluaral);
      row.add(ukipa);
      row.add(ukipaPlural);
      row.add(ukInfo['arpabet']);
      row.add(ukPluralInfo['arpabet']);
      row.add(inUse);
      row.add(pluralInuse);
      rows.add(row);
      print('process word $word');
    }

    final csv = const ListToCsvConverter().convert(rows);
    final appDocDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(appDocDir.path, 'mapping.csv'));
    await file.writeAsString(csv);
    print('done');
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
    // records = await _storeRef.find(_db,
    //     finder: Finder(
    //         filter: Filter.and([
    //       Filter.notEquals('inUse', true),
    //       Filter.notEquals('pluralInUse', true),
    //     ])));
    // await _db.transaction((db) async {
    //   for (final requeryRecord in records) {
    //     final data = requeryRecord.value;
    //     final id = data['id'] as String;
    //     final findingRecord = _storeRef.record(id);
    //     final deleteResult = await findingRecord.delete(db);
    //     print('remove word $id $deleteResult');
    //   }
    // });

    await _db.close();
    print('done');
  }

  Future<List<String>> _findIPA(String word, String language) async {
    final finder = Finder(
        filter: Filter.and([
      Filter.equals('word', word),
      Filter.equals('language', language)
    ]));
    final record = await _storeRef.findFirst(_db, finder: finder);
    final value = record?.value;
    if (value == null) {
      return [];
    }

    String ipa = value['ipa'];
    switch (language) {
      case 'id':
        return _ttsPlugin.breakIPA(ipa
            .replaceAll('.', '')
            .characters
            .map((e) => e.toLowerCase())
            .where((e) => e.isNotEmpty)
            .join(''));
      case 'en':
      default:
        final normalize = _ttsPlugin.normalizeIPA(ipa, language: language);
        return _ttsPlugin.breakIPA(normalize
            .replaceAll('.', ' ')
            .split(' ')
            .map((e) => e.toLowerCase())
            .where((e) => e.isNotEmpty)
            .join(''));
    }
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

  static List<String> breakWords(String sentence) {
    return sentence
        .split(spaceRegEx)
        .where((element) => element.trim().isNotEmpty)
        .toList();
  }

  Future<void> _speak() async {
    await initTask;
    setState(() {
      _isRunning = true;
      _result = '';
    });

    try {
      final startTime = DateTime.now().millisecondsSinceEpoch;
      var text = _textController.text;

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
          final ipa = await _findIPA(word, 'en');
          final characters = ipaCharacters(allAvailableIPAs, ipa);
          wordIPAs.add(characters);
          final map = _ttsPlugin.search(characters);
          inputIds.addAll(map['inputIds'] as List<int>);
          visemes.addAll(map['visemes'] as List<String>);
          wirdInputIds.add(map['inputIds']);
        }

        request = RequestInfo(
          'fastspeech2_quan.tflite',
          'mb_melgan.tflite',
          inputIds,
          visemes,
          useDot: true,
          speakerId: 2,
          singleThread: true,
          playerCompletedDelayed: 0,
          speed: 1.0,
          useEos: true,
          dot: 72,
          eos: 95,
        );
      } else {
        final wordTexts = breakWords(text);
        for (var wordText in wordTexts) {
          var normalise = wordText
              .replaceAll(curlyTagRegex, '')
              .replaceAll(nonAlphaUnicodeWithContractedRegEx, '')
              .toLowerCase();
          if (normalise.trim().isEmpty) {
            print('Word is empty $wordText');
            continue;
          }

          final characters = await _findIPA(normalise, 'id');
          final map = _ttsPlugin.search(characters, language: 'id');
          inputIds.addAll(map['inputIds'] as List<int>);
          visemes.addAll(map['visemes'] as List<String>);
          wordIPAs.add(characters);
          wirdInputIds.add(map['inputIds']);
        }

        request = RequestInfo(
          'id_fastspeech2_quant.tflite',
          'id_mbmelgan.tflite',
          inputIds,
          visemes,
          speakerId: 0,
          singleThread: true,
          playerCompletedDelayed: 0,
          speed: 1.0,
          useEos: true,
          dot: 31,
          eos: 36,
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
    await _ttsPlugin.loadIPAsMapping('assets/tts/en_tts_mapping.csv',
        language: 'en');
    await _ttsPlugin.loadIPAsMapping('assets/tts/id_tts_mapping.csv',
        language: 'id');

    // copy word db into storage
    Directory appDocDir = await getApplicationDocumentsDirectory();

    final assetContent = await rootBundle.load('assets/WordUniversal.db');
    final dbFile = File(p.join(appDocDir.path, 'WordUniversal.db'));
    if (!await dbFile.exists()) {
      final bytes = assetContent.buffer
          .asUint8List(assetContent.offsetInBytes, assetContent.lengthInBytes);
      await dbFile.writeAsBytes(bytes);
    }

    _db = await databaseFactoryIo.openDatabase(dbFile.path);
    _storeRef = StoreRef.main();
  }

  List<T> _parseList<T>(String? data) {
    if (data == null) return [];
    data = data.replaceAll('[', '').replaceAll(']', '');
    return List<T>.from(data
        .split(',')
        .map((e) => e.replaceAll("'", '').trim())
        .where((e) => e.isNotEmpty)
        .map((e) {
      switch (T) {
        case int:
          return int.parse(e);
        case double:
          return double.parse(e);
        default:
          return e;
      }
    }).toList());
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
