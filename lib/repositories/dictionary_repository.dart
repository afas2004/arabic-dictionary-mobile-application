// lib/repositories/dictionary_repository.dart

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
import '../engine/arabic_stemmer.dart';

class DictionaryRepository {
  static Database? _db;
  final ArabicStemmer _stemmer = ArabicStemmer();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'arabic_dictionary_v7.db');

    if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
      final ByteData data =
          await rootBundle.load(join('assets', 'arabic_dictionary_v7.db'));
      final List<int> bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }

    return await openDatabase(path);
  }

  // ── Common words (for cache preload) ─────────────────────────────────────

  Future<List<Word>> getCommonWords() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text
      FROM lexicon l
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      WHERE l.is_common = 1
      ORDER BY l.frequency DESC
      LIMIT 100
    ''');
    return maps.map((map) => Word.fromMap(map)).toList();
  }

  // ── Main search — Arabic and English ─────────────────────────────────────

  /// Entry point for all search queries.
  ///
  /// Arabic flow:
  ///   1. Direct form_stripped / root lookup
  ///   2. If empty → stemmer fallback (root column, then form_stripped LIKE)
  ///
  /// English flow:
  ///   Standard meaning_text LIKE with relevance ranking (no stemming needed).
  Future<List<Word>> searchWords(String query) async {
    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(query);
    return isArabic
        ? await _searchArabic(query)
        : await _searchEnglish(query);
  }

  // ── Arabic search ─────────────────────────────────────────────────────────

  Future<List<Word>> _searchArabic(String query) async {
    // Strip diacritics from query so vocalized input also matches form_stripped
    final stripped = query.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');

    // Step 1 — Direct lookup
    final directResults = await _directArabicLookup(stripped);
    if (directResults.isNotEmpty) return directResults;

    // Step 2 — Stemmer fallback
    return await _stemmerFallback(stripped);
  }

  /// Direct lookup: exact/prefix/substring on form_stripped + root starts-with.
  Future<List<Word>> _directArabicLookup(String stripped) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text,
        CASE
          WHEN l.form_stripped = ?         THEN 4
          WHEN l.form_stripped LIKE ? || '%' THEN 3
          WHEN l.form_stripped LIKE '%' || ? || '%' THEN 2
          WHEN l.root LIKE ? || '%'        THEN 1
          ELSE 0
        END AS relevance_score
      FROM lexicon l
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      WHERE l.form_stripped LIKE '%' || ? || '%'
         OR l.root LIKE ? || '%'
      ORDER BY relevance_score DESC, l.is_common DESC, l.frequency DESC
      LIMIT 50
    ''', [
      stripped,  // score 4: exact
      stripped,  // score 3: starts-with
      stripped,  // score 2: substring
      stripped,  // score 1: root starts-with
      stripped,  // WHERE form_stripped
      stripped,  // WHERE root
    ]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  /// Stemmer fallback:
  ///   1. WHERE root = 'ك-ت-ب'          (exact root family)
  ///   2. WHERE root LIKE '%ك-ت-ب%'     (handles compound roots like و-ه-ب-;-ه-ي-ب)
  ///   3. WHERE form_stripped LIKE '%كتب%' (broadest fallback)
  Future<List<Word>> _stemmerFallback(String query) async {
    final stemResult = _stemmer.stem(query);
    if (!stemResult.success) return [];

    final db = await database;

    // 2a — Exact root match
    if (stemResult.rootForDB != null) {
      final exactRoot = await db.rawQuery('''
        SELECT l.*, m.meaning_text
        FROM lexicon l
        LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
        WHERE l.root = ?
        ORDER BY l.is_common DESC, l.frequency DESC
        LIMIT 50
      ''', [stemResult.rootForDB]);

      if (exactRoot.isNotEmpty) {
        return exactRoot.map((m) => Word.fromMap(m)).toList();
      }

      // 2b — LIKE root match (catches compound roots)
      final likeRoot = await db.rawQuery('''
        SELECT l.*, m.meaning_text
        FROM lexicon l
        LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
        WHERE l.root LIKE '%' || ? || '%'
        ORDER BY l.is_common DESC, l.frequency DESC
        LIMIT 50
      ''', [stemResult.rootForDB]);

      if (likeRoot.isNotEmpty) {
        return likeRoot.map((m) => Word.fromMap(m)).toList();
      }
    }

    // 2c — form_stripped LIKE (broadest, last resort)
    if (stemResult.extractedRoot != null) {
      final likeForm = await db.rawQuery('''
        SELECT l.*, m.meaning_text
        FROM lexicon l
        LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
        WHERE l.form_stripped LIKE '%' || ? || '%'
        ORDER BY l.is_common DESC, l.frequency DESC
        LIMIT 50
      ''', [stemResult.extractedRoot]);

      return likeForm.map((m) => Word.fromMap(m)).toList();
    }

    return [];
  }

  // ── English search ────────────────────────────────────────────────────────

  Future<List<Word>> _searchEnglish(String query) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text,
        CASE
          WHEN m.meaning_text LIKE '% ' || ? || ' %' THEN 3
          WHEN m.meaning_text LIKE ? || ' %'          THEN 2
          WHEN m.meaning_text LIKE '%' || ? || '%'    THEN 1
          ELSE 0
        END AS relevance_score
      FROM lexicon l
      JOIN meanings m ON m.lexicon_id = l.id
      WHERE m.meaning_text LIKE '%' || ? || '%'
      ORDER BY relevance_score DESC, l.is_common DESC, l.frequency DESC
      LIMIT 50
    ''', [query, query, query, query]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  // ── Detail queries ────────────────────────────────────────────────────────

  Future<List<Meaning>> getMeanings(int wordId) async {
    final db = await database;
    final maps = await db.query(
      'meanings',
      where: 'lexicon_id = ?',
      whereArgs: [wordId],
      orderBy: 'order_num ASC',
    );
    return maps.map((m) => Meaning.fromMap(m)).toList();
  }

  /// Returns all words that share the same root as [wordId].
  /// Used on the detail screen to show the full root family.
  Future<List<Word>> getRelatedForms(int wordId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text
      FROM related_forms rf
      JOIN lexicon l ON l.id = rf.related_word_id
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      WHERE rf.source_word_id = ?
      ORDER BY l.is_common DESC, l.frequency DESC
    ''', [wordId]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  // ── Conjugation cache ─────────────────────────────────────────────────────

  Future<List<Conjugation>> getConjugations(int wordId) async {
    final db = await database;
    final maps = await db.query(
      'conjugations',
      where: 'base_word_id = ?',
      whereArgs: [wordId],
      orderBy: 'display_order ASC',
    );
    return maps.map((m) => Conjugation.fromMap(m)).toList();
  }

  Future<void> saveConjugations(List<Conjugation> conjugations) async {
    final db = await database;
    final Batch batch = db.batch();
    for (final conj in conjugations) {
      batch.insert('conjugations', conj.toMap());
    }
    await batch.commit(noResult: true);
  }
}
