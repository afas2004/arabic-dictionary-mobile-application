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

  // ── Common words ───────────────────────────────────────────────────────────

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

  // ── Main search entry point ────────────────────────────────────────────────

  Future<List<Word>> searchWords(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(trimmed);
    return isArabic
        ? await _searchArabic(trimmed)
        : await _searchEnglish(trimmed);
  }

  // ── Arabic search ──────────────────────────────────────────────────────────

  Future<List<Word>> _searchArabic(String query) async {
    final stripped = query.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');

    // Tier 1: Direct lookup on full query (exact / prefix / substring)
    final directResults = await _directArabicLookup(stripped);

    // Single word — direct + stemmer fallback, done
    final tokens = stripped.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.length == 1) {
      if (directResults.isNotEmpty) return directResults;
      return await _stemmerFallback(stripped);
    }

    // Multi-word:
    // Tier 1 results (full phrase) go first
    final seen = <int, Word>{};
    for (final w in directResults) seen[w.id] = w;

    // Tier 2: per-token direct lookup
    final tier2 = <int, _ScoredWord>{};
    for (final token in tokens) {
      final results = await _directArabicLookup(token);
      for (final word in results) {
        if (seen.containsKey(word.id)) continue; // already in tier 1
        if (tier2.containsKey(word.id)) {
          tier2[word.id]!.matchCount++;
        } else {
          tier2[word.id] = _ScoredWord(word: word, matchCount: 1);
        }
      }
    }

    // Tier 3: per-token stemmer fallback
    final tier3 = <int, _ScoredWord>{};
    for (final token in tokens) {
      final results = await _stemmerFallback(token);
      for (final word in results) {
        if (seen.containsKey(word.id)) continue;
        if (tier2.containsKey(word.id)) continue;
        if (tier3.containsKey(word.id)) {
          tier3[word.id]!.matchCount++;
        } else {
          tier3[word.id] = _ScoredWord(word: word, matchCount: 1);
        }
      }
    }

    final tier2Sorted = _sortScoredWords(tier2);
    final tier3Sorted = _sortScoredWords(tier3);

    return [
      ...directResults,
      ...tier2Sorted,
      ...tier3Sorted,
    ].take(50).toList();
  }

  /// Direct lookup on form_stripped and root.
  /// Groups by form_stripped + word_type to eliminate duplicate DB entries.
  Future<List<Word>> _directArabicLookup(String stripped) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l.*, m.meaning_text,
        CASE
          WHEN l.form_stripped = ?                  THEN 4
          WHEN l.form_stripped LIKE ? || '%'         THEN 3
          WHEN l.form_stripped LIKE '%' || ? || '%'  THEN 2
          WHEN l.root LIKE ? || '%'                  THEN 1
          ELSE 0
        END AS relevance_score
      FROM lexicon l
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      WHERE l.form_stripped LIKE '%' || ? || '%'
         OR l.root LIKE ? || '%'
      GROUP BY l.form_stripped, l.word_type
      ORDER BY relevance_score DESC, l.is_common DESC, l.frequency DESC
      LIMIT 50
    ''', [stripped, stripped, stripped, stripped, stripped, stripped]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  /// Stemmer fallback: root column → compound root LIKE → form_stripped LIKE.
  Future<List<Word>> _stemmerFallback(String query) async {
    final stemResult = _stemmer.stem(query);
    if (!stemResult.success) return [];

    final db = await database;

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

      // Handles compound roots like 'وهب-;-هيب'
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

  // ── English search ─────────────────────────────────────────────────────────

  /// 3-tier English search:
  ///   Tier 1 — full phrase match in meaning_text
  ///   Tier 2 — per-token exact/boundary matches (deduped against tier 1)
  ///   Tier 3 — per-token substring/related matches (deduped against tiers 1+2)
  Future<List<Word>> _searchEnglish(String query) async {
    final lowerQuery = query.toLowerCase().trim();

    // Tokenize — skip single-char noise words ("a", "I")
    final tokens = lowerQuery
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1)
        .toList();

    if (tokens.isEmpty) return [];

    // Tier 1: full phrase search
    final tier1 = await _searchEnglishPhrase(lowerQuery);
    final seen = <int>{};
    for (final w in tier1) seen.add(w.id);

    // Single word — tier 1 is sufficient (phrase == token)
    if (tokens.length == 1) return tier1;

    // Tier 2: per-token high-score matches (score ≥ 3 = word boundary hit)
    final tier2 = <int, _ScoredWord>{};
    for (final token in tokens) {
      final results = await _searchEnglishSingleToken(token, minScore: 3);
      for (final word in results) {
        if (seen.contains(word.id)) continue;
        if (tier2.containsKey(word.id)) {
          tier2[word.id]!.matchCount++;
        } else {
          tier2[word.id] = _ScoredWord(word: word, matchCount: 1);
        }
      }
    }
    final tier2Ids = tier2.keys.toSet();

    // Tier 3: per-token substring/related matches (score < 3)
    final tier3 = <int, _ScoredWord>{};
    for (final token in tokens) {
      final results = await _searchEnglishSingleToken(token, minScore: 1);
      for (final word in results) {
        if (seen.contains(word.id)) continue;
        if (tier2Ids.contains(word.id)) continue;
        if (tier3.containsKey(word.id)) {
          tier3[word.id]!.matchCount++;
        } else {
          tier3[word.id] = _ScoredWord(word: word, matchCount: 1);
        }
      }
    }

    return [
      ...tier1,
      ..._sortScoredWords(tier2),
      ..._sortScoredWords(tier3),
    ].take(50).toList();
  }

  /// Full phrase search — treats the entire query as one string.
  ///
  /// Scoring (high → low):
  ///   5 — meaning_text is exactly the phrase
  ///   4 — phrase starts meaning ("eat something...") OR ends meaning ("to eat")
  ///   3 — phrase appears at word boundary inside meaning, or before comma/semicolon
  ///   2 — substring match anywhere
  ///
  /// Deduplication: groups by form_stripped + word_type to remove duplicate
  /// DB entries that share the same surface form and meaning.
  Future<List<Word>> _searchEnglishPhrase(String phrase) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT * FROM (
        SELECT l.*, m.meaning_text,
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
        FROM lexicon l
        JOIN meanings m ON m.lexicon_id = l.id
        WHERE lower(m.meaning_text) LIKE '%' || ? || '%'
        GROUP BY l.form_stripped, l.word_type
      ) AS scored
      ORDER BY scored.relevance_score DESC, scored.is_common DESC, scored.frequency DESC
      LIMIT 50
    ''', [phrase, phrase, phrase, phrase, phrase, phrase, phrase, phrase]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  /// Single token search. [minScore] filters results to only include
  /// rows at or above that relevance score, allowing tier separation.
  /// Uses a subquery so we can filter on the computed relevance_score
  /// with WHERE (SQLite does not allow HAVING without GROUP BY).
  /// Same scoring and deduplication as phrase search.
  Future<List<Word>> _searchEnglishSingleToken(
    String token, {
    int minScore = 1,
  }) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT * FROM (
        SELECT l.*, m.meaning_text,
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
        FROM lexicon l
        JOIN meanings m ON m.lexicon_id = l.id
        WHERE lower(m.meaning_text) LIKE '%' || ? || '%'
        GROUP BY l.form_stripped, l.word_type
      ) AS scored
      WHERE scored.relevance_score >= ?
      ORDER BY scored.relevance_score DESC, scored.is_common DESC, scored.frequency DESC
      LIMIT 50
    ''', [token, token, token, token, token, token, token, token, minScore]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  // ── Detail queries ─────────────────────────────────────────────────────────

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
      SELECT l.*, m.meaning_text
      FROM related_forms rf
      JOIN lexicon l ON l.id = rf.related_word_id
      LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
      WHERE rf.source_word_id = ?
      ORDER BY l.is_common DESC, l.frequency DESC
    ''', [wordId]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  // ── Conjugation cache ──────────────────────────────────────────────────────

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

  // ── Internal helpers ───────────────────────────────────────────────────────

  List<Word> _sortScoredWords(Map<int, _ScoredWord> scored) {
    final list = scored.values.toList()
      ..sort((a, b) {
        if (b.matchCount != a.matchCount) {
          return b.matchCount.compareTo(a.matchCount);
        }
        if (a.word.isCommon != b.word.isCommon) return a.word.isCommon ? -1 : 1;
        return b.word.frequency.compareTo(a.word.frequency);
      });
    return list.map((s) => s.word).toList();
  }
}

class _ScoredWord {
  final Word word;
  int matchCount;
  _ScoredWord({required this.word, required this.matchCount});
}