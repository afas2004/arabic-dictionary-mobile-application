// lib/engine/stemmer.dart
//
// Runtime Arabic Stemmer — 7-tier cascading resolver.
//
// Replaces the old ISRI+Khoja-only `arabic_stemmer.dart`.  Unlike the previous
// engine, this stemmer is DB-aware: it consults the `lexicon` and
// `conjugations` tables directly at each tier, only falling back to pattern
// analysis when every lookup-based path has been exhausted.
//
// ── Normalisation ─────────────────────────────────────────────────────────────
//
//   Every input is normalised with exactly the same pipeline used at build
//   time by `populate_conjugations.py`:
//     1. strip diacritics (U+064B..U+065F, U+0670)
//     2. strip tatweel    (U+0640)
//     3. unify alef variants (أ إ آ ٱ → ا)
//
//   This guarantees that if a form is stored under `form_stripped`, the
//   runtime's `form_stripped` of the user query will match byte-for-byte.
//
// ── Tier cascade ──────────────────────────────────────────────────────────────
//
//   T1  directLexicon             — user's form_stripped hits lexicon row
//   T2  conjugationTable          — form_stripped hits a conjugations row,
//                                   returns base_word_id → base verb
//   T3  cliticStripped  (single)  — strip ONE single-char proclitic, retry T1/T2
//   T4  cliticStripped  (al+cmp)  — strip ال and compound proclitics (وال/بال/
//                                   كال/فال/لل), retry T1/T2
//   T5  cliticStripped  (suffix)  — strip one enclitic (ه/ها/هم/كم/ني/…), retry
//   T6  cliticStripped  (combo)   — try a capped cross-product of prefix ×
//                                   suffix (≤30 pairs), retry T1/T2
//   T7  fuzzyRoot                 — Khoja pattern analysis → extract 3-letter
//                                   root → lexicon lookup by `root` column
//
//   The first tier that produces a non-empty result short-circuits the rest.
//   If every tier misses, the stemmer returns StemSource.notFound.
//
// ── Performance logging ───────────────────────────────────────────────────────
//
//   Each tier emits `[PERF] tier=TX … µs` via debugPrint.  SearchManager can
//   aggregate these into its own `[PERF] stemmer : …ms` line.
//
// ── Caveats ───────────────────────────────────────────────────────────────────
//
//   • The stemmer returns the first plausible hit; it does not attempt to
//     disambiguate homographs.  SearchManager is responsible for broader
//     ranking via directArabicLookup / exactRootLookup.
//   • T6's cross-product is deliberately bounded.  We cap at 30 combinations
//     so pathological inputs cannot blow up query count.
//   • Requires the DB to have `idx_conj_stripped` on `conjugations.form_stripped`
//     (added by `populate_conjugations.py`).  Without it, T2 degrades from
//     index-seek to table-scan and the tier budget suffers.

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

enum StemSource {
  /// Exact match against `lexicon.form_stripped`.
  directLexicon,

  /// Exact match against `conjugations.form_stripped` → base verb.
  conjugationTable,

  /// After stripping clitics, matched `lexicon.form_stripped`.
  cliticStrippedLexicon,

  /// After stripping clitics, matched `conjugations.form_stripped`.
  cliticStrippedConjugation,

  /// Khoja-style pattern extracted a 3-letter root that matched `lexicon.root`.
  fuzzyRoot,

  /// No tier produced a hit.
  notFound,
}

class StemResult {
  /// `lexicon.id` of the resolved base form (null on a miss).
  final int? lexiconId;

  /// The stored `form_arabic` of the resolved lexicon row (fully diacritised),
  /// null on a miss.  Useful for confirming the match to the user.
  final String? matchedForm;

  /// Which tier produced the result.
  final StemSource source;

  /// Extracted 3-letter root — only populated by T7.
  final String? extractedRoot;

  /// The exact sequence of clitics removed, e.g. "وس…ون".  Null on T1/T2/T7.
  final String? strippedClitics;

  /// True iff [source] != [StemSource.notFound].
  bool get success => source != StemSource.notFound;

  const StemResult({
    this.lexiconId,
    this.matchedForm,
    required this.source,
    this.extractedRoot,
    this.strippedClitics,
  });

  /// Canonical notFound instance.
  static const StemResult miss =
      StemResult(source: StemSource.notFound);

  @override
  String toString() => 'StemResult(source: $source, id: $lexiconId, '
      'matched: $matchedForm, root: $extractedRoot, '
      'clitics: $strippedClitics)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Stemmer
// ─────────────────────────────────────────────────────────────────────────────

class Stemmer {
  final Database _db;

