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
//   Every search emits ONE structured [SEARCH] line:
//
//     [SEARCH] "query"             TIER               N result(s)  Xms     ram N/2000  Nq  XX% hit
//
//   TIER values:
//     CACHE HIT            — result served from RAM, no DB trip
//     T1-direct            — exact match in lexicon table (DB)
//     T1-direct(stm)       — exact lexicon match resolved inside the Stemmer
//     T2-conjugation       — conjugation table match inside the Stemmer
//     T3-6  clitic→lex     — clitic stripped → lexicon match (T3/T4/T5/T6)
//     T3-6  clitic→conj    — clitic stripped → conjugation match (T3/T4/T5/T6)
//     T7-fuzzyRoot         — Khoja pattern root extraction (low confidence)
//     MISS                 — all tiers failed, 0 results returned
//     MULTI(Nt)            — sentence input with N tokens, resolved independently
//     ENGLISH              — English search path (no tier cascade)
//
//   Every 25 searches a [STATS] dump is printed:
//
//     [STATS @25q]  CACHE HIT 52% avg 0ms | T1-direct 24% avg 8ms | ...
//                   |  ram 49/2000  evictions 0  lifetime-hit 67%
//
//   Cold-start banner in preWarm():
//
//     [STARTUP] pre-warm 87 keys from 100 words  in 45ms  |  ram 87/2000

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

  // ── Session-level logging state ───────────────────────────────────────────
  // _lastTier is set by _resolveToken / _stemmerFallback / _searchArabic /
  // _searchEnglish and read by search() to emit the unified [SEARCH] line.
  String _lastTier = 'MISS';

  int _totalSearches = 0;
  final _tierCounts   = <String, int>{};
  final _tierTotalMs  = <String, double>{};

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
    debugPrint(
      '[STARTUP] pre-warm ${_cache.size} keys from ${words.length} words'
      '  in ${sw.elapsedMilliseconds}ms'
      '  |  ram ${_cache.size}/${_cache.capacity}',
    );
    return words;
  }

  // ── Public search API ─────────────────────────────────────────────────────

  Future<List<Word>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final sw = Stopwatch()..start();
    _lastTier = 'MISS'; // default; overwritten by the path that resolves first

    // ── Tier 0: RAM cache (whole-query key) ──────────────────────────────────
    // Catches exact repeat searches and pre-warmed common-word lookups.
    final cached = _cache.get(trimmed);
    if (cached != null) {
      _lastTier = 'CACHE HIT';
      _logSearch(trimmed, _lastTier, cached.length, sw.elapsedMilliseconds);
      return cached;
    }

    final isArabic = RegExp(r'[؀-ۿ]').hasMatch(trimmed);
    final results  = isArabic
        ? await _searchArabic(trimmed)
        : await _searchEnglish(trimmed);

    // Write-through: cache the final merged result under the original query.
    if (results.isNotEmpty) _cache.put(trimmed, results);

    _logSearch(trimmed, _lastTier, results.length, sw.elapsedMilliseconds);
    return results;
  }

  // ── Arabic search ─────────────────────────────────────────────────────────

  Future<List<Word>> _searchArabic(String query) async {
    final stripped = CacheManager.normaliseKey(query);

    final tokens = stripped
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    // ── Single token ─────────────────────────────────────────────────────────
    if (tokens.length == 1) {
      return _resolveToken(stripped);
    }

    // ── Multi-token (sentence) ────────────────────────────────────────────────
    // Each token is resolved independently through the full cache→DB→stemmer
    // pipeline.  Results are scored by match count across tokens.
    final seen  = <int, Word>{};
    final tier2 = <int, _ScoredWord>{};
    final tier3 = <int, _ScoredWord>{};

    // Tier 1 equivalent: whole-phrase direct lookup
    final phraseResults = await _directLookup(stripped);
    for (final w in phraseResults) seen[w.id] = w;

    for (final token in tokens) {
      // Per-token: cache → DB (no stemmer for multi-token to keep it fast)
      final tokenResults = await _cachedDirectLookup(token);
      for (final w in tokenResults) {
        if (seen.containsKey(w.id)) continue;
        tier2.containsKey(w.id)
            ? tier2[w.id]!.matchCount++
            : tier2[w.id] = _ScoredWord(word: w, matchCount: 1);
      }
    }

    // Tier 3: stemmer fallback per token (only for tokens with no DB hit)
    for (final token in tokens) {
      final cachedToken = _cache.get(token);
      if (cachedToken != null && cachedToken.isNotEmpty) continue;
      for (final w in await _stemmerFallback(token)) {
        if (seen.containsKey(w.id)) continue;
        if (tier2.containsKey(w.id)) continue;
        tier3.containsKey(w.id)
            ? tier3[w.id]!.matchCount++
            : tier3[w.id] = _ScoredWord(word: w, matchCount: 1);
      }
    }

    // Label the whole query as MULTI — overwrites any per-token _lastTier.
    _lastTier = 'MULTI(${tokens.length}t)';

    return [
      ...phraseResults,
      ..._sortScored(tier2),
      ..._sortScored(tier3),
    ].take(50).toList();
  }

  // ── Token resolution (cache → DB → stemmer) ───────────────────────────────

  Future<List<Word>> _resolveToken(String token) async {
    // Tier 0: per-token cache check
    final cached = _cache.get(token);
    if (cached != null) {
      _lastTier = 'CACHE HIT';
      return cached;
    }

    // Tier 1: DB direct lookup
    final direct = await _directLookup(token);
    if (direct.isNotEmpty) {
      _cache.put(token, direct);
      _lastTier = 'T1-direct';
      return direct;
    }

    // Tier 2+: stemmer fallback (runs T1–T7 internally)
    // _lastTier is set inside _stemmerFallback based on StemSource.
    final stemmed = await _stemmerFallback(token);
    if (stemmed.isNotEmpty) _cache.put(token, stemmed);
    return stemmed;
  }

  /// Looks up [token] in cache; falls back to DB if not found.
  /// Writes DB results back to cache (write-through).
  /// Used for per-token multi-token resolution.
  Future<List<Word>> _cachedDirectLookup(String token) async {
    final cached = _cache.get(token);
    if (cached != null) return cached;
    final results = await _directLookup(token);
    if (results.isNotEmpty) _cache.put(token, results);
    return results;
  }

  Future<List<Word>> _directLookup(String token) =>
      _repository.directArabicLookup(token);

  // ── Stemmer fallback ──────────────────────────────────────────────────────
  //
  // The new 7-tier Stemmer already performs all DB lookups internally and
  // returns a resolved `lexicon.id` on success.  SearchManager's only job here
  // is to turn that id into a full `Word` for the UI layer.  On a fuzzy-root
  // hit we also broaden the result set via `exactRootLookup` so the detail
  // page has siblings to show.

  Future<List<Word>> _stemmerFallback(String query) async {
    final result = await _stemmer.resolve(query);

    if (!result.success || result.lexiconId == null) {
      _lastTier = 'MISS';
      return [];
    }

    // Fuzzy-root hits are low-confidence — broaden to all words sharing the
    // extracted root so the user has options.
    if (result.source == StemSource.fuzzyRoot && result.extractedRoot != null) {
      final dashed = result.extractedRoot!.split('').join('-');
      final words  = await _repository.exactRootLookup(dashed);
      if (words.isNotEmpty) {
        _lastTier = 'T7-fuzzyRoot';
        return words;
      }
      final like = await _repository.likeRootLookup(dashed);
      _lastTier  = like.isNotEmpty ? 'T7-fuzzyRoot' : 'MISS';
      return like;
    }

    // High-confidence hits (T1–T6) — return the single resolved base form.
    final word = await _repository.getWordById(result.lexiconId!);
    _lastTier  = _tierLabel(result.source);
    return word == null ? [] : [word];
  }

  // ── English search ────────────────────────────────────────────────────────

  Future<List<Word>> _searchEnglish(String query) async {
    _lastTier = 'ENGLISH';

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

  // ── Logging helpers ───────────────────────────────────────────────────────

  /// Emits one [SEARCH] line and, every 25 searches, a [STATS] summary.
  void _logSearch(String query, String tier, int resultCount, int ms) {
    _totalSearches++;
    _tierCounts[tier]  = (_tierCounts[tier]  ?? 0)   + 1;
    _tierTotalMs[tier] = (_tierTotalMs[tier] ?? 0.0) + ms;

    final q      = '"$query"'.padRight(24);
    final t      = tier.padRight(22);
    final r      = '$resultCount result${resultCount == 1 ? '' : 's'}'.padRight(12);
    final timing = ms < 1 ? '<1ms'.padRight(8) : '${ms}ms'.padRight(8);
    final fill   = 'ram ${_cache.size}/${_cache.capacity}';
    final rate   = '${(_cache.hitRate * 100).toStringAsFixed(0)}% hit';

    debugPrint('[SEARCH] $q  $t  $r  $timing  $fill  ${_totalSearches}q  $rate');

    if (_totalSearches % 25 == 0) _logStats();
  }

  /// Prints a tier-breakdown summary — called automatically every 25 searches.
  void _logStats() {
    final tierStats = _tierCounts.entries.map((e) {
      final pct = (_tierCounts[e.key]! / _totalSearches * 100)
          .toStringAsFixed(0)
          .padLeft(3);
      final avg = (_tierTotalMs[e.key]! / _tierCounts[e.key]!)
          .toStringAsFixed(0);
      return '${e.key} ${pct}% avg ${avg}ms';
    }).join(' | ');

    debugPrint(
      '[STATS @${_totalSearches}q]  $tierStats\n'
      '              |  ram ${_cache.size}/${_cache.capacity}'
      '  evictions ${_cache.evictions}'
      '  lifetime-hit ${(_cache.hitRate * 100).toStringAsFixed(0)}%',
    );
  }

  /// Maps a [StemSource] enum value to a human-readable tier label.
  static String _tierLabel(StemSource source) {
    switch (source) {
      case StemSource.directLexicon:
        return 'T1-direct(stm)';
      case StemSource.conjugationTable:
        return 'T2-conjugation';
      case StemSource.cliticStrippedLexicon:
        return 'T3-6  clitic→lex';
      case StemSource.cliticStrippedConjugation:
        return 'T3-6  clitic→conj';
      case StemSource.fuzzyRoot:
        return 'T7-fuzzyRoot';
      case StemSource.notFound:
        return 'MISS';
    }
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
