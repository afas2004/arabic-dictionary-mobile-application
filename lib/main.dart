import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'controllers/favourites_controller.dart';
import 'controllers/recent_searches_controller.dart';
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
  final db         = await repository.rawDatabase;
  final stemmer    = Stemmer(db);
  final cache      = CacheManager();
  final search     = SearchManager(
    repository: repository,
    stemmer:    stemmer,
    cache:      cache,
  );

  // Load persisted preferences in parallel. Fall back to defaults if the
  // platform channel isn't ready (e.g. first launch after fresh install).
  final results = await Future.wait([
    ThemeController.load().catchError((_) => ThemeController()),
    RecentSearchesController.load().catchError((_) => RecentSearchesController()),
    FavouritesController.load().catchError((_) => FavouritesController()),
  ]);

  final themeController   = results[0] as ThemeController;
  final recentSearches    = results[1] as RecentSearchesController;
  final favourites        = results[2] as FavouritesController;

  runApp(MyApp(
    repository:       repository,
    searchManager:    search,
    themeController:  themeController,
    recentSearches:   recentSearches,
    favourites:       favourites,
  ));
}

class MyApp extends StatelessWidget {
  final DictionaryRepository      repository;
  final SearchManager             searchManager;
  final ThemeController           themeController;
  final RecentSearchesController  recentSearches;
  final FavouritesController      favourites;

  const MyApp({
    Key? key,
    required this.repository,
    required this.searchManager,
    required this.themeController,
    required this.recentSearches,
    required this.favourites,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Plain data objects — no notification needed
        RepositoryProvider.value(value: repository),
        RepositoryProvider.value(value: searchManager),
        // ChangeNotifiers — must use ChangeNotifierProvider so dependents rebuild
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider.value(value: recentSearches),
        ChangeNotifierProvider.value(value: favourites),
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
            final bool  isDark  = themeController.isDark;

            final lightScheme = ColorScheme.fromSeed(
              seedColor: primary,
              primary: primary,
            );
            final darkScheme = ColorScheme.fromSeed(
              seedColor: primary,
              primary: primary,
              brightness: Brightness.dark,
            );

            return MaterialApp(
              title: 'Arabic Dictionary',
              debugShowCheckedModeBanner: false,
              themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
              theme: ThemeData(
                colorScheme: lightScheme,
                primaryColor: primary,
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: darkScheme,
                primaryColor: primary,
                useMaterial3: true,
              ),
              home: SearchScreen(),
            );
          },
        ),
      ),
    );
  }
}