  Stemmer(this._db);

  // ── Normalisation constants ────────────────────────────────────────────────

  static final RegExp _diacriticsRegex = RegExp(r'[\u064B-\u065F\u0670]');
  static final RegExp _tatweelRegex    = RegExp(r'\u0640');
  static final RegExp _alefVariants    = RegExp(r'[\u0623\u0625\u0622\u0671]');
  static final RegExp _arabicLetter    = RegExp(r'[\u0600-\u06FF]');

  /// Strips diacritics + tatweel, unifies alef variants.  Matches
  /// `populate_conjugations.py::normalize()` byte-for-byte.
  static String normalize(String input) {
    var s = input.trim();
    s = s.replaceAll(_diacriticsRegex, '');
    s = s.replaceAll(_tatweelRegex, '');
    s = s.replaceAll(_alefVariants, '\u0627');
    return s;
  }

  // ── Clitic inventories ─────────────────────────────────────────────────────
  //
  // Single proclitics — conjunctions / preposition / future marker / vocative.
  // Note: 'ال' is treated separately (T4) so T3 can short-circuit on easy
  // one-letter strips without also testing the article.
  static const List<String> _singleProclitics = [
    'و', 'ف', 'ب', 'ل', 'ك', 'س',
  ];

  // Compound proclitics — conjunction/preposition + definite article.
  // Longest first: T4 greedy-strips using this ordered list.
  // Four-char combos (و/ف + preposition + ال) come first so "وبالمدرسة"
  // peels cleanly to "مدرسة" in a single strip.
  static const List<String> _compoundProclitics = [
    'وبال', 'فبال', 'ولل', 'فلل', 'وكال', 'فكال',  // 4-char: conj + prep + al
    'وال', 'فال', 'بال', 'كال',                     // 3-char
    'لل',                                            // 2-char (ل + ال)
    'ال',                                            // bare definite article
  ];

  // Enclitics — object pronouns, feminine markers, dual/plural verbal suffixes,
  // nisba 'ي', and the teh-marbuta variants.
  // Longest first so a greedy strip picks ـكم over ـك.
  static const List<String> _suffixes = [
    'تموها', 'تموهم',            // 2-mp-past + obj
    'تمون', 'تموه',
    'كموه', 'كموها',
    'تموا', 'نيهم', 'نيها',
    'كما', 'كنّ', 'هما', 'هنّ',
    'هم', 'هن', 'كم', 'كن',
    'نا', 'ني', 'ها', 'وا', 'تن', 'تم',
    'ون', 'ين', 'ان', 'ات',
    'ه', 'ك', 'ي', 'ا', 'ن', 'ة', 'ى',
  ];

  // ── Khoja-style pattern table (T7) ────────────────────────────────────────
  static const List<_PatternDef> _patterns = [
    // 4-letter
    _PatternDef(4, [0, 2, 3], {1: 'ا'}, 'فاعل'),
    _PatternDef(4, [0, 1, 3], {2: 'ا'}, 'فعال'),
    _PatternDef(4, [0, 1, 3], {2: 'ي'}, 'فعيل'),
    _PatternDef(4, [0, 1, 3], {2: 'و'}, 'فعول'),
    _PatternDef(4, [1, 2, 3], {0: 'م'}, 'مفعل'),
    _PatternDef(4, [1, 2, 3], {0: 'ا'}, 'أفعل'),  // alef-normalised
    _PatternDef(4, [1, 2, 3], {0: 'ت'}, 'تفعل'),
    _PatternDef(4, [1, 2, 3], {0: 'ي'}, 'يفعل'),
    _PatternDef(4, [1, 2, 3], {0: 'ن'}, 'نفعل'),
    _PatternDef(4, [0, 1, 2], {3: 'ة'}, 'فعلة'),
    // 5-letter
    _PatternDef(5, [1, 2, 4], {0: 'م', 3: 'و'}, 'مفعول'),
    _PatternDef(5, [1, 3, 4], {0: 'م', 2: 'ا'}, 'مفاعل'),
    _PatternDef(5, [1, 3, 4], {0: 'ت', 2: 'ا'}, 'تفاعل'),
    _PatternDef(5, [1, 3, 4], {0: 'ا', 2: 'ت'}, 'افتعل'),
    _PatternDef(5, [2, 3, 4], {0: 'ا', 1: 'ن'}, 'انفعل'),
    _PatternDef(5, [1, 2, 4], {0: 'ت', 3: 'ي'}, 'تفعيل'),
    _PatternDef(5, [0, 1, 2], {3: 'ا', 4: 'ن'}, 'فعلان'),
    _PatternDef(5, [0, 2, 3], {1: 'ا', 4: 'ة'}, 'فاعلة'),
    _PatternDef(5, [1, 3, 4], {0: 'م', 2: 'ت'}, 'مفتعل'),
    _PatternDef(5, [1, 2, 4], {0: 'م', 3: 'ا'}, 'مفعال'),
    // 6-letter
    _PatternDef(6, [3, 4, 5], {0: 'ا', 1: 'س', 2: 'ت'}, 'استفعل'),
    _PatternDef(6, [3, 4, 5], {0: 'م', 1: 'س', 2: 'ت'}, 'مستفعل'),
    _PatternDef(6, [1, 3, 5], {0: 'ا', 2: 'ت', 4: 'ا'}, 'افتعال'),
    _PatternDef(6, [2, 3, 5], {0: 'ا', 1: 'ن', 4: 'ا'}, 'انفعال'),
    // 7-letter
    _PatternDef(7, [3, 4, 6], {0: 'ا', 1: 'س', 2: 'ت', 5: 'ا'}, 'استفعال'),
  ];

