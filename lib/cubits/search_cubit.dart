import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:arabic_dictionary/models/models.dart';
import 'package:arabic_dictionary/repositories/dictionary_repository.dart';

// --- STATE ---
abstract class SearchState extends Equatable {
  @override
  List<Object?> get props => [];
}

class SearchInitial extends SearchState {}

class SearchLoading extends SearchState {}

class SearchLoaded extends SearchState {
  final List<Word> words;
  final String query; // Added so UI knows what string to highlight
  
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
  List<Word> _commonWordsCache = [];

  SearchCubit({required this.repository}) : super(SearchInitial());

  Future<void> loadInitial() async {
    emit(SearchLoading());
    try {
      if (_commonWordsCache.isEmpty) {
        _commonWordsCache = await repository.getCommonWords();
      }
      emit(SearchLoaded(_commonWordsCache, "")); // Empty query for initial load
    } catch (e) {
      emit(SearchError(e.toString()));
    }
  }

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      emit(SearchLoaded(_commonWordsCache, ""));
      return;
    }
    
    emit(SearchLoading());
    try {
      final results = await repository.searchWords(query);
      emit(SearchLoaded(results, query)); // Pass the active query to the state
    } catch (e) {
      emit(SearchError(e.toString()));
    }
  }
}