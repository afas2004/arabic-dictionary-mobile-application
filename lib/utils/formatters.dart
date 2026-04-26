// lib/utils/formatters.dart
//
// Display utilities for the Arabic Dictionary UI.
// Hans Wehr data-cleaning logic has been removed (no longer needed in v7).
// Remaining functions handle word type labels, root display logic, and
// weak/irregular root detection for the search and detail screens.

import '../models/models.dart';

class Formatters {
  // ── Word type labels ──────────────────────────────────────────────────────

  /// Converts a DB word_type string into a short, learner-friendly label.
  /// For places where we have the room, prefer [formatWordTypeRich] which
  /// also includes the Arabic grammatical term in parentheses.
  static String formatWordType(String wordType) {
    switch (wordType) {
      case 'base_verb':           return 'Verb';
      case 'verbal_noun':         return 'Verbal Noun';
      case 'active_participle':   return 'Active Participle';
      case 'passive_participle':  return 'Passive Participle';
      case 'intensive_form':      return 'Intensive';
      case 'singular_noun':       return 'Noun';
      case 'adjective':           return 'Adjective';
      case 'adjective_sifat':     return 'Quality Adjective';
      case 'adjective_mansoub':   return 'Relative Adjective';
      case 'comparative':         return 'Comparative';
      case 'particle':            return 'Particle';
      case 'conjunction':         return 'Conjunction';
      case 'pronoun':             return 'Pronoun';
      case 'preposition':         return 'Preposition';
      default:                    return wordType;
    }
  }

  /// Long-form word_type label including the Arabic grammatical term.
  /// Used on the word detail header where a single line of secondary info
  /// has room to spare. e.g. "Verbal Noun · مصدر".
  ///
  /// Returns the same value as [formatWordType] for types that have no
  /// distinct Arabic grammar term (e.g. Pronoun, Conjunction).
  static String formatWordTypeRich(String wordType) {
    switch (wordType) {
      case 'base_verb':           return 'Verb · فعل';
      case 'verbal_noun':         return 'Verbal Noun · مصدر';
      case 'active_participle':   return 'Active Participle · اسم الفاعل';
      case 'passive_participle':  return 'Passive Participle · اسم المفعول';
      case 'intensive_form':      return 'Intensive · صيغة المبالغة';
      case 'singular_noun':       return 'Noun · اسم';
      case 'adjective':           return 'Adjective · صفة';
      case 'adjective_sifat':     return 'Quality Adjective · صفة مشبهة';
      case 'adjective_mansoub':   return 'Relative Adjective · نسبة';
      case 'comparative':         return 'Comparative · اسم التفضيل';
      case 'particle':            return 'Particle · حرف';
      case 'conjunction':         return 'Conjunction · حرف عطف';
      case 'pronoun':             return 'Pronoun · ضمير';
      case 'preposition':         return 'Preposition · حرف جر';
      default:                    return formatWordType(wordType);
    }
  }

  // ── Verb form label ───────────────────────────────────────────────────────

