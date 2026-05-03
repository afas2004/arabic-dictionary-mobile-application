# Known Issues — Arabic Dictionary Search Stack
*Last updated: 2026-05-02*

This document catalogues every known problem in the search pipeline, grouped
by the layer that owns it.  Each entry states the symptom, the root cause, the
affected component, and the recommended fix.

---

## Layer 1 — Database (DB content / schema)

### DB-1 · Derived-form verb conjugations are incorrect (Gap B)
**Symptom:** Searching any present-tense Form V or Form X verb (e.g. `تستهدف`,
`يستخدم`, `يتحدث`) returns 0 results.  The base form (`استهدف`, `استخدم`,
`تحدث`) resolves fine when typed directly.

**Root cause:** The `populate_v13.py` script generated Form I conjugation
paradigms for verbs that are structurally Form V or Form X.  For example,
`استهدف` (Form X of `هدف`) received rows like `هدفت`, `هدفوا` instead of
`يستهدف`, `تستهدف`, `استهدفوا`.  Because rows already exist in the
`conjugations` table, the Dart engine considers the verb cached and never
regenerates the correct stems.  Every Form X verb currently has
`present_form_x = 0`.

**Affected component:** `arabic_dictionary_v13.db` → `conjugations` table;
`lib/engine/conjugation_engine.dart` (`_engineVersion`).

**Fix:** Bump `_engineVersion` from `4` to `5` in `conjugation_engine.dart`
and add a targeted `DELETE` to `_initDB` that removes only the incorrectly
generated rows (those belonging to derived-form verbs: `word_type = 'base_verb'`
AND `LENGTH(form_stripped) >= 4`).  On the next cold start the engine will
regenerate all Form V/X paradigms correctly.

---

### DB-2 · Alef normalisation creates homograph collisions
**Symptom:** Searching `اخلاء` (the normalised form of `إخلاء`, evacuation)
returns `أَخِلاَّء` (plural of `خليل`, close friends) instead of — or in
addition to — the intended word.  No disambiguation signal is surfaced to the
user.

**Root cause:** `Stemmer.normalize()` collapses all alef-hamza variants
(`أ / إ / آ / ٱ`) to bare `ا` before every DB lookup.  Different lexical items
that differ only in their initial hamza therefore map to the same `form_stripped`
key, and the DB returns all of them with equal ranking.

**Affected component:** `lib/engine/stemmer.dart` (`normalize()`);
`arabic_dictionary_v13.db` → `lexicon.form_stripped` column.

**Fix (short-term):** Add a frequency/is_common tie-break so the more common
word surfaces first.  **Fix (long-term):** Store original hamza spelling in a
separate `form_canonical` column and rank exact-hamza matches above
normalised matches, restoring the disambiguation that normalisation erased.

---

### DB-3 · `stemmer_test.dart` references the old v11 database
**Symptom:** `flutter test test/stemmer_test.dart` opens
`arabic_dictionary_v11.db`.  The v11 DB is missing conjugation rows added in
v12/v13, so several T2 and T3–T6 tests produce false negatives.

**Affected component:** `test/stemmer_test.dart` line 26 (`_dbPath`).

**Fix:** Update `_dbPath` to point at `arabic_dictionary_v13.db` and add test
cases for the new clitic-stripping and conjugation tiers.

---

## Layer 2 — Stemmer (`lib/engine/stemmer.dart`)

### ST-1 · Teh-marbuta + suffix not handled (Gap A)
**Symptom:** Words like `مدرستنا`, `سيارتها`, `حكومتهم` return 0 results.

**Root cause:** Arabic feminine nouns end in `ة` (teh-marbuta) in their base
form, but the final letter changes to `ت` when any suffix is attached
(`مدرسة + نا → مدرستنا`).  The stemmer's `_trySuffixes` and `_tryCombined`
tiers strip the suffix (leaving `مدرست`) but do not attempt a second lookup
with `ت → ة` substitution.  `مدرست` has no lexicon entry, so all tiers fail.

**Affected component:** `lib/engine/stemmer.dart` (`_trySuffixes`,
`_tryCombined`).

**Fix:** After stripping a suffix, if the remaining stem ends in `ت`, retry
the DB lookup with the final `ت` replaced by `ة`.

