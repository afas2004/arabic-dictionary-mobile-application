// lib/repositories/dictionary_repository.dart
//
// Pure data-access layer. No search orchestration, no stemmer logic.
// Every public method maps 1-to-1 with one SQL query or one DB operation.
// Search orchestration lives in SearchManager (business layer).

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
import '../engine/conjugation_engine.dart';

class DictionaryRepository {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'arabic_dictionary_v11.db');

    if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
      final ByteData data =
          await rootBundle.load(join('assets', 'arabic_dictionary_v11.db'));
      final List<int> bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }

    final db = await openDatabase(path);

    // Ensure conjugations lookup indexes exist (idempotent).
    // idx_conj_base is used by ConjugationEngine for the detail-page table.
    // idx_conj_stripped is used by the Stemmer's T2 form_stripped lookup —
    // without it that tier degrades from index-seek to full table-scan.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_conj_base ON conjugations(base_word_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_conj_stripped ON conjugations(form_stripped)',
    );

    return db;
  }

  // ── Common words ─────────────────────────────────────────────────────────────

  Future<List<Word>> getCommonWords() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text, parent.form_arabic AS base_form_arabic
      FROM lexicon l
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      LEFT JOIN lexicon parent ON l.base_form_id = parent.id
      WHERE l.is_common = 1
      ORDER BY l.frequency DESC
      LIMIT 100
    ''');
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  // ── Arabic lookup queries ─────────────────────────────────────────────────────
  //
  // directArabicLookup — form_stripped prefix/substring + root prefix match.
  // Uses MIN(id) subquery to guarantee deterministic row selection when
  // multiple DB entries share the same (form_stripped, word_type) pair.

  Future<List<Word>> directArabicLookup(String stripped) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l2.*, m.meaning_text, parent.form_arabic AS base_form_arabic,
        CASE
          WHEN l2.form_stripped = ?                  THEN 4
          WHEN l2.form_stripped LIKE ? || '%'         THEN 3
          WHEN l2.form_stripped LIKE '%' || ? || '%'  THEN 2
          WHEN l2.root LIKE ? || '%'                  THEN 1
          ELSE 0
        END AS relevance_score
      FROM (
        SELECT MIN(id) AS min_id
        FROM lexicon
        WHERE form_stripped LIKE '%' || ? || '%'
           OR root LIKE ? || '%'
        GROUP BY form_stripped, word_type
      ) g
      JOIN lexicon l2 ON l2.id = g.min_id
      LEFT JOIN meanings m ON l2.id = m.lexicon_id AND m.order_num = 1
      LEFT JOIN lexicon parent ON l2.base_form_id = parent.id
      ORDER BY relevance_score DESC, l2.is_common DESC, l2.frequency DESC
      LIMIT 50
    ''', [stripped, stripped, stripped, stripped, stripped, stripped]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  /// Exact root match — used as first stemmer fallback tier.
  Future<List<Word>> exactRootLookup(String rootForDB) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text, parent.form_arabic AS base_form_arabic
      FROM lexicon l
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      LEFT JOIN lexicon parent ON l.base_form_id = parent.id
      WHERE l.root = ?
      ORDER BY l.is_common DESC, l.frequency DESC
      LIMIT 50
    ''', [rootForDB]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  /// LIKE root match — handles compound roots like 'وهب-;-هيب'.
  Future<List<Word>> likeRootLookup(String rootForDB) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text, parent.form_arabic AS base_form_arabic
      FROM lexicon l
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      LEFT JOIN lexicon parent ON l.base_form_id = parent.id
      WHERE l.root LIKE '%' || ? || '%'
      ORDER BY l.is_common DESC, l.frequency DESC
      LIMIT 50
    ''', [rootForDB]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  /// form_stripped LIKE match — last-resort stemmer fallback.
  Future<List<Word>> likeFormLookup(String extractedRoot) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text, parent.form_arabic AS base_form_arabic
      FROM lexicon l
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      LEFT JOIN lexicon parent ON l.base_form_id = parent.id
      WHERE l.form_stripped LIKE '%' || ? || '%'
      ORDER BY l.is_common DESC, l.frequency DESC
      LIMIT 50
    ''', [extractedRoot]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  /// Fetch a single lexicon row by its primary key.  Used by the new
  /// Stemmer — which already resolves an input to a `lexicon.id` — to return
  /// the full [Word] (with first meaning + parent base form) to SearchManager.
  Future<Word?> getWordById(int id) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text, parent.form_arabic AS base_form_arabic
      FROM lexicon l
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      LEFT JOIN lexicon parent ON l.base_form_id = parent.id
      WHERE l.id = ?
      LIMIT 1
    ''', [id]);
    if (maps.isEmpty) return null;
    return Word.fromMap(maps.first);
  }

  /// Raw DB handle for callers that need it (notably the new Stemmer, which
  /// owns its own SQL for the cascade rather than routing through bespoke
  /// repository methods).
  Future<Database> get rawDatabase => database;

  // ── English lookup queries ────────────────────────────────────────────────────
  //
  // Scoring (high → low):
  //   5 — meaning_text exactly equals query
  //   4 — query starts or ends meaning
  //   3 — query appears at word boundary or before comma/semicolon
  //   2 — substring match anywhere
  //
  // Deduplication: MIN(id) subquery per (form_stripped, word_type) group.

  Future<List<Word>> englishPhraseLookup(String phrase) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l2.*, m.meaning_text, parent.form_arabic AS base_form_arabic,
        CASE
          WHEN lower(m.meaning_text) = ?                      THEN 5
          WHEN lower(m.meaning_text) LIKE ? || ' %'           THEN 4
          WHEN lower(m.meaning_text) LIKE '% ' || ?           THEN 4
          WHEN lower(m.meaning_text) LIKE '% ' || ? || ' %'   THEN 3
          WHEN lower(m.meaning_text) LIKE '% ' || ? || ',%'   THEN 3
          WHEN lower(m.meaning_text) LIKE '% ' || ? || ';%'   THEN 3
          WHEN lower(m.meaning_text) LIKE '%' || ? || '%'      THEN 2
          ELSE 0
        END AS relevance_score
      FROM (
        SELECT MIN(l.id) AS min_id
        FROM lexicon l
        JOIN meanings m ON m.lexicon_id = l.id
        WHERE lower(m.meaning_text) LIKE '%' || ? || '%'
        GROUP BY l.form_stripped, l.word_type
      ) g
      JOIN lexicon l2 ON l2.id = g.min_id
      JOIN meanings m ON m.lexicon_id = l2.id AND m.order_num = 1
      LEFT JOIN lexicon parent ON l2.base_form_id = parent.id
      ORDER BY relevance_score DESC, l2.is_common DESC, l2.frequency DESC
      LIMIT 50
    ''', [phrase, phrase, phrase, phrase, phrase, phrase, phrase, phrase]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  /// Single token search. [minScore] gates tier separation in SearchManager.
  Future<List<Word>> englishTokenLookup(
    String token, {
    int minScore = 1,
  }) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l2.*, m.meaning_text, parent.form_arabic AS base_form_arabic,
        CASE
          WHEN lower(m.meaning_text) = ?                      THEN 5
          WHEN lower(m.meaning_text) LIKE ? || ' %'           THEN 4
          WHEN lower(m.meaning_text) LIKE '% ' || ?           THEN 4
          WHEN lower(m.meaning_text) LIKE '% ' || ? || ' %'   THEN 3
          WHEN lower(m.meaning_text) LIKE '% ' || ? || ',%'   THEN 3
          WHEN lower(m.meaning_text) LIKE '% ' || ? || ';%'   THEN 3
          WHEN lower(m.meaning_text) LIKE '%' || ? || '%'      THEN 2
          ELSE 0
        END AS relevance_score
      FROM (
        SELECT MIN(l.id) AS min_id
        FROM lexicon l
        JOIN meanings m ON m.lexicon_id = l.id
        WHERE lower(m.meaning_text) LIKE '%' || ? || '%'
        GROUP BY l.form_stripped, l.word_type
      ) g
      JOIN lexicon l2 ON l2.id = g.min_id
      JOIN meanings m ON m.lexicon_id = l2.id AND m.order_num = 1
      LEFT JOIN lexicon parent ON l2.base_form_id = parent.id
      WHERE (
        CASE
          WHEN lower(m.meaning_text) = ?                      THEN 5
          WHEN lower(m.meaning_text) LIKE ? || ' %'           THEN 4
          WHEN lower(m.meaning_text) LIKE '% ' || ?           THEN 4
          WHEN lower(m.meaning_text) LIKE '% ' || ? || ' %'   THEN 3
          WHEN lower(m.meaning_text) LIKE '% ' || ? || ',%'   THEN 3
          WHEN lower(m.meaning_text) LIKE '% ' || ? || ';%'   THEN 3
          WHEN lower(m.meaning_text) LIKE '%' || ? || '%'      THEN 2
          ELSE 0
        END
      ) >= ?
      ORDER BY relevance_score DESC, l2.is_common DESC, l2.frequency DESC
      LIMIT 50
    ''', [
      token, token, token, token, token, token, token, // outer CASE (7)
      token,                                            // inner WHERE LIKE (1)
      token, token, token, token, token, token, token, // WHERE CASE (7)
      minScore,                                         // >= minScore (1)
    ]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  // ── Detail queries ────────────────────────────────────────────────────────────

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

  Future<List<Word>> getRelatedForms(int wordId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text, parent.form_arabic AS base_form_arabic
      FROM related_forms rf
      JOIN lexicon l ON l.id = rf.related_word_id
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      LEFT JOIN lexicon parent ON l.base_form_id = parent.id
      WHERE rf.source_word_id = ?
      ORDER BY l.is_common DESC, l.frequency DESC
    ''', [wordId]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  // ── Root family ───────────────────────────────────────────────────────────────

  /// All words sharing the same root, capped at [limit] to prevent
  /// common roots (ك-ت-ب etc.) from flooding the tab.
  Future<List<Word>> getRootFamily(String root, {int limit = 10}) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text, parent.form_arabic AS base_form_arabic
      FROM lexicon l
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      LEFT JOIN lexicon parent ON l.base_form_id = parent.id
      WHERE l.root = ?
      ORDER BY l.is_common DESC, l.frequency DESC
      LIMIT ?
    ''', [root, limit]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  // ── Favourites ────────────────────────────────────────────────────────────────

  /// Fetches full Word objects for a list of IDs (used by FavouritesScreen).
  Future<List<Word>> getFavouriteWords(List<int> ids) async {
    if (ids.isEmpty) return [];
    final db = await database;
    final placeholders = ids.map((_) => '?').join(',');
    final maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text, parent.form_arabic AS base_form_arabic
      FROM lexicon l
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      LEFT JOIN lexicon parent ON l.base_form_id = parent.id
      WHERE l.id IN ($placeholders)
    ''', ids);
    // Preserve the order the user starred them (ids list order).
    final byId = {for (final w in maps.map((m) => Word.fromMap(m))) w.id: w};
    return ids.map((id) => byId[id]).whereType<Word>().toList();
  }

  // ── Conjugation ───────────────────────────────────────────────────────────────
  //
  // Keeps ConjugationEngine creation here so cubits never touch the raw db handle.

  Future<ConjugationTable?> getConjugationTable(Word word) async {
    if (word.wordType != 'base_verb') return null;
    final db = await database;
    final engine = ConjugationEngine(db);
    return engine.getConjugations(
      lexiconId: word.id,
      formStripped: word.formStripped,
      root: word.root,
    );
  }
}
