// lib/controllers/theme_controller.dart
//
// Owns the app's primary color and dark-mode flag.
// Persists both to SharedPreferences so they survive restarts.
// Exposed via RepositoryProvider in main.dart; consumed by SettingsScreen
// and via AnimatedBuilder in MyApp.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static const _keyColor = 'theme_primary_color';
  static const _keyDark  = 'theme_dark_mode';

  static const List<Color> swatches = [
    Color(0xFF1976D2), // Blue (default)
    Color(0xFF2E7D32), // Green
    Color(0xFFC62828), // Red
    Color(0xFF6A1B9A), // Purple
    Color(0xFFE65100), // Orange
    Color(0xFF455A64), // Slate
  ];

  Color _primaryColor;
  bool  _isDark;

  ThemeController({Color? primaryColor, bool isDark = false})
      : _primaryColor = primaryColor ?? swatches.first,
        _isDark = isDark;

  Color get primaryColor => _primaryColor;
  bool  get isDark       => _isDark;

  /// Load persisted values from SharedPreferences and return a ready controller.
  static Future<ThemeController> load() async {
    final prefs    = await SharedPreferences.getInstance();
    final colorVal = prefs.getInt(_keyColor);
    final isDark   = prefs.getBool(_keyDark) ?? false;

    Color primary = swatches.first;
    if (colorVal != null) {
      primary = swatches.firstWhere(
        (c) => c.toARGB32() == colorVal,
        orElse: () => swatches.first,
      );
    }
    return ThemeController(primaryColor: primary, isDark: isDark);
  }

  void setPrimaryColor(Color color) async {
    if (_primaryColor.toARGB32() == color.toARGB32()) return;
    _primaryColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt(_keyColor, color.toARGB32());
  }

  void setDarkMode(bool value) async {
    if (_isDark == value) return;
    _isDark = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool(_keyDark, value);
  }
}
