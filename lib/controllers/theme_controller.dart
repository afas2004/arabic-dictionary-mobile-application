// lib/controllers/theme_controller.dart
//
// Lightweight theme controller that owns the app's primary color.
// Consumed by MaterialApp (wrapped in AnimatedBuilder) and by SettingsScreen
// to let users change the accent/primary color at runtime.
//
// This is intentionally a minimal stub:
//   - No persistence yet — color resets to default on app restart.
//   - Future: wire SharedPreferences so the choice survives restarts.
//   - Future: add font-size, Arabic font family, light/dark toggle.
//
// Exposed via MultiRepositoryProvider in main.dart so any screen can read
// and mutate the current theme with `context.read<ThemeController>()`.

import 'package:flutter/material.dart';

class ThemeController extends ChangeNotifier {
  /// Swatches offered in the settings screen. The first entry is the default.
  /// Ordering matches the mockups (blue, green, red, purple, orange, slate).
  static const List<Color> swatches = [
    Color(0xFF1976D2), // Blue (default — matches v1 app theme)
    Color(0xFF2E7D32), // Green
    Color(0xFFC62828), // Red
    Color(0xFF6A1B9A), // Purple
    Color(0xFFE65100), // Orange
    Color(0xFF455A64), // Slate
  ];

  Color _primaryColor = swatches.first;

  /// Current primary / accent colour used by the app theme.
  Color get primaryColor => _primaryColor;

  /// Updates the primary colour and notifies listeners.
  /// No-op if the colour is already selected.
  void setPrimaryColor(Color color) {
    if (_primaryColor.value == color.value) return;
    _primaryColor = color;
    notifyListeners();
  }
}
