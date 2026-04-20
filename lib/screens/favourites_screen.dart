// lib/screens/favourites_screen.dart
//
// Displays the user's starred words. IDs are stored in FavouritesController;
// the full Word objects are fetched from the repository on open.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arabic_dictionary/controllers/favourites_controller.dart';
import 'package:arabic_dictionary/models/models.dart';
import 'package:arabic_dictionary/repositories/dictionary_repository.dart';
import 'package:arabic_dictionary/utils/formatters.dart';
import 'word_detail_screen.dart';

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
                    'Tap ★ on a word to save it here.',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: words.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.grey[200]),
            itemBuilder: (context, i) {
              final w = words[i];
              return InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WordDetailScreen(word: w),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Left: type
                      Text(
                        Formatters.formatWordType(w.wordType),
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                      // Right: Arabic + meaning
                      Expanded(
                        child: Column(
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
                      // Unstar button
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => widget.controller.toggle(w.id),
                        child: Icon(
                          Icons.star,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
