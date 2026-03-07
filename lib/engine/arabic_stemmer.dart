// lib/engine/arabic_stemmer.dart
//
// Hybrid Arabic Stemmer — ISRI affix stripping + Khoja pattern matching
// Written in pure Dart, no external dependencies. Fully offline.
//
// Pipeline:
//   1. Normalize  — strip diacritics, normalise alef variants internally
//   2. Suffixes   — ISRI suffix list, longest-first, min 3-letter guard
//   3. Prefixes   — ISRI prefix list, longest-first
//   4. Patterns   — Khoja-style pattern table → extract root letter positions
//   5. Format     — 'كتب' → 'ك-ت-ب'  (matches lexicon.root column)
//
// Only invoked as a fallback when direct form_stripped lookup returns nothing.
// The DB root column may contain compound entries like 'وهب-;-هيب' —
// the stemmer always produces a single 3-letter root; compound roots are
// handled at the repository query layer (LIKE search).

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

enum StemMethod {
  /// Word was exactly 3 letters after stripping — used directly as root
  direct,

  /// Root extracted by matching a Khoja morphological pattern
  pattern,

  /// No pattern matched; first 3 letters of stripped word used as best guess
  fallback,

  /// Stemming failed — word too short or fully ambiguous
  failed,
}

class StemResult {
  final String originalInput;
  final String normalizedInput;
  final String? strippedWord;   // after suffix + prefix removal
  final String? extractedRoot;  // plain letters e.g. 'كتب'
  final String? rootForDB;      // dash-separated e.g. 'ك-ت-ب'
  final StemMethod method;

  const StemResult({
    required this.originalInput,
    required this.normalizedInput,
    this.strippedWord,
    this.extractedRoot,
    this.rootForDB,
    required this.method,
  });

  bool get success => method != StemMethod.failed;

  @override
  String toString() =>
      'StemResult(root: $rootForDB, method: $method, stripped: $strippedWord)';
}

// ---------------------------------------------------------------------------
// Pattern definition
// ---------------------------------------------------------------------------

class _PatternDef {
  final int wordLength;
  final List<int> rootPositions;
  final Map<int, String> fixedLetters;
  final String label;

  const _PatternDef({
    required this.wordLength,
    required this.rootPositions,
    required this.fixedLetters,
    required this.label,
  });

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

// ---------------------------------------------------------------------------
// ArabicStemmer
// ---------------------------------------------------------------------------

class ArabicStemmer {
  static final _diacriticsRegex   = RegExp(r'[\u064B-\u065F\u0670]');
  static final _alefVariantsRegex = RegExp(r'[أإآٱ]');

  // ── ISRI Prefix list — longest first ─────────────────────────────────────
  static const List<String> _prefixes = [
    'وال', 'بال', 'كال', 'فال',
    'لل',
    'ال',
    'و', 'ف', 'ب', 'ك', 'ل', 'س',
  ];

  // ── ISRI Suffix list — longest first ─────────────────────────────────────
  static const List<String> _suffixes = [
    'تين', 'تان', 'ونه', 'يني', 'وها', 'يها',
    'ية', 'ون', 'ين', 'ان', 'ات', 'ها', 'نا',
    'كم', 'هم', 'وا', 'تم', 'يا', 'هن', 'كن', 'تن',
    'ةً', 'ةٌ',
    'ة', 'ه', 'ي', 'ا', 'ن',
  ];

