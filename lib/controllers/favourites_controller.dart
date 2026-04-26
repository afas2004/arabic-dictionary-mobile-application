// lib/controllers/favourites_controller.dart
//
// Persists starred word IDs via SharedPreferences.
// FavouritesScreen fetches the full Word objects by ID from the repository.
// Use FavouritesController.load() at app startup; pass via RepositoryProvider.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavouritesController extends ChangeNotifier {
  static const _key = 'favourites';

  List<int> _ids = [];
  List<int> get ids => List.unmodifiable(_ids);

  static Future<FavouritesController> load() async {
    final ctrl = FavouritesController();
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    ctrl._ids = list.map((s) => int.tryParse(s)).whereType<int>().toList();
    return ctrl;
  }

  bool isFavourite(int id) => _ids.contains(id);

  Future<void> toggle(int id) async {
    if (_ids.contains(id)) {
      _ids.remove(id);
    } else {
      _ids.insert(0, id);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(_key, _ids.map((i) => i.toString()).toList());
  }

  /// Remove all favourites. Used by the "Clear favourites" action in Settings.
  Future<void> clear() async {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.remove(_key);
  }
}
