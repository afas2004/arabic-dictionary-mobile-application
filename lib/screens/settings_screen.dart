// lib/screens/settings_screen.dart
//
// Settings screen — currently exposes theme-colour personalisation only.
// Built as a stub so later additions (font size, Arabic font family,
// light/dark toggle, cache controls) can slot in without a rewrite.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/theme_controller.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeController controller;

  const SettingsScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Color primary = widget.controller.primaryColor;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          'Settings',
          style: GoogleFonts.manrope(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Theme color section ──────────────────────────────────────
          _SectionHeader(title: 'Theme color'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: ThemeController.swatches.map((c) {
              final bool selected = c.value == primary.value;
              return _SwatchTile(
                color: c,
                selected: selected,
                onTap: () => widget.controller.setPrimaryColor(c),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            'Changes the accent color used across the app. More personalisation '
            '(font size, light/dark mode) will land in a future version.',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: Colors.grey[500],
              height: 1.4,
            ),
          ),

          const SizedBox(height: 32),

          // ── About section ────────────────────────────────────────────
          _SectionHeader(title: 'About'),
          const SizedBox(height: 8),
          Text(
            'Arabic Dictionary · offline build',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Works fully offline. Search with diacritics or without, in Arabic '
            'or English — the stemmer handles conjugations and derivations.',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: Colors.grey[500],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.grey[700],
        letterSpacing: 0.3,
      ),
    );
  }
}

class _SwatchTile extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SwatchTile({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.black87 : Colors.transparent,
            width: 3,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}
