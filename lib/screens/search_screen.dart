// lib/screens/search_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arabic_dictionary/cubits/search_cubit.dart';
import 'package:arabic_dictionary/models/models.dart';
import 'package:arabic_dictionary/utils/formatters.dart';
import 'package:arabic_dictionary/utils/text_highlighter.dart';
import 'word_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isArabicInput = true; // tracks current script for TextField direction

  @override
  void initState() {
    super.initState();
    context.read<SearchCubit>().loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'قاموس عربي',
          style: GoogleFonts.notoNaskhArabic(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(60.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              textAlign: _isArabicInput ? TextAlign.right : TextAlign.left,
              textDirection: _isArabicInput ? TextDirection.rtl : TextDirection.ltr,
              onChanged: (val) {
                final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(val);
                final hasLatin  = RegExp(r'[a-zA-Z]').hasMatch(val);
                if (hasLatin && !hasArabic && _isArabicInput) {
                  setState(() => _isArabicInput = false);
                } else if (hasArabic && !_isArabicInput) {
                  setState(() => _isArabicInput = true);
                } else if (val.isEmpty && !_isArabicInput) {
                  setState(() => _isArabicInput = true);
                }
                context.read<SearchCubit>().search(val);
              },
              decoration: InputDecoration(
                hintText: 'ابحث عن كلمة...',
                hintStyle: GoogleFonts.notoNaskhArabic(color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: EdgeInsets.symmetric(vertical: 0),
                prefixIcon: IconButton(
                  icon: Icon(Icons.close, color: Colors.grey[400], size: 20),
                  onPressed: () {
                    _searchController.clear();
                    context.read<SearchCubit>().loadInitial();
                  },
                ),
                suffixIcon: Icon(Icons.search, color: Color(0xFF1976D2)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: BlocBuilder<SearchCubit, SearchState>(
        builder: (context, state) {
          if (state is SearchLoading) {
            return Center(child: CircularProgressIndicator());
          }
          if (state is SearchError) {
            return Center(child: Text('Error: ${state.message}'));
          }
          if (state is SearchEmpty) {
            return Center(
              child: Text(
                'Search anything in Arabic/English...',
                style: GoogleFonts.manrope(color: Colors.grey[400], fontSize: 16),
              ),
            );
          }
          if (state is SearchLoaded) {
            if (state.words.isEmpty) {
              return Center(
                child: Text(
                  'No results found.',
                  style: GoogleFonts.manrope(color: Colors.grey[400], fontSize: 16),
                ),
              );
            }
            return ListView.separated(
              itemCount: state.words.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey[200]),
              itemBuilder: (context, index) =>
                  _buildWordTile(context, state.words[index], state.query),
            );
          }
          return SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildWordTile(BuildContext context, Word word, String query) {
    final isArabicSearch = RegExp(r'[\u0600-\u06FF]').hasMatch(query);

    // v7 meanings are clean — no wordType arg needed
    final String displayMeaning = Formatters.cleanMeaning(word.primaryMeaning ?? '');
    final String readableType   = Formatters.formatWordType(word.wordType);
    final bool showRoot         = Formatters.shouldDisplayRoot(word);
    final bool isWeak           = Formatters.isWeakRoot(word);

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WordDetailScreen(word: word)),
      ),
      child: Container(
        padding: EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Left: root or weak tag ──────────────────────────────────
            if (showRoot)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isWeak)
                    Text(
                      'from',
                      style: GoogleFonts.manrope(
                          fontSize: 11, color: Colors.grey[500]),
                    ),
                  if (isWeak)
                    Container(
                      margin: EdgeInsets.only(top: 2),
                      padding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              )
            else
              SizedBox(width: 40),

            // ── Right: word details (RTL) ───────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Arabic form + romanization
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
                      SizedBox(width: 8),
                      RichText(
                        text: TextSpan(
                          style: GoogleFonts.notoNaskhArabic(
                              fontSize: 20, fontWeight: FontWeight.bold),
                          // Arabic: always highlight root consonants (works for
                          // both direct matches and stemmer fallback results).
                          // English: no Arabic highlight needed.
                          children: isArabicSearch
                              ? TextHighlighter.highlightArabicRoot(
                                  word.formArabic, word.root,
                                  baseColor: Colors.black87)
                              : [
                                  TextSpan(
                                    text: word.formArabic,
                                    style: TextStyle(color: Colors.black87),
                                  )
                                ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),

                  // Badges + word type
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (word.isCommon)
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          margin: EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'COMMON',
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ),
                      Text(
                        readableType,
                        style: GoogleFonts.manrope(
                            fontSize: 11, color: Colors.grey[500]),
                      ),
                      if (Formatters.formatVerbForm(word.verbForm) != null)
                        Text(
                          ' • ${Formatters.formatVerbForm(word.verbForm)!}',
                          style: GoogleFonts.manrope(
                              fontSize: 11, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                  SizedBox(height: 6),

                  // Meaning (max 3 lines, grey)
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
}