  // ── Tier budget (T6 cross-product cap) ────────────────────────────────────
  static const int _combinedCap = 30;

  // ── Public resolve() ──────────────────────────────────────────────────────

  Future<StemResult> resolve(String input) async {
    final sw = Stopwatch()..start();

    final normalized = normalize(input);
    // Reject anything shorter than two Arabic letters: no tier can produce a
    // meaningful hit from a single character, and one-letter particles in the
    // lexicon (e.g. كَ "like", ل "for") are better handled as sentence glue
    // via the clitic-strip tiers than as standalone search results.
    if (normalized.length < 2 || !_arabicLetter.hasMatch(normalized)) {
      return StemResult.miss;
    }

    // ── T1: direct lexicon ───────────────────────────────────────────────────
    final t1 = await _lookupLexicon(normalized);
    debugPrint('[PERF] tier=T1 direct-lexicon    ${sw.elapsedMicroseconds}µs  '
        '"$normalized" → ${t1 == null ? "miss" : "hit id=${t1['id']}"}');
    if (t1 != null) {
      return StemResult(
        lexiconId: t1['id'] as int,
        matchedForm: t1['form_arabic'] as String?,
        source: StemSource.directLexicon,
      );
    }

    // ── T2: conjugations table ───────────────────────────────────────────────
    final t2Start = sw.elapsedMicroseconds;
    final t2 = await _lookupConjugation(normalized);
    debugPrint('[PERF] tier=T2 conjugation       '
        '${sw.elapsedMicroseconds - t2Start}µs  '
        '"$normalized" → ${t2 == null ? "miss" : "hit base_id=${t2['id']}"}');
    if (t2 != null) {
      return StemResult(
        lexiconId: t2['id'] as int,
        matchedForm: t2['form_arabic'] as String?,
        source: StemSource.conjugationTable,
      );
    }

    // ── T3: strip one single-char proclitic ──────────────────────────────────
    final t3Start = sw.elapsedMicroseconds;
    final t3 = await _tryProclitics(normalized, _singleProclitics);
    debugPrint('[PERF] tier=T3 single-proclitic  '
        '${sw.elapsedMicroseconds - t3Start}µs  '
        '"$normalized" → ${t3?.matchedForm ?? "miss"}');
    if (t3 != null) return t3;

    // ── T4: strip definite article / compound proclitic ──────────────────────
    final t4Start = sw.elapsedMicroseconds;
    final t4 = await _tryProclitics(normalized, _compoundProclitics);
    debugPrint('[PERF] tier=T4 al+compound       '
        '${sw.elapsedMicroseconds - t4Start}µs  '
        '"$normalized" → ${t4?.matchedForm ?? "miss"}');
    if (t4 != null) return t4;

    // ── T5: strip one enclitic ───────────────────────────────────────────────
    final t5Start = sw.elapsedMicroseconds;
    final t5 = await _trySuffixes(normalized, _suffixes);
    debugPrint('[PERF] tier=T5 suffix-strip      '
        '${sw.elapsedMicroseconds - t5Start}µs  '
        '"$normalized" → ${t5?.matchedForm ?? "miss"}');
    if (t5 != null) return t5;

    // ── T6: combined prefix × suffix (capped) ────────────────────────────────
    final t6Start = sw.elapsedMicroseconds;
    final t6 = await _tryCombined(normalized);
    debugPrint('[PERF] tier=T6 combined          '
        '${sw.elapsedMicroseconds - t6Start}µs  '
        '"$normalized" → ${t6?.matchedForm ?? "miss"}');
    if (t6 != null) return t6;

    // ── T7: fuzzy root via Khoja patterns ────────────────────────────────────
    final t7Start = sw.elapsedMicroseconds;
    final t7 = await _tryFuzzyRoot(normalized);
    debugPrint('[PERF] tier=T7 fuzzy-root        '
        '${sw.elapsedMicroseconds - t7Start}µs  '
        '"$normalized" → ${t7?.extractedRoot ?? "miss"}');
    if (t7 != null) return t7;

    debugPrint('[PERF] stemmer miss             total=${sw.elapsedMicroseconds}µs  '
        '"$input" / normalised="$normalized"');
    return StemResult.miss;
  }

