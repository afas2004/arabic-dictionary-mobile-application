/// Arabic Verb Conjugation Engine
/// =================================
/// Generates full conjugation tables for Arabic triliteral verbs.
///
/// Architecture:
///   1. Detail page opens → fetch verb from lexicon
///   2. Check conjugations table (write-through cache)
///   3. Cache hit  → return stored rows instantly
///   4. Cache miss → generate using triverbtable pattern → store → return
///
/// Usage:
///   final engine = ConjugationEngine(db);
///   final table  = await engine.getConjugations(lexiconId, formStripped, root);
///
/// Files:
///   conjugation_engine.dart   ← this file
///   triverbtable_data.dart    ← auto-generated verb pattern lookup

library conjugation_engine;

import 'package:sqflite/sqflite.dart';

part 'triverbtable_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

class ConjugationRow {
  final int     baseWordId;
  final String  formArabic;
  final String  tense;
  final String? pronoun;
  final String  number;
  final String? gender;
  final String  voice;
  final String  mood;
  final int     displayOrder;

  const ConjugationRow({
    required this.baseWordId,
    required this.formArabic,
    required this.tense,
    this.pronoun,
    required this.number,
    this.gender,
    required this.voice,
    required this.mood,
    required this.displayOrder,
  });

  Map<String, dynamic> toMap() => {
    'base_word_id':  baseWordId,
    'form_arabic':   formArabic,
    'tense':         tense,
    'pronoun':       pronoun,
    'number':        number,
    'gender':        gender,
    'voice':         voice,
    'mood':          mood,
    'display_order': displayOrder,
  };

  factory ConjugationRow.fromMap(Map<String, dynamic> m) => ConjugationRow(
    baseWordId:  m['base_word_id'] as int,
    formArabic:  m['form_arabic'] as String,
    tense:       m['tense'] as String,
    pronoun:     m['pronoun'] as String?,
    number:      m['number'] as String,
    gender:      m['gender'] as String?,
    voice:       m['voice'] as String,
    mood:        m['mood'] as String,
    displayOrder: m['display_order'] as int,
  );
}

class ConjugationTable {
  final List<ConjugationRow> past;
  final List<ConjugationRow> present;
  final List<ConjugationRow> imperative;
  final bool fromCache;

  const ConjugationTable({
    required this.past,
    required this.present,
    required this.imperative,
    required this.fromCache,
  });

  List<ConjugationRow> get all => [...past, ...present, ...imperative];
}

// ─────────────────────────────────────────────────────────────────────────────
// DIACRITICS
// ─────────────────────────────────────────────────────────────────────────────

const String _damma  = '\u064F'; // ُ
const String _kasra  = '\u0650'; // ِ
const String _fatha  = '\u064E'; // َ
const String _sukun  = '\u0652'; // ْ
const String _shadda = '\u0651'; // ّ

String _presentVowel(VerbPattern pattern) {
  switch (pattern.haraka) {
    case Haraka.damma:  return _damma;
    case Haraka.kasra:  return _kasra;
    case Haraka.fatha:  return _fatha;
  }
}

