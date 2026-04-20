import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'controllers/theme_controller.dart';
import 'repositories/dictionary_repository.dart';
import 'engine/stemmer.dart';
import 'managers/cache_manager.dart';
import 'managers/search_manager.dart';
import 'cubits/search_cubit.dart';
import 'screens/search_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = DictionaryRepository();
  // New 7-tier Stemmer needs the DB handle — force the repo to open the DB
  // up front so the stemmer can issue its own queries against `conjugations`
  // and `lexicon` (both indexed for direct form_stripped lookup).
  final db         = await repository.rawDatabase;
  final stemmer    = Stemmer(db);
  final cache      = CacheManager();
  final search     = SearchManager(
    repository: repository,
    stemmer:    stemmer,
    cache:      cache,
  );

  // Owns the user-configurable primary colour. Rebuilds MaterialApp below
  // whenever it notifies so theme changes take effect app-wide.
  final themeController = ThemeController();

  runApp(MyApp(
    repository: repository,
    searchManager: search,
    themeController: themeController,
  ));
}

class MyApp extends StatelessWidget {
  final DictionaryRepository repository;
  final SearchManager searchManager;
  final ThemeController themeController;

  const MyApp({
    Key? key,
    required this.repository,
    required this.searchManager,
    required this.themeController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: repository),
        RepositoryProvider.value(value: searchManager),
        RepositoryProvider.value(value: themeController),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => SearchCubit(searchManager: searchManager),
          ),
        ],
        child: AnimatedBuilder(
          animation: themeController,
          builder: (context, _) {
            final Color primary = themeController.primaryColor;
            return MaterialApp(
              title: 'Arabic Dictionary',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                primaryColor: primary,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: primary,
                  primary: primary,
                ),
              ),
              home: SearchScreen(),
            );
          },
        ),
      ),
    );
  }
}