  /// Maps verb_form DB values to display labels.
  ///
  /// IMPORTANT: in the v11 DB the `verb_form` column contains Hans Wehr /
  /// Buckwalter conjugation-class codes (`v`, `y`, `x`, `u`, `yz`, …) NOT
  /// the morphological Form numerals.  This map is therefore effectively
  /// dead code on the current corpus; the real Form-label source is
  /// [detectVerbFormLabel] which works off the surface form_stripped.
  /// Kept for forward-compatibility with future DB schemas.
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
    return known[verbForm];
  }

  /// Detects verb form from the surface form (formStripped) rather than
  /// relying on the DB verb_form column, which contains Buckwalter codes.
  /// Returns an Arabic pattern label like "Form: أَفْعَلَ" or null for
  /// Form I / non-verbs.
  static String? detectVerbFormLabel(String formStripped) {
    // Strip diacritics + dagger-alef to work on pure consonants.
    final s = formStripped.replaceAll(RegExp(r'[ً-ٰٟ]'), '');
    if (s.length <= 3) return null; // Form I — no label needed

    // The v11 lexicon's form_stripped column keeps أ / إ / آ at populate
    // time (only diacritics + tatweel are stripped).  We match the
    // hamza-bearing variants directly, plus plain alef U+0627 for forward
    // compatibility with a future DB rebuild that fully alef-normalises
    // the column.
    bool isAlef(String c) =>
        c == 'أ' || // أ  alef-with-hamza-above
        c == 'إ' || // إ  alef-with-hamza-below
        c == 'آ' || // آ  alef-with-madda
        c == 'ٱ' || // ٱ  alef-wasla
        c == 'ا';   // ا  plain alef

    if (s.length == 4) {
      if (isAlef(s[0]))           return 'Form: أَفْعَلَ';        // أَفْعَلَ   (Form IV)
      if (s[1] == 'ا')       return 'Form: فَاعَلَ';              // فَاعَلَ    (Form III)
      if (s[0] == 'ت')       return 'Form: تَفَعَّلَ';  // تَفَعَّلَ  (Form V)
      return null;
    }
    if (s.length == 5) {
      // ا_ت__ — alef at pos 0 + ta at pos 2 → Form VIII (افْتَعَلَ)
      if (isAlef(s[0]) && s[2] == 'ت') {
        return 'Form: افْتَعَلَ';
      }
      // ان___ — alef + nun → Form VII (انْفَعَلَ)
      if (isAlef(s[0]) && s[1] == 'ن') {
        return 'Form: انْفَعَلَ';
      }
      // ت_ا__ — ta + alef at pos 2 → Form VI (تَفَاعَلَ)
      if (s[0] == 'ت' && s[2] == 'ا') {
        return 'Form: تَفَاعَلَ';
      }
      return null;
    }
    if (s.length == 6) {
      // است___ — alef+sin+ta prefix → Form X (اسْتَفْعَلَ)
      if (isAlef(s[0]) && s[1] == 'س' && s[2] == 'ت') {
        return 'Form: اسْتَفْعَلَ';
      }
      return null;
    }
    return null;
  }

  /// Returns the English meaning category that goes alongside the verb-form
  /// pattern, e.g. "causative · to make happen" for Form IV.  Useful as a
  /// secondary line under [detectVerbFormLabel].  Returns null for
  /// patterns we don't have a stock gloss for.
  static String? verbFormGloss(String? formLabel) {
    if (formLabel == null) return null;
    // formLabel arrives as "Form: <arabic-pattern>"; key off the pattern.
    if (formLabel.contains('أَف')) return 'causative';                      // Form IV
    if (formLabel.contains('فَا')) return 'associative';                    // Form III
    if (formLabel.contains('تَفَعّ')) return 'reflexive of II';   // Form V
    if (formLabel.contains('تَفَا')) return 'mutual / reflexive of III'; // Form VI
    if (formLabel.contains('انْف')) return 'passive / reflexive';      // Form VII
    if (formLabel.contains('افْت')) return 'reflexive of I';           // Form VIII
    if (formLabel.contains('اسْت')) return 'seek / request';           // Form X
    return null;
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

    // Passive participles follow a fixed مَفْعُول pattern and conjugate normally
    if (word.wordType == 'passive_participle') return false;

    // Extract only the letter characters from the dash-separated root
    final letters = word.root.replaceAll('-', '');

    // Hamzated radicals — always flag as weak
    if (letters.contains('ء') ||
        letters.contains('أ') ||
        letters.contains('إ') ||
        letters.contains('آ')) return true;

    // No weak radicals at all — strong root
    if (!letters.contains('و') && !letters.contains('ي')) return false;

    // Form III (ا at pos 1) and Form V (ت at pos 0): R2=و/ي acts as a
    // regular consonant that receives shadda or stays phonetically stable —
    // conjugates as strong, so don't show "Weak Root" badge.
    final s =
        word.formStripped.replaceAll(RegExp(r'[ً-ٰٟ]'), '');
    if (s.length == 4) {
      if (s[1] == 'ا') return false; // Form III: _ا__
      if (s[0] == 'ت') return false; // Form V:  ت___
    }

    return true;
  }

  // ── Meaning display ───────────────────────────────────────────────────────

  /// Returns the meaning text ready for display.
  /// v7+ meanings are already clean — no regex stripping needed.
  /// Kept as a pass-through so callers don't have to special-case.
  static String cleanMeaning(String meaning) {
    return meaning.trim();
  }
}
