# Arabic Dictionary — Handoff to Code Chat

This document hands a Flutter Arabic-English dictionary project from a
Cowork-mode planning/design session to Claude Code for the active build,
debug, and UI implementation work.

Target audience: the next Claude instance running in Code Chat with shell
access to this repo on the user's machine. Read this end-to-end before
touching code.

---

## 1. Project Briefing

**What it is.** An offline-first Arabic-English dictionary built in Flutter.
Ships the entire dictionary as a bundled SQLite asset so it works with zero
network. Primary audience: Arabic learners (learner-grammar slant, not
classical Arabic philology). It is the user's final-year project.

**Who the user is.** Fahmi (`afahmi2004@gmail.com`). Developer-ish but not a
Flutter veteran. Prefers being shown *what to change and why* over being
handed a PR and told to trust it. Will be running the app on a real device
via `flutter run`, so your debugging loop involves an actual emulator/phone,
not just `flutter test`.

**Architecture at a glance.**

- Flutter + `flutter_bloc` for state (Cubits, not full Blocs).
- SQLite via `sqflite` — DB shipped as asset, copied to app docs dir on
  first launch, opened read/write for index creation.
- Search pipeline is three layers:
  1. `SearchManager` (business layer) — orchestrates the cascade.
  2. `Stemmer` (engine layer) — 7-tier resolver, DB-aware.
  3. `DictionaryRepository` (data layer) — pure SQL.
- UI: Material, `google_fonts` for Noto Naskh Arabic + Manrope, RTL handling
  done per-widget rather than app-wide.

**Build state.** Android primary target. iOS/macOS/Linux/Windows
scaffolding exists in the repo but nobody is building for those; if
`git status` shows 80+ modified platform files, that is line-ending drift
from moving the repo between machines, not intentional change. Ignore it
or normalize with a `.gitattributes` in a separate commit — do not mix it
with feature commits.

---

## 2. Runtime State You Are Inheriting

### What works

- The app builds and launches.
- Search works on lexicon entries that already existed in v9.
- The 7-tier stemmer is present at `lib/engine/stemmer.dart` and its DB
  lookups resolve correctly against v11 when v11 is actually shipped.
- A settings screen exists at `lib/screens/settings_screen.dart` with a
  six-swatch theme-color picker wired to `ThemeController`. The swatch tap
  does propagate via `notifyListeners()` → `AnimatedBuilder` in
  `lib/main.dart` → rebuilds `MaterialApp` with new `ColorScheme`.

### What is broken right now

- **The v11 DB is not actually shipping in the APK.** `pubspec.yaml` now
  declares `assets/arabic_dictionary_v11.db` and the file is in `assets/`,
  but the user's last build was before those changes landed. APK size
  went from 54 MB → 58 MB when it should have jumped to ~80 MB. Until the
  v11 DB ships, `يكتبون` returns zero results because the `conjugations`
  table is v11-only.

- **Last commit message is mangled.** Commit `839e073` has
  `$(cat <<'EOF'` literally as its subject line because a heredoc didn't
  expand when pasted into the shell. The *content* of that commit is
  correct (theme controller, settings screen, highlighter fix, plus some
  earlier stemmer work). Amend or leave it — but if you push a fix, do it
  deliberately and document it.

- **`git status` is noisy.** The `git status` shows ~80 modified platform
  scaffolding files (iOS/Android/macOS/Windows/Linux). These are almost
  certainly line-ending changes, not real edits. Do not stage them as part
  of feature work. Either leave them dirty or commit them alone as
  `chore: normalize line endings`.

### What was explicitly *not* done

The HTML mockup file `ui_mockups_v2.html` is a design spec, not
implementation. Only two Flutter code changes landed this session:

1. Highlighter bug fix (`lib/utils/text_highlighter.dart` +
   `lib/screens/search_screen.dart` wiring).
2. Theme controller + settings screen (`lib/controllers/theme_controller.dart`,
   `lib/screens/settings_screen.dart`, `lib/main.dart` wiring, minor swaps
   in `word_detail_screen.dart`).

The full mockup redesign — token filter bar, long-press action sheet,
detail-page tabs, favourites, recent searches, copy-bundle — is all still
unbuilt. That is the bulk of the work you are inheriting.

---

## 3. Immediate Blocker: Ship the v11 DB

This has to be resolved before anything else, including testing the
highlighter fix, because the search pipeline silently degrades without v11.

### Steps

