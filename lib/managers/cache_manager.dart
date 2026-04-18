// lib/managers/cache_manager.dart
//
// Two-level search result cache.
//
// ── Architecture ──────────────────────────────────────────────────────────────
//
//   RAM tier  — dart:collection LinkedHashMap used as an LRU cache.
//               O(1) get and put.  Evicts the least-recently-used entry when
//               capacity is reached.
//
//   Disk tier — intentionally omitted.  The SQLite database already acts as
//               the persistent tier; a separate disk cache would be a redundant
//               copy with no meaningful cold-start benefit.
//
// ── Key normalisation ──────────────────────────────────────────────────────────
//
//   All keys are normalised before storage or lookup:
//     1. Trim whitespace
//     2. Strip diacritics (U+064B – U+065F, U+0670)
//     3. Collapse alef variants (أ إ آ ٱ) → plain alef (ا)
//
//   This ensures كَتَبَ, كتب, and أكتب (if same root) all map to the same key
//   and both the pre-warm indexer and runtime search share cache entries.
//
// ── Pre-warm ──────────────────────────────────────────────────────────────────
//
//   On cold start SearchManager calls preWarm(commonWords).
//   Each word is indexed under its normalised form_stripped so the most
//   frequent searches return instantly without a DB round-trip.
//
// ── Performance logging ───────────────────────────────────────────────────────
//
//   CacheManager itself does not log.  SearchManager wraps each tier with a
//   Stopwatch and emits [PERF] lines via debugPrint for report benchmarking.

import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LRU CACHE
// ─────────────────────────────────────────────────────────────────────────────

class _LruCache<K, V> {
  final int capacity;

  // LinkedHashMap preserves insertion order.
  // Convention: tail = most recently used, head = least recently used.
  final _map = LinkedHashMap<K, V>();

  _LruCache(this.capacity) : assert(capacity > 0);

  /// Returns the value for [key], promoting it to most-recently-used.
  /// Returns null on a cache miss.
  V? get(K key) {
    if (!_map.containsKey(key)) return null;
    final v = _map.remove(key)!; // pull from current position
    _map[key] = v;               // re-insert at tail (MRU)
    return v;
  }

  /// Stores [value] under [key].
  /// Evicts the LRU entry if capacity is reached.
  void put(K key, V value) {
    _map.remove(key);                // remove stale entry if present
    if (_map.length >= capacity) {
      _map.remove(_map.keys.first); // evict LRU (head)
    }
    _map[key] = value;              // insert at tail (MRU)
  }

  void remove(K key) => _map.remove(key);
  void clear()       => _map.clear();
  int  get length    => _map.length;
}

// ─────────────────────────────────────────────────────────────────────────────
// CACHE MANAGER
// ─────────────────────────────────────────────────────────────────────────────

class CacheManager {
  // 2 000 entries ≈ 3–5 MB RAM — covers all common words plus a typical
  // session's worth of unique queries with room to spare.
  static const int _ramCapacity = 2000;

  final _ram = _LruCache<String, List<Word>>(_ramCapacity);

  // ── Key normalisation (static — shared with SearchManager) ───────────────

  static String normaliseKey(String query) => query
      .trim()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')       // diacritics
      .replaceAll(RegExp(r'[\u0623\u0625\u0622\u0671]'), '\u0627'); // أإآٱ → ا

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns cached results for [query], or null on a miss.
  List<Word>? get(String query) => _ram.get(normaliseKey(query));

  /// Stores [results] under the normalised form of [query].
  void put(String query, List<Word> results) =>
      _ram.put(normaliseKey(query), results);

  /// Removes the entry for [query] from the cache.
  void invalidate(String query) => _ram.remove(normaliseKey(query));

  /// Clears all cached entries (e.g. after a DB schema upgrade).
  void clear() => _ram.clear();

  /// Number of entries currently in the RAM cache.
  int get size => _ram.length;

  // ── Pre-warm ──────────────────────────────────────────────────────────────

  /// Populates the cache from [commonWords] fetched at startup.
  ///
  /// Words are grouped by their normalised form_stripped so a search for
  /// "كتب" immediately returns all common words with that stripped form
  /// without hitting the DB.
  ///
  /// Pre-warm entries may be partial (only common words, not all DB variants).
  /// The first real DB search for a key will overwrite with a full result set
  /// via write-through.
  void preWarm(List<Word> commonWords) {
    final groups = <String, List<Word>>{};
    for (final word in commonWords) {
      final key = normaliseKey(word.formStripped);
      groups.putIfAbsent(key, () => []).add(word);
    }
    for (final entry in groups.entries) {
      _ram.put(entry.key, entry.value);
    }
    debugPrint('[CACHE] pre-warmed ${groups.length} keys '
        'from ${commonWords.length} common words');
  }
}
