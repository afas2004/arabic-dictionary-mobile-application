import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:arabic_dictionary/models/models.dart';
import 'package:arabic_dictionary/managers/search_manager.dart';

// --- STATE ---
abstract class SearchState extends Equatable {
  @override
  List<Object?> get props => [];
}

class SearchEmpty extends SearchState {}

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
  final SearchManager _searchManager;

  SearchCubit({required SearchManager searchManager})
      : _searchManager = searchManager,
        super(SearchEmpty());

  /// Called on app start and when the search field is cleared.
  ///
  /// On the first call: pre-warms the RAM cache with common words and
  /// displays them immediately — no DB round-trip needed after the first open.
  /// On subsequent calls (e.g. clear button): preWarm() returns [] instantly
  /// (idempotent guard), so we fall back to SearchEmpty.
  Future<void> loadInitial() async {
    emit(SearchLoading());
    try {
      final words = await _searchManager.preWarm();
      emit(words.isNotEmpty ? SearchLoaded(words, '') : SearchEmpty());
    } catch (_) {
      emit(SearchEmpty());
    }
  }

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      emit(SearchEmpty());
      return;
    }

    emit(SearchLoading());
    try {
      final results = await _searchManager.search(query);
      emit(SearchLoaded(results, query));
    } catch (e) {
      emit(SearchError(e.toString()));
    }
  }
}
