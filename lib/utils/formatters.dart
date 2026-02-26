/// Utility functions to clean and format database strings for the UI.

class Formatters {
  
  /// 1. Cleans raw Hans Wehr meaning strings
  static String cleanMeaning(String raw, String wordType) {
    if (raw.isEmpty) return raw;
    String cleaned = raw;

    // Remove anything inside parentheses e.g. "(katb, kitba, kitāba)"
    cleaned = cleaned.replaceAll(RegExp(r'\(.*?\)'), '').trim();

    // Remove plural notation e.g. "pl. makātib2 "
    cleaned = cleaned.replaceAll(RegExp(r'pl\. [^\s]+ '), '').trim();

    // For verbs, the actual English meaning almost always starts with "to "
    // This perfectly strips leading romanizations like "kataba u " or "ḳabura u "
    if (wordType.contains('verb') && cleaned.contains('to ')) {
      cleaned = cleaned.substring(cleaned.indexOf('to '));
    } else {
      // For nouns, we do a basic cleanup of leading romanized single words
      // if they precede the actual definition (heuristic approach)
      List<String> words = cleaned.split(' ');
      if (words.length > 1 && !words[0].contains(RegExp(r'[A-Z]'))) {
         // This is a simplistic strip, but works for most Hans Wehr noun prefixes
         if (words[0].endsWith('a') || words[0].endsWith('un') || words[0].endsWith('in')) {
            words.removeAt(0);
            cleaned = words.join(' ');
         }
      }
    }

    // Clean up any double spaces left behind
    return cleaned.replaceAll('  ', ' ').trim();
  }

  /// 2. Truncates long meanings for the Search Results preview
  static String truncateMeaningPreview(String cleanedMeaning) {
    if (cleanedMeaning.isEmpty) return cleanedMeaning;

    // Truncate at the first comma
    int commaIndex = cleanedMeaning.indexOf(',');
    if (commaIndex != -1 && commaIndex <= 50) {
      return '${cleanedMeaning.substring(0, commaIndex)}...';
    }

    // Or truncate at ~50 characters if no early comma exists
    if (cleanedMeaning.length > 50) {
      return '${cleanedMeaning.substring(0, 50)}...';
    }

    return cleanedMeaning;
  }

  /// 4. Maps raw DB word_type to readable UI strings
  static String formatWordType(String type) {
    if (type.isEmpty) return type;
    
    // e.g., "verbal_noun" -> ["verbal", "noun"] -> "Verbal Noun"
    return type.split('_').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}