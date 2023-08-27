// Future<void> _exportWords() async {
//   Directory appDocDir = await getApplicationDocumentsDirectory();
//   final assetContent = await rootBundle.load('assets/WordUniversal.db');
//   final dbFile = File(p.join(appDocDir.path, 'WordUniversal.db'));
//   if (!await dbFile.exists()) {
//     final bytes = assetContent.buffer
//         .asUint8List(assetContent.offsetInBytes, assetContent.lengthInBytes);
//     await dbFile.writeAsBytes(bytes);
//   }

//   final exportDb = await databaseFactoryIo.openDatabase(dbFile.path);
//   final storeRef = StoreRef.main();
//   final allWords = await storeRef.find(exportDb, finder: Finder());
//   List<List<dynamic>> enRows = [];
//   enRows.add([
//     'id',
//     'word',
//     'inUse',
//     'validated',
//     'language',
//     'ipa',
//     'syllable',
//     'level'
//   ]);

//   List<List<dynamic>> biRows = [];
//   biRows.add([
//     'id',
//     'word',
//     'inUse',
//     'validated',
//     'language',
//     'ipa',
//     'syllable',
//     'level'
//   ]);

//   List<List<dynamic>> enEmptyRows = [];
//   enEmptyRows.add([
//     'id',
//     'word',
//     'inUse',
//     'validated',
//     'language',
//     'ipa',
//     'syllable',
//     'level'
//   ]);

//   List<List<dynamic>> biEmptyRows = [];
//   biEmptyRows.add([
//     'id',
//     'word',
//     'inUse',
//     'validated',
//     'language',
//     'ipa',
//     'syllable',
//     'level'
//   ]);

//   for (final record in allWords) {
//     if (record['deletedAt'] != null) {
//       continue;
//     }

//     String id = record['id'] as String;
//     String word = record['word'] as String;
//     bool inUse = record['inUse'] as bool;
//     bool validated = record['validated'] as bool;
//     String language = record['language'] as String;
//     String ipa = record['ipa'] as String;
//     String syllable = record['syllable'] as String;
//     int level = record['level'] as int;

//     print('word $id');
//     if (ipa.isEmpty) {
//       print('word $word has empty ipa');
//       if (language == 'id') {
//         final rows = [
//           id,
//           word,
//           inUse,
//           validated,
//           language,
//           ipa,
//           syllable,
//           level
//         ];
//         biEmptyRows.add(rows);
//       } else if (language == 'en') {
//         final rows = [
//           id,
//           word,
//           inUse,
//           validated,
//           language,
//           ipa,
//           syllable,
//           level
//         ];
//         enEmptyRows.add(rows);
//       }
//       continue;
//     }

//     final normalize = ipa.replaceAll('ˈ', '').replaceAll(' ', '');
//     if (normalize.length > 2) {
//       print('word $word invalid');
//       continue;
//     }

//     if (language == 'id') {
//       final rows = [
//         id,
//         word,
//         inUse,
//         validated,
//         language,
//         ipa,
//         syllable,
//         level
//       ];
//       biRows.add(rows);
//     } else if (language == 'en') {
//       final rows = [
//         id,
//         word,
//         inUse,
//         validated,
//         language,
//         ipa,
//         syllable,
//         level
//       ];
//       enRows.add(rows);
//     } else {
//       throw Exception('wrong language');
//     }
//   }

//   Directory dir = await getTemporaryDirectory();
//   final biFile = File(p.join(dir.path, 'bi_words.csv'));
//   await biFile.writeAsString(const ListToCsvConverter().convert(biRows));

//   final enFile = File(p.join(dir.path, 'en_words.csv'));
//   await enFile.writeAsString(const ListToCsvConverter().convert(enRows));

//   final biEnmptyFile = File(p.join(dir.path, 'bi_empty_words.csv'));
//   await biEnmptyFile
//       .writeAsString(const ListToCsvConverter().convert(biEmptyRows));

//   final enEmptyFile = File(p.join(dir.path, 'en_empty_words.csv'));
//   await enEmptyFile
//       .writeAsString(const ListToCsvConverter().convert(enEmptyRows));
//   print('done');
// }

// Future<void> _exportBIWords() async {
//   Directory appDocDir = await getApplicationDocumentsDirectory();

//   final assetContent = await rootBundle.load('assets/WordIndonesia.db');
//   final dbFile = File(p.join(appDocDir.path, 'WordIndonesia.db'));
//   if (!await dbFile.exists()) {
//     final bytes = assetContent.buffer
//         .asUint8List(assetContent.offsetInBytes, assetContent.lengthInBytes);
//     await dbFile.writeAsBytes(bytes);
//   }