  // ── DB helpers ─────────────────────────────────────────────────────────────

  /// Returns `{id, form_arabic}` for the first `lexicon` row whose
  /// `form_stripped` equals [token], or null on a miss.
  ///
  /// Ordering philosophy for a learner's dictionary:
  ///   1. Frequency first — a common noun must beat a rare verb homograph.
  ///     Without this,  بيت → بَيَّتَ (obscure verb) instead of بَيْتٌ (house).
  ///   2. Nouns / adjectives preferred over base_verb as a tie-breaker,
  ///     because dictionary queries skew heavily toward nominal forms.
  ///   3. Anything else falls to the bottom.
  Future<Map<String, Object?>?> _lookupLexicon(String token) async {
    final rows = await _db.rawQuery(
      '''
      SELECT id, form_arabic, word_type, frequency
      FROM lexicon
      WHERE form_stripped = ?
      ORDER BY
        is_common DESC,
        frequency DESC,
        CASE word_type
          WHEN 'noun'      THEN 0
          WHEN 'adjective' THEN 1
          WHEN 'base_verb' THEN 2
          ELSE 3
        END
      LIMIT 1
      ''',
      [token],
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Returns the `{id, form_arabic}` of the base verb whose `conjugations`
  /// table contains [token], or null on a miss.
  ///
  /// When several verbs share a stripped conjugated form (e.g. قُلْتُ "I said"
  /// from قَالَ and قَلَّتْ "she was few" from قَلَّ both strip to قلت), prefer
  /// the base verb with the highest is_common / frequency — NOT the lowest
  /// display_order.  display_order is meaningful only within a single verb's
  /// paradigm, so using it as the primary sort key picks the wrong verb
  /// whenever two paradigms collide on a shared stripped form.
  Future<Map<String, Object?>?> _lookupConjugation(String token) async {
    final rows = await _db.rawQuery(
      '''
      SELECT l.id, l.form_arabic
      FROM conjugations c
      JOIN lexicon l ON l.id = c.base_word_id
      WHERE c.form_stripped = ?
      ORDER BY l.is_common DESC, l.frequency DESC, c.display_order ASC
      LIMIT 1
      ''',
      [token],
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ── Tier 3 / 4: proclitic strip + retry ──────────────────────────────────

  /// For each proclitic in [proclitics] (already in longest-first order),
  /// strip a single instance and re-query T1 then T2.  Returns the first hit.
  Future<StemResult?> _tryProclitics(
      String token, List<String> proclitics) async {
    for (final p in proclitics) {
      if (!token.startsWith(p)) continue;
      final remaining = token.substring(p.length);
      if (remaining.length < 2) continue;

      final lex = await _lookupLexicon(remaining);
      if (lex != null) {
        return StemResult(
          lexiconId: lex['id'] as int,
          matchedForm: lex['form_arabic'] as String?,
          source: StemSource.cliticStrippedLexicon,
          strippedClitics: p,
        );
      }
      final conj = await _lookupConjugation(remaining);
      if (conj != null) {
        return StemResult(
          lexiconId: conj['id'] as int,
          matchedForm: conj['form_arabic'] as String?,
          source: StemSource.cliticStrippedConjugation,
          strippedClitics: p,
        );
      }
    }
    return null;
  }

  // ── Tier 5: suffix strip + retry ──────────────────────────────────────────

  Future<StemResult?> _trySuffixes(
      String token, List<String> suffixes) async {
    for (final s in suffixes) {
      if (!token.endsWith(s)) continue;
      if (token.length - s.length < 2) continue;
      final remaining = token.substring(0, token.length - s.length);

      final lex = await _lookupLexicon(remaining);
      if (lex != null) {
        return StemResult(
          lexiconId: lex['id'] as int,
          matchedForm: lex['form_arabic'] as String?,
          source: StemSource.cliticStrippedLexicon,
          strippedClitics: s,
        );
      }
      final conj = await _lookupConjugation(remaining);
      if (conj != null) {
        return StemResult(
          lexiconId: conj['id'] as int,
          matchedForm: conj['form_arabic'] as String?,
          source: StemSource.cliticStrippedConjugation,
          strippedClitics: s,
        );
      }
    }
    return null;
  }

  // ── Tier 6: combined prefix × suffix, capped ──────────────────────────────

  Future<StemResult?> _tryCombined(String token) async {
    // Build candidate proclitic list from both T3 and T4 sources, longest-first.
    final allProclitics = <String>[
      ..._compoundProclitics,        // longest first (3..2 chars)
      ..._singleProclitics,          // 1 char each
    ];

    var budget = _combinedCap;

    for (final p in allProclitics) {
      if (!token.startsWith(p)) continue;
      for (final s in _suffixes) {
        if (!token.endsWith(s)) continue;
        final innerLen = token.length - p.length - s.length;
        if (innerLen < 2) continue;

        if (budget-- <= 0) return null;

        final remaining = token.substring(p.length, token.length - s.length);

        final lex = await _lookupLexicon(remaining);
        if (lex != null) {
          return StemResult(
            lexiconId: lex['id'] as int,
            matchedForm: lex['form_arabic'] as String?,
            source: StemSource.cliticStrippedLexicon,
            strippedClitics: '$p…$s',
          );
        }
        final conj = await _lookupConjugation(remaining);
        if (conj != null) {
          return StemResult(
            lexiconId: conj['id'] as int,
            matchedForm: conj['form_arabic'] as String?,
            source: StemSource.cliticStrippedConjugation,
            strippedClitics: '$p…$s',
          );
        }
      }
    }
    return null;
  }

  // ── Tier 7: fuzzy root via Khoja patterns ─────────────────────────────────

  Future<StemResult?> _tryFuzzyRoot(String token) async {
    // Length 3: treat as its own root.
    String? root;
    if (token.length == 3) {
      root = token;
    } else {
      for (final p in _patterns) {
        if (p.matches(token)) {
          root = p.extractRoot(token);
          break;
        }
      }
      // Last resort: if token ≥ 3, guess first three letters.  We only use
      // this when no pattern matched; the DB acts as the truth gate.
      root ??= token.length >= 3 ? token.substring(0, 3) : null;
    }
    if (root == null || root.length != 3) return null;

    final dashed = root.split('').join('-');

    // Exact root match first — cheap, indexed.
    final exact = await _db.rawQuery(
      '''
      SELECT id, form_arabic
      FROM lexicon
      WHERE root = ?
      ORDER BY is_common DESC, frequency DESC
      LIMIT 1
      ''',
      [dashed],
    );
    if (exact.isNotEmpty) {
      return StemResult(
        lexiconId: exact.first['id'] as int,
        matchedForm: exact.first['form_arabic'] as String?,
        source: StemSource.fuzzyRoot,
        extractedRoot: root,
      );
    }

    // LIKE fallback for compound-root rows (e.g. 'وهب-;-هيب').
    final like = await _db.rawQuery(
      '''
      SELECT id, form_arabic
      FROM lexicon
      WHERE root LIKE '%' || ? || '%'
      ORDER BY is_common DESC, frequency DESC
      LIMIT 1
      ''',
      [dashed],
    );
    if (like.isNotEmpty) {
      return StemResult(
        lexiconId: like.first['id'] as int,
        matchedForm: like.first['form_arabic'] as String?,
        source: StemSource.fuzzyRoot,
        extractedRoot: root,
      );
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pattern definition (private — used by T7 only)
// ─────────────────────────────────────────────────────────────────────────────

class _PatternDef {
  final int wordLength;
  final List<int> rootPositions;
  final Map<int, String> fixedLetters;
  final String label;

  const _PatternDef(
    this.wordLength,
    this.rootPositions,
    this.fixedLetters,
    this.label,
  );

  bool matches(String word) {
    if (word.length != wordLength) return false;
    for (final entry in fixedLetters.entries) {
      if (word[entry.key] != entry.value) return false;
    }
    return true;
  }

  String extractRoot(String word) =>
      rootPositions.map((i) => word[i]).join();
}
