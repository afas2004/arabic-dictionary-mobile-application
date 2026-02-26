import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';

class DictionaryRepository {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, "arabic_dictionary_v5.db");

    if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
      ByteData data = await rootBundle.load(join('assets', 'arabic_dictionary_v5.db'));
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return await openDatabase(path);
  }

  Future<List<Word>> getCommonWords() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text 
      FROM lexicon l 
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      WHERE l.is_common = 1 
      ORDER BY l.frequency DESC LIMIT 100
    ''');
    return maps.map((map) => Word.fromMap(map)).toList();
  }

  Future<List<Word>> searchWords(String query) async {
    final db = await database;
    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(query);
    
    List<Map<String, dynamic>> maps;
    if (isArabic) {
      // Point 3 FIX: Added verb_form ASC to order Form I before Form II
      maps = await db.rawQuery('''
        SELECT l.*, m.meaning_text 
        FROM lexicon l 
        LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
        WHERE l.form_stripped LIKE ? OR l.root LIKE ?
        ORDER BY l.verb_form ASC, l.frequency DESC LIMIT 50
      ''', ['%$query%', '$query%']);
    } else {
      // Relevance-ranked English search
      maps = await db.rawQuery('''
        SELECT l.*, m.meaning_text,
          CASE 
            WHEN m.meaning_text LIKE ? THEN 3
            WHEN m.meaning_text LIKE ? THEN 2
            WHEN m.meaning_text LIKE ? THEN 1
            ELSE 0 
          END as relevance_score
        FROM lexicon l
        JOIN meanings m ON m.lexicon_id = l.id
        WHERE m.meaning_text LIKE ?
        ORDER BY relevance_score DESC, l.frequency DESC 
        LIMIT 50
      ''', [
        '% $query %', // Score 3: Standalone word in the middle
        '$query %',   // Score 2: Starts with the word
        '%$query%',   // Score 1: Substring match
        '%$query%'    // WHERE clause filter
      ]);
    }
    return maps.map((map) => Word.fromMap(map)).toList();
  }

  Future<List<Meaning>> getMeanings(int wordId) async {
    final db = await database;
    final maps = await db.query('meanings', where: 'lexicon_id = ?', whereArgs: [wordId], orderBy: 'order_num ASC');
    return maps.map((map) => Meaning.fromMap(map)).toList();
  }

  Future<List<Conjugation>> getConjugations(int wordId) async {
    final db = await database;
    final maps = await db.query('conjugations', where: 'base_word_id = ?', whereArgs: [wordId]);
    return maps.map((map) => Conjugation.fromMap(map)).toList();
  }

  Future<void> saveConjugations(List<Conjugation> conjugations) async {
    final db = await database;
    Batch batch = db.batch();
    for (var conj in conjugations) {
      batch.insert('conjugations', conj.toMap());
    }
    await batch.commit(noResult: true);
  }
}