//   final db = await databaseFactoryIo.openDatabase(dbFile.path);
//   final store = StoreRef.main();
//   final allWords = await store.find(db);
//   List<List<dynamic>> rows = [];
//   List<dynamic> row = [];
//   row.add("id");
//   row.add("word");
//   row.add("plural");
//   row.add("syllable");
//   row.add("syllablePlural");

//   rows.add(row);
//   for (var i = 0; i < allWords.length; i++) {
//     final item = allWords[i].value;
//     if (item == null) continue;
//     List<dynamic> row = [];
//     final id = item['id'];
//     String word = item['word'] ?? '';
//     String plural = item['plural'] ?? '';
//     String syllable = item['syllable'] ?? '';
//     if (syllable.isEmpty) {
//       syllable = getBISyllables(word).join('.');
//     }

//     String syllablePlural = item['syllablePlural'] ?? '';
//     if (syllablePlural.isEmpty) {
//       syllablePlural = getBISyllables(plural).join('.');
//     }

//     row.add(id);
//     row.add(word);
//     row.add(plural);
//     row.add(syllable);
//     row.add(syllablePlural);
//     rows.add(row);

//     print('Listing word $word ($i)');
//   }

//   Directory dir = await getTemporaryDirectory();
//   final file = File(p.join(dir.path, 'bi_words.csv'));
//   String csv = const ListToCsvConverter().convert(rows);
//   await file.writeAsString(csv);
//   print('done');
// }

// Future<void> _importCsvToWordUniversal() async {
//   await initTask;
//   Directory appDocDir = await getApplicationDocumentsDirectory();
//   // copy word.db
//   final assetContent = await rootBundle.load('assets/Word.db');
//   final dbFile = File(p.join(appDocDir.path, 'Word.db'));
//   if (!await dbFile.exists()) {
//     final bytes = assetContent.buffer
//         .asUint8List(assetContent.offsetInBytes, assetContent.lengthInBytes);
//     await dbFile.writeAsBytes(bytes);
//   }

//   // copy WordIndonesia.db
//   final assetContent2 = await rootBundle.load('assets/WordIndonesia.db');
//   final dbFile2 = File(p.join(appDocDir.path, 'WordIndonesia.db'));
//   if (!await dbFile2.exists()) {
//     final bytes = assetContent2.buffer.asUint8List(
//         assetContent2.offsetInBytes, assetContent2.lengthInBytes);
//     await dbFile2.writeAsBytes(bytes);
//   }

//   final wordDb = await databaseFactoryIo.openDatabase(dbFile.path);
//   final wordIndonesiaDb = await databaseFactoryIo.openDatabase(dbFile2.path);

//   var csvRows = await _ttsPlugin.readCSV('assets/gruut_syllables.csv');

//   final exportDbFile = File(p.join(appDocDir.path, 'WordUniversal.db'));
//   final exportDb = await databaseFactoryIo.openDatabase(exportDbFile.path);
//   final storeRef = StoreRef.main();
//   csvRows = csvRows.skip(1).toList();
//   const uuid = Uuid();
//   await exportDb.transaction((transaction) async {
//     // copy english words
//     for (final row in csvRows) {
//       final word = row[0];
//       final syllable = row[1];
//       final ipa = row[3];
//       final search = await storeRef.find(wordDb,
//           finder: Finder(
//             filter: Filter.equals('word', word),
//           ));
//       if (search.isEmpty) {
//         var id = uuid.v4();
//         await storeRef.record(id).put(transaction, {
//           'id': id,
//           'word': word,
//           'createdAt': DateTime.now().millisecondsSinceEpoch,
//           'updatedAt': DateTime.now().millisecondsSinceEpoch,
//           '_status': 'synced',
//           'inUse': true,
//           'validated': false,
//           'language': 'en',
//           'ipa': ipa,
//           'syllable': syllable,
//           'level': 0
//         });
//       } else {
//         final existingWord = search.first.value;
//         var id = existingWord['id'];
//         var syllable = existingWord['syllable'] ?? '';
//         var inUse = existingWord['inUse'] ?? false;
//         var level = existingWord['level'] ?? 0;
//         await storeRef.record(id).put(transaction, {
//           'id': id,
//           'word': word,
//           'createdAt': DateTime.now().millisecondsSinceEpoch,
//           'updatedAt': DateTime.now().millisecondsSinceEpoch,
//           '_status': 'synced',
//           'inUse': inUse,
//           'validated': false,
//           'language': 'en',
//           'ipa': ipa,
//           'syllable': syllable,
//           'level': level
//         });
//       }

