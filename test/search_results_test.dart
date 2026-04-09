// test/search_results_test.dart
//
// Run with: flutter test test/search_results_test.dart --verbose
//
// Uses sqflite_common_ffi so the DB runs in pure Dart — no platform needed.
// Opens the DB directly from your assets folder path.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:arabic_dictionary/models/models.dart';
import 'package:arabic_dictionary/engine/arabic_stemmer.dart';

// ── Lightweight repo that opens DB directly (no path_provider needed) ────────

class _TestRepository {
  final Database _db;
  final ArabicStemmer _stemmer = ArabicStemmer();

  _TestRepository(this._db);

  static Future<_TestRepository> open() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Direct path to your DB in the assets folder
    const dbPath =
        r'C:\Users\afahm\OneDrive\Documents\sem 5\CSP600 FYP\dataset\arabic_dictionary_v9.db';

    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    return _TestRepository(db);
  }

  Future<List<Word>> searchWords(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(trimmed);
    return isArabic ? await _searchArabic(trimmed) : await _searchEnglish(trimmed);
  }

  // ── Arabic ──────────────────────────────────────────────────────────────────

  Future<List<Word>> _searchArabic(String query) async {
    final stripped = query.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    final tokens = stripped.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    if (tokens.length > 1) {
      final seen = <int, Word>{};
      for (final token in tokens) {
        List<Word> r = await _directArabicLookup(token);
        if (r.isEmpty) r = await _stemmerFallback(token);
        for (final w in r) seen.putIfAbsent(w.id, () => w);
      }
      final merged = seen.values.toList()
        ..sort((a, b) {
          if (a.isCommon != b.isCommon) return a.isCommon ? -1 : 1;
          return b.frequency.compareTo(a.frequency);
        });
      return merged.take(50).toList();
    }

    final direct = await _directArabicLookup(stripped);
    if (direct.isNotEmpty) return direct;
    return await _stemmerFallback(stripped);
  }

  Future<List<Word>> _directArabicLookup(String stripped) async {
    final maps = await _db.rawQuery('''
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
      ORDER BY relevance_score DESC, l.is_common DESC, l.frequency DESC
      LIMIT 50
    ''', [stripped, stripped, stripped, stripped, stripped, stripped]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  Future<List<Word>> _stemmerFallback(String query) async {
    final stemResult = _stemmer.stem(query);
    if (!stemResult.success) return [];

    if (stemResult.rootForDB != null) {
      final exact = await _db.rawQuery('''
        SELECT l.*, m.meaning_text FROM lexicon l
        LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
        WHERE l.root = ?
        ORDER BY l.is_common DESC, l.frequency DESC LIMIT 50
      ''', [stemResult.rootForDB]);
      if (exact.isNotEmpty) return exact.map((m) => Word.fromMap(m)).toList();

      final likeRoot = await _db.rawQuery('''
        SELECT l.*, m.meaning_text FROM lexicon l
        LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
        WHERE l.root LIKE '%' || ? || '%'
        ORDER BY l.is_common DESC, l.frequency DESC LIMIT 50
      ''', [stemResult.rootForDB]);
      if (likeRoot.isNotEmpty) return likeRoot.map((m) => Word.fromMap(m)).toList();
    }

    if (stemResult.extractedRoot != null) {
      final likeForm = await _db.rawQuery('''
        SELECT l.*, m.meaning_text FROM lexicon l
        LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
        WHERE l.form_stripped LIKE '%' || ? || '%'
        ORDER BY l.is_common DESC, l.frequency DESC LIMIT 50
      ''', [stemResult.extractedRoot]);
      return likeForm.map((m) => Word.fromMap(m)).toList();
    }
    return [];
  }

  // ── English ─────────────────────────────────────────────────────────────────

  Future<List<Word>> _searchEnglish(String query) async {
    final lowerQuery = query.toLowerCase().trim();
    final tokens = lowerQuery.split(RegExp(r'\s+')).where((t) => t.length > 1).toList();
    if (tokens.isEmpty) return [];
    if (tokens.length == 1) return await _searchEnglishPhrase(lowerQuery);

    final tier1 = await _searchEnglishPhrase(lowerQuery);
    final seen = <int>{for (final w in tier1) w.id};

    final tier2 = <int, _SW>{};
    for (final token in tokens) {
      for (final word in await _searchEnglishToken(token, minScore: 3)) {
        if (seen.contains(word.id)) continue;
        tier2.containsKey(word.id) ? tier2[word.id]!.n++ : tier2[word.id] = _SW(word);
      }
    }

    final tier3 = <int, _SW>{};
    final tier2ids = tier2.keys.toSet();
    for (final token in tokens) {
      for (final word in await _searchEnglishToken(token, minScore: 1)) {
        if (seen.contains(word.id) || tier2ids.contains(word.id)) continue;
        tier3.containsKey(word.id) ? tier3[word.id]!.n++ : tier3[word.id] = _SW(word);
      }
    }

    return [...tier1, ..._sort(tier2), ..._sort(tier3)].take(50).toList();
  }

  Future<List<Word>> _searchEnglishPhrase(String phrase) async {
    final maps = await _db.rawQuery('''
      SELECT l.*, m.meaning_text,
        CASE
          WHEN lower(m.meaning_text) = ?                      THEN 5
          WHEN lower(m.meaning_text) LIKE ? || ' %'           THEN 4
          WHEN lower(m.meaning_text) LIKE '% ' || ? || ' %'   THEN 3
          WHEN lower(m.meaning_text) LIKE '% ' || ?           THEN 3
          WHEN lower(m.meaning_text) LIKE '% ' || ? || ',%'   THEN 3
          WHEN lower(m.meaning_text) LIKE '% ' || ? || ';%'   THEN 3
          WHEN lower(m.meaning_text) LIKE '%' || ? || '%'      THEN 2
          ELSE 0
        END AS relevance_score
      FROM lexicon l
      JOIN meanings m ON m.lexicon_id = l.id
      WHERE lower(m.meaning_text) LIKE '%' || ? || '%'
      ORDER BY relevance_score DESC, l.is_common DESC, l.frequency DESC
      LIMIT 50
    ''', [phrase, phrase, phrase, phrase, phrase, phrase, phrase, phrase]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  Future<List<Word>> _searchEnglishToken(String token, {int minScore = 1}) async {
    final maps = await _db.rawQuery('''
      SELECT * FROM (
        SELECT l.*, m.meaning_text,
          CASE
            WHEN lower(m.meaning_text) = ?                      THEN 5
            WHEN lower(m.meaning_text) LIKE ? || ' %'           THEN 4
            WHEN lower(m.meaning_text) LIKE '% ' || ? || ' %'   THEN 3
            WHEN lower(m.meaning_text) LIKE '% ' || ?           THEN 3
            WHEN lower(m.meaning_text) LIKE '% ' || ? || ',%'   THEN 3
            WHEN lower(m.meaning_text) LIKE '% ' || ? || ';%'   THEN 3
            WHEN lower(m.meaning_text) LIKE '%' || ? || '%'      THEN 2
            ELSE 0
          END AS relevance_score
        FROM lexicon l
        JOIN meanings m ON m.lexicon_id = l.id
        WHERE lower(m.meaning_text) LIKE '%' || ? || '%'
      ) AS scored
      WHERE scored.relevance_score >= ?
      ORDER BY scored.relevance_score DESC, scored.is_common DESC, scored.frequency DESC
      LIMIT 50
    ''', [token, token, token, token, token, token, token, token, minScore]);
    return maps.map((m) => Word.fromMap(m)).toList();
  }

  List<Word> _sort(Map<int, _SW> m) {
    final list = m.values.toList()
      ..sort((a, b) {
        if (b.n != a.n) return b.n.compareTo(a.n);
        if (a.word.isCommon != b.word.isCommon) return a.word.isCommon ? -1 : 1;
        return b.word.frequency.compareTo(a.word.frequency);
      });
    return list.map((s) => s.word).toList();
  }
}

class _SW {
  final Word word;
  int n;
  _SW(this.word) : n = 1;
}

// ── Print helper ──────────────────────────────────────────────────────────────

void printResults(String query, List<Word> results) {
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('QUERY: "$query"  →  ${results.length} result(s)');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  if (results.isEmpty) { print('  (no results)'); return; }
  for (int i = 0; i < results.length && i < 10; i++) {
    final w = results[i];
    final common = w.isCommon ? ' ★' : '';
    print('  ${(i + 1).toString().padLeft(2)}. '
        '${w.formArabic.padRight(18)} [${w.wordType}]$common  '
        'freq:${w.frequency}');
    print('      root: ${w.root}');
    print('      meaning: ${w.primaryMeaning ?? "(none)"}');
  }
  if (results.length > 10) print('  ... and ${results.length - 10} more');
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _TestRepository repo;

  setUpAll(() async {
    repo = await _TestRepository.open();
    print('\n✓ DB opened successfully');
  });

  group('English — single word', () {
    test('eat', () async {
      printResults('eat', await repo.searchWords('eat'));
    });
    test('write', () async {
      printResults('write', await repo.searchWords('write'));
    });
    test('book', () async {
      printResults('book', await repo.searchWords('book'));
    });
    test('go', () async {
      printResults('go', await repo.searchWords('go'));
    });
    test('knowledge', () async {
      printResults('knowledge', await repo.searchWords('knowledge'));
    });
  });

  group('English — phrase / sentence', () {
    test('to eat', () async {
      printResults('to eat', await repo.searchWords('to eat'));
    });
    test('to write', () async {
      printResults('to write', await repo.searchWords('to write'));
    });
    test('to go to the mosque', () async {
      printResults('to go to the mosque', await repo.searchWords('to go to the mosque'));
    });
  });

  group('Arabic — single word', () {
    test('كتب', () async {
      printResults('كتب', await repo.searchWords('كتب'));
    });
    test('أكل', () async {
      printResults('أكل', await repo.searchWords('أكل'));
    });
    test('ذهب', () async {
      printResults('ذهب', await repo.searchWords('ذهب'));
    });
    test('علم', () async {
      printResults('علم', await repo.searchWords('علم'));
    });
  });

  group('Arabic — stemmer fallback', () {
    test('كتبوا', () async {
      final r = await repo.searchWords('كتبوا');
      printResults('كتبوا', r);
      if (r.isNotEmpty) {
        print('  Roots found: ${r.map((w) => w.root).toSet().join(', ')}');
      }
    });
    test('مكتوب', () async {
      printResults('مكتوب', await repo.searchWords('مكتوب'));
    });
    test('الكتاب', () async {
      printResults('الكتاب', await repo.searchWords('الكتاب'));
    });
    test('يذهبون', () async {
      printResults('يذهبون', await repo.searchWords('يذهبون'));
    });
    test('مدارس', () async {
      printResults('مدارس', await repo.searchWords('مدارس'));
    });
  });

  group('Arabic — sentence', () {
    test('ذهب الرجل', () async {
      printResults('ذهب الرجل', await repo.searchWords('ذهب الرجل'));
    });
    test('كتب الطالب الدرس', () async {
      printResults('كتب الطالب الدرس', await repo.searchWords('كتب الطالب الدرس'));
    });
  });

  group('Edge cases', () {
    test('empty string', () async {
      final r = await repo.searchWords('');
      expect(r, isEmpty);
      print('\nQUERY: "" → ${r.length} results ✓');
    });
    test('unknown word xyzxyz', () async {
      final r = await repo.searchWords('xyzxyz');
      expect(r, isEmpty);
      print('\nQUERY: "xyzxyz" → ${r.length} results ✓');
    });
  });
}