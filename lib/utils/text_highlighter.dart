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
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'[\u0623\u0625\u0622\u0671]'), '\u0627');
    if (cleanQuery.isEmpty) {
      return [TextSpan(text: text, style: TextStyle(color: baseColor))];
    }

    // Build a regex: between every query letter allow any diacritics,
    // and for any bare alef also match its hamzated/wasla variants.
    String letterClass(String ch) {
      if (ch == '\u0627') return '[\u0627\u0623\u0625\u0622\u0671]';
      return RegExp.escape(ch);
    }

    final String regexStr = cleanQuery
            .split('')
            .map(letterClass)
            .join(r'[\u064B-\u065F\u0670]*') +
        r'[\u064B-\u065F\u0670]*';
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

    bool isDiacritic(String char) {
      int code = char.codeUnitAt(0);
      return code >= 0x064B && code <= 0x065F;
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
  /// verb forms (e.g. ا replacing hollow R2=و, or ى replacing defective R3=ي).
  /// Every other letter gets [baseColor].
  ///
  /// Typical [mutationLetters] values:
  ///   Hollow R2=و  → {'ا', 'ي'}   (ا in past long, ي in present kasra context)
  ///   Hollow R2=ي  → {'ا'}         (ا in past long only; ي is the root letter)
  ///   Defective R3 → {'\u0649'}    (ى alef-maqsura)
  ///   Strong       → {}            (degrades to root-only blue highlighting)
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

    String normalize(String s) => s.replaceAll(RegExp(r'[أإآ]'), 'ا');

    // Build the root letter set (no dashes, normalized)
    final rootSet = root
        .replaceAll('-', '')
        .split('')
        .map(normalize)
        .toSet();

    // Mutation set = mutation letters NOT already in rootSet
    final mutSet = mutationLetters
        .map(normalize)
        .where((l) => !rootSet.contains(l))
        .toSet();

    bool isDiacritic(String char) {
      final code = char.codeUnitAt(0);
      return code >= 0x064B && code <= 0x065F;
    }

    // Categorise: 0 = base, 1 = root (blue), 2 = mutation (red)
    int category(String char) {
      final n = normalize(char);
      if (rootSet.contains(n)) return 1;
      if (mutSet.contains(n))  return 2;
      return 0;
    }

    final spans    = <TextSpan>[];
    int curCat     = -1;
    String chunk   = '';

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
        final cat = category(char);
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

    String normalize(String s) => s.replaceAll(RegExp(r'[أإآ]'), 'ا');

    // Strip diacritics from formStripped to get pure consonant set
    final cleanForm =
        formStripped.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    final Set<String> consonants =
        cleanForm.split('').map((l) => normalize(l)).toSet();

    List<TextSpan> spans = [];
    bool wasHighlighted = false;
    String currentChunk = '';

    bool isDiacritic(String char) {
      final code = char.codeUnitAt(0);
      return code >= 0x064B && code <= 0x065F;
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