```bash
# from project root
flutter clean
flutter pub get
# uninstall the app from device/emulator so the stale app-documents-dir
# file (arabic_dictionary_v9.db) is cleared. this matters because the
# repository code uses typeSync() which returns "exists" for the stale
# file and skips the bundle copy.
adb uninstall com.example.arabic_dictionary   # or whatever the package is
flutter run --release
```

### Verification

- APK size should be ~80 MB (up from 54 MB).
- Query `يكتبون` should return the lemma `كَتَبَ` with root letters
  highlighted.
- Query `اخذ` (bare alef) should match `أَخَذَ` (hamzated) — this exercises
  the alef-unification path added to `highlightArabicQuery`.
- Tapping a result should open the detail screen with a populated
  conjugation table (Past / Present / Imperative, 4×3 grid).

### If search still returns blank after a clean rebuild

Likely causes in order of probability:

1. DB file didn't end up in the APK. Check with
   `unzip -l build/app/outputs/flutter-apk/app-release.apk | grep v11`.
   If missing, confirm `pubspec.yaml` has `assets: - assets/arabic_dictionary_v11.db`
   (note the two-space indent and leading hyphen) and run
   `flutter clean && flutter pub get` again.
2. DB file shipped but is the wrong one. Pull it back out of the APK and
   run `sqlite3 extracted.db "SELECT COUNT(*) FROM conjugations"` — should
   be ~306k rows.
3. DB shipped, populated, but the Stemmer's DB handle isn't being passed
   in. Check `lib/main.dart` — `Stemmer(db)` is constructed with
   `repository.rawDatabase`. If that getter doesn't exist, look at an
   earlier commit for its definition.

---

## 4. Scope of Remaining Work

Broken into phases by dependency, not priority. Phase 1 is the blocker.
Phases 2–4 are roughly independent — do them in whatever order the user
wants. Phase 5 is polish.

### Phase 1 — Ship the v11 DB (§3 above)

Non-negotiable prerequisite for everything else.

### Phase 2 — Implement the list-tile redesign from the mockup

Source of truth: `ui_mockups_v2.html`, sections "List Page" and "Detail
Page". Compare against the current `lib/screens/search_screen.dart`
`_buildWordTile`.

The current tile is structurally close to the mockup already: it has the
"from" + base form / Weak Root badge on the left, COMMON green badge
below, romanization in parens, Arabic form, word type + verb form label,
and meaning. What the mockup adds:

1. **Token filter chips above the list.** When the user types a multi-word
   English query or a phrase, chips appear (one per token) and can be
   tapped to filter down. Currently not implemented. Decide with the user:
   does it filter the result set client-side, or does it rerun the query?
   Client-side is simpler and matches what the mockup implies.

2. **Long-press action sheet on a list tile.** Options per the user's
   spec: copy word, copy meaning, copy word+meaning, copy word bundle,
   favourite, share bundle. The "bundle" is a multi-line string: lemma +
   first-listed meaning, plus initial tenses for verbs (past, present,
   imperative) or plural forms for nouns. Format the user agreed to:

   ```
   kataba: to write, to compose
   kataba, yaktubu, uktub
   ```

   Romanization is not required in the bundle per the user. Implement this
   as a `showModalBottomSheet` — Takoboto-style. The mockup has a
   reference illustration under "Action sheet".

### Phase 3 — Implement the detail-page redesign

Source of truth: `ui_mockups_v2.html` "Detail Page" sections (verb and
noun variants).

Current `lib/screens/word_detail_screen.dart` shows the header, meanings
list, and a 4×3 conjugation grid. The mockup reorganizes this into tabs:

- **Verbs:** Grammar / Root / Conjugation
- **Non-verbs (nouns/adjectives):** Grammar / Root / Forms (plural,
  feminine, mansub, comparative)

"Root" tab shows the root family — all words sharing this root, clickable,
capped at some number (the user agreed to cap at 10 to prevent
common-root drowning).

"Grammar" tab is the pedagogical layer: word type, verb form, binyan
pattern, voice, tense. For learner users, not philologists.

Preserve the existing 4×3 conjugation grid *exactly* — the user called
this out specifically last session. Columns are أنتِ / أنتَ / هي / هو,
rows are Singular / Dual / Plural, followed by a نحن / أنا first-person
strip. Do not replace this with a simpler format.

