/// Arabic Verb Conjugation Engine
/// =================================
/// Generates full conjugation tables for Arabic verbs.
///
/// Supports:
///   - Form I  (strong, hollow R2=و/ي, defective R3=ي/و)
///   - Forms III, IV, V, VIII, X  (strong, hollow, defective)
///   - Form III / V with hollow R2: treated as strong (و is just a consonant)
///
/// Architecture:
///   1. Detail page opens → fetch verb from lexicon
///   2. Check conjugations table (write-through cache)
///   3. Cache hit  → return stored rows instantly
///   4. Cache miss → detect form → generate → store → return
///
/// Cache versioning:
///   Uses SQLite PRAGMA user_version.  Increment _engineVersion whenever
///   the conjugation logic changes to force a cache wipe on next open.
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
    // gender is not a column in v9 conjugations schema — kept in-memory only
    'voice':         voice,
    'mood':          mood,
    'display_order': displayOrder,
  };

  factory ConjugationRow.fromMap(Map<String, dynamic> m) {
    final displayOrder = m['display_order'] as int? ?? 0;
    return ConjugationRow(
      baseWordId:   m['base_word_id'] as int,
      formArabic:   m['form_arabic'] as String,
      tense:        m['tense'] as String,
      pronoun:      m['pronoun'] as String?,
      number:       m['number'] as String,
      gender:       m['gender'] as String? ?? _genderFromDisplayOrder(displayOrder),
      voice:        m['voice'] as String,
      mood:         m['mood'] as String,
      displayOrder: displayOrder,
    );
  }

  static String? _genderFromDisplayOrder(int d) {
    const pattern = [
      '',           // 0 unused
      'masculine',  // 1  — 3rd singular
      'feminine',   // 2  — 3rd singular
      'masculine',  // 3  — 3rd dual
      'feminine',   // 4  — 3rd dual
      'masculine',  // 5  — 3rd plural
      'feminine',   // 6  — 3rd plural
      'masculine',  // 7  — 2nd singular
      'feminine',   // 8  — 2nd singular
      'common',     // 9  — 2nd dual
      'masculine',  // 10 — 2nd plural
      'feminine',   // 11 — 2nd plural
      'common',     // 12 — 1st singular
      'common',     // 13 — 1st plural
    ];
    if (d >= 1 && d <= 13)  return pattern[d];
    if (d >= 14 && d <= 26) return pattern[d - 13];
    const impGender = ['masculine', 'feminine', 'common', 'masculine', 'feminine'];
    final i = d - 27;
    if (i >= 0 && i < impGender.length) return impGender[i];
    return null;
  }
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
// DIACRITICS & FIXED LETTER CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const String _damma  = '\u064F'; // ُ
const String _kasra  = '\u0650'; // ِ
const String _fatha  = '\u064E'; // َ
const String _sukun  = '\u0652'; // ْ
const String _shadda = '\u0651'; // ّ
const String _alef   = '\u0627'; // ا  (alef-wasla / plain alef)
const String _alefH  = '\u0623'; // أ  (alef + hamza above)
const String _waw    = '\u0648'; // و
const String _ya     = '\u064A'; // ي
const String _ta     = '\u062A'; // ت
const String _sin    = '\u0633'; // س
const String _alefMaqsura = '\u0649'; // ى

// ─────────────────────────────────────────────────────────────────────────────
// FORM DETECTION
// ─────────────────────────────────────────────────────────────────────────────

enum _ArabicForm { formI, formIII, formIV, formV, formVIII, formX, other }

