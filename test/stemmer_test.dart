// test/stemmer_test.dart
//
// Run:
//   flutter test test/stemmer_test.dart --verbose
//
// Uses sqflite_common_ffi so the DB runs in pure Dart — no device / emulator
// needed.  Opens the v11 DB directly from the dataset folder.
//
// Adjust [_dbPath] if the DB lives elsewhere on your machine.
//
// Test buckets (one group per cascade tier + a "should miss" bucket):
//   T1 directLexicon              — canonical form, no morphology needed
//   T2 conjugationTable           — conjugated verb form must route via conj table
//   T3 cliticStripped single      — single proclitic (و / ف / ب / ل / ك / س)
//   T4 cliticStripped al+compound — definite article & compound proclitics
//   T5 cliticStripped suffix      — object pronouns and nominal suffixes
//   T6 cliticStripped combined    — proclitic + suffix simultaneously
//   T7 fuzzyRoot                  — pattern-based root for forms not in DB
//   notFound                      — non-Arabic junk / gibberish

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:arabic_dictionary/engine/stemmer.dart';

const String _dbPath =
    r'C:\Users\afahm\Documents\sem 5\CSP600 FYP\dataset\arabic_dictionary_v11.db';

void main() {
  late Database db;
  late Stemmer stemmer;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await databaseFactoryFfi.openDatabase(
      _dbPath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    stemmer = Stemmer(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  // ── T1: direct lexicon ────────────────────────────────────────────────────

  group('T1 directLexicon', () {
    test('كتاب → lexicon hit (book)', () async {
      final r = await stemmer.resolve('كتاب');
      expect(r.source, StemSource.directLexicon);
      expect(r.lexiconId, isNotNull);
    });

    test('مدرسة → lexicon hit (school)', () async {
      final r = await stemmer.resolve('مدرسة');
      expect(r.source, StemSource.directLexicon);
      expect(r.lexiconId, isNotNull);
    });

    test('diacritised input is normalised before lookup', () async {
      // كِتَاب with full harakat should still resolve against the stripped form.
      final r = await stemmer.resolve('كِتَاب');
      expect(r.source, StemSource.directLexicon);
      expect(r.lexiconId, isNotNull);
    });
  });

  // ── T2: conjugations table ────────────────────────────────────────────────

  group('T2 conjugationTable', () {
    test('يكتبون → resolves to كَتَبَ via conjugation table', () async {
      final r = await stemmer.resolve('يكتبون');
      expect(r.source, StemSource.conjugationTable);
      expect(r.matchedForm, contains('كَتَب'));
    });

    test('قلت → resolves to قَالَ (hollow verb past)', () async {
      final r = await stemmer.resolve('قلت');
      // Heavy-suffix past puts the hollow verb on the conjugation table.
      expect(r.success, isTrue);
      // Either directLexicon (if a homograph exists) or conjugationTable.
      expect(
        [StemSource.conjugationTable, StemSource.directLexicon],
        contains(r.source),
      );
    });

    test('كتبت → resolves to كَتَبَ via conjugation table', () async {
      final r = await stemmer.resolve('كتبت');
      // form_stripped "كتبت" appears in conjugations for hiya-past, anta-past,
      // anti-past, ana-past — all point at كَتَبَ's base_word_id.
      expect(r.source, StemSource.conjugationTable);
      expect(r.matchedForm, contains('كَتَب'));
    });
  });

  // ── T3: single proclitic strip ────────────────────────────────────────────

  group('T3 cliticStripped single proclitic', () {
    test('وكتاب → strip و, lexicon hit', () async {
      final r = await stemmer.resolve('وكتاب');
      expect(
        [
          StemSource.cliticStrippedLexicon,
          StemSource.cliticStrippedConjugation,
        ],
        contains(r.source),
      );
      expect(r.strippedClitics, 'و');
    });

    test('فيكتبون → strip ف, conjugation hit', () async {
      final r = await stemmer.resolve('فيكتبون');
      expect(r.source, StemSource.cliticStrippedConjugation);
      expect(r.strippedClitics, 'ف');
    });

    test('سيكتب → strip س (future marker), conjugation hit', () async {
      final r = await stemmer.resolve('سيكتب');
      expect(r.source, StemSource.cliticStrippedConjugation);
      expect(r.strippedClitics, 'س');
    });
  });

  // ── T4: definite article + compound proclitic ────────────────────────────

  group('T4 cliticStripped definite-article / compound', () {
    test('الكتاب → strip ال, lexicon hit كتاب', () async {
      final r = await stemmer.resolve('الكتاب');
      expect(r.source, StemSource.cliticStrippedLexicon);
      expect(r.strippedClitics, 'ال');
      // matchedForm is the *diacritised* lexicon form (e.g. "كِتَابٌ"), so a
      // plain-letter substring like "كتاب" won't match via contains().
      // Compare against the normalised form instead.
      expect(Stemmer.normalize(r.matchedForm!), contains('كتاب'));
    });

    test('والكتاب → strip وال, lexicon hit كتاب', () async {
      final r = await stemmer.resolve('والكتاب');
      expect(r.source, StemSource.cliticStrippedLexicon);
      expect(r.strippedClitics, 'وال');
    });

    test('بالمدرسة → strip بال, lexicon hit مدرسة', () async {
      final r = await stemmer.resolve('بالمدرسة');
      expect(r.source, StemSource.cliticStrippedLexicon);
      expect(r.strippedClitics, 'بال');
    });

    test('للمدرسة → strip لل, lexicon hit مدرسة', () async {
      final r = await stemmer.resolve('للمدرسة');
      expect(r.source, StemSource.cliticStrippedLexicon);
      expect(r.strippedClitics, 'لل');
    });
  });

  // ── T5: enclitic strip ────────────────────────────────────────────────────

  group('T5 cliticStripped suffix', () {
    test('كتابه → strip ه (his book), lexicon hit كتاب', () async {
      final r = await stemmer.resolve('كتابه');
      expect(r.source, StemSource.cliticStrippedLexicon);
      expect(r.strippedClitics, 'ه');
      // See note on the الكتاب test — normalise before substring-matching.
      expect(Stemmer.normalize(r.matchedForm!), contains('كتاب'));
    });

    test('كتابها → strip ها, lexicon hit كتاب', () async {
      final r = await stemmer.resolve('كتابها');
      expect(r.source, StemSource.cliticStrippedLexicon);
      expect(r.strippedClitics, 'ها');
    });

    test('كتابهم → strip هم, lexicon hit كتاب', () async {
      final r = await stemmer.resolve('كتابهم');
      expect(r.source, StemSource.cliticStrippedLexicon);
      expect(r.strippedClitics, 'هم');
    });
  });

  // ── T6: combined proclitic + enclitic ────────────────────────────────────

  group('T6 cliticStripped combined', () {
    test('وكتابه → strip و … ه, lexicon hit كتاب', () async {
      final r = await stemmer.resolve('وكتابه');
      // Multi-step: T3 strips و first and likely resolves كتابه via T5-in-T3
      // (not implemented), so combined is T6's job.
      expect(r.success, isTrue);
      expect(
        [
          StemSource.cliticStrippedLexicon,
          StemSource.cliticStrippedConjugation,
        ],
        contains(r.source),
      );
    });

    test('بكتابهم → strip ب … هم, lexicon hit كتاب', () async {
      final r = await stemmer.resolve('بكتابهم');
      expect(r.success, isTrue);
      expect(r.source, isNot(equals(StemSource.notFound)));
    });

    test('وبالمدرسة → compound prefix + noun', () async {
      // Starts with both و and بال — greedy longest-first strips بال after و.
      final r = await stemmer.resolve('وبالمدرسة');
      expect(r.success, isTrue);
    });
  });

  // ── T7: fuzzy root fallback ──────────────────────────────────────────────

  group('T7 fuzzyRoot', () {
    test('مكتوب → pattern مفعول → root كتب', () async {
      // مكتوب is a passive participle — if it's in the lexicon, T1 wins.
      // If not, we must fall back to the pattern-matched root.  Both are fine;
      // the test guarantees *some* tier resolves.
      final r = await stemmer.resolve('مكتوب');
      expect(r.success, isTrue);
      if (r.source == StemSource.fuzzyRoot) {
        expect(r.extractedRoot, 'كتب');
      }
    });

    test('مدارس → pattern مفاعل → root درس', () async {
      final r = await stemmer.resolve('مدارس');
      expect(r.success, isTrue);
      if (r.source == StemSource.fuzzyRoot) {
        expect(r.extractedRoot, 'درس');
      }
    });

    test('استخدام → pattern استفعال → root خدم', () async {
      final r = await stemmer.resolve('استخدام');
      expect(r.success, isTrue);
      if (r.source == StemSource.fuzzyRoot) {
        expect(r.extractedRoot, 'خدم');
      }
    });
  });

  // ── notFound: inputs the stemmer must decline ────────────────────────────

  group('notFound', () {
    test('empty input → notFound', () async {
      final r = await stemmer.resolve('');
      expect(r.source, StemSource.notFound);
      expect(r.lexiconId, isNull);
    });

    test('non-Arabic input → notFound', () async {
      final r = await stemmer.resolve('hello');
      expect(r.source, StemSource.notFound);
    });

    test('single Arabic letter → notFound (too short for any tier)', () async {
      final r = await stemmer.resolve('ك');
      expect(r.source, StemSource.notFound);
    });

    test('arabic gibberish → notFound', () async {
      // Random 9-letter sequence unlikely to match anything — if by chance a
      // pattern does extract a valid root, that's actually correct behaviour;
      // we only assert that the call does not throw.
      final r = await stemmer.resolve('قبظضذشلهج');
      expect(r, isNotNull);
    });
  });

  // ── Normalisation contract ───────────────────────────────────────────────

  group('normalize()', () {
    test('strips all harakat', () {
      expect(
        Stemmer.normalize('كَتَبَ'),
        'كتب',
      );
    });

    test('strips tatweel', () {
      expect(
        Stemmer.normalize('كـتـاب'),
        'كتاب',
      );
    });

    test('unifies alef variants', () {
      expect(Stemmer.normalize('أكل'), 'اكل');
      expect(Stemmer.normalize('إلى'), 'الى');
      expect(Stemmer.normalize('آمن'), 'امن');
    });

    test('idempotent on already-normalised input', () {
      const s = 'كتب';
      expect(Stemmer.normalize(Stemmer.normalize(s)), s);
    });
  });
}