A granular copy icon next to the Arabic headword (per the user's spec)
should copy only the word, no meaning. Distinct from the long-press
bundle action.

### Phase 4 — Add the missing screens

The mockup includes placeholders for five screens that don't exist in
Flutter yet:

1. **Empty state** (before any search). Current app shows a centered gray
   "Search anything in Arabic/English..." string. Mockup adds "Recent
   searches" pinned to the empty state.
2. **Recent searches** — list of the last N queries, tap to re-run.
   Persist via `shared_preferences`.
3. **Favourites** — list of words the user has starred. Persist via the
   DB (new table, or `shared_preferences` of lexicon IDs — start with the
   latter for simplicity).
4. **No-results state.** Current app shows "No results found." — mockup
   adds a suggestion to try the romanized form or search by root.
5. **Settings.** Done. Theme-color swatch picker. `shared_preferences`
   persistence is NOT yet done — add it so the choice survives restarts.

### Phase 5 — Polish, accessibility, performance

- Persist `ThemeController.primaryColor` via `shared_preferences`.
- Add dark mode toggle to settings. `ThemeController` is the right place.
- The `lexicon_fts` table in the v11 DB is currently unused — the English
  search goes through LIKE queries. If English search feels slow on real
  data, wire `lexicon_fts` into `searchEnglish` in the repository. Note:
  the FTS table's columns don't match what the Dart code would naively
  expect — `CREATE VIRTUAL TABLE lexicon_fts USING fts4(meaning_text, content="meanings")` — so you query via
  `MATCH` against `meaning_text` and join back on rowid.
- The bundled DB is 49 MB. Dropping `lexicon_fts*` tables would shave a
  few MB; running `VACUUM` another 10–20%. Shipping gzipped and
  decompressing on first launch cuts the download further. None are
  required.

---

## 5. Architectural Primer

### 5a. The 7-tier stemmer cascade

Read `lib/engine/stemmer.dart`'s header comment end-to-end before modifying
search behavior. In short:

- T1 direct lexicon lookup on `form_stripped`
- T2 conjugations table lookup → returns `base_word_id`
- T3 strip one single-char proclitic, retry T1/T2
- T4 strip ال and compound proclitics (وال/بال/كال/فال/لل), retry
- T5 strip one enclitic (ه/ها/هم/كم/ني/…), retry
- T6 prefix × suffix combo, capped at 30 pairs
- T7 fuzzy root via Khoja pattern analysis → lexicon lookup by `root`

Every input is normalized at build time *and* query time with the same
pipeline: strip diacritics (U+064B..U+065F, U+0670), strip tatweel
(U+0640), unify alef variants (أ إ آ ٱ → ا). If you change this, change
it in both the Dart stemmer and `populate_conjugations.py` — currently
they match.

The stemmer emits `[PERF] tier=TX … µs` logs. `SearchManager` can surface
these in debug builds for profiling.

### 5b. Provider chain

`main.dart` sets up the chain in this order, outermost to innermost:

```
MultiRepositoryProvider
  ├─ RepositoryProvider.value(repository)
  ├─ RepositoryProvider.value(searchManager)
  └─ RepositoryProvider.value(themeController)
MultiBlocProvider
  └─ BlocProvider(SearchCubit)
AnimatedBuilder(animation: themeController)
  └─ MaterialApp
      └─ SearchScreen
```

Anything that needs to read/mutate theme uses
`context.read<ThemeController>()`. The `AnimatedBuilder` rebuilds
`MaterialApp` on every `notifyListeners()` call, which causes the whole
widget tree under it to re-derive `Theme.of(context).colorScheme.primary`.

If you add new cross-cutting state (e.g. favourites, recent searches), add
it as a `ChangeNotifier` exposed via `RepositoryProvider.value` and read
from context, unless it's specifically bloc-shaped — then add a BlocProvider.

### 5c. Theme-integration rule

The primary color is `Theme.of(context).colorScheme.primary`. Currently
themed surfaces:

- Search-bar magnifying-glass icon
- Detail-screen favourite star icon

Deliberately NOT themed (semantic colors):

- `TextHighlighter.matchColor` (still hardcoded `0xFF1976D2` blue) — this
  is the "this matched your query" signal. Discussed with the user: if
  the user picks a different theme and you want the highlight to match,
  fine, but be explicit about it. Current default: stays blue.
- COMMON badge (green) and Weak Root badge (red) — stay fixed because they
  are semantic signals independent of user preference.

The user's feedback after the first build was that the theme felt
invisible because only two pixels of the app were themed. If you want to
expand theming, the biggest lever is AppBar accents and the highlight
color itself. Ask the user before making that call — they previously said
"default blue works best" and wanted theming mostly as a placeholder.

### 5d. Highlighter semantics: EXACT or ROOT only

`lib/utils/text_highlighter.dart` implements the "EXACT or ROOT only"
policy — there is no in-between state like "partial match" or "prefix
match" that gets a different color.

- `highlightArabicQuery(text, query)` tries to match the query as a
  substring of the text (diacritic-agnostic, alef-variant-agnostic).
  Returns `const []` on no-match so the caller can fall through.
- `highlightArabicForList(text, query, root)` is the list-tile entry
  point. Tries exact first, falls back to `highlightRootWithMutations`
  keyed on the word's root. Every tile renders one of the two — never a
  blank tile.
- `highlightRootWithMutations(text, root, {mutationLetters})` is used by
  the detail-page conjugation grid to highlight root radicals blue and
  weak-verb mutation letters (ا/ى replacing missing radicals) red.
- `highlightArabicBaseForm(text, formStripped)` highlights the full
  consonant set of the base form including morphological prefixes (أ for
  Form IV, ا+ت for Form VIII, اسـت for Form X). Used inside derived-form
  conjugation tables so the Form X prefix is visibly part of "the word"
  rather than confused with mutations.

If you add a new tile or row type, pick one of these entry points. Don't
invent a new half-way highlighter without consensus — the rendering
consistency matters more than micro-optimizing a single case.

### 5e. Conventions

- Relative imports within `lib/`, e.g. `../controllers/theme_controller.dart`.
- No explicit `late` or `!` bang on repository/stemmer fields that are
  required at construction — pass them as constructor args and keep them
  `final`.
- Comments at the top of non-trivial files explain *why* the file exists
  and what invariants it maintains. Don't strip these when editing — they
  are load-bearing context for future sessions.

---

## 6. File Map

Files you will touch or read most often:

### Business + engine layer
- `lib/engine/stemmer.dart` — 7-tier cascade. Read header comment before
  modifying.
- `lib/engine/conjugation_engine.dart` — generates verb conjugations at
  DB-build time. Only relevant if you regenerate the DB.
- `lib/engine/triverbtable_data.dart` — static data tables for
  conjugation patterns.
- `lib/managers/search_manager.dart` — orchestrates
  stemmer + repository calls, ranks results.
- `lib/managers/cache_manager.dart` — in-memory LRU for hot queries.
- `lib/repositories/dictionary_repository.dart` — SQL queries. Every
  method is one query.

### UI layer
- `lib/screens/search_screen.dart` — list view, search input, tile
  layout.
- `lib/screens/word_detail_screen.dart` — header, meanings, conjugation
  grid.
- `lib/screens/settings_screen.dart` — theme picker.
- `lib/cubits/search_cubit.dart` — search state machine.
- `lib/cubits/word_detail_cubit.dart` — detail screen state.

### Utilities
- `lib/utils/text_highlighter.dart` — see §5d.
- `lib/utils/formatters.dart` — `formatWordType`, `detectVerbFormLabel`,
  `shouldDisplayRoot`, `isWeakRoot`. Preserve these — they encode the
  list-tile display rules.

### Models
- `lib/models/models.dart` — `Word`, `Meaning`, `Conjugation`. Equatable.
  `Word.fromMap` reads joined fields `meaning_text` and `base_form_arabic`
  that come from the repository's LEFT JOINs — don't remove them.

### Controllers
- `lib/controllers/theme_controller.dart` — `ChangeNotifier`, primary
  color. Add dark-mode state + `shared_preferences` persistence here when
  Phase 5 starts.

### Assets
- `assets/arabic_dictionary_v11.db` — the dictionary DB. 49 MB.
- `assets/arabic_dictionary_v9.db` — legacy, no longer declared in
  pubspec. Safe to `git rm` in a cleanup commit.
- `assets/arabic_dictionary_v7.db` — even older. Same.

### Design
- `ui_mockups_v2.html` — the design spec for Phases 2–4. Open in a
  browser — it uses JS to render Arabic highlighting so copy-paste doesn't
  work reliably.
- `ui_mockups.html` — earlier iteration; superseded by v2.

### Reports
- `UI_PRIORITY_AND_CACHE.md` — ranking logic and cache policy write-up.
- `stemmer_eval_report.html` — stemmer tier-by-tier pass/fail evaluation.

### Tests
- `test/search_results_test.dart` — end-to-end search tests.
- `test/stemmer_test.dart` — stemmer tier tests.
- `test/word_detail_cubit_test.dart` — cubit state transitions.

---

## 7. Testing Checklist

After Phase 1 (shipping v11), manually verify on device:

- [ ] App launches without exception.
- [ ] APK size is roughly 80 MB (release build).
- [ ] Search `كتاب` → result highlights the literal substring.
- [ ] Search `يكتبون` → result is `كَتَبَ`, root letters highlighted blue.
- [ ] Search `اخذ` → result is `أَخَذَ`, letters highlighted (alef
      unification path).
- [ ] Search `write` (English) → returns Arabic verbs meaning to write,
      English word `write` highlighted in the meaning column.
- [ ] Tap a result → detail screen loads.
- [ ] Conjugation grid renders in 4×3 format with نحن/أنا strip below.
- [ ] Gear icon in AppBar → settings screen opens.
- [ ] Tap a different swatch → search and detail screen accents change
      color (search icon, favourite star). Check that not everything
      changes (highlight color should stay blue by design).

Automated tests to run (`flutter test`):

- `test/stemmer_test.dart` — all tiers pass
- `test/search_results_test.dart` — the baseline cases the user has been
  iterating on
- `test/word_detail_cubit_test.dart` — untouched this session, should
  still pass

If the cubit or search-results tests fail and the failure references
something introduced this session (the new `highlightArabicForList`
method, `ThemeController`), that's my fault — investigate. If they fail
referencing unrelated files (models, formatters, etc.), that's drift
from earlier sessions — check recent commits.

---

## 8. Design Decisions the User Has Already Committed To

Do not relitigate these unless the user brings them up:

1. **Offline-first.** No network calls anywhere.
2. **Single-color highlighting.** Matches are a single shade — no
   gradient between "very close" and "sort of close". The two states that
   exist are EXACT (substring match) and ROOT (the root radicals). No
   third tier.
3. **Root family capped at 10** in the root tab. Prevents common roots
   from drowning the list.
4. **Root family comes before prefix-match in result ranking.** If the
   user searches كتب, the lemma and root family outrank `كتيب`-prefix
   results.
5. **Provenance labels (lexicon source) hidden by default.** The user
   doesn't want Hans Wehr / Lane / Lisan tags surfaced in the UI. The DB
   has the data but the UI ignores it.
6. **Default theme is blue.** Theming is a personalization layer, not a
   rebrand. Ship with blue as the default and don't push users to change.
7. **No romanization in the copy bundle.** Users who want transliteration
   can see it on the detail page; the bundle is lemma + meaning + tenses
   only.
8. **Granular copy icon copies word only** (no meaning); long-press sheet
   offers more options.
9. **Takoboto is the UX reference** for the list-tile layout and the
   long-press action sheet. When in doubt, mimic Takoboto.
10. **Preserve the existing 4×3 conjugation grid.** Don't replace it with
    a simpler layout even if it seems cleaner. The user called this out
    explicitly.

---

## 9. Open Items (From the Mockup) That Need a Decision Before Implementing

These are unresolved — ask the user before building:

1. **Token filter behaviour.** Do the chips filter client-side (show the
   full result set, hide rows that don't contain the token) or rerun
   the search with the token as an additional constraint? Client-side is
   simpler and faster; server-side is more rigorous. Suggestion:
   client-side, rows where *any* token appears.
2. **Favourites storage.** `shared_preferences` of lexicon IDs, or a new
   DB table with timestamp and user notes? Start with the former;
   upgrade later if notes become a requirement.
3. **Recent searches depth.** Last 20? Last 50? User hasn't said.
   Suggestion: 20, persistable via `shared_preferences`.
4. **Theme color applied to highlight color.** Currently the highlight
   is hardcoded blue regardless of theme. User liked this because
   highlight is a semantic signal. But the theme feels invisible without
   it. Worth a user decision.
5. **Dark mode.** Not in the mockups but the user mentioned
   personalization in general. Low priority unless asked.

---

## 10. Handoff Checklist for the Incoming Claude Code Instance

Before you start making changes:

- [ ] Read this file end-to-end.
- [ ] Open `ui_mockups_v2.html` in a browser to see the design target.
- [ ] Run `git log --oneline -20` to understand the commit history style.
- [ ] Run `git status` and notice the noisy platform-scaffolding diffs;
      exclude them from your first commit.
- [ ] Confirm the mangled last commit `839e073` is real by running
      `git log -1 --format="%s"` — expect literal `$(cat <<'EOF'`. Decide
      with the user whether to amend it.
- [ ] Finish Phase 1 (§3) and verify via the testing checklist (§7)
      before touching any new feature work.
- [ ] When in doubt about a design call, refer to §8. When in doubt about
      a decision, refer to §9 and ask the user.

Good luck. The user is thoughtful and will push back when something
doesn't feel right — trust the feedback, don't dig in defensively.