String _pastVowel(VerbPattern pattern) {
  switch (pattern.bab) {
    case 4:
    case 6:
      return _kasra;
    case 5:
      return _damma;
    case 1:
    case 2:
    case 3:
    default:
      return _fatha;
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// SUFFIX TABLES
// ─────────────────────────────────────────────────────────────────────────────

// (person, number, gender, suffix, displayOrder)
const List<_SuffixEntry> _pastSuffixes = [
  _SuffixEntry('3rd', 'singular', 'masculine', '\u064E',          1),
  _SuffixEntry('3rd', 'singular', 'feminine',  '\u064E\u062A\u0652', 2),
  _SuffixEntry('3rd', 'dual',     'masculine', '\u064E\u0627',     3),
  _SuffixEntry('3rd', 'dual',     'feminine',  '\u064E\u062A\u064E\u0627', 4),
  _SuffixEntry('3rd', 'plural',   'masculine', '\u064F\u0648\u0627', 5),
  _SuffixEntry('3rd', 'plural',   'feminine',  '\u0652\u0646\u064E', 6),
  _SuffixEntry('2nd', 'singular', 'masculine', '\u0652\u062A\u064E', 7),
  _SuffixEntry('2nd', 'singular', 'feminine',  '\u0652\u062A\u0650', 8),
  _SuffixEntry('2nd', 'dual',     'common',    '\u0652\u062A\u064F\u0645\u064E\u0627', 9),
  _SuffixEntry('2nd', 'plural',   'masculine', '\u0652\u062A\u064F\u0645\u0652', 10),
  _SuffixEntry('2nd', 'plural',   'feminine',  '\u0652\u062A\u064F\u0646\u0651\u064E', 11),
  _SuffixEntry('1st', 'singular', 'common',    '\u0652\u062A\u064F',  12),
  _SuffixEntry('1st', 'plural',   'common',    '\u0652\u0646\u064E\u0627', 13),
];

// (person, number, gender, prefix, suffix, displayOrder)
const List<_AffixEntry> _presentAffixes = [
  _AffixEntry('3rd', 'singular', 'masculine', '\u064A\u064E', '\u064F',          1),
  _AffixEntry('3rd', 'singular', 'feminine',  '\u062A\u064E', '\u064F',          2),
  _AffixEntry('3rd', 'dual',     'masculine', '\u064A\u064E', '\u064E\u0627\u0646\u0650', 3),
  _AffixEntry('3rd', 'dual',     'feminine',  '\u062A\u064E', '\u064E\u0627\u0646\u0650', 4),
  _AffixEntry('3rd', 'plural',   'masculine', '\u064A\u064E', '\u064F\u0648\u0646\u064E', 5),
  _AffixEntry('3rd', 'plural',   'feminine',  '\u064A\u064E', '\u0652\u0646\u064E',       6),
  _AffixEntry('2nd', 'singular', 'masculine', '\u062A\u064E', '\u064F',          7),
  _AffixEntry('2nd', 'singular', 'feminine',  '\u062A\u064E', '\u0650\u064A\u0646\u064E', 8),
  _AffixEntry('2nd', 'dual',     'common',    '\u062A\u064E', '\u064E\u0627\u0646\u0650', 9),
  _AffixEntry('2nd', 'plural',   'masculine', '\u062A\u064E', '\u064F\u0648\u0646\u064E', 10),
  _AffixEntry('2nd', 'plural',   'feminine',  '\u062A\u064E', '\u0652\u0646\u064E',       11),
  _AffixEntry('1st', 'singular', 'common',    '\u0623\u064E', '\u064F',          12),
  _AffixEntry('1st', 'plural',   'common',    '\u0646\u064E', '\u064F',          13),
];

// (number, gender, suffix, displayOrder)
const List<_ImperativeEntry> _imperativeForms = [
  _ImperativeEntry('singular', 'masculine', '\u0652',          1),
  _ImperativeEntry('singular', 'feminine',  '\u0650\u064A',    2),
  _ImperativeEntry('dual',     'common',    '\u064E\u0627',    3),
  _ImperativeEntry('plural',   'masculine', '\u064F\u0648\u0627', 4),
  _ImperativeEntry('plural',   'feminine',  '\u0652\u0646\u064E', 5),
];

// ─────────────────────────────────────────────────────────────────────────────
// INTERNAL DATA CLASSES
// ─────────────────────────────────────────────────────────────────────────────

class _SuffixEntry {
  final String person, number, gender, suffix;
  final int displayOrder;
  const _SuffixEntry(this.person, this.number, this.gender, this.suffix, this.displayOrder);
}

class _AffixEntry {
  final String person, number, gender, prefix, suffix;
  final int displayOrder;
  const _AffixEntry(this.person, this.number, this.gender, this.prefix, this.suffix, this.displayOrder);
}

class _ImperativeEntry {
  final String number, gender, suffix;
  final int displayOrder;
  const _ImperativeEntry(this.number, this.gender, this.suffix, this.displayOrder);
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOT HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/// Extract radicals from formatted root like ك-ت-ب
List<String> _extractRadicals(String root) {
  final stripped = root.replaceAll(RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670]'), '');
  return stripped.split('-').where((p) => p.isNotEmpty).toList();
}

/// Strip diacritics from Arabic text
String _stripDiacritics(String text) {
  return text.replaceAll(RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED]'), '');
}

// ─────────────────────────────────────────────────────────────────────────────
// STEM BUILDERS
// ─────────────────────────────────────────────────────────────────────────────

String? _buildPastStem(List<String> radicals, String pastVowel) {
  if (radicals.length < 3) return null;
  final f   = radicals[0];
  final ain = radicals[1];
  final lam = radicals[2];
  // Use pastVowel for middle radical instead of hardcoded fatha
  return '$f${_fatha}$ain${pastVowel}$lam';
}

/// Build present tense stem: فْعَلُ pattern (first radical gets sukun)
String? _buildPresentStem(List<String> radicals, String presentVowel) {
  if (radicals.length < 3) return null;
  final f   = radicals[0];
  final ain = radicals[1];
  final lam = radicals[2];
  return '$f${_sukun}$ain${presentVowel}$lam';
}

// ─────────────────────────────────────────────────────────────────────────────
// CONJUGATION GENERATOR
// ─────────────────────────────────────────────────────────────────────────────

List<ConjugationRow> _generateConjugations(
  int verbId,
  String root,
  VerbPattern pattern,
) {
  final radicals     = _extractRadicals(root);
  final presentVowel = _presentVowel(pattern);
  final pastVowel    = _pastVowel(pattern);           // ← NEW
  final pastStem     = _buildPastStem(radicals, pastVowel);  // ← UPDATED
  final presentStem  = _buildPresentStem(radicals, presentVowel);

  if (pastStem == null || presentStem == null) return [];

  final rows = <ConjugationRow>[];

  // ── Past tense ──
  for (final s in _pastSuffixes) {
    final stem = pastStem.endsWith(_fatha)
        ? pastStem.substring(0, pastStem.length - 1)
        : pastStem;
    rows.add(ConjugationRow(
      baseWordId:  verbId,
      formArabic:  '$stem${s.suffix}',
      tense:       'past',
      pronoun:     s.person,
      number:      s.number,
      gender:      s.gender,
      voice:       'active',
      mood:        'indicative',
      displayOrder: s.displayOrder,
    ));
  }

  // ── Present tense ──
  for (final a in _presentAffixes) {
    rows.add(ConjugationRow(
      baseWordId:  verbId,
      formArabic:  '${a.prefix}$presentStem${a.suffix}',
      tense:       'present',
      pronoun:     a.person,
      number:      a.number,
      gender:      a.gender,
      voice:       'active',
      mood:        'indicative',
      displayOrder: a.displayOrder + 13,
    ));
  }

  // ── Imperative ──
  final impVowel  = pattern.haraka == Haraka.damma ? _damma : _kasra;
  final impPrefix = '\u0627$impVowel';

  for (final imp in _imperativeForms) {
    rows.add(ConjugationRow(
      baseWordId:  verbId,
      formArabic:  '$impPrefix$presentStem${imp.suffix}',
      tense:       'imperative',
      pronoun:     '2nd',
      number:      imp.number,
      gender:      imp.gender,
      voice:       'active',
      mood:        'imperative',
      displayOrder: imp.displayOrder + 26,
    ));
  }

  return rows;
}

// ─────────────────────────────────────────────────────────────────────────────
// CONJUGATION ENGINE — PUBLIC API
// ─────────────────────────────────────────────────────────────────────────────

class ConjugationEngine {
  final Database _db;

  ConjugationEngine(this._db);

  /// Get conjugation table for a verb.
  /// Checks write-through cache first, generates and stores if not found.
  ///
  /// [lexiconId]   — lexicon.id of the base verb
  /// [formStripped] — unvocalized form (e.g. "كتب") for pattern lookup
  /// [root]        — formatted root (e.g. "ك-ت-ب") for stem building
  Future<ConjugationTable> getConjugations({
    required int    lexiconId,
    required String formStripped,
    required String root,
  }) async {
    // ── 1. Check cache ──
    final cached = await _db.query(
      'conjugations',
      where: 'base_word_id = ?',
      whereArgs: [lexiconId],
      orderBy: 'display_order ASC',
    );

    if (cached.isNotEmpty) {
      return _buildTable(
        cached.map(ConjugationRow.fromMap).toList(),
        fromCache: true,
      );
    }

    // ── 2. Look up verb pattern ──
    final pattern = kVerbPatterns[formStripped] ??
        kVerbPatterns[_stripDiacritics(formStripped)] ??
        VerbPattern(1, Haraka.damma); // default fallback

    // ── 3. Generate ──
    final rows = _generateConjugations(lexiconId, root, pattern);

    if (rows.isEmpty) {
      return const ConjugationTable(
        past: [], present: [], imperative: [], fromCache: false,
      );
    }

    // ── 4. Store in cache (write-through) ──
    final batch = _db.batch();
    for (final row in rows) {
      batch.insert('conjugations', row.toMap());
    }
    await batch.commit(noResult: true);

    return _buildTable(rows, fromCache: false);
  }

  /// Clear cached conjugations for a specific verb (useful for testing)
  Future<void> clearCache(int lexiconId) async {
    await _db.delete(
      'conjugations',
      where: 'base_word_id = ?',
      whereArgs: [lexiconId],
    );
  }

  /// Clear all cached conjugations
  Future<void> clearAllCache() async {
    await _db.delete('conjugations');
  }

  /// Split flat list into tense groups
  ConjugationTable _buildTable(List<ConjugationRow> rows, {required bool fromCache}) {
    return ConjugationTable(
      past:       rows.where((r) => r.tense == 'past').toList(),
      present:    rows.where((r) => r.tense == 'present').toList(),
      imperative: rows.where((r) => r.tense == 'imperative').toList(),
      fromCache:  fromCache,
    );
  }
}
