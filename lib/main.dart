import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'repositories/dictionary_repository.dart';
import 'cubits/search_cubit.dart';
import 'screens/search_screen.dart';
import 'engine/conjugation_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final dictionaryRepo = DictionaryRepository();
  // Optional: await dictionaryRepo.database; // Pre-warm DB
  runApp(MyApp(repository: dictionaryRepo));
}

class MyApp extends StatelessWidget {
  final DictionaryRepository repository;
  
  const MyApp({Key? key, required this.repository}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        RepositoryProvider.value(value: repository),
        BlocProvider(create: (_) => SearchCubit(repository: repository)),
      ],
      child: MaterialApp(
        title: 'Arabic Dictionary',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: Color(0xFF1976D2),
        ),
        home: SearchScreen(),
      ),
    );
  }
}