import 'package:flutter/material.dart';

class TextHighlighter {
  static const Color matchColor = Color(0xFF1976D2);

  /// 1. English Substring Highlight
  static List<TextSpan> highlightQuery(String text, String query, {Color baseColor = const Color(0xFF374151)}) {
    if (query.trim().isEmpty) return [TextSpan(text: text, style: TextStyle(color: baseColor))];

    final String lowerText = text.toLowerCase();
    final String lowerQuery = query.toLowerCase();

    List<TextSpan> spans = [];
    int start = 0;
    int indexOfMatch = lowerText.indexOf(lowerQuery, start);

    while (indexOfMatch != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(text: text.substring(start, indexOfMatch), style: TextStyle(color: baseColor)));
      }
      spans.add(TextSpan(
        text: text.substring(indexOfMatch, indexOfMatch + query.length),
        style: const TextStyle(color: matchColor, fontWeight: FontWeight.bold),
      ));
      start = indexOfMatch + query.length;
      indexOfMatch = lowerText.indexOf(lowerQuery, start);
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: TextStyle(color: baseColor)));
    }

    return spans;
  }

  /// 2. Arabic Diacritic-Agnostic Highlight
  /// Finds unvocalized query (e.g. كتب) inside vocalized text (e.g. كَتَبَ).
  ///
  /// Normalises both diacritics (U+064B..U+065F, U+0670) and alef variants
  /// (أإآٱ → ا) so that a bare-alef query matches the hamzated form in the
  /// result and vice versa. Returns an empty list when no match is found,
  /// which lets callers decide whether to fall back to root highlighting.
  static List<TextSpan> highlightArabicQuery(
    String text,
    String query, {
    Color baseColor = const Color(0xFF374151),
  }) {
    if (query.trim().isEmpty) {
      return [TextSpan(text: text, style: TextStyle(color: baseColor))];
    }

    // Strip diacritics + unify alef variants in the query
    String cleanQuery = query
        .replaceAll(RegExp(r'[ً-ٰٟ]'), '')
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا');
    if (cleanQuery.isEmpty) {
      return [TextSpan(text: text, style: TextStyle(color: baseColor))];
    }

    // Build a regex: between every query letter allow any diacritics,
    // and for any bare alef also match its hamzated/wasla variants.
    String letterClass(String ch) {
      if (ch == 'ا') return '[اأإآٱ]';
      return RegExp.escape(ch);
    }

    final String regexStr = cleanQuery
            .split('')
            .map(letterClass)
            .join(r'[ً-ٰٟ]*') +
        r'[ً-ٰٟ]*';
    final RegExp regex = RegExp(regexStr);

    final List<RegExpMatch> matches = regex.allMatches(text).toList();
    if (matches.isEmpty) return const [];

    final List<TextSpan> spans = [];
    int start = 0;
    for (final match in matches) {
      if (match.start > start) {
        spans.add(TextSpan(
            text: text.substring(start, match.start),
            style: TextStyle(color: baseColor)));
      }
      spans.add(TextSpan(
        text: match.group(0)!,
        style: const TextStyle(color: matchColor, fontWeight: FontWeight.bold),
      ));
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(
          text: text.substring(start), style: TextStyle(color: baseColor)));
    }
    return spans;
  }

  /// 2a. List-tile smart highlight — "EXACT or ROOT only".
  ///
  /// First tries exact diacritic/alef-agnostic substring matching via
  /// [highlightArabicQuery]. When the query doesn't appear in [text]
  /// (e.g. user searched the conjugated form `يكتبون` and the tile is
  /// the lemma `كَتَبَ`), falls back to highlighting the root radicals
  /// using [highlightRootWithMutations]. This keeps every tile visually
  /// anchored to either the literal match or the shared root — never a
  /// partial/misleading highlight.
  static List<TextSpan> highlightArabicForList(
    String text,
    String query,
    String root, {
    Color baseColor = const Color(0xFF374151),
  }) {
    final exact = highlightArabicQuery(text, query, baseColor: baseColor);
    if (exact.isNotEmpty) return exact;
    // Fallback: colour the root radicals. No mutation letters on list tiles —
    // that red-tier detail is reserved for the conjugation grid.
    return highlightRootWithMutations(text, root, baseColor: baseColor);
  }

  /// 3. Detail Page: Arabic Root Highlight (by root letters)
  static List<TextSpan> highlightArabicRoot(String word, String root, {Color baseColor = const Color(0xFF374151)}) {
    if (root.isEmpty) return [TextSpan(text: word, style: TextStyle(color: baseColor))];

    String normalize(String s) => s.replaceAll(RegExp(r'[أإآ]'), 'ا');
    final List<String> rootLetters = root.replaceAll('-', '').split('').map((l) => normalize(l)).toList();

    List<TextSpan> spans = [];
    bool wasRoot = false;
    String currentChunk = "";

    // U+064B..U+065F: combining diacritics; U+0670: dagger alef.
    bool isDiacritic(String char) {
      int code = char.codeUnitAt(0);
      return (code >= 0x064B && code <= 0x065F) || code == 0x0670;
    }

    for (int i = 0; i < word.length; i++) {
      String char = word[i];
      if (isDiacritic(char)) {
         currentChunk += char;
      } else {
         bool isRoot = rootLetters.contains(normalize(char));
         if (isRoot != wasRoot && currentChunk.isNotEmpty) {
           spans.add(TextSpan(
             text: currentChunk,
             style: TextStyle(color: wasRoot ? matchColor : baseColor)
           ));
           currentChunk = "";
         }
         wasRoot = isRoot;
         currentChunk += char;
      }
    }

    if (currentChunk.isNotEmpty) {
       spans.add(TextSpan(text: currentChunk, style: TextStyle(color: wasRoot ? matchColor : baseColor)));
    }

    return spans;
  }

  /// 4. Detail Page: Highlight root letters (blue) + mutation letters (red).
  ///
  /// Root radicals that appear in a conjugated form are coloured [matchColor]
  /// (blue).  Letters in [mutationLetters] that are NOT root radicals are
  /// coloured [mutationColor] (red) — these are the "changed" letters in weak
  /// verb forms (e.g. ا replacing hollow R2=و).
  /// Every other letter gets [baseColor].
  ///
  /// ── Position-aware mutation rule ─────────────────────────────────────────
  /// A non-root letter only counts as a *mutation* when it sits BETWEEN two
  /// root letters in the surface form.  This stops the imperfect prefix يَ
  /// and the dual suffix ـَا from being painted red just because ي / ا are
  /// in the per-verb mutation set.
  ///
  /// Examples for قال (root ق-و-ل, mutationLetters = {ا, ي}):
  ///   قَالَ        → ق(blue) ا(red, between R1+R3) ل(blue)            ✓
  ///   يَقُولُ       → ي(base, prefix) ق(blue) و(blue) ل(blue)            ✓
  ///   يَقُولَانِ    → ي(base) ق(blue) و(blue) ل(blue) ا(base) ن(base)   ✓
  ///   اقُلْ         → ا(base, helping-alef) ق(blue) ل(blue)              ✓
  ///
  /// Edge case: a defective ى at word-final (e.g. رَمَى) is left un-painted
  /// because there's no flanking letter on the right.  Acceptable trade-off:
  /// the form still reads correctly with R1+R2 in blue and ى in base.
  ///
  /// Typical [mutationLetters] values:
  ///   Hollow R2=و  → {'ا', 'ي'}   (ا past long, ي present kasra)
  ///   Hollow R2=ي  → {'ا'}              (ا past long only)
  ///   Defective R3 → {'ى'}              (ى alef-maqsura)
  ///   Strong       → {}                       (root-only blue highlighting)
  static List<TextSpan> highlightRootWithMutations(
    String text,
    String root, {
    Set<String> mutationLetters = const {},
    Color mutationColor = const Color(0xFFD32F2F), // red
    Color baseColor = const Color(0xFF374151),
  }) {
    if (root.isEmpty) {
      return [TextSpan(text: text, style: TextStyle(color: baseColor))];
    }

    String normalize(String s) =>
        s.replaceAll(RegExp(r'[أإآ]'), 'ا');

    final rootSet = root
        .replaceAll('-', '')
        .split('')
        .map(normalize)
        .toSet();

    final mutSet = mutationLetters
        .map(normalize)
        .where((l) => !rootSet.contains(l))
        .toSet();

    // U+064B..U+065F: combining diacritics; U+0670: dagger alef.
    bool isDiacritic(String char) {
      final code = char.codeUnitAt(0);
      return (code >= 0x064B && code <= 0x065F) || code == 0x0670;
    }

    // Pass 1: list every non-diacritic letter with its index in [text].
    // This lets us look at left/right neighbours when deciding whether
    // a mutation-set letter is a real mutation or just a grammatical
    // affix (prefix / suffix).
    final letterIndices = <int>[];
    final letterChars = <String>[];
    for (int i = 0; i < text.length; i++) {
      if (!isDiacritic(text[i])) {
        letterIndices.add(i);
        letterChars.add(text[i]);
      }
    }

    // Pass 2: identify which text indices are TRUE mutations
    // (flanked by root letters on BOTH sides).
    final trueMutationIndices = <int>{};
    for (int j = 0; j < letterChars.length; j++) {
      final ch = letterChars[j];
      final n = normalize(ch);
      if (!mutSet.contains(n) || rootSet.contains(n)) continue;
      if (j == 0 || j == letterChars.length - 1) continue;
      final leftN = normalize(letterChars[j - 1]);
      final rightN = normalize(letterChars[j + 1]);
      if (rootSet.contains(leftN) && rootSet.contains(rightN)) {
        trueMutationIndices.add(letterIndices[j]);
      }
    }

    // Categorise per text index: 0 = base, 1 = root (blue), 2 = mutation (red).
    int category(int textIndex, String ch) {
      final n = normalize(ch);
      if (rootSet.contains(n)) return 1;
      if (trueMutationIndices.contains(textIndex)) return 2;
      return 0;
    }

    final spans = <TextSpan>[];
    int curCat = -1;
    String chunk = '';

    void flush(int cat) {
      if (chunk.isEmpty) return;
      Color color;
      if (cat == 1)      color = matchColor;
      else if (cat == 2) color = mutationColor;
      else               color = baseColor;
      spans.add(TextSpan(text: chunk, style: TextStyle(color: color)));
      chunk = '';
    }

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (isDiacritic(char)) {
        chunk += char; // attach diacritic to current chunk
      } else {
        final cat = category(i, char);
        if (cat != curCat && chunk.isNotEmpty) {
          flush(curCat);
        }
        curCat = cat;
        chunk += char;
      }
    }
    flush(curCat);

    return spans;
  }

  /// 6. Detail Page: Highlight base form consonants (by formStripped letters)
  /// Uses the full consonant set from formStripped, which includes morphological
  /// prefixes such as أ (Form IV), ا+ت (Form VIII), اسـت (Form X). This gives
  /// correct highlighting inside derived-form conjugation tables.
  static List<TextSpan> highlightArabicBaseForm(
    String text,
    String formStripped, {
    Color baseColor = const Color(0xFF374151),
  }) {
    if (formStripped.isEmpty) {
      return [TextSpan(text: text, style: TextStyle(color: baseColor))];
    }

    String normalize(String s) =>
        s.replaceAll(RegExp(r'[أإآ]'), 'ا');

    // Strip diacritics from formStripped to get pure consonant set
    final cleanForm =
        formStripped.replaceAll(RegExp(r'[ً-ٰٟ]'), '');
    final Set<String> consonants =
        cleanForm.split('').map((l) => normalize(l)).toSet();

    List<TextSpan> spans = [];
    bool wasHighlighted = false;
    String currentChunk = '';

    bool isDiacritic(String char) {
      final code = char.codeUnitAt(0);
      return (code >= 0x064B && code <= 0x065F) || code == 0x0670;
    }

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (isDiacritic(char)) {
        currentChunk += char;
      } else {
        final isHighlighted = consonants.contains(normalize(char));
        if (isHighlighted != wasHighlighted && currentChunk.isNotEmpty) {
          spans.add(TextSpan(
            text: currentChunk,
            style: TextStyle(
                color: wasHighlighted ? matchColor : baseColor),
          ));
          currentChunk = '';
        }
        wasHighlighted = isHighlighted;
        currentChunk += char;
      }
    }

    if (currentChunk.isNotEmpty) {
      spans.add(TextSpan(
        text: currentChunk,
        style: TextStyle(color: wasHighlighted ? matchColor : baseColor),
      ));
    }

    return spans;
  }
}
