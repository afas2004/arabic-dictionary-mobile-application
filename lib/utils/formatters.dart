// lib/utils/formatters.dart
//
// Display utilities for the Arabic Dictionary UI.
// Hans Wehr data-cleaning logic has been removed (no longer needed in v7).
// Remaining functions handle word type labels, root display logic, and
// weak/irregular root detection for the search and detail screens.

import '../models/models.dart';

class Formatters {
  // ── Word type labels ──────────────────────────────────────────────────────

  /// Converts a DB word_type string into a human-readable label.
  static String formatWordType(String wordType) {
    switch (wordType) {
      case 'base_verb':           return 'Verb';
      case 'verbal_noun':         return 'Verbal Noun';
      case 'active_participle':   return 'Active Participle';
      case 'passive_participle':  return 'Passive Participle';
      case 'intensive_form':      return 'Intensive Form';
      case 'singular_noun':       return 'Noun';
      case 'adjective':           return 'Adjective';
      case 'adjective_sifat':     return 'Adjective';
      case 'adjective_mansoub':   return 'Relative Adjective';
      case 'comparative':         return 'Comparative';
      default:                    return wordType;
    }
  }

  // ── Verb form label ───────────────────────────────────────────────────────

  /// Maps verb_form DB values to display labels.
  /// Returns null for unrecognized codes (e.g. Buckwalter class codes like
  /// 'v', 'y', 'x') so the caller can hide the display entirely.
  static String? formatVerbForm(String? verbForm) {
    if (verbForm == null) return null;
    const Map<String, String> known = {
      'I':    'Form I',
      'II':   'Form II',
      'III':  'Form III',
      'IV':   'Form IV',
      'V':    'Form V',
      'VI':   'Form VI',
      'VII':  'Form VII',
      'VIII': 'Form VIII',
      'IX':   'Form IX',
      'X':    'Form X',
    };
    return known[verbForm]; // null for unrecognized codes
  }

  // ── Root display logic ────────────────────────────────────────────────────

  /// Returns true if the base-form reference should be shown on the word tile.
  ///
  /// Rules:
  /// - Hide for standalone nouns and adjectives.
  /// - Hide if the word IS the base form (baseFormId == null) — showing its
  ///   own root would be redundant.
  /// - Hide for non-triliteral roots (4+ consonants — quadriliteral/compound).
  static bool shouldDisplayRoot(Word word) {
    // Hide for standalone nouns and pure adjectives
    if (word.wordType == 'singular_noun' ||
        word.wordType == 'adjective' ||
        word.wordType == 'adjective_sifat' ||
        word.wordType == 'adjective_mansoub') {
      return false;
    }

    // Hide if word IS the base form — no parent to point to
    if (word.baseFormId == null) return false;

    // Hide if non-triliteral: root letters are separated by '-',
    // so a triliteral root has exactly 5 chars: 'ك-ت-ب' (3 letters + 2 dashes).
    // Anything longer is quadriliteral or compound.
    if (word.root.length > 5) return false;

    return true;
  }

  /// Returns true if the root is weak (mu'tal) or hamzated.
  ///
  /// Weak roots contain و or ي as a radical, or ء/أ/إ (hamza).
  /// The UI replaces the root display with a red "Weak Root" tag for these
  /// to avoid confusing learners with the mutated surface form.
  static bool isWeakRoot(Word word) {
    if (!shouldDisplayRoot(word)) return false;

    // Extract only the letter characters from the dash-separated root
    final letters = word.root.replaceAll('-', '');

    // Weak (mu'tal) radicals
    if (letters.contains('و') || letters.contains('ي')) return true;

    // Hamzated radicals
    if (letters.contains('ء') ||
        letters.contains('أ') ||
        letters.contains('إ') ||
        letters.contains('آ')) return true;

    return false;
  }

  // ── Meaning display ───────────────────────────────────────────────────────

  /// Returns the meaning text ready for display.
  /// v7 meanings are already clean — no regex stripping needed.
  /// This method is kept as a pass-through for future use and UI consistency.
  static String cleanMeaning(String meaning) {
    return meaning.trim();
  }
}