//       print('Listing english word $word');
//     }

//     // copy indonesian words
//     final allIdWords = await storeRef.find(wordIndonesiaDb, finder: Finder());
//     for (final record in allIdWords) {
//       var existingWord = record.value;
//       var word = existingWord['word'] ?? '';
//       var inUse = existingWord['inUse'] ?? false;
//       if (!inUse || word.isEmpty) continue;
//       var id = existingWord['id'];
//       var syllable = existingWord['syllable'] ?? '';

//       var level = existingWord['level'] ?? 0;
//       var ipa = existingWord['ipa'] ?? '';

//       await storeRef.record(id).put(transaction, {
//         'id': id,
//         'word': word,
//         'createdAt': DateTime.now().millisecondsSinceEpoch,
//         'updatedAt': DateTime.now().millisecondsSinceEpoch,
//         '_status': 'synced',
//         'inUse': inUse,
//         'validated': false,
//         'language': 'id',
//         'ipa': ipa,
//         'syllable': syllable,
//         'level': level
//       });

//       print('Listing id word $word');
//     }
//   });

//   print('done');
// }

// Future<void> _exportCsv() async {
//   await initTask;
//   final allWords = await _storeRef.find(_db);
//   print('there are ${allWords.length} words');

//   List<List<dynamic>> rows = [];
//   List<dynamic> row = [];
//   row.add("id");
//   row.add("word");
//   row.add("plural");
//   row.add("syllable");
//   row.add("syllablePlural");
//   row.add("ukipa");
//   row.add("usipa");
//   row.add("ukipaPlural");
//   row.add("usipaPlural");
//   row.add("inUse");
//   row.add("pluralInUse");

//   rows.add(row);
//   for (var i = 0; i < allWords.length; i++) {
//     final item = allWords[i].value;
//     if (item == null) continue;
//     List<dynamic> row = [];
//     final id = item['id'];
//     final word = item['word'] ?? '';
//     final plural = item['plural'] ?? '';
//     final syllable = item['syllable'] ?? '';
//     final syllablePlural = item['syllablePlural'] ?? '';
//     final ukipa = item['ukipa'] ?? '';
//     final usipa = item['usipa'] ?? '';
//     final ukipaPlural = item['ukipaPlural'] ?? '';
//     final usipaPlural = item['usipaPlural'] ?? '';
//     final inUse = item['inUse'] ?? false;
//     final pluralInUse = item['pluralInUse'] ?? false;

//     row.add(id);
//     row.add(word);
//     row.add(plural);
//     row.add(syllable);
//     row.add(syllablePlural);
//     row.add(ukipa);
//     row.add(usipa);
//     row.add(ukipaPlural);
//     row.add(usipaPlural);
//     row.add(inUse);
//     row.add(pluralInUse);
//     rows.add(row);

//     print('Listing word $word ($i)');
//   }

//   Directory dir = await getTemporaryDirectory();
//   final file = File(p.join(dir.path, 'words.csv'));
//   String csv = const ListToCsvConverter().convert(rows);
//   await file.writeAsString(csv);
//   print('done');
// }

// Future<void> _mapping() async {
//   await initTask;
//   final finder = Finder();
//   var records = await _storeRef.find(_db, finder: finder);
//   List<List<dynamic>> rows = [];
//   List row = [
//     'id',
//     'word',
//     'plural',
//     'ukIPA',
//     'pluralIPA',
//     'ukARPA',
//     'ukPluralARPA',
//     'inUse',
//     'pluralInUse'
//   ];
//   rows.add(row);
//   for (final record in records) {
//     List row = [];
//     final data = record.value;
//     final id = data['id'] ?? '';
//     final word = data['word'] ?? '';
//     final pluaral = data['plural'] ?? '';
//     final ukipa = data['ukipa'] ?? '';
//     final ukipaPlural = data['ukipaPlural'] ?? '';
//     final inUse = data['inUse'] ?? false;
//     final pluralInuse = data['pluralInUse'] ?? false;
//     final ukChars = _ttsPlugin.breakIPA(ukipa, language: 'en');
//     final ukPluralChars = _ttsPlugin.breakIPA(ukipaPlural, language: 'en');
//     final ukInfo = _ttsPlugin.search(ukChars, language: 'en');
//     final ukPluralInfo = _ttsPlugin.search(ukPluralChars, language: 'en');

