import 'package:arabic_dictionary/cubits/search_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import 'word_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();

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
          style: GoogleFonts.notoNaskhArabic(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(60.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              onChanged: (val) => context.read<SearchCubit>().search(val),
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
          if (state is SearchLoading) return Center(child: CircularProgressIndicator());
          if (state is SearchError) return Center(child: Text('Error: ${state.message}'));
          if (state is SearchLoaded) {
            return ListView.separated(
              itemCount: state.words.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[200]),
              itemBuilder: (context, index) {
                final word = state.words[index];
                return _buildWordTile(context, word);
              },
            );
          }
          return SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildWordTile(BuildContext context, Word word) {
    // Determine colors based on your HTML spec
    final isVerb = word.wordType.contains('verb');
    final mainColor = isVerb ? Color(0xFF1976D2) : Color(0xFF2E7D32); // Blue for Verb, Green for Noun

    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => WordDetailScreen(word: word),
        ));
      },
      child: Container(
        padding: EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left Side: Root
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Root:', style: GoogleFonts.manrope(fontSize: 11, color: Colors.grey[500])),
                Text(
                  word.root,
                  textDirection: TextDirection.ltr,
                  style: GoogleFonts.notoNaskhArabic(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFF57C00)),
                ),
              ],
            ),
            // Right Side: Word details (RTL)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('(${word.formRomanized})', style: GoogleFonts.manrope(fontSize: 12, color: Colors.grey[400])),
                      SizedBox(width: 8),
                      Text(
                        word.formArabic,
                        style: GoogleFonts.notoNaskhArabic(fontSize: 20, fontWeight: FontWeight.bold, color: mainColor),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (word.isCommon)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          margin: EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(3)),
                          child: Text('COMMON', style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                        ),
                      Text(
                        '${word.partOfSpeech} • ${word.tense ?? ''} • ${word.voice ?? ''}',
                        style: GoogleFonts.manrope(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    word.primaryMeaning ?? 'No meaning available',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(fontSize: 15, color: Colors.black87),
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