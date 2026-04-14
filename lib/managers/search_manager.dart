// lib/managers/search_manager.dart
//
// Business-layer search orchestrator.
//
// Sits between the Cubits (presentation) and DictionaryRepository (data).
// Owns all search logic: script detection, tokenization, tier ranking,
// deduplication, and stemmer fallback. The repository is called only for
// raw DB queries — no SQL lives here.
//
// Future extension points (see architecture diagram):
//   - AraBERT semantic search slot (replaces / augments stemmer fallback)
//   - CacheManager integration (check cache before hitting DB)
//   - Tashaphyne stemmer swap-in (replace ArabicStemmer with Tashaphyne)

import '../models/models.dart';
import '../repositories/dictionary_repository.dart';
import '../engine/arabic_stemmer.dart';

class SearchManager {
  final DictionaryRepository _repository;
  final ArabicStemmer _stemmer;

  SearchManager({
    required DictionaryRepository repository,
    required ArabicStemmer stemmer,
  })  : _repository = repository,
        _stemmer = stemmer;

  // ── Public API ────────────────────────────────────────────────────────────────

  Future<List<Word>> getCommonWords() => _repository.getCommonWords();

  Future<List<Word>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(trimmed);
    return isArabic ? _searchArabic(trimmed) : _searchEnglish(trimmed);
  }

  // ── Arabic search ─────────────────────────────────────────────────────────────

  Future<List<Word>> _searchArabic(String query) async {
    // Strip diacritics then normalise alef variants (أ إ آ ٱ → ا) so that
    // searching "أكل" and "اكل" both hit the same entries.
    final stripped = query
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'[\u0623\u0625\u0622\u0671]'), '\u0627');

    // Tier 1: direct lookup on the full query
    final directResults = await _repository.directArabicLookup(stripped);

    // Single word — direct hit or stemmer fallback
    final tokens =
        stripped.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.length == 1) {
      if (directResults.isNotEmpty) return directResults;
      return _stemmerFallback(stripped);
    }

    // Multi-word: full phrase first, then per-token tiers
    final seen = <int, Word>{};
    for (final w in directResults) seen[w.id] = w;

    // Tier 2: per-token direct lookup
    final tier2 = <int, _ScoredWord>{};
    for (final token in tokens) {
      for (final word in await _repository.directArabicLookup(token)) {
        if (seen.containsKey(word.id)) continue;
        tier2.containsKey(word.id)
            ? tier2[word.id]!.matchCount++
            : tier2[word.id] = _ScoredWord(word: word, matchCount: 1);
      }
    }

    // Tier 3: per-token stemmer fallback
    final tier3 = <int, _ScoredWord>{};
    for (final token in tokens) {
      for (final word in await _stemmerFallback(token)) {
        if (seen.containsKey(word.id)) continue;
        if (tier2.containsKey(word.id)) continue;
        tier3.containsKey(word.id)
            ? tier3[word.id]!.matchCount++
            : tier3[word.id] = _ScoredWord(word: word, matchCount: 1);
      }
    }

    return [
      ...directResults,
      ..._sortScored(tier2),
      ..._sortScored(tier3),
    ].take(50).toList();
  }

  // ── Stemmer fallback ──────────────────────────────────────────────────────────
  //
  // TODO: swap _stemmer for Tashaphyne or AraBERT embeddings when ready.

  Future<List<Word>> _stemmerFallback(String query) async {
    final result = _stemmer.stem(query);
    if (!result.success) return [];

    if (result.rootForDB != null) {
      final exact = await _repository.exactRootLookup(result.rootForDB!);
      if (exact.isNotEmpty) return exact;

      final likeRoot = await _repository.likeRootLookup(result.rootForDB!);
      if (likeRoot.isNotEmpty) return likeRoot;
    }

    if (result.extractedRoot != null) {
      return _repository.likeFormLookup(result.extractedRoot!);
    }

    return [];
  }

  // ── English search ────────────────────────────────────────────────────────────

  Future<List<Word>> _searchEnglish(String query) async {
    String lowerQuery = query.toLowerCase().trim();
    // Strip "to " — common when users type English verb infinitives
    if (lowerQuery.startsWith('to ') && lowerQuery.length > 3) {
      lowerQuery = lowerQuery.substring(3).trim();
    }

    // Tokenize — skip single-char noise words ("a", "I")
    final tokens =
        lowerQuery.split(RegExp(r'\s+')).where((t) => t.length > 1).toList();
    if (tokens.isEmpty) return [];

    // Tier 1: full phrase
    final tier1 = await _repository.englishPhraseLookup(lowerQuery);
    final seen = <int>{for (final w in tier1) w.id};

    if (tokens.length == 1) return tier1; // phrase == token, done

    // Tier 2: per-token word-boundary matches (score ≥ 3)
    final tier2 = <int, _ScoredWord>{};
    for (final token in tokens) {
      for (final word
          in await _repository.englishTokenLookup(token, minScore: 3)) {
        if (seen.contains(word.id)) continue;
        tier2.containsKey(word.id)
            ? tier2[word.id]!.matchCount++
            : tier2[word.id] = _ScoredWord(word: word, matchCount: 1);
      }
    }
    final tier2Ids = tier2.keys.toSet();

    // Tier 3: per-token substring matches (score ≥ 1, not in tier 2)
    final tier3 = <int, _ScoredWord>{};
    for (final token in tokens) {
      for (final word
          in await _repository.englishTokenLookup(token, minScore: 1)) {
        if (seen.contains(word.id)) continue;
        if (tier2Ids.contains(word.id)) continue;
        tier3.containsKey(word.id)
            ? tier3[word.id]!.matchCount++
            : tier3[word.id] = _ScoredWord(word: word, matchCount: 1);
      }
    }

    return [
      ...tier1,
      ..._sortScored(tier2),
      ..._sortScored(tier3),
    ].take(50).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  List<Word> _sortScored(Map<int, _ScoredWord> scored) {
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
