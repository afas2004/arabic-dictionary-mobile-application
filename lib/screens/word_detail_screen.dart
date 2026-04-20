// lib/screens/word_detail_screen.dart
//
// Three-tab detail page: Grammar | Root | Conjugation (verbs) / Forms (non-verbs).
// The conjugation grid (4×3 + نحن/أنا strip) is preserved exactly as before.
// The copy icon in the header copies the Arabic headword only (no meaning).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
              appBar: _buildAppBar(context, null, null),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          if (state is WordDetailError) {
            return Scaffold(
              appBar: _buildAppBar(context, null, null),
              body: Center(child: Text(state.message)),
            );
          }
          if (state is WordDetailLoaded) {
            final isVerb = state.word.wordType == 'base_verb';
            final thirdTab = isVerb ? 'Conjugation' : 'Forms';

            return DefaultTabController(
              length: 3,
              child: Scaffold(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                appBar: _buildAppBar(context, state.word, state.conjugationTable),
                body: Column(
                  children: [
                    _buildHeader(context, state.word),
                    Container(
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
                          const Tab(text: 'Grammar'),
                          const Tab(text: 'Root'),
                          Tab(text: thirdTab),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _GrammarTab(word: state.word, meanings: state.meanings),
                          _RootTab(rootFamily: state.rootFamily, currentWord: state.word),
                          isVerb
                              ? _ConjugationTab(
                                  table: state.conjugationTable,
                                  word: state.word,
                                )
                              : _FormsTab(relatedForms: state.relatedForms),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return Scaffold(appBar: _buildAppBar(context, null, null));
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    Word? loadedWord,
    ConjugationTable? table,
  ) {
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
          // Copy Arabic headword only
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 20),
            color: Colors.grey[600],
            tooltip: 'Copy word',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: loadedWord.formArabic));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Word copied'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          // Favourite star
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
                onPressed: () => favs.toggle(loadedWord.id),
              );
            },
          ),
        ],
      ],
    );
  }

  // ── Header (persists across all tabs) ───────────────────────────────────────

  static Set<String> _mutationLetters(Word word) {
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
    final mutations = _mutationLetters(word);

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
                Formatters.formatWordType(word.wordType),
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

// ── Grammar tab ──────────────────────────────────────────────────────────────

class _GrammarTab extends StatelessWidget {
  final Word word;
  final List<Meaning> meanings;

  const _GrammarTab({required this.word, required this.meanings});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Meanings
          if (meanings.isEmpty)
            Text(
              'No meaning available.',
              style: GoogleFonts.manrope(fontSize: 14, color: Colors.grey[400]),
            )
          else
            ...meanings.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${m.orderNum}. ${Formatters.cleanMeaning(m.meaningText)}',
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                )),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),

          // Grammar metadata
          _GrammarRow(label: 'Part of speech', value: word.partOfSpeech),
          _GrammarRow(label: 'Word type', value: Formatters.formatWordType(word.wordType)),
          if (Formatters.detectVerbFormLabel(word.formStripped) != null)
            _GrammarRow(
              label: 'Verb form',
              value: Formatters.detectVerbFormLabel(word.formStripped)!,
            ),
          if (word.voice != null && word.voice!.isNotEmpty)
            _GrammarRow(label: 'Voice', value: word.voice!),
          if (word.tense != null && word.tense!.isNotEmpty)
            _GrammarRow(label: 'Tense', value: word.tense!),
          if (word.gender != null && word.gender!.isNotEmpty)
            _GrammarRow(label: 'Gender', value: word.gender!),
          if (word.domain != null && word.domain!.isNotEmpty)
            _GrammarRow(label: 'Domain', value: word.domain!),
          if (word.isCommon)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                children: [
                  Text(
                    'Frequency',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GrammarRow extends StatelessWidget {
  final String label;
  final String value;

  const _GrammarRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.manrope(fontSize: 13, color: Colors.grey[500]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Root tab ─────────────────────────────────────────────────────────────────

class _RootTab extends StatelessWidget {
  final List<Word> rootFamily;
  final Word currentWord;

  const _RootTab({required this.rootFamily, required this.currentWord});

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

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rootFamily.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
      itemBuilder: (context, i) {
        final w = rootFamily[i];
        final isCurrent = w.id == currentWord.id;
        return InkWell(
          onTap: isCurrent
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WordDetailScreen(word: w),
                    ),
                  ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left: word type + COMMON badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Formatters.formatWordType(w.wordType),
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: isCurrent
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[500],
                      ),
                    ),
                    if (w.isCommon)
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'COMMON',
                          style: GoogleFonts.manrope(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                  ],
                ),
                // Right: Arabic word + meaning
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        w.formArabic,
                        style: GoogleFonts.notoNaskhArabic(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black87,
                        ),
                      ),
                      if (w.primaryMeaning != null &&
                          w.primaryMeaning!.isNotEmpty)
                        Text(
                          w.primaryMeaning!,
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Conjugation tab ───────────────────────────────────────────────────────────
// Wraps the existing 4×3 grid exactly as before.

class _ConjugationTab extends StatelessWidget {
  final ConjugationTable? table;
  final Word word;

  const _ConjugationTab({required this.table, required this.word});

  @override
  Widget build(BuildContext context) {
    if (table == null || table!.past.isEmpty) {
      return Center(
        child: Text(
          'No conjugation data.',
          style: GoogleFonts.manrope(color: Colors.grey[400], fontSize: 14),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        children: [
          _buildTenseBlock('Past Tense', 'الماضي', table!.past, word),
          const SizedBox(height: 16),
          _buildTenseBlock('Present Tense', 'المضارع', table!.present, word),
          const SizedBox(height: 16),
          _buildImperativeBlock(table!.imperative, word),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  static Set<String> _mutationLetters(Word word) {
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
                  mutationLetters: _mutationLetters(word),
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
                      mutationLetters: _mutationLetters(word),
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

class _FormsTab extends StatelessWidget {
  final List<Word> relatedForms;

  const _FormsTab({required this.relatedForms});

  @override
  Widget build(BuildContext context) {
    if (relatedForms.isEmpty) {
      return Center(
        child: Text(
          'No additional forms.',
          style: GoogleFonts.manrope(color: Colors.grey[400], fontSize: 14),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: relatedForms.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
      itemBuilder: (context, i) {
        final w = relatedForms[i];
        return InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => WordDetailScreen(word: w)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  Formatters.formatWordType(w.wordType),
                  style: GoogleFonts.manrope(fontSize: 12, color: Colors.grey[500]),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      w.formArabic,
                      style: GoogleFonts.notoNaskhArabic(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (w.primaryMeaning != null && w.primaryMeaning!.isNotEmpty)
                      Text(
                        w.primaryMeaning!,
                        style: GoogleFonts.manrope(fontSize: 13, color: Colors.grey[600]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
