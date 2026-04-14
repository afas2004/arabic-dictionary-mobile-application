import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:arabic_dictionary/models/models.dart';
import 'package:arabic_dictionary/repositories/dictionary_repository.dart';
import 'package:arabic_dictionary/engine/conjugation_engine.dart';

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
  final ConjugationTable? conjugationTable;

  WordDetailLoaded({
    required this.word,
    required this.meanings,
    this.conjugationTable,
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
  final DictionaryRepository _repository;

  WordDetailCubit({required DictionaryRepository repository})
      : _repository = repository,
        super(WordDetailInitial());

  Future<void> loadDetails(Word word) async {
    emit(WordDetailLoading());
    try {
      final meanings = await _repository.getMeanings(word.id);
      // Repository handles ConjugationEngine instantiation — cubit never
      // touches the raw db handle.
      final table = await _repository.getConjugationTable(word);
      emit(WordDetailLoaded(word: word, meanings: meanings, conjugationTable: table));
    } catch (e) {
      emit(WordDetailError(e.toString()));
    }
  }
}
