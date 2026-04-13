import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:arabic_dictionary/models/models.dart';
import 'package:arabic_dictionary/repositories/dictionary_repository.dart';

// --- STATE ---
abstract class SearchState extends Equatable {
  @override
  List<Object?> get props => [];
}

class SearchEmpty extends SearchState {} // Replaced Initial with Empty

class SearchLoading extends SearchState {}

class SearchLoaded extends SearchState {
  final List<Word> words;
  final String query; 
  
  SearchLoaded(this.words, this.query);
  
  @override
  List<Object?> get props => [words, query];
}

class SearchError extends SearchState {
  final String message;
  SearchError(this.message);
  
  @override
  List<Object?> get props => [message];
}

// --- CUBIT ---
class SearchCubit extends Cubit<SearchState> {
  final DictionaryRepository repository;

  SearchCubit({required this.repository}) : super(SearchEmpty());

  Future<void> loadInitial() async {
    emit(SearchLoading());
    try {
      final words = await repository.getCommonWords();
      emit(SearchLoaded(words, ''));
    } catch (_) {
      emit(SearchEmpty());
    }
  }

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      loadInitial();
      return;
    }
    
    emit(SearchLoading());
    try {
      final results = await repository.searchWords(query);
      emit(SearchLoaded(results, query)); 
    } catch (e) {
      emit(SearchError(e.toString()));
    }
  }
}