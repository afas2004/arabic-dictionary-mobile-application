import 'package:equatable/equatable.dart';

class Word extends Equatable {
  final int id;
  final String root;
  final String rootRomanized;
  final String formArabic;
  final String formStripped;
  final String formRomanized;
  final String partOfSpeech;
  final String wordType;
  final String? verbForm;
  final String? tense;
  final String? voice;
  final String? gender;
  final String? number;
  final int frequency;
  final bool isCommon;
  final bool isIrregular;
  final String? domain;
  final int? baseFormId;

  // Joined field — primary meaning from meanings table (order_num = 1)
  final String? primaryMeaning;

  const Word({
    required this.id,
    required this.root,
    required this.rootRomanized,
    required this.formArabic,
    required this.formStripped,
    required this.formRomanized,
    required this.partOfSpeech,
    required this.wordType,
    this.verbForm,
    this.tense,
    this.voice,
    this.gender,
    this.number,
    required this.frequency,
    required this.isCommon,
    required this.isIrregular,
    this.domain,
    this.baseFormId,
    this.primaryMeaning,
  });

  factory Word.fromMap(Map<String, dynamic> map) {
    return Word(
      id: map['id'] as int,
      root: map['root'] as String,
      rootRomanized: map['root_romanized'] as String? ?? '',
      formArabic: map['form_arabic'] as String,
      formStripped: map['form_stripped'] as String,
      formRomanized: map['form_romanized'] as String? ?? '',
      partOfSpeech: map['part_of_speech'] as String,
      wordType: map['word_type'] as String,
      verbForm: map['verb_form'] as String?,
      tense: map['tense'] as String?,
      voice: map['voice'] as String?,
      gender: map['gender'] as String?,
      number: map['number'] as String?,
      frequency: map['frequency'] as int? ?? 1,
      isCommon: (map['is_common'] as int? ?? 0) == 1,
      isIrregular: (map['is_irregular'] as int? ?? 0) == 1,
      domain: map['domain'] as String?,
      baseFormId: map['base_form_id'] as int?,
      primaryMeaning: map['meaning_text'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, formArabic, baseFormId];
}

class Meaning extends Equatable {
  final int id;
  final int lexiconId;
  final String language;
  final String meaningText;
  final int orderNum;

  const Meaning({
    required this.id,
    required this.lexiconId,
    required this.language,
    required this.meaningText,
    required this.orderNum,
  });

  factory Meaning.fromMap(Map<String, dynamic> map) {
    return Meaning(
      id: map['id'] as int,
      lexiconId: map['lexicon_id'] as int,
      language: map['language'] as String,
      meaningText: map['meaning_text'] as String,
      orderNum: map['order_num'] as int? ?? 1,
    );
  }

  @override
  List<Object?> get props => [id, meaningText];
}

class Conjugation extends Equatable {
  final int id;
  final int baseWordId;
  final String formArabic;
  final String tense;
  final String? pronoun;
  final String number;
  final String? gender;
  final String voice;
  final String? mood;
  final int displayOrder;

  const Conjugation({
    required this.id,
    required this.baseWordId,
    required this.formArabic,
    required this.tense,
    this.pronoun,
    required this.number,
    this.gender,
    required this.voice,
    this.mood,
    this.displayOrder = 0,
  });

  factory Conjugation.fromMap(Map<String, dynamic> map) {
    return Conjugation(
      id: map['id'] as int? ?? 0,
      baseWordId: map['base_word_id'] as int,
      formArabic: map['form_arabic'] as String,
      tense: map['tense'] as String,
      pronoun: map['pronoun'] as String?,
      number: map['number'] as String,
      gender: map['gender'] as String?,
      voice: map['voice'] as String? ?? 'active',
      mood: map['mood'] as String?,
      displayOrder: map['display_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'base_word_id': baseWordId,
      'form_arabic': formArabic,
      'tense': tense,
      'pronoun': pronoun,
      'number': number,
      'gender': gender,
      'voice': voice,
      'mood': mood,
      'display_order': displayOrder,
    };
  }

  @override
  List<Object?> get props => [formArabic, tense, pronoun, number, gender];
}
