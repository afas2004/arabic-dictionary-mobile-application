// lib/screens/word_detail_screen.dart
//
// Three-tab detail page per ui_mockups_v2.html §3:
//   Verbs: Meaning | Conjugation | Relation
//   Non-verbs: Meaning | Forms | Relation
//
// The 4×3 conjugation grid (+ نحن/أنا strip) is preserved exactly as before.
// AppBar carries: back · copy-word (granular, lemma only) · favourite.
// The long-press action sheet on the search list still offers the richer
// copy variants (meaning, word+meaning, bundle, share).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arabic_dictionary/controllers/favourites_controller.dart';
import 'package:arabic_dictionary/cubits/word_detail_cubit.dart';
import 'package:arabic_dictionary/models/models.dart';
import 'package:arabic_dictionary/repositories/dictionary_repository.dart';
import 'package:arabic_dictionary/utils/formatters.dart';
import 'package:arabic_dictionary/utils/text_highlighter.dart';
import 'package:arabic_dictionary/engine/conjugation_engine.dart';

class WordDetailScreen extends StatelessWidget {
  final Word word;

  const WordDetailScreen({Key? key, required this.word}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => WordDetailCubit(
        repository: context.read<DictionaryRepository>(),
      )..loadDetails(word),
      child: BlocBuilder<WordDetailCubit, WordDetailState>(
        builder: (context, state) {
          if (state is WordDetailLoading) {
            return Scaffold(
              appBar: _buildAppBar(context, null),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          if (state is WordDetailError) {
            return Scaffold(
              appBar: _buildAppBar(context, null),
              body: Center(child: Text(state.message)),
            );
          }
          if (state is WordDetailLoaded) {
            final isVerb = state.word.wordType == 'base_verb';
            final middleTabLabel = isVerb ? 'Conjugation' : 'Forms';

            // Build the three pieces once, reuse them in both layouts.
            final header = _buildHeader(context, state.word);
            final tabBar = Container(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                labelStyle: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: GoogleFonts.manrope(fontSize: 13),
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Colors.grey[500],
                indicatorColor: Theme.of(context).colorScheme.primary,
                tabs: [
                  const Tab(text: 'Meaning'),
                  Tab(text: middleTabLabel),
                  const Tab(text: 'Relation'),
                ],
              ),
            );
            final tabView = TabBarView(
              children: [
                _MeaningTab(
                  word: state.word,
                  meanings: state.meanings,
                  conjugationTable: state.conjugationTable,
                  relatedForms: state.relatedForms,
                ),
                isVerb
                    ? _ConjugationTab(
                        table: state.conjugationTable,
                        word: state.word,
                      )
                    : _FormsTab(
                        word: state.word,
                        relatedForms: state.relatedForms,
                      ),
                _RelationTab(
                  rootFamily: state.rootFamily,
                  currentWord: state.word,
                ),
              ],
            );

            return DefaultTabController(
              length: 3,
              child: Scaffold(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                appBar: _buildAppBar(context, state.word),
                // Two-pane on wide screens (~landscape phones, tablets)
                // so the big Arabic header doesn't eat all the vertical
                // space and the user can keep the lemma in view while
                // scrolling the tab content.  Phone portrait stays on
                // the original top-stacked layout.
                body: LayoutBuilder(
                  builder: (context, constraints) {
                    const wideBreakpoint = 700.0;
                    if (constraints.maxWidth >= wideBreakpoint) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header column — fixed width, full height,
                          // scrollable in case content overflows on
                          // a small landscape viewport.
                          SizedBox(
                            width: 320,
                            child: SingleChildScrollView(child: header),
                          ),
                          Container(
                              width: 1,
                              color: Colors.grey[200]),
                          Expanded(
                            child: Column(
                              children: [
                                tabBar,
                                Expanded(child: tabView),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        header,
                        tabBar,
                        Expanded(child: tabView),
                      ],
                    );
                  },
                ),
              ),
            );
          }
          return Scaffold(appBar: _buildAppBar(context, null));
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, Word? loadedWord) {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black87),
        onPressed: () => Navigator.pop(context),
      ),
      centerTitle: true,
      title: const SizedBox.shrink(),
      actions: [
        if (loadedWord != null) ...[
          // Granular copy — copies the Arabic lemma only (no meaning).
          // Distinct from the long-press action sheet's bundle/meaning
          // variants per ui_mockups_v2 §3 and the original handoff.
          IconButton(
            icon: const Icon(Icons.content_copy_outlined, color: Colors.black87),
            tooltip: 'Copy word',
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: loadedWord.formArabic));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    'Copied ${loadedWord.formArabic}',
                    style: GoogleFonts.manrope(),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: context.read<FavouritesController>(),
            builder: (context, _) {
              final favs = context.read<FavouritesController>();
              final isFav = favs.isFavourite(loadedWord.id);
              return IconButton(
                icon: Icon(
                  isFav ? Icons.star : Icons.star_border,
                  color: Theme.of(context).colorScheme.primary,
                ),
                tooltip: isFav ? 'Remove from favourites' : 'Add to favourites',
                onPressed: () => favs.toggle(loadedWord.id),
              );
            },
          ),
        ],
      ],
    );
  }

  // ── Header (persists across all tabs) ───────────────────────────────────────

  static Set<String> mutationLettersFor(Word word) {
    final parts = word.root.split('-').where((p) => p.isNotEmpty).toList();
    if (parts.length != 3) return {};
    final r2 = parts[1];
    final r3 = parts[2];
    const weak = {'\u0648', '\u064A'};
    if (weak.contains(r2)) {
      final s = word.formStripped.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
      final isFormIII = s.length == 4 && s.codeUnitAt(1) == 0x0627;
      final isFormV   = s.length == 4 && s.codeUnitAt(0) == 0x062A;
      if (isFormIII || isFormV) return {};
      return r2 == '\u0648' ? {'\u0627', '\u064A'} : {'\u0627'};
    }
    if (weak.contains(r3)) return {'\u0649'};
    return {};
  }

  Widget _buildHeader(BuildContext context, Word word) {
    final bool showRoot = Formatters.shouldDisplayRoot(word);
    final bool isWeak   = Formatters.isWeakRoot(word);
    final triRoot = word.root.split('-').where((p) => p.isNotEmpty).length == 3;
    final mutations = mutationLettersFor(word);

    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          triRoot
              ? RichText(
                  text: TextSpan(
                    style: GoogleFonts.notoNaskhArabic(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                    ),
                    children: TextHighlighter.highlightRootWithMutations(
                      word.formArabic,
                      word.root,
                      mutationLetters: mutations,
                      // Per-user spec: paint mutations in the same blue as
                      // root letters for now.  The function still supports
                      // a separate red so we can reintroduce it later
                      // without code changes — only this call site moves.
                      mutationColor: TextHighlighter.matchColor,
                    ),
                  ),
                )
              : Text(
                  word.formArabic,
                  style: GoogleFonts.notoNaskhArabic(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
          if (word.formRomanized.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              word.formRomanized,
              style: GoogleFonts.manrope(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              if (showRoot) ...[
                if (isWeak)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Weak Root',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                    ),
                  )
                else
                  Text(
                    word.baseFormArabic ?? word.root.replaceAll('-', ''),
                    style: GoogleFonts.notoNaskhArabic(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                Text('•', style: TextStyle(color: Colors.grey[400])),
              ],
              Text(
                // Rich label (English · Arabic grammar term).  Detail page has
                // room for the long form per ui_mockups_v2 §3.
                Formatters.formatWordTypeRich(word.wordType),
                style: GoogleFonts.manrope(fontSize: 12, color: Colors.black54),
              ),
              if (Formatters.detectVerbFormLabel(word.formStripped) != null) ...[
                Text('•', style: TextStyle(color: Colors.grey[400])),
                Text(
                  Formatters.detectVerbFormLabel(word.formStripped)!,
                  textDirection: TextDirection.ltr,
                  style: GoogleFonts.manrope(fontSize: 12, color: Colors.black54),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Meaning tab ──────────────────────────────────────────────────────────────
// Numbered gloss list + compact callout:
//  • verbs → INITIAL TENSES (past / present / imperative 3rd-masc-sing)
//  • nouns with plural → PLURAL (singular → plural)

class _MeaningTab extends StatelessWidget {
  final Word word;
  final List<Meaning> meanings;
  final ConjugationTable? conjugationTable;
  final List<Word> relatedForms;

  const _MeaningTab({
    required this.word,
    required this.meanings,
    required this.conjugationTable,
    required this.relatedForms,
  });

  static bool _isPlural(Word w) {
    final t = w.wordType.toLowerCase();
    if (t.contains('plural')) return true;
    if ((w.number ?? '').toLowerCase() == 'plural') return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bool isVerb = word.wordType == 'base_verb';
    Word? plural;
    if (!isVerb) {
      for (final w in relatedForms) {
        if (_isPlural(w)) {
          plural = w;
          break;
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Meanings
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: meanings.isEmpty
                ? Text(
                    'No meaning available.',
                    style: GoogleFonts.manrope(fontSize: 14, color: Colors.grey[400]),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: meanings
                        .map((m) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${m.orderNum}. ${Formatters.cleanMeaning(m.meaningText)}',
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  color: Colors.black87,
                                  height: 1.5,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
          ),

          if (isVerb) ...[
            const SizedBox(height: 10),
            _InitialTensesCallout(word: word, table: conjugationTable),
          ] else if (plural != null) ...[
            const SizedBox(height: 10),
            _PluralCallout(singular: word, plural: plural),
          ],
        ],
      ),
    );
  }
}

class _CalloutHeader extends StatelessWidget {
  final String label;
  const _CalloutHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.manrope(
        fontSize: 11,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _InitialTensesCallout extends StatelessWidget {
  final Word word;
  final ConjugationTable? table;

  const _InitialTensesCallout({required this.word, required this.table});

  String _find(List<ConjugationRow> rows, String p, String n, String g) {
    try {
      return rows
          .firstWhere((r) => r.pronoun == p && r.number == n && r.gender == g)
          .formArabic;
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (table == null || table!.past.isEmpty) {
      return const SizedBox.shrink();
    }
    final past = _find(table!.past, '3rd', 'singular', 'masculine');
    final present = _find(table!.present, '3rd', 'singular', 'masculine');
    final imperative = _find(table!.imperative, '2nd', 'singular', 'masculine');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CalloutHeader('INITIAL TENSES'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFEEF0F3)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _tenseLabel('past'),
                    _tenseLabel('present'),
                    _tenseLabel('imperative'),
                  ],
                ),
                const SizedBox(height: 4),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _tenseForm(context, past, word),
                      _tenseForm(context, present, word),
                      _tenseForm(context, imperative, word),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tenseLabel(String s) => Text(
        s,
        style: GoogleFonts.manrope(fontSize: 11, color: Colors.grey[400]),
      );

  Widget _tenseForm(BuildContext context, String text, Word word) {
    final baseStyle = GoogleFonts.notoNaskhArabic(
      fontSize: 18,
      fontWeight: FontWeight.bold,
    );
    if (text == '—') {
      return Text(text, style: baseStyle.copyWith(color: Colors.grey[400]));
    }
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: TextHighlighter.highlightRootWithMutations(
          text,
          word.root,
          mutationLetters: WordDetailScreen.mutationLettersFor(word),
          mutationColor: TextHighlighter.matchColor,
          baseColor: Colors.black87,
        ),
      ),
    );
  }
}

class _PluralCallout extends StatelessWidget {
  final Word singular;
  final Word plural;

  const _PluralCallout({required this.singular, required this.plural});

  @override
  Widget build(BuildContext context) {
    final arStyle = GoogleFonts.notoNaskhArabic(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: Colors.black87,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CalloutHeader('PLURAL'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFEEF0F3)),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(singular.formArabic, style: arStyle),
                  Text('→', style: TextStyle(color: Colors.grey[400])),
                  Text(plural.formArabic, style: arStyle),
                ],
              ),
            ),
          ),
          if (plural.wordType.toLowerCase().contains('broken')) ...[
            const SizedBox(height: 4),
            Text(
              'broken plural',
              style: GoogleFonts.manrope(fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Relation tab ─────────────────────────────────────────────────────────────
// Root header + family grouped by POS (Verbs / Nouns / Participles / Adjectives / Other).

class _RelationTab extends StatelessWidget {
  final List<Word> rootFamily;
  final Word currentWord;

  const _RelationTab({required this.rootFamily, required this.currentWord});

  static String _groupFor(Word w) {
    final t = w.wordType.toLowerCase();
    if (t == 'base_verb') return 'Verbs';
    if (t.contains('participle')) return 'Participles';
    if (t.contains('adjective') || t == 'comparative') return 'Adjectives';
    if (t == 'verbal_noun' ||
        t.contains('noun') ||
        t.contains('plural')) {
      return 'Nouns';
    }
    return 'Other';
  }

  static const _groupOrder = ['Verbs', 'Nouns', 'Participles', 'Adjectives', 'Other'];

  @override
  Widget build(BuildContext context) {
    if (rootFamily.isEmpty) {
      return Center(
        child: Text(
          'No root family found.',
          style: GoogleFonts.manrope(color: Colors.grey[400], fontSize: 14),
        ),
      );
    }

    final Map<String, List<Word>> groups = {};
    for (final w in rootFamily) {
      groups.putIfAbsent(_groupFor(w), () => []).add(w);
    }

    final primary = Theme.of(context).colorScheme.primary;
    final rootLetters = currentWord.root
        .split('-')
        .where((p) => p.isNotEmpty)
        .join(' ');

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Root header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: const Color(0xFFF9FAFB),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rootLetters.isEmpty ? currentWord.root : rootLetters,
                textDirection: TextDirection.rtl,
                style: GoogleFonts.notoNaskhArabic(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: primary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'root family · ${rootFamily.length} entries',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),

        // Grouped sections
        for (final group in _groupOrder)
          if (groups[group] != null && groups[group]!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                group,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[700],
                ),
              ),
            ),
            for (final w in groups[group]!)
              _RelationCard(word: w, currentWord: currentWord),
          ],
      ],
    );
  }
}

class _RelationCard extends StatelessWidget {
  final Word word;
  final Word currentWord;

  const _RelationCard({required this.word, required this.currentWord});

  @override
  Widget build(BuildContext context) {
    final isCurrent = word.id == currentWord.id;
    final meaning = Formatters.cleanMeaning(word.primaryMeaning ?? '');

    return InkWell(
      onTap: isCurrent
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => WordDetailScreen(word: word)),
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              word.formArabic,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.notoNaskhArabic(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isCurrent
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black87,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('·', style: TextStyle(color: Colors.grey[400])),
            ),
            Expanded(
              child: Text(
                meaning,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Conjugation tab (verbs) ──────────────────────────────────────────────────
// Preserved 4×3 grid + نحن/أنا strip + imperative block exactly as before.

class _ConjugationTab extends StatelessWidget {
  final ConjugationTable? table;
  final Word word;

  const _ConjugationTab({required this.table, required this.word});

  @override
  Widget build(BuildContext context) {
    // For any verb we always render the Past / Present / Imperative
    // scaffold — even if the conjugation engine returned no rows.  The
    // empty cells render as "—" via [_findConj], so the user still sees
    // the structure of the paradigm and can tell which slot is missing,
    // rather than a blank tab.  This addresses the case where the engine
    // fails to populate a particular lemma but the verb itself is real.
    final past = table?.past ?? const <ConjugationRow>[];
    final present = table?.present ?? const <ConjugationRow>[];
    final imperative = table?.imperative ?? const <ConjugationRow>[];
    final everythingEmpty =
        past.isEmpty && present.isEmpty && imperative.isEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        children: [
          if (everythingEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Conjugation paradigm not available for this entry — '
                'showing the empty scaffold for reference.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: Colors.grey[500],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
          _buildTenseBlock('Past Tense', 'الماضي', past, word),
          const SizedBox(height: 16),
          _buildTenseBlock('Present Tense', 'المضارع', present, word),
          const SizedBox(height: 16),
          _buildImperativeBlock(imperative, word),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  String _findConj(List<ConjugationRow> rows, String person, String number, String gender) {
    try {
      return rows.firstWhere(
        (r) => r.pronoun == person && r.number == number && r.gender == gender,
      ).formArabic;
    } catch (_) {
      return '-';
    }
  }

  Widget _buildTenseBlock(String titleEn, String titleAr, List<ConjugationRow> rows, Word word) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            color: Colors.grey[50],
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(titleEn, style: GoogleFonts.manrope(fontSize: 12, color: Colors.grey)),
                Text(titleAr, style: GoogleFonts.notoNaskhArabic(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),
          Table(
            border: TableBorder.all(color: Colors.grey[100]!),
            columnWidths: const {
              0: FlexColumnWidth(1),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
              4: IntrinsicColumnWidth(),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Colors.white),
                children: [
                  _tableHeader('أنتِ\nYou (f)'),
                  _tableHeader('أنتَ\nYou (m)'),
                  _tableHeader('هي\nShe'),
                  _tableHeader('هو\nHe'),
                  _tableHeader(''),
                ],
              ),
              TableRow(children: [
                _tableCell(_findConj(rows, '2nd', 'singular', 'feminine'), word),
                _tableCell(_findConj(rows, '2nd', 'singular', 'masculine'), word),
                _tableCell(_findConj(rows, '3rd', 'singular', 'feminine'), word),
                _tableCell(_findConj(rows, '3rd', 'singular', 'masculine'), word),
                _sideHeader('مفرد\nSing.'),
              ]),
              TableRow(children: [
                _tableCell(_findConj(rows, '2nd', 'dual', 'common'), word),
                _tableCell(_findConj(rows, '2nd', 'dual', 'common'), word),
                _tableCell(_findConj(rows, '3rd', 'dual', 'feminine'), word),
                _tableCell(_findConj(rows, '3rd', 'dual', 'masculine'), word),
                _sideHeader('مثنى\nDual'),
              ]),
              TableRow(children: [
                _tableCell(_findConj(rows, '2nd', 'plural', 'feminine'), word),
                _tableCell(_findConj(rows, '2nd', 'plural', 'masculine'), word),
                _tableCell(_findConj(rows, '3rd', 'plural', 'feminine'), word),
                _tableCell(_findConj(rows, '3rd', 'plural', 'masculine'), word),
                _sideHeader('جمع\nPlural'),
              ]),
            ],
          ),
          Container(
            color: Colors.grey[50],
            child: Row(
              children: [
                Expanded(child: _tableCellWithLabel('نحن (We)', _findConj(rows, '1st', 'plural', 'common'), word)),
                Container(width: 1, height: 50, color: Colors.grey[100]),
                Expanded(child: _tableCellWithLabel('أنا (I)', _findConj(rows, '1st', 'singular', 'common'), word)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImperativeBlock(List<ConjugationRow> rows, Word word) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            color: Colors.grey[50],
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Imperative', style: GoogleFonts.manrope(fontSize: 12, color: Colors.grey)),
                Text('الأمر', style: GoogleFonts.notoNaskhArabic(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),
          Row(
            children: [
              Expanded(child: _tableCellWithLabel('Singular (f)', _findConj(rows, '2nd', 'singular', 'feminine'), word)),
              Container(width: 1, height: 50, color: Colors.grey[100]),
              Expanded(child: _tableCellWithLabel('Singular (m)', _findConj(rows, '2nd', 'singular', 'masculine'), word)),
            ],
          ),
          Divider(height: 1, color: Colors.grey[100]),
          Container(
            color: Colors.grey[50],
            child: _tableCellWithLabel('Dual', _findConj(rows, '2nd', 'dual', 'common'), word),
          ),
          Divider(height: 1, color: Colors.grey[100]),
          Row(
            children: [
              Expanded(child: _tableCellWithLabel('Plural (f)', _findConj(rows, '2nd', 'plural', 'feminine'), word)),
              Container(width: 1, height: 50, color: Colors.grey[100]),
              Expanded(child: _tableCellWithLabel('Plural (m)', _findConj(rows, '2nd', 'plural', 'masculine'), word)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[500]),
      ),
    );
  }

  Widget _sideHeader(String text) {
    return Container(
      color: Colors.grey[50],
      padding: const EdgeInsets.all(8),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[500]),
        ),
      ),
    );
  }

  Widget _tableCell(String arabicText, Word word) {
    final baseStyle = GoogleFonts.notoNaskhArabic(fontSize: 16, fontWeight: FontWeight.bold);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: arabicText == '-'
          ? Text('-', textAlign: TextAlign.center, style: baseStyle.copyWith(color: Colors.grey[400]))
          : RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: baseStyle,
                children: TextHighlighter.highlightRootWithMutations(
                  arabicText,
                  word.root,
                  mutationLetters: WordDetailScreen.mutationLettersFor(word),
                  mutationColor: TextHighlighter.matchColor,
                  baseColor: Colors.black87,
                ),
              ),
            ),
    );
  }

  Widget _tableCellWithLabel(String label, String arabicText, Word word) {
    final baseStyle = GoogleFonts.notoNaskhArabic(fontSize: 16, fontWeight: FontWeight.bold);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(label, style: GoogleFonts.manrope(fontSize: 10, color: Colors.grey[400])),
          const SizedBox(height: 4),
          arabicText == '-'
              ? Text('-', style: baseStyle.copyWith(color: Colors.grey[400]))
              : RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: baseStyle,
                    children: TextHighlighter.highlightRootWithMutations(
                      arabicText,
                      word.root,
                      mutationLetters: WordDetailScreen.mutationLettersFor(word),
                      mutationColor: TextHighlighter.matchColor,
                      baseColor: Colors.black87,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// ── Forms tab (non-verbs) ─────────────────────────────────────────────────────
// Labeled rows per ui_mockups_v2.html §3 phone 7:
//   Singular / Dual / Plural / Diminutive / Definite / Nisba
// Each row pulls from relatedForms when available; otherwise the Definite
// row is computed (ال + singular) and missing ones show "—".

class _FormsTab extends StatelessWidget {
  final Word word;
  final List<Word> relatedForms;

  const _FormsTab({required this.word, required this.relatedForms});

  Word? _findByPredicate(bool Function(Word) pred) {
    for (final w in relatedForms) {
      if (pred(w)) return w;
    }
    return null;
  }

  bool _isDual(Word w) {
    final t = w.wordType.toLowerCase();
    if (t.contains('dual')) return true;
    if ((w.number ?? '').toLowerCase() == 'dual') return true;
    return false;
  }

  bool _isPlural(Word w) {
    final t = w.wordType.toLowerCase();
    if (t.contains('plural')) return true;
    if ((w.number ?? '').toLowerCase() == 'plural') return true;
    return false;
  }

  bool _isDiminutive(Word w) {
    return w.wordType.toLowerCase().contains('diminutive');
  }

  bool _isNisba(Word w) {
    final t = w.wordType.toLowerCase();
    if (t.contains('nisba') || t == 'adjective_mansoub') return true;
    // Heuristic: ending in يّ (yeh + shadda)
    final s = w.formArabic;
    if (s.endsWith('\u064A\u0651') || s.endsWith('\u064A\u0651\u0629')) {
      return true;
    }
    return false;
  }

  String _computeDefinite(String singular) {
    if (singular.startsWith('\u0627\u0644')) return singular;
    return '\u0627\u0644$singular';
  }

  @override
  Widget build(BuildContext context) {
    final dual       = _findByPredicate(_isDual);
    final plural     = _findByPredicate(_isPlural);
    final diminutive = _findByPredicate(_isDiminutive);
    final nisba      = _findByPredicate(_isNisba);

    // If nothing to show beyond singular, render a friendly empty-state
    // rather than a column of "—" rows.
    final hasAnyForm =
        dual != null || plural != null || diminutive != null || nisba != null;
    if (!hasAnyForm) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No additional forms recorded for this word.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(color: Colors.grey[400], fontSize: 14),
          ),
        ),
      );
    }

    final rows = <_FormRow>[
      _FormRow('Singular', word.formArabic),
      _FormRow('Dual', dual?.formArabic),
      _FormRow('Plural', plural?.formArabic),
      _FormRow('Diminutive', diminutive?.formArabic),
      _FormRow('Definite', _computeDefinite(word.formArabic)),
      _FormRow('Nisba', nisba?.formArabic),
    ];

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
      itemBuilder: (context, i) {
        final r = rows[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                r.label,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: Colors.grey[500],
                ),
              ),
              Text(
                r.value ?? '—',
                textDirection: TextDirection.rtl,
                style: GoogleFonts.notoNaskhArabic(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: r.value == null ? Colors.grey[400] : Colors.black87,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FormRow {
  final String label;
  final String? value;
  const _FormRow(this.label, this.value);
}
