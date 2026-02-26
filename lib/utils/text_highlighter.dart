import 'package:flutter/material.dart';

class TextHighlighter {
  
  /// 1. English Exact String Highlight
  /// Wraps matches of the search query with a yellow background.
  static List<TextSpan> highlightEnglish(String text, String query) {
    if (query.trim().isEmpty) return [TextSpan(text: text)];
    
    final String lowerText = text.toLowerCase();
    final String lowerQuery = query.toLowerCase();
    
    List<TextSpan> spans = [];
    int start = 0;
    int indexOfMatch = lowerText.indexOf(lowerQuery, start);
    
    while (indexOfMatch != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(text: text.substring(start, indexOfMatch)));
      }
      // The highlighted matched word
      spans.add(TextSpan(
        text: text.substring(indexOfMatch, indexOfMatch + query.length),
        style: const TextStyle(
          backgroundColor: Color(0xFFFFF59D), // Light yellow highlight
          fontWeight: FontWeight.bold, 
          color: Colors.black87
        ),
      ));
      start = indexOfMatch + query.length;
      indexOfMatch = lowerText.indexOf(lowerQuery, start);
    }
    
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    
    return spans;
  }

  /// 2. Arabic Root Highlight
  /// Highlights letters matching the root (e.g. ك-ت-ب) inside a derived word (e.g. مَكْتَبَة).
  static List<TextSpan> highlightArabicRoot(
    String word, 
    String root, {
    Color rootColor = const Color(0xFFF57C00), // Orange
    Color baseColor = const Color(0xFF374151)  // Dark Gray
  }) {
    if (root.isEmpty) return [TextSpan(text: word, style: TextStyle(color: baseColor))];

    // Normalize Alif variations to ensure roots match properly
    String normalize(String s) => s.replaceAll(RegExp(r'[أإآ]'), 'ا');
    
    // Extract raw root letters without hyphens
    final List<String> rootLetters = root.replaceAll('-', '').split('').map((l) => normalize(l)).toList();
    
    List<TextSpan> spans = [];
    bool wasRoot = false;
    String currentChunk = "";

    // Arabic diacritics Unicode range
    bool isDiacritic(String char) {
      int code = char.codeUnitAt(0);
      return code >= 0x064B && code <= 0x065F;
    }

    for (int i = 0; i < word.length; i++) {
      String char = word[i];
      
      if (isDiacritic(char)) {
         // Diacritic inherits the color of its base letter
         currentChunk += char;
      } else {
         bool isRoot = rootLetters.contains(normalize(char));
         
         // If we switch from root to non-root (or vice versa), save the chunk and switch colors
         if (isRoot != wasRoot && currentChunk.isNotEmpty) {
           spans.add(TextSpan(
             text: currentChunk, 
             style: TextStyle(color: wasRoot ? rootColor : baseColor)
           ));
           currentChunk = "";
         }
         
         wasRoot = isRoot;
         currentChunk += char;
      }
    }
    
    // Add the final remaining chunk
    if (currentChunk.isNotEmpty) {
       spans.add(TextSpan(
         text: currentChunk, 
         style: TextStyle(color: wasRoot ? rootColor : baseColor)
       ));
    }

    return spans;
  }
}