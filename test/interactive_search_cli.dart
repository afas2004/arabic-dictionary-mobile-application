import 'dart:io';
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:arabic_dictionary/models/models.dart';

// Run this in terminal using: dart run test/interactive_search_cli.dart

void main() async {
  // 1. Initialize FFI for desktop/terminal environment
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;

  // 2. Point directly to your actual database file in the assets folder
  String dbPath = '${Directory.current.path}/assets/arabic_dictionary_v5.db';

  if (!File(dbPath).existsSync()) {
    print('❌ Database not found! Please ensure arabic_dictionary_v5.db is in the assets/ folder.');
    exit(1);
  }

  var db = await databaseFactory.openDatabase(dbPath);
  print('✅ Connected to dictionary database!');
  print('==================================================');

  // 3. Interactive Loop
  while (true) {
    stdout.write('🔍 Enter Arabic or English word (type "q" to quit): ');
    
    // Forced utf8 encoding to prevent Windows terminal from mangling Arabic text
    String? query = stdin.readLineSync(encoding: utf8)?.trim();

    if (query == null || query.isEmpty) continue;
    if (query.toLowerCase() == 'q') break;

    // Check if the input contains Arabic characters
    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(query);
    List<Map<String, dynamic>> maps;

    try {
      if (isArabic) {
        // Arabic search (form_stripped or root)
        maps = await db.rawQuery('''
          SELECT l.*, m.meaning_text 
          FROM lexicon l 
          LEFT JOIN meanings m ON l.id = m.lexicon_id AND m.order_num = 1
          WHERE l.form_stripped LIKE ? OR l.root LIKE ?
          ORDER BY l.frequency DESC LIMIT 10
        ''', ['%$query%', '$query%']);
      } else {
        // English reverse lookup. 
        // Replaced FTS4 with a standard LIKE query for desktop CLI compatibility.
        maps = await db.rawQuery('''
          SELECT l.*, m.meaning_text 
          FROM lexicon l
          JOIN meanings m ON l.id = m.lexicon_id
          WHERE m.meaning_text LIKE ?
          ORDER BY l.frequency DESC LIMIT 10
        ''', ['%$query%']);
      }

      if (maps.isEmpty) {
        print('   ❌ No results found for "$query"');
      } else {
        print('\n   Found ${maps.length} results:');
        for (var map in maps) {
          final word = Word.fromMap(map);
          print('   -----------------------------------');
          print('   ${word.formArabic} (${word.formRomanized})');
          print('   Root: ${word.root}  |  Type: ${word.wordType}');
          print('   Meaning: ${word.primaryMeaning ?? "No meaning"}');
        }
      }
    } catch (e) {
      print('   ⚠️ Error executing query: $e');
    }
    print('==================================================');
  }

  await db.close();
  print('Goodbye!');
}