```dart
// Inside _trySuffixes / _tryCombined, after stripping suffix:
if (stem.endsWith('ت')) {
  final withTa = stem.substring(0, stem.length - 1) + 'ة';
  final hit = await _lookupLexicon(withTa);
  if (hit != null) return hit;
}
```

---

### ST-2 · T7 fuzzy root does not match present-tense derived-form verbs
**Symptom:** Even after Gap B (DB-1) is fixed, a word like `تستهدف` that is
genuinely absent from the conjugations table will still fail T7 because no
Khoja pattern covers a ت-prefixed Form X present tense.

**Root cause:** The pattern table encodes noun and verbal-noun templates
(`مفعول`, `استفعال`, `مفاعل`, etc.).  Present-tense verb prefixes (`ي / ت / ن / أ`)
introduce a family of patterns not represented in the table.  The last-resort
3-letter root extraction returns `تست`, which is not a valid Arabic root.

**Affected component:** `lib/engine/stemmer.dart` (`_tryFuzzyRoot`,
`triverbtable_data.dart`).

**Fix (primary):** Fix DB-1 so present-tense Form V/X verbs hit T2 and never
reach T7.  **Fix (supplementary):** Add imperfect-tense strip rules to T7 that
remove standard present-tense prefixes (`ي / ت / ن / أ` + optional Form marker)
before applying root extraction.

---

### ST-3 · Tolerant hamza fallback gap in T3–T6
**Symptom:** A word that combines a proclitic with a hamza-bearing stem (e.g.
`وسؤال`) may miss the tolerant REPLACE() scan in T3–T6 clitic-strip tiers.

**Root cause:** The `_conjNeedsTolerantFallback` guard and the always-on
lexicon tolerant scan are both applied at the point of the *initial* token
lookup (T1/T2).  When T3–T6 strip clitics and re-call `_lookupLexicon` /
`_lookupConjugation` on the stripped form, whether the tolerant scan fires
depends on whether the stripped form still carries a hamza character.  This
path has not been fully tested for every clitic combination.

**Affected component:** `lib/engine/stemmer.dart` (all clitic-strip tiers).

**Fix:** Add an integration test for each tier with a hamza-bearing stem
covered by a proclitic, and verify the tolerant scan fires correctly.

---

### ST-4 · Diacritized input loses disambiguation signal *(new)*
**Symptom:** A user who searches `كَتَبَ` (with full harakat) gets the same
result set as someone who searches `كتب` (unvocalised).  If there are multiple
homographs in the lexicon (different words sharing the same consonant skeleton),
all are returned with equal ranking — the harakat that uniquely identify the
intended word are discarded.

**Root cause:** `normalize()` strips all diacritics as step one, before any DB
query.  The original diacritized form is never compared against
`lexicon.form_arabic`, which retains the canonical harakat in the DB.  There
is no post-hit re-rank step.

**Affected component:** `lib/engine/stemmer.dart` (`normalize()`);
`lib/managers/search_manager.dart` (`_resolveToken`).

**Fix:** After a T1 direct-lexicon hit returns multiple candidates, run a
secondary pass: compare the user's original (non-normalised) input against
each candidate's `form_arabic` column using diacritic-aware equality.  Sort
exact harakat matches to the top before returning the result list.

```dart
// SearchManager._resolveToken — post-hit re-rank
if (direct.length > 1 && Stemmer.hasDiacritics(query)) {
  direct.sort((a, b) {
    final aMatch = a.formArabic == query ? 0 : 1;
    final bMatch = b.formArabic == query ? 0 : 1;
    return aMatch.compareTo(bMatch);
  });
}
```

---

### ST-5 · Form X present tense verbs return 0 results — `تستهدف` *(new)*
This is the user-visible symptom of DB-1 combined with ST-2.  Documented here
as a named issue because it is the most reported example.

**Full cascade (confirmed from device logs):**
- T1 miss — `تستهدف` is not in `lexicon.form_stripped`
- T2 miss — `conjugations` table has wrong rows for `استهدف` (Form I, not X)
- T3 miss — no single-character proclitic prefix reduces it to a known form
- T4 miss — no `ال` or compound proclitic
- T5 miss — no suffix strip produces a valid base form
- T6 miss — no proclitic + suffix combination resolves
- T7 miss — Khoja pattern table has no ت-prefixed Form X present-tense pattern
- **Result: 0 results, ~534ms wasted on fruitless DB scans**