//     row.add(id);
//     row.add(word);
//     row.add(pluaral);
//     row.add(ukipa);
//     row.add(ukipaPlural);
//     row.add(ukInfo['arpabet']);
//     row.add(ukPluralInfo['arpabet']);
//     row.add(inUse);
//     row.add(pluralInuse);
//     rows.add(row);
//     print('process word $word');
//   }

//   final csv = const ListToCsvConverter().convert(rows);
//   final appDocDir = await getApplicationDocumentsDirectory();
//   final file = File(p.join(appDocDir.path, 'mapping.csv'));
//   await file.writeAsString(csv);
//   print('done');
// }

// Future<void> _updateWordDb() async {
//   await initTask;
//   // read csv
//   final csvData = await rootBundle.loadString('assets/words.csv');
//   var detector = const FirstOccurrenceSettingsDetector(
//       fieldDelimiters: [',', ';'],
//       textDelimiters: ['"'],
//       textEndDelimiters: ['"'],
//       eols: ['\r\n', '\n']);
//   var converter = CsvToListConverter(
//     csvSettingsDetector: detector,
//     shouldParseNumbers: false,
//     allowInvalid: true,
//   );

//   final allRows = converter.convert(csvData);
//   final newWords = [];
//   allRows.skip(1).forEach((row) {
//     // inuse
//     if ('true' == row[9]?.toString().toLowerCase() ||
//         'true' == row[10]?.toString().toLowerCase()) {
//       final item = [];

//       for (var i = 0; i < row.length; i++) {
//         item.add(row[i]);
//       }
//       newWords.add(item);
//     }
//   });
//   final finder = Finder(
//       filter: Filter.or([
//     Filter.equals('inUse', true),
//     Filter.equals('pluralInUse', true),
//   ]));

//   var records = await _storeRef.find(_db, finder: finder);
//   await _db.transaction((db) async {
//     for (final requeryRecord in records) {
//       final data = requeryRecord.value;
//       final id = data['id'] as String;
//       final csvRow = newWords.firstWhereOrNull((element) => element[0] == id);
//       if (csvRow == null) {
//         continue;
//       }

//       final updateRecord = _storeRef.record(id);
//       await updateRecord.update(db, {
//         'syllable': csvRow[3],
//         'syllablePlural': csvRow[4],
//         'ukipa': csvRow[5],
//         'usipa': csvRow[6],
//         'ukipaPlural': csvRow[7],
//         'usipaPlural': csvRow[8],
//       });
//       print('update word $id');
//     }
//   });

//   // remove unused
//   // records = await _storeRef.find(_db,
//   //     finder: Finder(
//   //         filter: Filter.and([
//   //       Filter.notEquals('inUse', true),
//   //       Filter.notEquals('pluralInUse', true),
//   //     ])));
//   // await _db.transaction((db) async {
//   //   for (final requeryRecord in records) {
//   //     final data = requeryRecord.value;
//   //     final id = data['id'] as String;
//   //     final findingRecord = _storeRef.record(id);
//   //     final deleteResult = await findingRecord.delete(db);
//   //     print('remove word $id $deleteResult');
//   //   }
//   // });

//   await _db.close();
//   print('done');
// }

// Future<void> _importCsv() async {
//   await initTask;
//   var csvRows = await _ttsPlugin.readCSV('assets/words_arpa.csv');
//   Directory appDocDir = await getApplicationDocumentsDirectory();
//   final dbFile = File(p.join(appDocDir.path, 'WordInfo.db'));
//   final db = await databaseFactoryIo.openDatabase(dbFile.path);
//   final storeRef = StoreRef.main();
//   csvRows = csvRows.skip(1).toList();
//   await db.transaction((transaction) async {
//     for (final row in csvRows) {
//       final id = row[0];
//       final word = row[1];
//       final plural = row[2];
//       final cmuarpaInputIds = _parseList<int>(row[3]);
//       final cmuarpaPluralInputIds = _parseList<int>(row[4]);
//       final cmuarpaVisemes = _parseList<String>(row[5]);
//       final cmuarpaPluralVisemes = _parseList<String>(row[6]);
//       await storeRef.record(id).put(transaction, {
//         'id': id,
//         'word': word,
//         'plural': plural,
//         'cmuarpaInputIds': cmuarpaInputIds,
//         'cmuarpaPluralInputIds': cmuarpaPluralInputIds,
//         'cmuarpaVisemes': cmuarpaVisemes,
//         'cmuarpaPluralVisemes': cmuarpaPluralVisemes,
//         'createdAt': DateTime.now().millisecondsSinceEpoch,
//         'updatedAt': DateTime.now().millisecondsSinceEpoch,
//         '_status': 'synced',
//       });
//     }
//   });

//   print('done');
// }
