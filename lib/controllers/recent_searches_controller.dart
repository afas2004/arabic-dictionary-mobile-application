// lib/controllers/recent_searches_controller.dart
//
// Persists the last 20 search queries so the empty state can show them.
// Use RecentSearchesController.load() at app startup; pass via
// RepositoryProvider so SearchScreen can read it from context.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentSearchesController extends ChangeNotifier {
  static const _key = 'recent_searches';
  static const _max = 20;

  List<String> _searches = [];
  List<String> get searches => List.unmodifiable(_searches);

  static Future<RecentSearchesController> load() async {
    final ctrl = RecentSearchesController();
    final prefs = await SharedPreferences.getInstance();
    ctrl._searches = prefs.getStringList(_key) ?? [];
    return ctrl;
  }

  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _searches.remove(q);
    _searches.insert(0, q);
    if (_searches.length > _max) _searches = _searches.sublist(0, _max);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(_key, _searches);
  }

  Future<void> remove(String query) async {
    _searches.remove(query);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(_key, _searches);
  }

  Future<void> clear() async {
    _searches.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.remove(_key);
  }
}
