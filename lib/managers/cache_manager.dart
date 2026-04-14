// lib/managers/cache_manager.dart
//
// Hybrid LRU cache — RAM + disk tiers.
//
// ── Current status: SKELETON ──────────────────────────────────────────────────
//
// The interface is defined here so the rest of the architecture can already
// depend on it. Both tiers return null until implemented.
//
// ── Planned implementation ────────────────────────────────────────────────────
//
//   RAM tier  — dart:collection LinkedHashMap as LRU (fast, evicted on pressure)
//   Disk tier — shared_preferences or hive for JSON-serialised result lists
//
// ── Usage (future SearchManager integration) ─────────────────────────────────
//
//   final cached = await cacheManager.get(query);
//   if (cached != null) return cached;
//   final results = await ... DB query ...;
//   await cacheManager.put(query, results);
//   return results;

import '../models/models.dart';

class CacheManager {
  // RAM LRU — max entries before eviction
  static const int _ramCapacity = 200;

  // Disk TTL — cached entries older than this are ignored
  static const Duration _diskTtl = Duration(hours: 24);

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Returns cached search results for [key], or null on cache miss.
  /// Checks RAM first, then disk.
  Future<List<Word>?> get(String key) async {
    // TODO: check RAM LRU map
    // TODO: check disk cache (hive / shared_preferences)
    return null;
  }

  /// Stores [results] for [key] in both RAM and disk tiers.
  Future<void> put(String key, List<Word> results) async {
    // TODO: insert into RAM LRU (evict LRU entry if over _ramCapacity)
    // TODO: write to disk with timestamp
  }

  /// Removes a single entry from both tiers.
  Future<void> invalidate(String key) async {
    // TODO: remove from RAM map
    // TODO: delete from disk
  }

  /// Clears all cached entries (e.g. after a DB schema upgrade).
  Future<void> clear() async {
    // TODO: clear RAM map
    // TODO: wipe disk cache
  }
}
