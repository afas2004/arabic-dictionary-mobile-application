// lib/screens/search_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arabic_dictionary/controllers/favourites_controller.dart';
import 'package:arabic_dictionary/controllers/recent_searches_controller.dart';
import 'package:arabic_dictionary/controllers/theme_controller.dart';
import 'package:arabic_dictionary/cubits/search_cubit.dart';
import 'package:arabic_dictionary/models/models.dart';
import 'package:arabic_dictionary/engine/conjugation_engine.dart';
import 'package:arabic_dictionary/repositories/dictionary_repository.dart';
import 'package:arabic_dictionary/utils/formatters.dart';
import 'package:arabic_dictionary/utils/text_highlighter.dart';
import 'favourites_screen.dart';
import 'settings_screen.dart';
import 'word_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isArabicInput = true;
  Timer? _debounce;
  Set<String> _activeFilters = {};

  @override
  void initState() {
    super.initState();
    context.read<SearchCubit>().loadInitial();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<String> _extractTokens(String query) {
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1)
        .toSet()
        .toList();
  }

  List<Word> _applyFilters(List<Word> words, String query) {
    if (_activeFilters.isEmpty) return words;
    return words.where((w) {
      final meaning = (w.primaryMeaning ?? '').toLowerCase();
      return _activeFilters.any((f) => meaning.contains(f));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'قاموس عربي',
          style: GoogleFonts.notoNaskhArabic(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // Favourites
          AnimatedBuilder(
            animation: context.read<FavouritesController>(),
            builder: (context, _) {
              final count = context.read<FavouritesController>().ids.length;
              return IconButton(
                icon: count > 0
                    ? Badge(
                        label: Text('$count'),
                        child: const Icon(Icons.star_border),
                      )
                    : const Icon(Icons.star_border),
                color: Colors.grey[700],
                tooltip: 'Favourites',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FavouritesScreen(
                        controller: context.read<FavouritesController>(),
                        repository: context.read<DictionaryRepository>(),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          // Settings
          IconButton(
            icon: Icon(Icons.settings_outlined, color: Colors.grey[700]),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    controller: context.read<ThemeController>(),
                  ),
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              textAlign: _isArabicInput ? TextAlign.right : TextAlign.left,
              textDirection:
                  _isArabicInput ? TextDirection.rtl : TextDirection.ltr,
              onChanged: (val) {
                final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(val);
                final hasLatin = RegExp(r'[a-zA-Z]').hasMatch(val);
                if (hasLatin && !hasArabic && _isArabicInput) {
                  setState(() => _isArabicInput = false);
                } else if (hasArabic && !_isArabicInput) {
                  setState(() => _isArabicInput = true);
                } else if (val.isEmpty && !_isArabicInput) {
                  setState(() => _isArabicInput = true);
                }
                // Reset filters when query changes
                if (_activeFilters.isNotEmpty) {
                  setState(() => _activeFilters = {});
                }
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  context.read<SearchCubit>().search(val);
                });
              },
              decoration: InputDecoration(
                hintText: 'ابحث عن كلمة...',
                hintStyle: GoogleFonts.notoNaskhArabic(color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: EdgeInsets.zero,
                prefixIcon: IconButton(
                  icon: Icon(Icons.close, color: Colors.grey[400], size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _activeFilters = {});
                    context.read<SearchCubit>().loadInitial();
                  },
                ),
                suffixIcon: Icon(
                  Icons.search,
                  color: Theme.of(context).colorScheme.primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: BlocConsumer<SearchCubit, SearchState>(
        listener: (context, state) {
          // Save to recent searches when we get a non-empty result
          if (state is SearchLoaded && state.query.trim().isNotEmpty) {
            context.read<RecentSearchesController>().add(state.query);
          }
        },
        builder: (context, state) {
          if (state is SearchLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is SearchError) {
            return Center(child: Text('Error: ${state.message}'));
          }
          if (state is SearchEmpty) {
            return _buildEmptyState(context);
          }
          if (state is SearchLoaded) {
            if (state.words.isEmpty) {
              return _buildNoResultsState(context, state.query);
            }

            final isEnglish = !RegExp(r'[\u0600-\u06FF]').hasMatch(state.query);
            final tokens = isEnglish ? _extractTokens(state.query) : <String>[];
            final showChips = tokens.length >= 2;
            final displayed = _applyFilters(state.words, state.query);

            return Column(
              children: [
                if (showChips) _buildFilterChips(tokens),
                Expanded(
                  child: displayed.isEmpty
                      ? Center(
                          child: Text(
                            'No results for selected filter.',
                            style: GoogleFonts.manrope(
                              color: Colors.grey[400],
                              fontSize: 14,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: displayed.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: Colors.grey[200]),
                          itemBuilder: (context, index) => _buildWordTile(
                            context,
                            displayed[index],
                            state.query,
                          ),
                        ),
                ),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    final recents = context.read<RecentSearchesController>().searches;

    if (recents.isEmpty) {
      return Center(
        child: Text(
          'Search anything in Arabic/English...',
          style: GoogleFonts.manrope(color: Colors.grey[400], fontSize: 16),
        ),
      );
    }

    return AnimatedBuilder(
      animation: context.read<RecentSearchesController>(),
      builder: (context, _) {
        final searches =
            context.read<RecentSearchesController>().searches;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[600],
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        context.read<RecentSearchesController>().clear(),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Clear',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: searches.length,
                itemBuilder: (context, i) {
                  final q = searches[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.history,
                        size: 18, color: Colors.grey[400]),
                    title: Text(
                      q,
                      style: GoogleFonts.manrope(
                          fontSize: 14, color: Colors.black87),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.close,
                          size: 16, color: Colors.grey[400]),
                      onPressed: () =>
                          context.read<RecentSearchesController>().remove(q),
                    ),
                    onTap: () {
                      _searchController.text = q;
                      context.read<SearchCubit>().search(q);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ── No-results state ─────────────────────────────────────────────────────────

  Widget _buildNoResultsState(BuildContext context, String query) {
    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(query);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'No results found.',
              style: GoogleFonts.manrope(
                  fontSize: 16, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            Text(
              isArabic
                  ? 'Try without diacritics, or search by root letters only.'
                  : 'Try a different spelling, or search in Arabic.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 13, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  // ── Token filter chips ───────────────────────────────────────────────────────

  Widget _buildFilterChips(List<String> tokens) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.grey[50],
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tokens.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final t = tokens[i];
          final active = _activeFilters.contains(t);
          return FilterChip(
            label: Text(
              t,
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: active
                    ? Colors.white
                    : Colors.grey[700],
              ),
            ),
            selected: active,
            onSelected: (val) {
              setState(() {
                if (val) {
                  _activeFilters.add(t);
                } else {
                  _activeFilters.remove(t);
                }
              });
            },
            selectedColor: Theme.of(context).colorScheme.primary,
            backgroundColor: Colors.grey[200],
            checkmarkColor: Colors.white,
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  // ── Word tile ────────────────────────────────────────────────────────────────

  Widget _buildWordTile(BuildContext context, Word word, String query) {
    final isArabicSearch = RegExp(r'[\u0600-\u06FF]').hasMatch(query);
    final String displayMeaning =
        Formatters.cleanMeaning(word.primaryMeaning ?? '');
    final String readableType = Formatters.formatWordType(word.wordType);
    final bool showRoot = Formatters.shouldDisplayRoot(word);
    final bool isWeak = Formatters.isWeakRoot(word);

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WordDetailScreen(word: word)),
      ),
      onLongPress: () => _showWordActions(context, word),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Left: root / weak tag + COMMON badge ──────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (showRoot) ...[
                  if (!isWeak)
                    Text(
                      'from',
                      style:
                          GoogleFonts.manrope(fontSize: 11, color: Colors.grey[500]),
                    ),
                  if (isWeak)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Weak Root',
                        style: GoogleFonts.manrope(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[700],
                        ),
                      ),
                    )
                  else
                    Text(
                      word.baseFormArabic ?? word.root.replaceAll('-', ''),
                      style: GoogleFonts.notoNaskhArabic(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                ],
                if (word.isCommon)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'COMMON',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                if (!showRoot && !word.isCommon) const SizedBox(width: 40),
              ],
            ),

            // ── Right: word details (RTL) ──────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '(${word.formRomanized})',
                        style: GoogleFonts.manrope(
                            fontSize: 12, color: Colors.grey[400]),
                      ),
                      const SizedBox(width: 8),
                      RichText(
                        text: TextSpan(
                          style: GoogleFonts.notoNaskhArabic(
                              fontSize: 20, fontWeight: FontWeight.bold),
                          children: isArabicSearch
                              ? TextHighlighter.highlightArabicForList(
                                  word.formArabic,
                                  query,
                                  word.root,
                                  baseColor: Colors.black87)
                              : [
                                  TextSpan(
                                    text: word.formArabic,
                                    style:
                                        const TextStyle(color: Colors.black87),
                                  )
                                ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        readableType,
                        style: GoogleFonts.manrope(
                            fontSize: 11, color: Colors.grey[500]),
                      ),
                      if (Formatters.detectVerbFormLabel(word.formStripped) !=
                          null)
                        Text(
                          ' • ${Formatters.detectVerbFormLabel(word.formStripped)!}',
                          textDirection: TextDirection.ltr,
                          style: GoogleFonts.manrope(
                              fontSize: 11, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  RichText(
                    textAlign: TextAlign.right,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: GoogleFonts.manrope(
                          fontSize: 14, color: Colors.grey[600]),
                      children: !isArabicSearch
                          ? TextHighlighter.highlightQuery(
                              displayMeaning, query,
                              baseColor: Colors.grey[600]!)
                          : [TextSpan(text: displayMeaning)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Long-press action sheet ──────────────────────────────────────────────────

  void _showWordActions(BuildContext context, Word word) {
    final favs = context.read<FavouritesController>();
    final repo = context.read<DictionaryRepository>();
    final isFav = favs.isFavourite(word.id);
    final meaning = word.primaryMeaning ?? '';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _WordActionSheet(
        word: word,
        meaning: meaning,
        isFavourite: isFav,
        repository: repo,
        onToggleFav: () => favs.toggle(word.id),
      ),
    );
  }
}

// ── Action sheet widget ──────────────────────────────────────────────────────

class _WordActionSheet extends StatelessWidget {
  final Word word;
  final String meaning;
  final bool isFavourite;
  final DictionaryRepository repository;
  final VoidCallback onToggleFav;

  const _WordActionSheet({
    required this.word,
    required this.meaning,
    required this.isFavourite,
    required this.repository,
    required this.onToggleFav,
  });

  void _copy(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(label), duration: const Duration(seconds: 1)),
    );
  }

  Future<String> _buildBundle() async {
    final firstLine = '${word.formArabic}: $meaning';
    if (word.wordType != 'base_verb') return firstLine;

    try {
      final table = await repository.getConjugationTable(word);
      if (table == null || table.past.isEmpty) return firstLine;

      String _find(List<ConjugationRow> rows, String p, String n, String g) {
        try {
          return rows.firstWhere(
            (r) => r.pronoun == p && r.number == n && r.gender == g,
          ).formArabic;
        } catch (_) {
          return '';
        }
      }

      final past = _find(table.past, '3rd', 'singular', 'masculine');
      final present = _find(table.present, '3rd', 'singular', 'masculine');
      final imp = _find(table.imperative, '2nd', 'singular', 'masculine');
      final forms = [past, present, imp].where((s) => s.isNotEmpty).join('، ');
      if (forms.isEmpty) return firstLine;
      return '$firstLine\n$forms';
    } catch (_) {
      return firstLine;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Word header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    meaning,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                        fontSize: 13, color: Colors.grey[500]),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  word.formArabic,
                  style: GoogleFonts.notoNaskhArabic(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _ActionTile(
            icon: Icons.copy_outlined,
            label: 'Copy word',
            onTap: () => _copy(context, word.formArabic, 'Word copied'),
          ),
          _ActionTile(
            icon: Icons.notes_outlined,
            label: 'Copy meaning',
            onTap: () => _copy(context, meaning, 'Meaning copied'),
          ),
          _ActionTile(
            icon: Icons.content_copy_outlined,
            label: 'Copy word + meaning',
            onTap: () => _copy(
              context,
              '${word.formArabic}: $meaning',
              'Copied',
            ),
          ),
          _ActionTile(
            icon: Icons.library_books_outlined,
            label: 'Copy bundle',
            onTap: () async {
              final bundle = await _buildBundle();
              if (context.mounted) _copy(context, bundle, 'Bundle copied');
            },
          ),
          _ActionTile(
            icon: isFavourite ? Icons.star : Icons.star_border,
            label: isFavourite ? 'Remove from favourites' : 'Add to favourites',
            onTap: () {
              onToggleFav();
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[700], size: 22),
      title: Text(
        label,
        style: GoogleFonts.manrope(fontSize: 14, color: Colors.black87),
      ),
      onTap: onTap,
      dense: true,
    );
  }
}
