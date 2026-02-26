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
  
  // Joined field from meanings table
  final String? primaryMeaning;

  const Word({
    required this.id, required this.root, required this.rootRomanized,
    required this.formArabic, required this.formStripped, required this.formRomanized,
    required this.partOfSpeech, required this.wordType, this.verbForm,
    this.tense, this.voice, this.gender, this.number, required this.frequency,
    required this.isCommon, required this.isIrregular, this.primaryMeaning,
  });

  factory Word.fromMap(Map<String, dynamic> map) {
    return Word(
      id: map['id'],
      root: map['root'],
      rootRomanized: map['root_romanized'] ?? '',
      formArabic: map['form_arabic'],
      formStripped: map['form_stripped'],
      formRomanized: map['form_romanized'],
      partOfSpeech: map['part_of_speech'],
      wordType: map['word_type'],
      verbForm: map['verb_form'],
      tense: map['tense'],
      voice: map['voice'],
      gender: map['gender'],
      number: map['number'],
      frequency: map['frequency'] ?? 1,
      isCommon: (map['is_common'] ?? 0) == 1,
      isIrregular: (map['is_irregular'] ?? 0) == 1,
      primaryMeaning: map['meaning_text'], // from JOIN
    );
  }

  @override
  List<Object?> get props => [id, formArabic];
}

class Meaning extends Equatable {
  final int id;
  final int lexiconId;
  final String language;
  final String meaningText;
  final int orderNum;

  const Meaning({required this.id, required this.lexiconId, required this.language, required this.meaningText, required this.orderNum});

  factory Meaning.fromMap(Map<String, dynamic> map) {
    return Meaning(
      id: map['id'], lexiconId: map['lexicon_id'], language: map['language'], 
      meaningText: map['meaning_text'], orderNum: map['order_num'],
    );
  }

  @override
  List<Object?> get props => [id, meaningText];
}

class Conjugation extends Equatable {
  final int id;
  final int baseWordId;
  final String conjugatedArabic;
  final String tense;
  final String? person;
  final String number;
  final String? gender;
  final String voice;
  final String? mood;

  const Conjugation({
    required this.id, required this.baseWordId, required this.conjugatedArabic, 
    required this.tense, this.person, required this.number, this.gender, 
    required this.voice, this.mood
  });

  factory Conjugation.fromMap(Map<String, dynamic> map) {
    return Conjugation(
      id: map['id'] ?? 0, // 0 for newly generated ones not yet in DB
      baseWordId: map['base_word_id'], conjugatedArabic: map['conjugated_arabic'],
      tense: map['tense'], person: map['person'], number: map['number'],
      gender: map['gender'], voice: map['voice'], mood: map['mood'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'base_word_id': baseWordId, 'conjugated_arabic': conjugatedArabic, 'tense': tense,
      'person': person, 'number': number, 'gender': gender, 'voice': voice, 'mood': mood,
    };
  }

  @override
  List<Object?> get props => [conjugatedArabic, tense, person, number, gender];
}