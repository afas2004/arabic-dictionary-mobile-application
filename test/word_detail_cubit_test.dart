import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Use package imports to avoid type mismatch errors
import 'package:arabic_dictionary/models/models.dart';
import 'package:arabic_dictionary/repositories/dictionary_repository.dart';
import 'package:arabic_dictionary/cubits/word_detail_cubit.dart';
import 'package:arabic_dictionary/engine/conjugation_engine.dart';

class MockDictionaryRepository extends Mock implements DictionaryRepository {}

void main() {
  late MockDictionaryRepository mockRepository;
  late Database testDb;

  final dummyVerb = Word(
    id: 1, root: 'ك-ت-ب', rootRomanized: 'k-t-b', formArabic: 'كَتَبَ',
    formStripped: 'كتب', formRomanized: 'kataba', partOfSpeech: 'Verb',
    wordType: 'base_verb', frequency: 100, isCommon: true, isIrregular: false,
  );

  // Set up the local SQLite environment before any tests run
  setUpAll(() async {
    // Initialize FFI for desktop/terminal environment
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Open an in-memory database that gets wiped after the test
    testDb = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Create the conjugations table just like in your schema
    await testDb.execute('''
      CREATE TABLE conjugations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        base_word_id INTEGER NOT NULL,
        conjugated_arabic TEXT NOT NULL,
        tense TEXT NOT NULL,
        person TEXT,
        number TEXT NOT NULL,
        gender TEXT,
        voice TEXT NOT NULL DEFAULT 'active',
        mood TEXT DEFAULT 'indicative',
        display_order INTEGER DEFAULT 0
      )
    ''');
  });

  tearDownAll(() async {
    await testDb.close();
  });

  setUp(() {
    mockRepository = MockDictionaryRepository();
  });

  group('Engine Results & WordDetailCubit', () {
    
    // 1. A visual test just to print and verify the engine's Arabic output
    test('Engine successfully generates Kataba conjugations', () async {
      final engine = ConjugationEngine(testDb);
      
      final table = await engine.getConjugations(
        lexiconId: dummyVerb.id,
        formStripped: dummyVerb.formStripped,
        root: dummyVerb.root,
      );

      print('--- GENERATED PAST TENSE FOR ${dummyVerb.formArabic} ---');
      for (var row in table.past) {
        print('${row.person} ${row.number} ${row.gender}: ${row.conjugatedArabic}');
      }
      
      // The engine should generate exactly 13 past tense forms
      expect(table.past.length, 13);
      expect(table.fromCache, false); // First run, shouldn't be from cache
    });

    // 2. Testing the Cubit state management
    blocTest<WordDetailCubit, WordDetailState>(
      'loadDetails emits [Loading, Loaded] with full conjugation table',
      build: () {
        // When the cubit asks for meanings, return an empty list
        when(() => mockRepository.getMeanings(dummyVerb.id))
            .thenAnswer((_) async => <Meaning>[]);
            
        // When the cubit asks for the database, provide our FFI in-memory db
        when(() => mockRepository.database)
            .thenAnswer((_) async => testDb);

        return WordDetailCubit(repository: mockRepository);
      },
      act: (cubit) => cubit.loadDetails(dummyVerb),
      expect: () => [
        WordDetailLoading(),
        isA<WordDetailLoaded>()
            .having((state) => state.word.formArabic, 'word form', 'كَتَبَ')
            // Verify that the table was successfully passed into the state
            .having((state) => state.conjugationTable?.past.length, 'past forms count', 13)
            .having((state) => state.conjugationTable?.present.length, 'present forms count', 13)
      ],
    );
  });
}