**Note:** Typing the base form `استهدف` directly returns 1 result in ~62ms,
confirming the lexicon entry exists.  The problem is entirely in conjugation
coverage.

**Fix:** See DB-1.  Fixing the conjugation rows resolves T2 for all Form X
present-tense forms in one change.

---

## Layer 3 — Cache / Search Manager

### CM-1 · RAM cache is session-only; cold starts pay full DB cost *(new)*
**Symptom:** Every app restart re-runs all DB queries from scratch.  Pre-warm
loads only the top-100 common words.  Any word outside that set — including
all derived forms, conjugations, and less-frequent vocabulary — costs a full
T1/T2 round-trip on every cold launch.

**Root cause:** `CacheManager` is deliberately RAM-only.  The comment in
`cache_manager.dart` explicitly omits a disk tier ("SQLite already acts as
the persistent tier").  However, SQLite is being used as the *source of truth*,
not as a results cache.  Each search still assembles `Word` objects from raw
SQL rows on every cold start; there is no pre-materialised results layer.

**Affected component:** `lib/managers/cache_manager.dart`;
`lib/managers/search_manager.dart` (`preWarm`).

**Fix:** Implement a hybrid caching strategy:
1. **Expand pre-warm** — increase the common-word limit from 100 to 500–1 000
   and include the top conjugation forms (present/past 3rd-person of the 200
   most frequent verbs).  Cost: ~20–30ms extra at cold start, saves 50–100ms
   on first searches.
2. **Persistent results table** — add a small `search_cache` table to the DB
   (key TEXT PRIMARY KEY, result_ids TEXT, cached_at INTEGER).  Write through
   after each successful resolve.  On cold start, re-hydrate the RAM cache
   from the 500 most recently cached keys.  This gives the app near-zero
   latency for the user's own search history across restarts.
3. **Sentence-level caching** — the current code explicitly opts out of caching
   multi-token queries ("near-zero hit rate").  This is true for novel sentences
   but false for common phrases the user searches repeatedly.  A small secondary
   LRU (50 entries) keyed on the full normalised sentence would cover repeated
   Quranic/hadith phrases.

---

### CM-2 · Multi-token path skips stemmer for tokens that get a DB miss
**Symptom:** In a sentence search, tokens that miss the direct DB lookup are
silently dropped — they reach `_stemmerFallback` only if `_cache.get(token)`
returns null.  But after `_cachedDirectLookup` writes a miss back to cache as
an empty list, the `continue` guard on line 139 (`if (_cache.get(token) != null)
continue`) skips the stemmer for that token entirely.

**Root cause:** `_cache.get(token)` returns an empty list (not null) after a
write-through miss, which the guard treats as a cache hit and skips the stemmer
call.

**Affected component:** `lib/managers/search_manager.dart`
(`_searchArabic`, line 139).

**Fix:** Change the guard to check for a non-empty cached result:

```dart
// Before (line 139):
if (_cache.get(token) != null) continue;

// After:
final cached = _cache.get(token);
if (cached != null && cached.isNotEmpty) continue;
```

---

## Summary Table

| ID   | Layer          | Severity | Status       | Short description                             |
|------|----------------|----------|--------------|-----------------------------------------------|
| DB-1 | Database       | Critical | Open         | Form V/X conjugation rows are wrong           |
| DB-2 | Database       | Medium   | Open         | Alef normalisation creates homograph mismatches |
| DB-3 | Database       | Low      | Open         | Test file points at v11 DB                    |
| ST-1 | Stemmer        | High     | Open         | Teh-marbuta + suffix gap                      |
| ST-2 | Stemmer        | Medium   | Open         | T7 pattern table misses present-tense verbs   |
| ST-3 | Stemmer        | Low      | Needs testing| Tolerant scan may not fire in T3–T6           |
| ST-4 | Stemmer        | Medium   | Open         | Diacritized input loses disambiguation signal |
| ST-5 | Stemmer        | Critical | Open         | تستهدف / Form X present tense → 0 results    |
| CM-1 | Cache/Manager  | Medium   | Open         | No persistent cache; cold starts pay full cost |
| CM-2 | Cache/Manager  | High     | Open         | Multi-token stemmer skipped on empty cache hit |

---

*Fixes should be applied in priority order: DB-1 + ST-5 (same root fix) first,
then CM-2 (one-line code change, high value), then ST-1, then ST-4 and CM-1.*
