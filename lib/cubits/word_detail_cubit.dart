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
  final List<Word> rootFamily;
  final List<Word> relatedForms;

  WordDetailLoaded({
    required this.word,
    required this.meanings,
    this.conjugationTable,
    this.rootFamily = const [],
    this.relatedForms = const [],
  });

  @override
  List<Object?> get props => [word, meanings, conjugationTable, rootFamily, relatedForms];
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
      final results = await Future.wait([
        _repository.getMeanings(word.id),
        _repository.getConjugationTable(word),
        _repository.getRootFamily(word.root),
        _repository.getRelatedForms(word.id),
      ]);

      emit(WordDetailLoaded(
        word: word,
        meanings: results[0] as List<Meaning>,
        conjugationTable: results[1] as ConjugationTable?,
        rootFamily: results[2] as List<Word>,
        relatedForms: results[3] as List<Word>,
      ));
    } catch (e) {
      emit(WordDetailError(e.toString()));
    }
  }
}
