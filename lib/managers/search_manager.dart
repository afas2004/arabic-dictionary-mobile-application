// lib/managers/search_manager.dart
//
// Business-layer search orchestrator.
//
// Sits between the Cubits (presentation) and DictionaryRepository (data).
// Owns all search logic: script detection, normalisation, tokenisation,
// cache lookup, tier ranking, deduplication, and stemmer fallback.
// The repository is called only for raw DB queries — no SQL lives here.
//
// ── Search tiers (Arabic) ─────────────────────────────────────────────────────
//
//   Tier 0 — RAM cache        (< 1 ms)
//   Tier 1 — DB direct lookup (~10–40 ms)
//   Tier 2 — Stemmer + DB     (~60–200 ms)
//
// ── Multi-token (sentence input) ─────────────────────────────────────────────
//
//   Each token is resolved independently through Tier 0 → 1 → 2.
//   Results are scored by how many tokens a word matched and merged.
//   No sentence-level cache key is stored (near-zero hit rate).
//
// ── Performance logging ───────────────────────────────────────────────────────
//
//   [PERF] lines are emitted via debugPrint for each tier hit.
//   Use these for report benchmarking:
//     [PERF] cache hit   : Xµs
//     [PERF] db direct   : Xµs
//     [PERF] stemmer     : Xµs
//     [PERF] total       : Xms

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../repositories/dictionary_repository.dart';
import '../engine/stemmer.dart';
import 'cache_manager.dart';

class SearchManager {
  final DictionaryRepository _repository;
  final Stemmer              _stemmer;
  final CacheManager         _cache;

  bool _preWarmed = false;

  SearchManager({
    required DictionaryRepository repository,
    required Stemmer stemmer,
    required CacheManager cache,
  })  : _repository = repository,
        _stemmer    = stemmer,
        _cache      = cache;

  // ── Pre-warm ──────────────────────────────────────────────────────────────

  /// Loads all common words from the DB into the RAM cache.
  ///
  /// Idempotent — subsequent calls return [] immediately without touching
  /// the DB again.  Returns the word list so [SearchCubit.loadInitial] can
  /// display it directly, avoiding a second round-trip.
  Future<List<Word>> preWarm() async {
    if (_preWarmed) return [];
    _preWarmed = true;

    final sw    = Stopwatch()..start();
    final words = await _repository.getCommonWords();
    _cache.preWarm(words);
    debugPrint('[CACHE] pre-warm done in ${sw.elapsedMilliseconds}ms '
        '— cache size: ${_cache.size}');
    return words;
  }

  // ── Public search API ─────────────────────────────────────────────────────

  Future<List<Word>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final sw = Stopwatch()..start();

    // ── Tier 0: RAM cache (whole-query key) ──────────────────────────────────
    // Catches exact repeat searches and pre-warmed common-word lookups.
    final cached = _cache.get(trimmed);
    if (cached != null) {
      debugPrint('[PERF] cache hit   : ${sw.elapsedMicroseconds}µs  "$trimmed"');
      return cached;
    }

    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(trimmed);
    final results  = isArabic
        ? await _searchArabic(trimmed, sw)
        : await _searchEnglish(trimmed, sw);

    // Write-through: cache the final merged result under the original query.
    if (results.isNotEmpty) _cache.put(trimmed, results);

