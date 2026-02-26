import 'package:arabic_dictionary/repositories/dictionary_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../models/models.dart';
import '../engine/conjugation_engine.dart';

// --- STATE ---
abstract class WordDetailState extends Equatable {
  @override
  List<Object?> get props => [];
}

class WordDetailInitial extends WordDetailState {}

class WordDetailLoading extends WordDetailState {}

class WordDetailLoaded extends WordDetailState {
  final Word word;
  final List<Meaning> meanings;
  // Replaced generic list with the engine's ConjugationTable
  final ConjugationTable? conjugationTable;
  
  WordDetailLoaded({
    required this.word, 
    required this.meanings, 
    this.conjugationTable
  });
  
  @override
  List<Object?> get props => [word, meanings, conjugationTable];
}

class WordDetailError extends WordDetailState {
  final String message;
  WordDetailError(this.message);
  
  @override
  List<Object?> get props => [message];
}

// --- CUBIT ---
class WordDetailCubit extends Cubit<WordDetailState> {
  final DictionaryRepository repository;

  WordDetailCubit({required this.repository}) : super(WordDetailInitial());

  Future<void> loadDetails(Word word) async {
    emit(WordDetailLoading());
    try {
      // 1. Load Meanings
      final meanings = await repository.getMeanings(word.id);
      
      ConjugationTable? table;

      // 2. Load/Generate Conjugations if the word is a base verb
      if (word.wordType == 'base_verb') {
        // Grab the raw sqflite database instance from our repository
        final db = await repository.database;
        
        // Instantiate your FYP engine
        final engine = ConjugationEngine(db);
        
        // The engine natively handles checking the cache -> generating -> saving
        table = await engine.getConjugations(
          lexiconId: word.id,
          formStripped: word.formStripped,
          root: word.root,
        );
      }

      emit(WordDetailLoaded(
        word: word, 
        meanings: meanings, 
        conjugationTable: table
      ));
    } catch (e) {
      emit(WordDetailError(e.toString()));
    }
  }
}