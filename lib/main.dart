import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'repositories/dictionary_repository.dart';
import 'engine/arabic_stemmer.dart';
import 'managers/search_manager.dart';
import 'cubits/search_cubit.dart';
import 'screens/search_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = DictionaryRepository();
  final stemmer    = ArabicStemmer();
  final search     = SearchManager(repository: repository, stemmer: stemmer);

  runApp(MyApp(repository: repository, searchManager: search));
}

class MyApp extends StatelessWidget {
  final DictionaryRepository repository;
  final SearchManager searchManager;

  const MyApp({
    Key? key,
    required this.repository,
    required this.searchManager,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: repository),
        RepositoryProvider.value(value: searchManager),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => SearchCubit(searchManager: searchManager),
          ),
        ],
        child: MaterialApp(
          title: 'Arabic Dictionary',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primaryColor: const Color(0xFF1976D2),
          ),
          home: SearchScreen(),
        ),
      ),
    );
  }
}
