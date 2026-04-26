// lib/screens/settings_screen.dart
//
// Settings screen per ui_mockups_v2.html §6.
// Three sections:
//   • Appearance — theme colour swatches, text size (stub), dark mode
//   • Data       — clear recent searches, clear favourites
//   • About      — version row
//
// FavouritesController and RecentSearchesController are optional; when
// provided, the corresponding "Clear …" rows are interactive. If omitted
// (e.g. from older callers) the row is still shown but greyed out.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/favourites_controller.dart';
import '../controllers/recent_searches_controller.dart';
import '../controllers/theme_controller.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeController controller;
  final FavouritesController? favourites;
  final RecentSearchesController? recentSearches;

  const SettingsScreen({
    Key? key,
    required this.controller,
    this.favourites,
    this.recentSearches,
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _keyTextSize = 'text_size';
  double _textSize = 1.0; // 0.85 / 1.0 / 1.15

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onThemeChanged);
    _loadTextSize();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadTextSize() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble(_keyTextSize);
    if (v != null && mounted) setState(() => _textSize = v);
  }

  Future<void> _setTextSize(double v) async {
    setState(() => _textSize = v);
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble(_keyTextSize, v);
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: Text(body, style: GoogleFonts.manrope()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.manrope()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              action,
              style: GoogleFonts.manrope(
                color: Colors.red[700],
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.manrope()),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color primary = widget.controller.primaryColor;
    final bool isDark = widget.controller.isDark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ══════════════════════════════════════════════════════════════
          // Appearance
          // ══════════════════════════════════════════════════════════════
          const _SectionHeader(title: 'Appearance'),
          const SizedBox(height: 12),

          // Theme colour
          Text(
            'Theme colour',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: ThemeController.swatches.map((c) {
              final bool selected = c.toARGB32() == primary.toARGB32();
              return _SwatchTile(
                color: c,
                selected: selected,
                onTap: () => widget.controller.setPrimaryColor(c),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text(
            'Changes the accent colour. Your choice is saved across restarts.',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: Colors.grey[500],
              height: 1.4,
            ),
          ),

          const SizedBox(height: 20),

          // Text size (stub — persisted but not yet wired to MediaQuery)
          Text(
            'Text size',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<double>(
            segments: [
              ButtonSegment(
                value: 0.85,
                label: Text('Small',
                    style: GoogleFonts.manrope(fontSize: 12)),
              ),
              ButtonSegment(
                value: 1.0,
                label: Text('Default',
                    style: GoogleFonts.manrope(fontSize: 13)),
              ),
              ButtonSegment(
                value: 1.15,
                label: Text('Large',
                    style: GoogleFonts.manrope(fontSize: 14)),
              ),
            ],
            selected: {_textSize},
            onSelectionChanged: (s) => _setTextSize(s.first),
          ),

          const SizedBox(height: 8),

          // Dark mode
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Dark mode',
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Dims the UI for low-light reading.',
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
            value: isDark,
            activeThumbColor: Theme.of(context).colorScheme.primary,
            onChanged: (val) => widget.controller.setDarkMode(val),
          ),

          const SizedBox(height: 20),

          // ══════════════════════════════════════════════════════════════
          // Data
          // ══════════════════════════════════════════════════════════════
          const _SectionHeader(title: 'Data'),
          const SizedBox(height: 4),

          _SettingsRow(
            icon: Icons.history,
            title: 'Clear recent searches',
            subtitle: 'Removes the list shown on the search screen.',
            enabled: widget.recentSearches != null,
            onTap: () async {
              if (widget.recentSearches == null) return;
              final ok = await _confirm(
                'Clear recent searches?',
                'This removes your recent search history. '
                    'Favourites and settings are unaffected.',
                'Clear',
              );
              if (!ok) return;
              await widget.recentSearches!.clear();
              if (mounted) _toast('Recent searches cleared');
            },
          ),
          Divider(height: 1, color: Colors.grey[200]),
          _SettingsRow(
            icon: Icons.star_border,
            title: 'Clear favourites',
            subtitle: 'Removes every saved word.',
            enabled: widget.favourites != null,
            destructive: true,
            onTap: () async {
              if (widget.favourites == null) return;
              if (widget.favourites!.ids.isEmpty) {
                _toast('No favourites to clear');
                return;
              }
              final count = widget.favourites!.ids.length;
              final ok = await _confirm(
                'Clear all favourites?',
                'This permanently removes $count saved word'
                    '${count == 1 ? '' : 's'}. You can\'t undo this.',
                'Clear favourites',
              );
              if (!ok) return;
              await widget.favourites!.clear();
              if (mounted) _toast('Favourites cleared');
            },
          ),

          const SizedBox(height: 20),

          // ══════════════════════════════════════════════════════════════
          // About
          // ══════════════════════════════════════════════════════════════
          const _SectionHeader(title: 'About'),
          const SizedBox(height: 4),

          _SettingsRow(
            icon: Icons.info_outline,
            title: 'Version',
            trailing: '1.0.0',
          ),
          Divider(height: 1, color: Colors.grey[200]),
          _SettingsRow(
            icon: Icons.cloud_off_outlined,
            title: 'Offline build',
            subtitle:
                'Works fully offline. Search with or without diacritics, '
                'in Arabic or English — the stemmer handles conjugations '
                'and derivations.',
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Helper widgets
// ══════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.grey[600],
        letterSpacing: 0.6,
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool destructive;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor = enabled
        ? (destructive ? Colors.red[700]! : Colors.grey[700]!)
        : Colors.grey[400]!;
    final Color titleColor = enabled
        ? (destructive ? Colors.red[700]! : Colors.black87)
        : Colors.grey[400]!;

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: titleColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: Colors.grey[500],
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            if (onTap != null && trailing == null && enabled)
              Icon(Icons.chevron_right, size: 20, color: Colors.grey[400]),
          ],
        ),
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
