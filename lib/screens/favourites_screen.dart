// lib/screens/favourites_screen.dart
//
// Displays the user's starred words. IDs are stored in FavouritesController;
// the full Word objects are fetched from the repository on open.
//
// Uses the same WordTile widget as the search results list so rows look
// identical across screens (per ui_mockups_v2.html §5).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arabic_dictionary/controllers/favourites_controller.dart';
import 'package:arabic_dictionary/models/models.dart';
import 'package:arabic_dictionary/repositories/dictionary_repository.dart';
import 'search_screen.dart' show WordTile;

class FavouritesScreen extends StatefulWidget {
  final FavouritesController controller;
  final DictionaryRepository repository;

  const FavouritesScreen({
    Key? key,
    required this.controller,
    required this.repository,
  }) : super(key: key);

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  late Future<List<Word>> _wordsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.controller.addListener(_reload);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    setState(() {
      _wordsFuture = widget.repository.getFavouriteWords(widget.controller.ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          'Favourites',
          style: GoogleFonts.manrope(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: FutureBuilder<List<Word>>(
        future: _wordsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final words = snapshot.data ?? [];
          if (words.isEmpty) {
            return _EmptyFavourites();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // "N saved words" section header per ui_mockups_v2.html §5
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  '${words.length} saved word${words.length == 1 ? '' : 's'}',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[700],
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: words.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey[200]),
                  itemBuilder: (context, i) => WordTile(word: words[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyFavourites extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_border, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'No favourites yet',
            style: GoogleFonts.manrope(
              fontSize: 16,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap \u2605 on a word to save it here.',
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }
}