_ArabicForm _detectArabicForm(String stripped) {
  final len = stripped.length;
  if (len <= 3) return _ArabicForm.formI;

  if (len == 4) {
    final c0 = stripped.codeUnitAt(0);
    final c1 = stripped.codeUnitAt(1);
    if (c0 == 0x0623 || c0 == 0x0625) return _ArabicForm.formIV; // أ or إ
    if (c1 == 0x0627)                  return _ArabicForm.formIII; // ا as 2nd char
    if (c0 == 0x062A)                  return _ArabicForm.formV;   // ت as 1st char
    if (c0 == 0x0627)                  return _ArabicForm.other;   // Form IX — skip
  }

  if (len == 5) {
    final c0 = stripped.codeUnitAt(0);
    final c2 = stripped.codeUnitAt(2);
    if (c0 == 0x0627 && c2 == 0x062A) return _ArabicForm.formVIII;
  }

  if (len == 6) {
    if (stripped.codeUnitAt(0) == 0x0627 &&
        stripped.codeUnitAt(1) == 0x0633 &&
        stripped.codeUnitAt(2) == 0x062A) return _ArabicForm.formX;
  }

  return _ArabicForm.other;
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOT WEAKNESS HELPERS
// ─────────────────────────────────────────────────────────────────────────────

const _weakLetters = {'\u0648', '\u064A'}; // و ي

bool _isStrongRoot(List<String> r) =>
    r.length >= 3 && !r.take(3).any(_weakLetters.contains);

bool _isHollowRoot(List<String> r) =>
    r.length >= 3 && _weakLetters.contains(r[1]);

bool _isDefectiveRoot(List<String> r) =>
    r.length >= 3 && _weakLetters.contains(r[2]);

// ─────────────────────────────────────────────────────────────────────────────
// SUFFIX / AFFIX TABLES
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

// ── Strong past suffixes ─────────────────────────────────────────────────────
const List<_SuffixEntry> _pastSuffixes = [
  _SuffixEntry('3rd', 'singular', 'masculine', '\u064E',                    1),
  _SuffixEntry('3rd', 'singular', 'feminine',  '\u064E\u062A\u0652',        2),
  _SuffixEntry('3rd', 'dual',     'masculine', '\u064E\u0627',               3),
  _SuffixEntry('3rd', 'dual',     'feminine',  '\u064E\u062A\u064E\u0627',  4),
  _SuffixEntry('3rd', 'plural',   'masculine', '\u064F\u0648\u0627',         5),
  _SuffixEntry('3rd', 'plural',   'feminine',  '\u0652\u0646\u064E',         6),
  _SuffixEntry('2nd', 'singular', 'masculine', '\u0652\u062A\u064E',         7),
  _SuffixEntry('2nd', 'singular', 'feminine',  '\u0652\u062A\u0650',         8),
  _SuffixEntry('2nd', 'dual',     'common',    '\u0652\u062A\u064F\u0645\u064E\u0627', 9),
  _SuffixEntry('2nd', 'plural',   'masculine', '\u0652\u062A\u064F\u0645\u0652',      10),
  _SuffixEntry('2nd', 'plural',   'feminine',  '\u0652\u062A\u064F\u0646\u0651\u064E',11),
  _SuffixEntry('1st', 'singular', 'common',    '\u0652\u062A\u064F',         12),
  _SuffixEntry('1st', 'plural',   'common',    '\u0652\u0646\u064E\u0627',   13),
];

// ── Defective past suffixes (R3=ي/و) ────────────────────────────────────────
// Base ends just before R3: append these directly (no fatha stripping needed).
const List<_SuffixEntry> _defPastSuffixes = [
  _SuffixEntry('3rd', 'singular', 'masculine', '\u0649',                              1), // ى
  _SuffixEntry('3rd', 'singular', 'feminine',  '\u062A\u0652',                        2), // تْ
  _SuffixEntry('3rd', 'dual',     'masculine', '\u064A\u064E\u0627',                  3), // يَا
  _SuffixEntry('3rd', 'dual',     'feminine',  '\u062A\u064E\u0627',                  4), // تَا
  _SuffixEntry('3rd', 'plural',   'masculine', '\u0648\u0652\u0627',                  5), // وْا
  _SuffixEntry('3rd', 'plural',   'feminine',  '\u064A\u0652\u0646\u064E',            6), // يْنَ
  _SuffixEntry('2nd', 'singular', 'masculine', '\u064A\u0652\u062A\u064E',            7), // يْتَ
  _SuffixEntry('2nd', 'singular', 'feminine',  '\u064A\u0652\u062A\u0650',            8), // يْتِ
  _SuffixEntry('2nd', 'dual',     'common',    '\u064A\u0652\u062A\u064F\u0645\u064E\u0627', 9), // يْتُمَا
  _SuffixEntry('2nd', 'plural',   'masculine', '\u064A\u0652\u062A\u064F\u0645\u0652',      10), // يْتُمْ
  _SuffixEntry('2nd', 'plural',   'feminine',  '\u064A\u0652\u062A\u064F\u0646\u0651\u064E',11), // يْتُنَّ
  _SuffixEntry('1st', 'singular', 'common',    '\u064A\u0652\u062A\u064F',            12), // يْتُ
  _SuffixEntry('1st', 'plural',   'common',    '\u064A\u0652\u0646\u064E\u0627',      13), // يْنَا
];

// ── Present affixes — fatha prefix (يَ/تَ/نَ/أَ) ─────────────────────────────
const List<_AffixEntry> _presentAffixes = [
  _AffixEntry('3rd', 'singular', 'masculine', '\u064A\u064E', '\u064F',                    1),
  _AffixEntry('3rd', 'singular', 'feminine',  '\u062A\u064E', '\u064F',                    2),
  _AffixEntry('3rd', 'dual',     'masculine', '\u064A\u064E', '\u064E\u0627\u0646\u0650',  3),
  _AffixEntry('3rd', 'dual',     'feminine',  '\u062A\u064E', '\u064E\u0627\u0646\u0650',  4),
  _AffixEntry('3rd', 'plural',   'masculine', '\u064A\u064E', '\u064F\u0648\u0646\u064E',  5),
  _AffixEntry('3rd', 'plural',   'feminine',  '\u064A\u064E', '\u0652\u0646\u064E',        6),
  _AffixEntry('2nd', 'singular', 'masculine', '\u062A\u064E', '\u064F',                    7),
  _AffixEntry('2nd', 'singular', 'feminine',  '\u062A\u064E', '\u0650\u064A\u0646\u064E',  8),
  _AffixEntry('2nd', 'dual',     'common',    '\u062A\u064E', '\u064E\u0627\u0646\u0650',  9),
  _AffixEntry('2nd', 'plural',   'masculine', '\u062A\u064E', '\u064F\u0648\u0646\u064E',  10),
  _AffixEntry('2nd', 'plural',   'feminine',  '\u062A\u064E', '\u0652\u0646\u064E',        11),
  _AffixEntry('1st', 'singular', 'common',    '\u0623\u064E', '\u064F',                    12),
  _AffixEntry('1st', 'plural',   'common',    '\u0646\u064E', '\u064F',                    13),
];

// ── Present affixes — damma prefix (يُ/تُ/نُ/أُ) — Forms III and IV ──────────
const List<_AffixEntry> _presentAffixesDamma = [
  _AffixEntry('3rd', 'singular', 'masculine', '\u064A\u064F', '\u064F',                    1),
  _AffixEntry('3rd', 'singular', 'feminine',  '\u062A\u064F', '\u064F',                    2),
  _AffixEntry('3rd', 'dual',     'masculine', '\u064A\u064F', '\u064E\u0627\u0646\u0650',  3),
  _AffixEntry('3rd', 'dual',     'feminine',  '\u062A\u064F', '\u064E\u0627\u0646\u0650',  4),
  _AffixEntry('3rd', 'plural',   'masculine', '\u064A\u064F', '\u064F\u0648\u0646\u064E',  5),
  _AffixEntry('3rd', 'plural',   'feminine',  '\u064A\u064F', '\u0652\u0646\u064E',        6),
  _AffixEntry('2nd', 'singular', 'masculine', '\u062A\u064F', '\u064F',                    7),
  _AffixEntry('2nd', 'singular', 'feminine',  '\u062A\u064F', '\u0650\u064A\u0646\u064E',  8),
  _AffixEntry('2nd', 'dual',     'common',    '\u062A\u064F', '\u064E\u0627\u0646\u0650',  9),
  _AffixEntry('2nd', 'plural',   'masculine', '\u062A\u064F', '\u064F\u0648\u0646\u064E',  10),
  _AffixEntry('2nd', 'plural',   'feminine',  '\u062A\u064F', '\u0652\u0646\u064E',        11),
  _AffixEntry('1st', 'singular', 'common',    '\u0623\u064F', '\u064F',                    12),
  _AffixEntry('1st', 'plural',   'common',    '\u0646\u064F', '\u064F',                    13),
];

// ── Imperative suffixes ───────────────────────────────────────────────────────
const List<_ImperativeEntry> _imperativeForms = [
  _ImperativeEntry('singular', 'masculine', '\u0652',                    1),
  _ImperativeEntry('singular', 'feminine',  '\u0650\u064A',              2),
  _ImperativeEntry('dual',     'common',    '\u064E\u0627',              3),
  _ImperativeEntry('plural',   'masculine', '\u064F\u0648\u0627',        4),
  _ImperativeEntry('plural',   'feminine',  '\u0652\u0646\u064E',        5),
];

// ─────────────────────────────────────────────────────────────────────────────
// ROOT HELPERS
// ─────────────────────────────────────────────────────────────────────────────

List<String> _extractRadicals(String root) {
  final stripped = root.replaceAll(RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670]'), '');
  return stripped.split('-').where((p) => p.isNotEmpty).toList();
}

String _stripDiacritics(String text) =>
    text.replaceAll(RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED]'), '');

// ─────────────────────────────────────────────────────────────────────────────
// FORM I  — STRONG STEMS
// ─────────────────────────────────────────────────────────────────────────────

String _presentVowel(VerbPattern pattern) {
  switch (pattern.haraka) {
    case Haraka.damma: return _damma;
    case Haraka.kasra: return _kasra;
    case Haraka.fatha: return _fatha;
  }
}

String _pastVowel(VerbPattern pattern) {
  switch (pattern.bab) {
    case 4: case 6: return _kasra;
    case 5:         return _damma;
    default:        return _fatha;
  }
}

String? _buildPastStem(List<String> radicals, String pastVowel) {
  if (radicals.length < 3) return null;
  return '${radicals[0]}$_fatha${radicals[1]}$pastVowel${radicals[2]}';
}

String? _buildPresentStem(List<String> radicals, String presentVowel) {
  if (radicals.length < 3) return null;
  return '${radicals[0]}$_sukun${radicals[1]}$presentVowel${radicals[2]}';
}

// ─────────────────────────────────────────────────────────────────────────────
// FORM I  — GENERATOR (strong)
// ─────────────────────────────────────────────────────────────────────────────

List<ConjugationRow> _generateConjugations(
  int verbId,
  String root,
  VerbPattern pattern,
) {
  final radicals    = _extractRadicals(root);
  final pastVowel   = _pastVowel(pattern);
  final presentVowel= _presentVowel(pattern);
  final pastStem    = _buildPastStem(radicals, pastVowel);
  final presentStem = _buildPresentStem(radicals, presentVowel);
  if (pastStem == null || presentStem == null) return [];

  final rows = <ConjugationRow>[];

  // Past
  for (final s in _pastSuffixes) {
    final base = pastStem.endsWith(_fatha)
        ? pastStem.substring(0, pastStem.length - 1)
        : pastStem;
    rows.add(ConjugationRow(
      baseWordId: verbId, formArabic: '$base${s.suffix}',
      tense: 'past', pronoun: s.person, number: s.number, gender: s.gender,
      voice: 'active', mood: 'indicative', displayOrder: s.displayOrder,
    ));
  }

  // Present
  for (final a in _presentAffixes) {
    rows.add(ConjugationRow(
      baseWordId: verbId, formArabic: '${a.prefix}$presentStem${a.suffix}',
      tense: 'present', pronoun: a.person, number: a.number, gender: a.gender,
      voice: 'active', mood: 'indicative', displayOrder: a.displayOrder + 13,
    ));
  }

  // Imperative — hamzat al-wasl (ا) carries no harakah in written Arabic
  final impPrefix = _alef;
  for (final imp in _imperativeForms) {
    rows.add(ConjugationRow(
      baseWordId: verbId, formArabic: '$impPrefix$presentStem${imp.suffix}',
      tense: 'imperative', pronoun: '2nd', number: imp.number, gender: imp.gender,
      voice: 'active', mood: 'imperative', displayOrder: imp.displayOrder + 26,
    ));
  }
  return rows;
}

// ─────────────────────────────────────────────────────────────────────────────
// DERIVED FORMS  — STRONG
// ─────────────────────────────────────────────────────────────────────────────

List<ConjugationRow> _generateDerivedConjugations(
  int verbId,
  String root,
  _ArabicForm form,
) {
  final radicals = _extractRadicals(root);
  if (radicals.length < 3) return [];

  final r1 = radicals[0];
  final r2 = radicals[1];
  final r3 = radicals[2];

  String pastBase;
  String presentStem;
  List<_AffixEntry> presAffixes;
  String impPrefix;

  switch (form) {
    case _ArabicForm.formIII:
      // فَاعَلَ  e.g. طَالَبَ
      pastBase     = '$r1${_fatha}$_alef$r2${_fatha}$r3${_fatha}';
      presentStem  = '$r1${_fatha}$_alef$r2${_kasra}$r3';
      presAffixes  = _presentAffixesDamma;
      impPrefix    = '';
      break;

    case _ArabicForm.formIV:
      // أَفْعَلَ  e.g. أَمْكَنَ
      pastBase     = '$_alefH${_fatha}$r1${_sukun}$r2${_fatha}$r3${_fatha}';
      presentStem  = '$r1${_sukun}$r2${_kasra}$r3';
      presAffixes  = _presentAffixesDamma;
      impPrefix    = '$_alefH${_fatha}';
      break;

    case _ArabicForm.formV:
      // تَفَعَّلَ  e.g. تَحَدَّثَ
      pastBase     = '$_ta${_fatha}$r1${_fatha}$r2${_shadda}${_fatha}$r3${_fatha}';
      presentStem  = '$_ta${_fatha}$r1${_fatha}$r2${_shadda}${_fatha}$r3';
      presAffixes  = _presentAffixes;
      impPrefix    = '';
      break;

    case _ArabicForm.formVIII:
      // اِفْتَعَلَ  e.g. اِعْتَبَرَ
      pastBase     = '$_alef${_kasra}$r1${_sukun}$_ta${_fatha}$r2${_fatha}$r3${_fatha}';
      presentStem  = '$r1${_sukun}$_ta${_fatha}$r2${_kasra}$r3';
      presAffixes  = _presentAffixes;
      impPrefix    = _alef; // hamzat al-wasl — no harakah
      break;

    case _ArabicForm.formX:
      // اِسْتَفْعَلَ  e.g. اِسْتَخْدَمَ
      pastBase     = '$_alef${_kasra}$_sin${_sukun}$_ta${_fatha}$r1${_sukun}$r2${_fatha}$r3${_fatha}';
      presentStem  = '$_sin${_sukun}$_ta${_fatha}$r1${_sukun}$r2${_kasra}$r3';
      presAffixes  = _presentAffixes;
      impPrefix    = _alef; // hamzat al-wasl — no harakah
      break;

    default:
      return [];
  }

  return _buildRowsFromStems(
    verbId:      verbId,
    pastBase:    pastBase,
    presentStem: presentStem,
    presAffixes: presAffixes,
    impPrefix:   impPrefix,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// DEFECTIVE FORMS  (R3 = ي or و)
// ─────────────────────────────────────────────────────────────────────────────

List<ConjugationRow> _generateDefectiveConjugations(
  int verbId,
  String root,
  _ArabicForm form,
) {
  final radicals = _extractRadicals(root);
  if (radicals.length < 3) return [];

  final r1 = radicals[0];
  final r2 = radicals[1];

  // Build past base (everything up to and including fatha on R2, before R3)
  // and present bases (kasra-context and fatha-context).
  String pastBase;
  String presBaseKasra;   // Forms I, III, IV, VIII, X  — R3 preceded by kasra
  String presBaseFatha;   // Form V                     — R3 preceded by fatha
  List<_AffixEntry> presAffixesBase; // which prefix-vowel set to use
  String impPrefix;
  bool isFathaContext; // true for Form V (and Form I bab with fatha present vowel)

  switch (form) {
    case _ArabicForm.formI:
      // Past base: R1+fatha+R2+fatha  (e.g. نَسِ for نَسِيَ, or مَشَ for مَشَى)
      // The past vowel on R2 can be fatha or kasra per bab — default fatha here.
      // We detect kasra-on-R2 case from root context but for defective Form I
      // the pattern lookup sets the vowel; we simplify to fatha for R2.
      pastBase       = '$r1${_fatha}$r2${_fatha}';
      presBaseKasra  = '$r1${_sukun}$r2${_kasra}';
      presBaseFatha  = '$r1${_sukun}$r2${_fatha}';
      presAffixesBase= _presentAffixes;
      impPrefix      = _alef; // hamzat al-wasl — no harakah
      isFathaContext = false;
      break;

    case _ArabicForm.formIII:
      pastBase       = '$r1${_fatha}$_alef$r2${_fatha}';
      presBaseKasra  = '$r1${_fatha}$_alef$r2${_kasra}';
      presBaseFatha  = presBaseKasra; // Form III always kasra context
      presAffixesBase= _presentAffixesDamma;
      impPrefix      = '';
      isFathaContext = false;
      break;

    case _ArabicForm.formIV:
      pastBase       = '$_alefH${_fatha}$r1${_sukun}$r2${_fatha}';
      presBaseKasra  = '$r1${_sukun}$r2${_kasra}';
      presBaseFatha  = presBaseKasra;
      presAffixesBase= _presentAffixesDamma;
      impPrefix      = '$_alefH${_fatha}';
      isFathaContext = false;
      break;

    case _ArabicForm.formV:
      pastBase       = '$_ta${_fatha}$r1${_fatha}$r2${_shadda}${_fatha}';
      presBaseKasra  = '$_ta${_fatha}$r1${_fatha}$r2${_shadda}${_fatha}'; // unused
      presBaseFatha  = '$_ta${_fatha}$r1${_fatha}$r2${_shadda}${_fatha}';
      presAffixesBase= _presentAffixes;
      impPrefix      = '';
      isFathaContext = true;
      break;

    case _ArabicForm.formVIII:
      pastBase       = '$_alef${_kasra}$r1${_sukun}$_ta${_fatha}$r2${_fatha}';
      presBaseKasra  = '$r1${_sukun}$_ta${_fatha}$r2${_kasra}';
      presBaseFatha  = presBaseKasra;
      presAffixesBase= _presentAffixes;
      impPrefix      = _alef; // hamzat al-wasl — no harakah
      isFathaContext = false;
      break;

    case _ArabicForm.formX:
      pastBase       = '$_alef${_kasra}$_sin${_sukun}$_ta${_fatha}$r1${_sukun}$r2${_fatha}';
      presBaseKasra  = '$_sin${_sukun}$_ta${_fatha}$r1${_sukun}$r2${_kasra}';
      presBaseFatha  = presBaseKasra;
      presAffixesBase= _presentAffixes;
      impPrefix      = _alef; // hamzat al-wasl — no harakah
      isFathaContext = false;
      break;

    default:
      return [];
  }

  final rows = <ConjugationRow>[];

  // ── Past (defective suffix table) ─────────────────────────────────────────
  for (final s in _defPastSuffixes) {
    rows.add(ConjugationRow(
      baseWordId: verbId, formArabic: '$pastBase${s.suffix}',
      tense: 'past', pronoun: s.person, number: s.number, gender: s.gender,
      voice: 'active', mood: 'indicative', displayOrder: s.displayOrder,
    ));
  }

  // ── Present ───────────────────────────────────────────────────────────────
  // Uses (person, number, gender) from presAffixesBase for the prefix,
  // but applies defective endings rather than the normal suffix.
  if (isFathaContext) {
    // Form V and Form I with fatha present vowel: R3 = ى / وْنَ / يْنَ pattern
    final prefixMap = {for (final a in presAffixesBase) '${a.person}|${a.number}|${a.gender}': a.prefix};
    for (final a in presAffixesBase) {
      final prefix = a.prefix;
      String suffix;
      if ((a.person == '3rd' || a.person == '2nd' || a.person == '1st') &&
          (a.number == 'plural') && a.gender == 'masculine') {
        suffix = '${_waw}${_sukun}${_nun}${_fatha}'; // وْنَ — 3/2 m.pl
      } else if (a.number == 'plural' && a.gender == 'feminine') {
        suffix = '${_ya}${_sukun}${_nun}${_fatha}'; // يْنَ
      } else if (a.number == 'dual') {
        suffix = '${_ya}${_fatha}${_alef}${_nun}${_kasra}'; // يَانِ
      } else if (a.person == '2nd' && a.number == 'singular' && a.gender == 'feminine') {
        suffix = '${_ya}${_sukun}${_nun}${_fatha}'; // يْنَ
      } else {
        suffix = _alefMaqsura; // ى  (3/2/1 singular and 1st plural)
      }
      rows.add(ConjugationRow(
        baseWordId: verbId, formArabic: '$prefix$presBaseFatha$suffix',
        tense: 'present', pronoun: a.person, number: a.number, gender: a.gender,
        voice: 'active', mood: 'indicative', displayOrder: a.displayOrder + 13,
      ));
    }
    // Imperative (fatha context): drop ى, add endings
    final impBase = presBaseFatha;
    final defImpSuffixes = [
      _ImperativeEntry('singular', 'masculine', '',                              1), // bare base
      _ImperativeEntry('singular', 'feminine',  '$_ya${_sukun}',                 2), // يْ
      _ImperativeEntry('dual',     'common',    '$_ya${_fatha}$_alef',           3), // يَا
      _ImperativeEntry('plural',   'masculine', '${_waw}${_sukun}$_alef',        4), // وْا
      _ImperativeEntry('plural',   'feminine',  '$_ya${_sukun}${_nun}${_fatha}', 5), // يْنَ
    ];
    for (final imp in defImpSuffixes) {
      rows.add(ConjugationRow(
        baseWordId: verbId, formArabic: '$impPrefix$impBase${imp.suffix}',
        tense: 'imperative', pronoun: '2nd', number: imp.number, gender: imp.gender,
        voice: 'active', mood: 'imperative', displayOrder: imp.displayOrder + 26,
      ));
    }
  } else {
    // Kasra context: R3 = ي / ونَ (with damma) / يْنَ pattern
    // Build a damma version of the present base (kasra→damma on last vowel)
    final presBaseDamma = presBaseKasra.endsWith(_kasra)
        ? '${presBaseKasra.substring(0, presBaseKasra.length - 1)}$_damma'
        : presBaseKasra;

    for (final a in presAffixesBase) {
      final prefix = a.prefix;
      String baseToUse;
      String suffix;
      if (a.number == 'plural' && a.gender == 'masculine') {
        baseToUse = presBaseDamma;
        suffix    = '${_waw}${_nun}${_fatha}'; // ونَ
      } else if (a.number == 'plural' && a.gender == 'feminine') {
        baseToUse = presBaseKasra;
        suffix    = '$_ya${_sukun}${_nun}${_fatha}'; // يْنَ
      } else if (a.number == 'dual') {
        baseToUse = presBaseKasra;
        suffix    = '$_ya${_fatha}${_alef}${_nun}${_kasra}'; // يَانِ
      } else if (a.person == '2nd' && a.number == 'singular' && a.gender == 'feminine') {
        baseToUse = presBaseKasra;
        suffix    = '$_ya${_sukun}${_nun}${_fatha}'; // يْنَ
      } else {
        baseToUse = presBaseKasra;
        suffix    = _ya; // ي
      }
      rows.add(ConjugationRow(
        baseWordId: verbId, formArabic: '$prefix$baseToUse$suffix',
        tense: 'present', pronoun: a.person, number: a.number, gender: a.gender,
        voice: 'active', mood: 'indicative', displayOrder: a.displayOrder + 13,
      ));
    }
    // Imperative (kasra context)
    final presBaseDammaImp = presBaseKasra.endsWith(_kasra)
        ? '${presBaseKasra.substring(0, presBaseKasra.length - 1)}$_damma'
        : presBaseKasra;
    final defImpSuffixes = [
      _ImperativeEntry('singular', 'masculine', '',                              1), // bare (drop ي)
      _ImperativeEntry('singular', 'feminine',  _ya,                             2), // ي
      _ImperativeEntry('dual',     'common',    '$_ya${_fatha}$_alef',           3), // يَا
      _ImperativeEntry('plural',   'masculine', '${_waw}${_sukun}$_alef',        4), // وْا (damma base)
      _ImperativeEntry('plural',   'feminine',  '$_ya${_sukun}${_nun}${_fatha}', 5), // يْنَ
    ];
    for (int i = 0; i < defImpSuffixes.length; i++) {
      final imp = defImpSuffixes[i];
      final useBase = (imp.number == 'plural' && imp.gender == 'masculine')
          ? presBaseDammaImp
          : presBaseKasra;
      rows.add(ConjugationRow(
        baseWordId: verbId, formArabic: '$impPrefix$useBase${imp.suffix}',
        tense: 'imperative', pronoun: '2nd', number: imp.number, gender: imp.gender,
        voice: 'active', mood: 'imperative', displayOrder: imp.displayOrder + 26,
      ));
    }
  }

  return rows;
}

// ─────────────────────────────────────────────────────────────────────────────
// HOLLOW FORMS  (R2 = و or ي) — Forms I, IV, VIII, X
// ─────────────────────────────────────────────────────────────────────────────

List<ConjugationRow> _generateHollowConjugations(
  int verbId,
  String root,
  _ArabicForm form,
) {
  final radicals = _extractRadicals(root);
  if (radicals.length < 3) return [];

  final r1  = radicals[0];
  final r2w = radicals[1]; // the weak middle radical (و or ي)
  final r3  = radicals[2];

  // Long-vowel character in past: always ا (alef) regardless of و or ي
  // Long-vowel character in present depends on form's vowel context:
  //   - Forms IV (damma prefix, kasra context): و→ي  (يُقِيمُ)
  //   - Forms VIII / X (fatha prefix, fatha context): و→ا  (يَحْتَاجُ)
  //   - Form I: depends on bab, simplified to و→و (damma) or و→ي (kasra)
  //             for now we use the R2 letter itself as long vowel in present

  // The long vowel for present: for Forms VIII/X fatha context → ا
  //                             for Form IV damma/kasra context → ي (from و) or ي (from ي)
  final String presLongVowel;
  switch (form) {
    case _ArabicForm.formVIII:
    case _ArabicForm.formX:
      presLongVowel = _alef; // fatha context → و/ي becomes ا
      break;
    case _ArabicForm.formIV:
      presLongVowel = _ya;   // kasra context → و/ي becomes ي
      break;
    default:
      // Form I: use the weak letter itself (و stays و in damma context)
      presLongVowel = (r2w == _waw) ? _waw : _ya;
  }

  // ── Past long/short stems per form ───────────────────────────────────────
  String pastLong;   // full 3rd-person form with ا
  String pastShort;  // contracted 2nd/1st form without ا

  // ── Present long/short stems ───────────────────────────────────────────
  String presLong;   // stem used for most present forms
  String presShort;  // contracted stem for 3f.pl / 2f.pl

  // ── Present prefix set ───────────────────────────────────────────────
  List<_AffixEntry> presAffixes;
  String impPrefix;
  String presVowelOnR1; // vowel on R1 in present (kasra for IV, fatha for VIII/X)

  switch (form) {
    case _ArabicForm.formIV:
      // Past long:  أَ + R1 + fatha + ا + R3 + fatha
      // Past short: أَ + R1 + fatha + R3  (ا removed)
      pastLong  = '$_alefH${_fatha}$r1${_fatha}$_alef$r3${_fatha}';
      pastShort = '$_alefH${_fatha}$r1${_fatha}$r3';
      // Present long:  R1 + kasra + ي + R3
      // Present short: R1 + kasra + R3
      presLong  = '$r1${_kasra}$presLongVowel$r3';
      presShort = '$r1${_kasra}$r3';
      presAffixes = _presentAffixesDamma;
      impPrefix   = '$_alefH${_fatha}';
      presVowelOnR1 = _kasra;
      break;

    case _ArabicForm.formVIII:
      // Past long:  اِ + R1 + sukun + تَ + ا + R3 + fatha   e.g. اِحْتَاجَ
      // Past short: اِ + R1 + sukun + تَ + R3               e.g. اِحْتَجْتَ
      pastLong  = '$_alef${_kasra}$r1${_sukun}$_ta${_fatha}$_alef$r3${_fatha}';
      pastShort = '$_alef${_kasra}$r1${_sukun}$_ta${_fatha}$r3';
      // Present long:  R1 + sukun + تَ + ا + R3   e.g. يَحْتَاجُ
      // Present short: R1 + sukun + تَ + R3        e.g. يَحْتَجْنَ
      presLong  = '$r1${_sukun}$_ta${_fatha}$presLongVowel$r3';
      presShort = '$r1${_sukun}$_ta${_fatha}$r3';
      presAffixes   = _presentAffixes;
      impPrefix     = _alef; // hamzat al-wasl — no harakah
      presVowelOnR1 = _fatha;
      break;

    case _ArabicForm.formX:
      // Past long:  اِسْتَ + R1 + fatha + ا + R3 + fatha   e.g. اِسْتَعَانَ
      // Past short: اِسْتَ + R1 + fatha + R3                e.g. اِسْتَعَنْتَ
      pastLong  = '$_alef${_kasra}$_sin${_sukun}$_ta${_fatha}$r1${_fatha}$_alef$r3${_fatha}';
      pastShort = '$_alef${_kasra}$_sin${_sukun}$_ta${_fatha}$r1${_fatha}$r3';
      // Present long:  سْتَ + R1 + kasra + ي + R3   e.g. يَسْتَعِينُ
      // Present short: سْتَ + R1 + kasra + R3        e.g. يَسْتَعِنَّ
      // Note: Form X hollow uses kasra on R1 + ي (unlike Form VIII which uses ا)
      presLong  = '$_sin${_sukun}$_ta${_fatha}$r1${_kasra}$_ya$r3';
      presShort = '$_sin${_sukun}$_ta${_fatha}$r1${_kasra}$r3';
      presAffixes   = _presentAffixes;
      impPrefix     = _alef; // hamzat al-wasl — no harakah (اسْتَعِنْ)
      presVowelOnR1 = _kasra;
      break;

    default:
      // Form I hollow: قَالَ / بَاعَ
      // Past long:  R1 + fatha + ا + R3 + fatha
      // Past short: R1 + (damma if R2=و, kasra if R2=ي) + R3
      final shortVowel = (r2w == _waw) ? _damma : _kasra;
      pastLong  = '$r1${_fatha}$_alef$r3${_fatha}';
      pastShort = '$r1${shortVowel}$r3';
      // Present long:  R1 + (damma if و, kasra if ي) + presLongVowel + R3
      // Present short: R1 + (same) + R3
      final presR1Vowel = (r2w == _waw) ? _damma : _kasra;
      presLong  = '$r1$presR1Vowel$presLongVowel$r3';
      presShort = '$r1$presR1Vowel$r3';
      presAffixes   = _presentAffixes;
      impPrefix     = _alef; // hamzat al-wasl — no harakah
      presVowelOnR1 = presR1Vowel;
  }

  final rows = <ConjugationRow>[];

  // ── Past  ─────────────────────────────────────────────────────────────────
  // displayOrder 1–5 → long; 6–13 → short
  for (final s in _pastSuffixes) {
    final useLong = s.displayOrder <= 5;
    final base    = useLong ? pastLong : pastShort;
    // Strip trailing fatha from long base before suffix
    final trimmed = base.endsWith(_fatha)
        ? base.substring(0, base.length - 1)
        : base;
    rows.add(ConjugationRow(
      baseWordId: verbId, formArabic: '$trimmed${s.suffix}',
      tense: 'past', pronoun: s.person, number: s.number, gender: s.gender,
      voice: 'active', mood: 'indicative', displayOrder: s.displayOrder,
    ));
  }

  // ── Present ───────────────────────────────────────────────────────────────
  // Most forms use long stem; 3f.pl and 2f.pl use short + نَ
  for (final a in presAffixes) {
    String stem;
    String suffix;
    if (a.number == 'plural' && a.gender == 'feminine') {
      stem   = presShort;
      suffix = '${_sukun}${_nun}${_fatha}'; // ْنَ
    } else {
      stem   = presLong;
      suffix = a.suffix;
    }
    rows.add(ConjugationRow(
      baseWordId: verbId, formArabic: '${a.prefix}$stem$suffix',
      tense: 'present', pronoun: a.person, number: a.number, gender: a.gender,
      voice: 'active', mood: 'indicative', displayOrder: a.displayOrder + 13,
    ));
  }

  // ── Imperative ────────────────────────────────────────────────────────────
  // m.s.: impPrefix + short + sukun
  // f.s.: impPrefix + long  + kasra + ي
  // dual: impPrefix + long  + fatha + ا
  // m.pl: impPrefix + long  + damma + وا
  // f.pl: impPrefix + short + sukun + نَ
  final impForms = [
    _ImperativeEntry('singular', 'masculine', '${_sukun}',                              1),
  ];
  rows.add(ConjugationRow(
    baseWordId: verbId,
    formArabic: '$impPrefix$presShort${_sukun}',
    tense: 'imperative', pronoun: '2nd', number: 'singular', gender: 'masculine',
    voice: 'active', mood: 'imperative', displayOrder: 27,
  ));
  rows.add(ConjugationRow(
    baseWordId: verbId,
    formArabic: '$impPrefix$presLong${_kasra}$_ya',
    tense: 'imperative', pronoun: '2nd', number: 'singular', gender: 'feminine',
    voice: 'active', mood: 'imperative', displayOrder: 28,
  ));
  rows.add(ConjugationRow(
    baseWordId: verbId,
    formArabic: '$impPrefix$presLong${_fatha}$_alef',
    tense: 'imperative', pronoun: '2nd', number: 'dual', gender: 'common',
    voice: 'active', mood: 'imperative', displayOrder: 29,
  ));
  rows.add(ConjugationRow(
    baseWordId: verbId,
    formArabic: '$impPrefix$presLong${_damma}${_waw}$_alef',
    tense: 'imperative', pronoun: '2nd', number: 'plural', gender: 'masculine',
    voice: 'active', mood: 'imperative', displayOrder: 30,
  ));
  rows.add(ConjugationRow(
    baseWordId: verbId,
    formArabic: '$impPrefix$presShort${_sukun}${_nun}${_fatha}',
    tense: 'imperative', pronoun: '2nd', number: 'plural', gender: 'feminine',
    voice: 'active', mood: 'imperative', displayOrder: 31,
  ));

  return rows;
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED BUILDER — STRONG STEMS → ROWS
// ─────────────────────────────────────────────────────────────────────────────

List<ConjugationRow> _buildRowsFromStems({
  required int verbId,
  required String pastBase,
  required String presentStem,
  required List<_AffixEntry> presAffixes,
  required String impPrefix,
}) {
  final rows = <ConjugationRow>[];

  // Past
  for (final s in _pastSuffixes) {
    final base = pastBase.endsWith(_fatha)
        ? pastBase.substring(0, pastBase.length - 1)
        : pastBase;
    rows.add(ConjugationRow(
      baseWordId: verbId, formArabic: '$base${s.suffix}',
      tense: 'past', pronoun: s.person, number: s.number, gender: s.gender,
      voice: 'active', mood: 'indicative', displayOrder: s.displayOrder,
    ));
  }

  // Present
  for (final a in presAffixes) {
    rows.add(ConjugationRow(
      baseWordId: verbId, formArabic: '${a.prefix}$presentStem${a.suffix}',
      tense: 'present', pronoun: a.person, number: a.number, gender: a.gender,
      voice: 'active', mood: 'indicative', displayOrder: a.displayOrder + 13,
    ));
  }

  // Imperative
  for (final imp in _imperativeForms) {
    rows.add(ConjugationRow(
      baseWordId: verbId, formArabic: '$impPrefix$presentStem${imp.suffix}',
      tense: 'imperative', pronoun: '2nd', number: imp.number, gender: imp.gender,
      voice: 'active', mood: 'imperative', displayOrder: imp.displayOrder + 26,
    ));
  }
  return rows;
}

// ─────────────────────────────────────────────────────────────────────────────
// CONJUGATION ENGINE — PUBLIC API
// ─────────────────────────────────────────────────────────────────────────────

// Increment this whenever conjugation logic changes to bust the SQLite cache.
const int _engineVersion = 3;

// Track whether we've checked the version in this DB session already.
bool _versionChecked = false;

class ConjugationEngine {
  final Database _db;

  ConjugationEngine(this._db);

  Future<ConjugationTable> getConjugations({
    required int    lexiconId,
    required String formStripped,
    required String root,
  }) async {
    // ── 0. Version check / cache wipe (once per DB session) ─────────────────
    if (!_versionChecked) {
      final v = (await _db.rawQuery('PRAGMA user_version')).first.values.first as int;
      if (v != _engineVersion) {
        await _db.execute('DELETE FROM conjugations');
        await _db.execute('PRAGMA user_version = $_engineVersion');
      }
      _versionChecked = true;
    }

    // ── 1. Check cache ───────────────────────────────────────────────────────
    final cached = await _db.query(
      'conjugations',
      where: 'base_word_id = ?',
      whereArgs: [lexiconId],
      orderBy: 'display_order ASC',
    );
    if (cached.isNotEmpty) {
      return _buildTable(cached.map(ConjugationRow.fromMap).toList(), fromCache: true);
    }

    // ── 2. Detect form and root type ─────────────────────────────────────────
    final form     = _detectArabicForm(formStripped);
    final radicals = _extractRadicals(root);

    List<ConjugationRow> rows;

    if (form == _ArabicForm.formI) {
      if (_isStrongRoot(radicals)) {
        final pattern = kVerbPatterns[formStripped] ??
            kVerbPatterns[_stripDiacritics(formStripped)] ??
            VerbPattern(1, Haraka.damma);
        rows = _generateConjugations(lexiconId, root, pattern);
      } else if (_isDefectiveRoot(radicals)) {
        rows = _generateDefectiveConjugations(lexiconId, root, form);
      } else if (_isHollowRoot(radicals)) {
        rows = _generateHollowConjugations(lexiconId, root, form);
      } else {
        rows = []; // doubly weak or geminate — skip for now
      }
    } else if (form != _ArabicForm.other) {
      // Form III / V with hollow R2: و is just a consonant → treat as strong
      final treatAsStrong = _isStrongRoot(radicals) ||
          ((_isHollowRoot(radicals)) &&
              (form == _ArabicForm.formIII || form == _ArabicForm.formV));

      if (treatAsStrong) {
        rows = _generateDerivedConjugations(lexiconId, root, form);
      } else if (_isDefectiveRoot(radicals)) {
        rows = _generateDefectiveConjugations(lexiconId, root, form);
      } else if (_isHollowRoot(radicals)) {
        // Forms IV, VIII, X with hollow root
        rows = _generateHollowConjugations(lexiconId, root, form);
      } else {
        rows = [];
      }
    } else {
      rows = []; // quadriliteral or unknown
    }

    if (rows.isEmpty) {
      return const ConjugationTable(past: [], present: [], imperative: [], fromCache: false);
    }

    // ── 3. Store in cache ────────────────────────────────────────────────────
    final batch = _db.batch();
    for (final row in rows) {
      batch.insert('conjugations', row.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);

    return _buildTable(rows, fromCache: false);
  }

  Future<void> clearCache(int lexiconId) async {
    await _db.delete('conjugations', where: 'base_word_id = ?', whereArgs: [lexiconId]);
  }

  Future<void> clearAllCache() async {
    await _db.delete('conjugations');
    _versionChecked = false;
  }

  ConjugationTable _buildTable(List<ConjugationRow> rows, {required bool fromCache}) {
    return ConjugationTable(
      past:       rows.where((r) => r.tense == 'past').toList(),
      present:    rows.where((r) => r.tense == 'present').toList(),
      imperative: rows.where((r) => r.tense == 'imperative').toList(),
      fromCache:  fromCache,
    );
  }
}

// ── Missing constant used in defective generation ────────────────────────────
const String _nun = '\u0646'; // ن