    debugPrint('[PERF] total       : ${sw.elapsedMilliseconds}ms  '
        '"$trimmed" → ${results.length} results');
    return results;
  }

  // ── Arabic search ─────────────────────────────────────────────────────────

  Future<List<Word>> _searchArabic(String query, Stopwatch sw) async {
    final stripped = CacheManager.normaliseKey(query);

    final tokens = stripped
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    // ── Single token ─────────────────────────────────────────────────────────
    if (tokens.length == 1) {
      return _resolveToken(stripped, sw);
    }

    // ── Multi-token (sentence) ────────────────────────────────────────────────
    // Each token is resolved independently through the full cache→DB→stemmer
    // pipeline.  Results are scored by match count across tokens.
    final seen = <int, Word>{};
    final tier2 = <int, _ScoredWord>{};
    final tier3 = <int, _ScoredWord>{};

    // Tier 1 equivalent: whole-phrase direct lookup
    final phraseResults = await _directLookup(stripped, sw);
    for (final w in phraseResults) seen[w.id] = w;

    for (final token in tokens) {
      // Per-token: cache → DB (no stemmer for multi-token to keep it fast)
      final tokenResults = await _cachedDirectLookup(token, sw);
      for (final w in tokenResults) {
        if (seen.containsKey(w.id)) continue;
        tier2.containsKey(w.id)
            ? tier2[w.id]!.matchCount++
            : tier2[w.id] = _ScoredWord(word: w, matchCount: 1);
      }
    }

    // Tier 3: stemmer fallback per token (only for tokens with no DB hit)
    for (final token in tokens) {
      if (_cache.get(token) != null) continue; // already resolved above
      for (final w in await _stemmerFallback(token, sw)) {
        if (seen.containsKey(w.id)) continue;
        if (tier2.containsKey(w.id)) continue;
        tier3.containsKey(w.id)
            ? tier3[w.id]!.matchCount++
            : tier3[w.id] = _ScoredWord(word: w, matchCount: 1);
      }
    }

    return [
      ...phraseResults,
      ..._sortScored(tier2),
      ..._sortScored(tier3),
    ].take(50).toList();
  }

  // ── Token resolution (cache → DB → stemmer) ───────────────────────────────

  Future<List<Word>> _resolveToken(String token, Stopwatch sw) async {
    // Tier 0: per-token cache check
    final cached = _cache.get(token);
    if (cached != null) {
      debugPrint('[PERF] cache hit   : ${sw.elapsedMicroseconds}µs  "$token"');
      return cached;
    }

    // Tier 1: DB direct lookup
    final direct = await _directLookup(token, sw);
    if (direct.isNotEmpty) {
      _cache.put(token, direct);
      debugPrint('[PERF] db direct   : ${sw.elapsedMilliseconds}ms  "$token"');
      return direct;
    }

    // Tier 2: stemmer fallback
    final stemmed = await _stemmerFallback(token, sw);
    if (stemmed.isNotEmpty) _cache.put(token, stemmed);
    debugPrint('[PERF] stemmer     : ${sw.elapsedMilliseconds}ms  "$token"');
    return stemmed;
  }

  /// Looks up [token] in cache; falls back to DB if not found.
  /// Writes DB results back to cache (write-through).
  /// Used for per-token multi-token resolution.
  Future<List<Word>> _cachedDirectLookup(String token, Stopwatch sw) async {
    final cached = _cache.get(token);
    if (cached != null) return cached;
    final results = await _directLookup(token, sw);
    if (results.isNotEmpty) _cache.put(token, results);
    return results;
  }

  Future<List<Word>> _directLookup(String token, Stopwatch sw) async {
    final t0 = sw.elapsedMicroseconds;
    final results = await _repository.directArabicLookup(token);
    debugPrint('[PERF] db direct   : ${sw.elapsedMicroseconds - t0}µs  "$token"');
    return results;
  }

  // ── Stemmer fallback ──────────────────────────────────────────────────────
  //
  // The new 7-tier Stemmer already performs all DB lookups internally and
  // returns a resolved `lexicon.id` on success.  SearchManager's only job here
  // is to turn that id into a full `Word` for the UI layer.  On a fuzzy-root
  // hit we also broaden the result set via `exactRootLookup` so the detail
  // page has siblings to show.

  Future<List<Word>> _stemmerFallback(String query, Stopwatch sw) async {
    final t0     = sw.elapsedMicroseconds;
    final result = await _stemmer.resolve(query);
    if (!result.success || result.lexiconId == null) {
      debugPrint('[PERF] stemmer     : ${sw.elapsedMicroseconds - t0}µs  '
          '"$query" → miss');
      return [];
    }

    // Fuzzy-root hits are low-confidence — broaden to all words sharing the
    // extracted root so the user has options.
    if (result.source == StemSource.fuzzyRoot && result.extractedRoot != null) {
      final dashed = result.extractedRoot!.split('').join('-');
      final words = await _repository.exactRootLookup(dashed);
      if (words.isNotEmpty) {
        debugPrint('[PERF] stemmer     : ${sw.elapsedMicroseconds - t0}µs  '
            '"$query" → fuzzyRoot ${words.length} results');
        return words;
      }
      final like = await _repository.likeRootLookup(dashed);
      debugPrint('[PERF] stemmer     : ${sw.elapsedMicroseconds - t0}µs  '
          '"$query" → fuzzyRoot-like ${like.length} results');
      return like;
    }

    // High-confidence hits (T1–T6) — return the single resolved base form.
    final word = await _repository.getWordById(result.lexiconId!);
    debugPrint('[PERF] stemmer     : ${sw.elapsedMicroseconds - t0}µs  '
        '"$query" → ${result.source.name} id=${result.lexiconId}');
    return word == null ? [] : [word];
  }

  // ── English search ────────────────────────────────────────────────────────

  Future<List<Word>> _searchEnglish(String query, Stopwatch sw) async {
    String lowerQuery = query.toLowerCase().trim();
    if (lowerQuery.startsWith('to ') && lowerQuery.length > 3) {
      lowerQuery = lowerQuery.substring(3).trim();
    }

    final tokens =
        lowerQuery.split(RegExp(r'\s+')).where((t) => t.length > 1).toList();
    if (tokens.isEmpty) return [];

    final tier1 = await _repository.englishPhraseLookup(lowerQuery);
    final seen  = <int>{for (final w in tier1) w.id};

    if (tokens.length == 1) return tier1;

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

  // ── Helpers ───────────────────────────────────────────────────────────────

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
