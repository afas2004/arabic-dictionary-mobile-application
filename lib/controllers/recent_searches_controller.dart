// lib/controllers/recent_searches_controller.dart
//
// Persists the last 20 search queries with timestamps so the empty state can
// show them with relative-time labels ("2 min ago", "yesterday", …).
// Use RecentSearchesController.load() at app startup; pass via
// ChangeNotifierProvider so SearchScreen can read it from context.
//
// Storage format: a single StringList where each entry is "<unixMs>|<query>".
// Kept as StringList (not JSON) to avoid pulling in dart:convert just for this.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentSearch {
  final String query;
  final DateTime time;

  const RecentSearch(this.query, this.time);

  String encode() => '${time.millisecondsSinceEpoch}|$query';

  static RecentSearch? decode(String raw) {
    final i = raw.indexOf('|');
    if (i <= 0) {
      // Legacy entry without timestamp — treat as "a while ago"
      return raw.isEmpty ? null : RecentSearch(raw, DateTime.fromMillisecondsSinceEpoch(0));
    }
    final ts = int.tryParse(raw.substring(0, i));
    if (ts == null) return null;
    return RecentSearch(raw.substring(i + 1), DateTime.fromMillisecondsSinceEpoch(ts));
  }
}

class RecentSearchesController extends ChangeNotifier {
  static const _key = 'recent_searches';
  static const _max = 20;

  List<RecentSearch> _searches = [];
  List<RecentSearch> get searches => List.unmodifiable(_searches);

  /// Backwards-compatible view: just the query strings.
  List<String> get queries => _searches.map((r) => r.query).toList();

  static Future<RecentSearchesController> load() async {
    final ctrl = RecentSearchesController();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    ctrl._searches = raw
        .map(RecentSearch.decode)
        .whereType<RecentSearch>()
        .toList();
    return ctrl;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(_key, _searches.map((r) => r.encode()).toList());
  }

  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _searches.removeWhere((r) => r.query == q);
    _searches.insert(0, RecentSearch(q, DateTime.now()));
    if (_searches.length > _max) {
      _searches = _searches.sublist(0, _max);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String query) async {
    _searches.removeWhere((r) => r.query == query);
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    _searches.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.remove(_key);
  }

  /// Human-readable relative time: "2 min ago", "yesterday", "3 days ago".
  static String relativeTime(DateTime t, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final diff = n.difference(t);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) {
      final w = (diff.inDays / 7).floor();
      return '$w week${w == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 365) {
      final m = (diff.inDays / 30).floor();
      return '$m month${m == 1 ? '' : 's'} ago';
    }
    final y = (diff.inDays / 365).floor();
    return '$y year${y == 1 ? '' : 's'} ago';
  }
}
