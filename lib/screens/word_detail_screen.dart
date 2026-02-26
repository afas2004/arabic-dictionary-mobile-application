import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../cubits/word_detail_cubit.dart';
import '../../models/models.dart';
import '../../repositories/dictionary_repository.dart';

class WordDetailScreen extends StatelessWidget {
  final Word word;

  const WordDetailScreen({Key? key, required this.word}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => WordDetailCubit(repository: context.read<DictionaryRepository>())..loadDetails(word),
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
          title: Text(word.root, style: GoogleFonts.notoNaskhArabic(color: Colors.black87, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(icon: Icon(Icons.star_border, color: Color(0xFF27679b)), onPressed: () {})
          ],
        ),
        body: BlocBuilder<WordDetailCubit, WordDetailState>(
          builder: (context, state) {
            if (state is WordDetailLoading) return Center(child: CircularProgressIndicator());
            if (state is WordDetailError) return Center(child: Text(state.message));
            if (state is WordDetailLoaded) {
              return SingleChildScrollView(
                child: Column(
                  children: [
                    _buildHeader(state.word),
                    _buildMeaningsList(state.meanings),
                    SizedBox(height: 24),
                    _buildConjugationTablePlaceholder(), // Replacing with table structure
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

  Widget _buildHeader(Word word) {
    return Container(
      width: double.infinity,
      color: Color(0xFFE3F2FD),
      padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Text(
            word.formArabic,
            style: GoogleFonts.notoNaskhArabic(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFFF57C00)),
          ),
          SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              Text('Root: ${word.root}', style: GoogleFonts.notoNaskhArabic(color: Color(0xFF27679b), fontWeight: FontWeight.bold)),
              Text('•', style: TextStyle(color: Colors.grey)),
              Text(word.partOfSpeech, style: GoogleFonts.manrope(fontSize: 12, color: Colors.black54)),
              if (word.verbForm != null) ...[
                Text('•', style: TextStyle(color: Colors.grey)),
                Text(word.verbForm!, style: GoogleFonts.manrope(fontSize: 12, color: Colors.black54)),
              ]
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMeaningsList(List<Meaning> meanings) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: meanings.map((m) => Padding(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: Text('${m.orderNum}. ${m.meaningText}', style: GoogleFonts.manrope(fontSize: 14, color: Colors.black87)),
        )).toList(),
      ),
    );
  }

  Widget _buildConjugationTablePlaceholder() {
    // Based on HTML layout, building the actual Past Tense Table is very complex 
    // requiring nested rows/columns. Here is a structural container matching the design.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.grey[50],
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Past Tense', style: GoogleFonts.manrope(fontSize: 12, color: Colors.grey)),
                  Text('الماضي', style: GoogleFonts.notoNaskhArabic(fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.grey[200]),
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Text('Conjugation Grid Rendered Here\n(Mapped to state.conjugations)', 
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              ),
            )
          ],
        ),
      ),
    );
  }
}