  // ── Khoja-style pattern table ─────────────────────────────────────────────
  static const List<_PatternDef> _patterns = [

    // ── 4-letter ─────────────────────────────────────────────────────────
    _PatternDef(  // فَاعِل  active participle Form I    كاتب → كتب
      wordLength: 4, rootPositions: [0, 2, 3],
      fixedLetters: {1: 'ا'}, label: 'فاعل',
    ),
    _PatternDef(  // فِعَال  intensive noun              كتاب → كتب
      wordLength: 4, rootPositions: [0, 1, 3],
      fixedLetters: {2: 'ا'}, label: 'فعال',
    ),
    _PatternDef(  // فَعِيل  adjectival noun             كبير → كبر
      wordLength: 4, rootPositions: [0, 1, 3],
      fixedLetters: {2: 'ي'}, label: 'فعيل',
    ),
    _PatternDef(  // فُعُول  broken plural               بيوت → بيت
      wordLength: 4, rootPositions: [0, 1, 3],
      fixedLetters: {2: 'و'}, label: 'فعول',
    ),
    _PatternDef(  // مَفْعَل  place/instrument noun      مدرس → درس
      wordLength: 4, rootPositions: [1, 2, 3],
      fixedLetters: {0: 'م'}, label: 'مفعل',
    ),
    _PatternDef(  // أَفْعَل  comparative / Form IV      اكبر → كبر  (alef normalised)
      wordLength: 4, rootPositions: [1, 2, 3],
      fixedLetters: {0: 'ا'}, label: 'أفعل',
    ),
    _PatternDef(  // تَفْعَل  Form V/VI imperfect        تكتب → كتب
      wordLength: 4, rootPositions: [1, 2, 3],
      fixedLetters: {0: 'ت'}, label: 'تفعل',
    ),
    _PatternDef(  // يَفْعَل  Form I present             يكتب → كتب
      wordLength: 4, rootPositions: [1, 2, 3],
      fixedLetters: {0: 'ي'}, label: 'يفعل',
    ),
    _PatternDef(  // فَعْلَة  feminine / verbal noun     رحلة → رحل
      wordLength: 4, rootPositions: [0, 1, 2],
      fixedLetters: {3: 'ة'}, label: 'فعلة',
    ),

    // ── 5-letter ─────────────────────────────────────────────────────────
    _PatternDef(  // مَفْعُول  passive participle        مكتوب → كتب
      wordLength: 5, rootPositions: [1, 2, 4],
      fixedLetters: {0: 'م', 3: 'و'}, label: 'مفعول',
    ),
    _PatternDef(  // مَفَاعِل  broken plural             مدارس → درس
      wordLength: 5, rootPositions: [1, 3, 4],
      fixedLetters: {0: 'م', 2: 'ا'}, label: 'مفاعل',
    ),
    _PatternDef(  // تَفَاعَل  Form VI                   تعاون → عون
      wordLength: 5, rootPositions: [1, 3, 4],
      fixedLetters: {0: 'ت', 2: 'ا'}, label: 'تفاعل',
    ),
    _PatternDef(  // اِفْتَعَل  Form VIII                استمع → سمع
      wordLength: 5, rootPositions: [1, 3, 4],
      fixedLetters: {0: 'ا', 2: 'ت'}, label: 'افتعل',
    ),
    _PatternDef(  // اِنْفَعَل  Form VII                 انكسر → كسر
      wordLength: 5, rootPositions: [2, 3, 4],
      fixedLetters: {0: 'ا', 1: 'ن'}, label: 'انفعل',
    ),
    _PatternDef(  // تَفْعِيل  verbal noun Form II       تدريس → درس
      wordLength: 5, rootPositions: [1, 2, 4],
      fixedLetters: {0: 'ت', 3: 'ي'}, label: 'تفعيل',
    ),
    _PatternDef(  // فَعَلَان  verbal noun / adjective   غضبان → غضب
      wordLength: 5, rootPositions: [0, 1, 2],
      fixedLetters: {3: 'ا', 4: 'ن'}, label: 'فعلان',
    ),
    _PatternDef(  // فَاعِلَة  active participle fem.   كاتبة → كتب
      wordLength: 5, rootPositions: [0, 2, 3],
      fixedLetters: {1: 'ا', 4: 'ة'}, label: 'فاعلة',
    ),
    _PatternDef(  // مُفْتَعَل  Form VIII masdar         مجتمع → جمع
      wordLength: 5, rootPositions: [1, 3, 4],
      fixedLetters: {0: 'م', 2: 'ت'}, label: 'مفتعل',
    ),
    _PatternDef(  // مَفْعَال  instrument noun           مفتاح → فتح
      wordLength: 5, rootPositions: [1, 2, 4],
      fixedLetters: {0: 'م', 3: 'ا'}, label: 'مفعال',
    ),

    // ── 6-letter ─────────────────────────────────────────────────────────
    _PatternDef(  // اِسْتَفْعَل  Form X                استخدم → خدم
      wordLength: 6, rootPositions: [3, 4, 5],
      fixedLetters: {0: 'ا', 1: 'س', 2: 'ت'}, label: 'استفعل',
    ),
    _PatternDef(  // مُسْتَفْعَل  Form X passive part.  مستخدم → خدم
      wordLength: 6, rootPositions: [3, 4, 5],
      fixedLetters: {0: 'م', 1: 'س', 2: 'ت'}, label: 'مستفعل',
    ),
    _PatternDef(  // اِفْتِعَال  Form VIII masdar        اجتماع → جمع
      wordLength: 6, rootPositions: [1, 3, 5],
      fixedLetters: {0: 'ا', 2: 'ت', 4: 'ا'}, label: 'افتعال',
    ),
    _PatternDef(  // اِنْفِعَال  Form VII masdar         انكسار → كسر
      wordLength: 6, rootPositions: [2, 3, 5],
      fixedLetters: {0: 'ا', 1: 'ن', 4: 'ا'}, label: 'انفعال',
    ),

    // ── 7-letter ─────────────────────────────────────────────────────────
    _PatternDef(  // اِسْتِفْعَال  Form X masdar         استخدام → خدم
      wordLength: 7, rootPositions: [3, 4, 6],
      fixedLetters: {0: 'ا', 1: 'س', 2: 'ت', 5: 'ا'}, label: 'استفعال',
    ),
  ];

