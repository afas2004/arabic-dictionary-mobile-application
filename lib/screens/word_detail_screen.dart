// lib/screens/word_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

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
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: true,
          title: const SizedBox.shrink(),
          actions: [
            IconButton(
              icon: Icon(Icons.star_border, color: Color(0xFF1976D2)),
              onPressed: () {},
            ),
          ],
        ),
        body: BlocBuilder<WordDetailCubit, WordDetailState>(
          builder: (context, state) {
            if (state is WordDetailLoading) {
              return Center(child: CircularProgressIndicator());
            }
            if (state is WordDetailError) {
              return Center(child: Text(state.message));
            }
            if (state is WordDetailLoaded) {
              return SingleChildScrollView(
                child: Column(
                  children: [
                    _buildHeader(state.word),
                    _buildMeaningsList(state.meanings),
                    SizedBox(height: 24),
                    if (state.conjugationTable != null &&
                        state.conjugationTable!.past.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Conjugation',
                              style: GoogleFonts.manrope(
                                  fontSize: 13, color: Colors.grey),
                            ),
                            Text(
                              'التصريف',
                              style: GoogleFonts.notoNaskhArabic(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      _buildConjugationGrids(
                          state.conjugationTable!, state.word),
                    ],
                    SizedBox(height: 48),
                  ],
                ),
              );
            }
            return SizedBox.shrink();
          },
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  // ── Mutation letter helper ───────────────────────────────────────────────────
  //
  // Returns the set of letters that appear in conjugated forms as a result of
  // root weakness (hollow or defective).  These are coloured red in cells;
  // true root radicals remain blue; all other letters stay grey.

  static Set<String> _mutationLetters(Word word) {
    final parts = word.root
        .split('-')
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length != 3) return {};

    final r2 = parts[1];
    final r3 = parts[2];
    const weak = {'\u0648', '\u064A'}; // و ي

    // Hollow root (R2 is weak)
    if (weak.contains(r2)) {
      // Form III / Form V with hollow R2: و is a plain consonant → no mutations
      final s = word.formStripped
          .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
      final isFormIII = s.length == 4 && s.codeUnitAt(1) == 0x0627;
      final isFormV   = s.length == 4 && s.codeUnitAt(0) == 0x062A;
      if (isFormIII || isFormV) return {};

      // R2=و:  ا  appears as past-long vowel (mutation)
      //        ي  appears in present kasra context (و→ي)
      // R2=ي:  ا  appears as past-long vowel only; ي is the root letter itself
      return r2 == '\u0648'
          ? {'\u0627', '\u064A'} // ا + ي
          : {'\u0627'};          // ا only
    }

    // Defective root (R3 is weak)
    if (weak.contains(r3)) {
      return {'\u0649'}; // ى  alef-maqsura (U+0649) replaces R3 in past 3m.sg
    }

    return {};
  }

  Widget _buildHeader(Word word) {
    final readableType = Formatters.formatWordType(word.wordType);
    final bool showRoot = Formatters.shouldDisplayRoot(word);
    final bool isWeak   = Formatters.isWeakRoot(word);

    // Show root+mutation highlighting for any word with a triliteral root
    final triRoot = word.root.split('-').where((p) => p.isNotEmpty).length == 3;
    final mutations = _mutationLetters(word);

    return Container(
      width: double.infinity,
      color: Color(0xFFF8FAFC),
      padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          // Arabic form — root letters blue, mutation letters red, rest grey
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

          SizedBox(height: 8),

          // Meta row: root • type • form
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              if (showRoot) ...[
                if (isWeak)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                Text('•', style: TextStyle(color: Colors.grey)),
              ],
              Text(
                readableType,
                style: GoogleFonts.manrope(fontSize: 12, color: Colors.black54),
              ),
              if (Formatters.detectVerbFormLabel(word.formStripped) != null) ...[
                Text('•', style: TextStyle(color: Colors.grey)),
                Text(
                  Formatters.detectVerbFormLabel(word.formStripped)!,
                  textDirection: TextDirection.ltr,
                  style:
                      GoogleFonts.manrope(fontSize: 12, color: Colors.black54),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Meanings list ────────────────────────────────────────────────────────────

  Widget _buildMeaningsList(List<Meaning> meanings) {
    if (meanings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          'No meaning available.',
          style: GoogleFonts.manrope(fontSize: 14, color: Colors.grey[400]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: meanings.map((m) {
          // v7 meanings are already clean — simple trim only
          final cleaned = Formatters.cleanMeaning(m.meaningText);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              '${m.orderNum}. $cleaned',
              style: GoogleFonts.manrope(
                fontSize: 15,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Conjugation grids ────────────────────────────────────────────────────────

  Widget _buildConjugationGrids(ConjugationTable table, Word word) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Column(
        children: [
          _buildTenseBlock('Past Tense', 'الماضي', table.past, word),
          SizedBox(height: 16),
          _buildTenseBlock('Present Tense', 'المضارع', table.present, word),
          SizedBox(height: 16),
          _buildImperativeBlock(table.imperative, word),
        ],
      ),
    );
  }

  /// Find a conjugation form by person / number / gender.
  /// Returns '-' if not found so the table always renders gracefully.
  String _findConj(
    List<ConjugationRow> rows,
    String person,
    String number,
    String gender,
  ) {
    try {
      return rows
          .firstWhere((r) =>
              r.pronoun == person &&
              r.number == number &&
              r.gender == gender)
          .formArabic;
    } catch (_) {
      return '-';
    }
  }

  Widget _buildTenseBlock(
    String titleEn,
    String titleAr,
    List<ConjugationRow> rows,
    Word word,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Block header
          Container(
            color: Colors.grey[50],
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(titleEn,
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: Colors.grey)),
                Text(titleAr,
                    style: GoogleFonts.notoNaskhArabic(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),

          // Grid (RTL: right = masculine 3rd, left = feminine 2nd)
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
              // Column headers
              TableRow(
                decoration: BoxDecoration(color: Colors.white),
                children: [
                  _tableHeader('أنتِ\nYou (f)'),
                  _tableHeader('أنتَ\nYou (m)'),
                  _tableHeader('هي\nShe'),
                  _tableHeader('هو\nHe'),
                  _tableHeader(''),
                ],
              ),
              // Singular row
              TableRow(children: [
                _tableCell(_findConj(rows, '2nd', 'singular', 'feminine'), word),
                _tableCell(_findConj(rows, '2nd', 'singular', 'masculine'), word),
                _tableCell(_findConj(rows, '3rd', 'singular', 'feminine'), word),
                _tableCell(_findConj(rows, '3rd', 'singular', 'masculine'), word),
                _sideHeader('مفرد\nSing.'),
              ]),
              // Dual row — 2nd person dual is gender-neutral in Arabic
              TableRow(children: [
                _tableCell(_findConj(rows, '2nd', 'dual', 'common'), word),
                _tableCell(_findConj(rows, '2nd', 'dual', 'common'), word),
                _tableCell(_findConj(rows, '3rd', 'dual', 'feminine'), word),
                _tableCell(_findConj(rows, '3rd', 'dual', 'masculine'), word),
                _sideHeader('مثنى\nDual'),
              ]),
              // Plural row
              TableRow(children: [
                _tableCell(_findConj(rows, '2nd', 'plural', 'feminine'), word),
                _tableCell(_findConj(rows, '2nd', 'plural', 'masculine'), word),
                _tableCell(_findConj(rows, '3rd', 'plural', 'feminine'), word),
                _tableCell(_findConj(rows, '3rd', 'plural', 'masculine'), word),
                _sideHeader('جمع\nPlural'),
              ]),
            ],
          ),

          // 1st person row (below the main grid)
          Container(
            color: Colors.grey[50],
            child: Row(
              children: [
                Expanded(
                  child: _tableCellWithLabel(
                    'نحن (We)',
                    _findConj(rows, '1st', 'plural', 'common'),
                    word,
                  ),
                ),
                Container(width: 1, height: 50, color: Colors.grey[100]),
                Expanded(
                  child: _tableCellWithLabel(
                    'أنا (I)',
                    _findConj(rows, '1st', 'singular', 'common'),
                    word,
                  ),
                ),
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
          // Block header
          Container(
            color: Colors.grey[50],
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Imperative',
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: Colors.grey)),
                Text('الأمر',
                    style: GoogleFonts.notoNaskhArabic(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),

          // Singular row
          Row(
            children: [
              Expanded(
                child: _tableCellWithLabel(
                  'Singular (f)',
                  _findConj(rows, '2nd', 'singular', 'feminine'),
                  word,
                ),
              ),
              Container(width: 1, height: 50, color: Colors.grey[100]),
              Expanded(
                child: _tableCellWithLabel(
                  'Singular (m)',
                  _findConj(rows, '2nd', 'singular', 'masculine'),
                  word,
                ),
              ),
            ],
          ),
          Divider(height: 1, color: Colors.grey[100]),

          // Dual row
          Container(
            color: Colors.grey[50],
            child: _tableCellWithLabel(
              'Dual',
              _findConj(rows, '2nd', 'dual', 'common'),
              word,
            ),
          ),
          Divider(height: 1, color: Colors.grey[100]),

          // Plural row
          Row(
            children: [
              Expanded(
                child: _tableCellWithLabel(
                  'Plural (f)',
                  _findConj(rows, '2nd', 'plural', 'feminine'),
                  word,
                ),
              ),
              Container(width: 1, height: 50, color: Colors.grey[100]),
              Expanded(
                child: _tableCellWithLabel(
                  'Plural (m)',
                  _findConj(rows, '2nd', 'plural', 'masculine'),
                  word,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Table cell helpers ───────────────────────────────────────────────────────

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey[500],
        ),
      ),
    );
  }

  Widget _sideHeader(String text) {
    return Container(
      color: Colors.grey[50],
      padding: const EdgeInsets.all(8.0),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey[500],
          ),
        ),
      ),
    );
  }

  Widget _tableCell(String arabicText, Word word) {
    final baseStyle = GoogleFonts.notoNaskhArabic(
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );
    return Padding(
      padding: const EdgeInsets.all(8.0),
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
    final baseStyle = GoogleFonts.notoNaskhArabic(
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.manrope(fontSize: 10, color: Colors.grey[400]),
          ),
          SizedBox(height: 4),
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
