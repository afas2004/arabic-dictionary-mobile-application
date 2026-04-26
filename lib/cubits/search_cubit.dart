import 'dart:async';

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

  /// Minimum query length before a real search runs.  Single-character
  /// Arabic queries match ~everything via LIKE '%x%' and return mostly
  /// noise at high cost; two characters is the smallest input that
  /// produces a useful result set.
  static const int _minQueryLength = 2;

  SearchCubit({required SearchManager searchManager})
      : _searchManager = searchManager,
        super(SearchEmpty());

  /// Called on app start and when the search field is cleared.
  ///
  /// Warms the RAM cache with common words in the background (one-shot,
  /// idempotent) but does NOT surface them to the UI.  The first-launch
  /// state on the search screen is the 📖 empty state, per
  /// ui_mockups_v2.html §5.
  Future<void> loadInitial() async {
    // Fire-and-forget pre-warm.  Errors are swallowed — the cache is a
    // performance optimisation, not a correctness gate.
    unawaited(_searchManager.preWarm().catchError((_) => <Word>[]));
    emit(SearchEmpty());
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();

    // Empty input → return to first-launch state.
    if (trimmed.isEmpty) {
      emit(SearchEmpty());
      return;
    }

    // Below the minimum length we silently keep the screen on the empty
    // state instead of running a doomed-to-be-noisy search.  We don't
    // surface a "type more" message because the keyboard / typing flow
    // already makes the implication clear.
    if (trimmed.length < _minQueryLength) {
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