  // ── Public API ────────────────────────────────────────────────────────────

  StemResult stem(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return StemResult(
          originalInput: input, normalizedInput: '', method: StemMethod.failed);
    }

    final normalized = _normalize(trimmed);

    if (normalized.length < 2) {
      return StemResult(
          originalInput: input,
          normalizedInput: normalized,
          method: StemMethod.failed);
    }

    String word = _stripSuffix(normalized);
    word = _stripPrefix(word);

    if (word.length < 2) {
      return StemResult(
          originalInput: input,
          normalizedInput: normalized,
          strippedWord: word,
          method: StemMethod.failed);
    }

    // Exactly 3 letters → direct root
    if (word.length == 3) {
      return StemResult(
        originalInput: input,
        normalizedInput: normalized,
        strippedWord: word,
        extractedRoot: word,
        rootForDB: _formatForDB(word),
        method: StemMethod.direct,
      );
    }

    // Pattern matching
    final patternRoot = _matchPattern(word);
    if (patternRoot != null && patternRoot.length == 3) {
      return StemResult(
        originalInput: input,
        normalizedInput: normalized,
        strippedWord: word,
        extractedRoot: patternRoot,
        rootForDB: _formatForDB(patternRoot),
        method: StemMethod.pattern,
      );
    }

    // Fallback — first 3 letters (DB validates naturally)
    if (word.length >= 3) {
      final guess = word.substring(0, 3);
      return StemResult(
        originalInput: input,
        normalizedInput: normalized,
        strippedWord: word,
        extractedRoot: guess,
        rootForDB: _formatForDB(guess),
        method: StemMethod.fallback,
      );
    }

    return StemResult(
        originalInput: input,
        normalizedInput: normalized,
        strippedWord: word,
        method: StemMethod.failed);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  String _normalize(String text) {
    String r = text.replaceAll(_diacriticsRegex, '');
    r = r.replaceAll(_alefVariantsRegex, 'ا');
    return r;
  }

  String _stripSuffix(String word) {
    for (final s in _suffixes) {
      if (word.length > s.length + 2 && word.endsWith(s)) {
        return word.substring(0, word.length - s.length);
      }
    }
    return word;
  }

  String _stripPrefix(String word) {
    for (final p in _prefixes) {
      if (word.length > p.length + 2 && word.startsWith(p)) {
        return word.substring(p.length);
      }
    }
    return word;
  }

  String? _matchPattern(String word) {
    for (final pattern in _patterns) {
      if (pattern.matches(word)) return pattern.extractRoot(word);
    }
    return null;
  }

  /// 'كتب' → 'ك-ت-ب'
  String _formatForDB(String root) => root.split('').join('-');
}
