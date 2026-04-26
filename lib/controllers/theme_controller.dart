// lib/controllers/theme_controller.dart
//
// Owns the app's primary color, dark-mode flag, and text scale.
// Persists all three to SharedPreferences so they survive restarts.
// Exposed via ChangeNotifierProvider in main.dart; consumed by SettingsScreen
// directly and via AnimatedBuilder in MyApp (which rebuilds MaterialApp on
// any change).

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static const _keyColor     = 'theme_primary_color';
  static const _keyDark      = 'theme_dark_mode';
  static const _keyTextScale = 'text_size';

  static const List<Color> swatches = [
    Color(0xFF1976D2), // Blue (default)
    Color(0xFF2E7D32), // Green
    Color(0xFFC62828), // Red
    Color(0xFF6A1B9A), // Purple
    Color(0xFFE65100), // Orange
    Color(0xFF455A64), // Slate
  ];

  /// Allowed text-scale values.  Tied to the SegmentedButton in
  /// SettingsScreen — keep in sync if you add another step.
  static const List<double> textScales = [0.85, 1.0, 1.15];
  static const double defaultTextScale = 1.0;

  Color  _primaryColor;
  bool   _isDark;
  double _textScale;

  ThemeController({
    Color? primaryColor,
    bool isDark = false,
    double textScale = defaultTextScale,
  })  : _primaryColor = primaryColor ?? swatches.first,
        _isDark       = isDark,
        _textScale    = textScale;

  Color  get primaryColor => _primaryColor;
  bool   get isDark       => _isDark;
  double get textScale    => _textScale;

  /// Load persisted values from SharedPreferences and return a ready controller.
  static Future<ThemeController> load() async {
    final prefs    = await SharedPreferences.getInstance();
    final colorVal = prefs.getInt(_keyColor);
    final isDark   = prefs.getBool(_keyDark) ?? false;
    final scale    = prefs.getDouble(_keyTextScale) ?? defaultTextScale;

    Color primary = swatches.first;
    if (colorVal != null) {
      primary = swatches.firstWhere(
        (c) => c.toARGB32() == colorVal,
        orElse: () => swatches.first,
      );
    }
    // Defensive: clamp to allowed values so a hand-edited pref can't
    // produce a wildly oversized UI.
    final safeScale = textScales.contains(scale) ? scale : defaultTextScale;
    return ThemeController(
      primaryColor: primary,
      isDark: isDark,
      textScale: safeScale,
    );
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

  /// Persists [scale] and notifies listeners.  Out-of-range values are
  /// silently clamped to [defaultTextScale] so we can never produce a
  /// crash-on-render layout from corrupted prefs.
  void setTextScale(double scale) async {
    final safe = textScales.contains(scale) ? scale : defaultTextScale;
    if (_textScale == safe) return;
    _textScale = safe;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble(_keyTextScale, safe);
  }
}
