# Flutter UI retuning — priority list & hybrid cache schema

Companion doc to `lib/engine/stemmer.dart` and `lib/managers/search_manager.dart`.
Describes what the UI layer needs to do to actually surface the new 7-tier
cascade's capabilities, plus a proposed two-tier cache design.

---

## Part A — UI priority list

The new cascade returns richer data than the old stemmer: every resolution
now carries a **tier source**, the **stripped clitics** (for T3–T6), and the
**extracted root** (for T7). The current UI throws all of that away. The
priority list below is ordered by user-visible impact; pick whichever horizon
you can afford before viva.

### P0 — must ship

**1. Surface the resolution tier on every result card.**
A result that came from T1 (direct lexicon hit, high confidence) should look
visually distinct from one that came from T7 (pattern-based guess, lower
confidence). Right now they look identical, which means users silently trust
T7 results they shouldn't.

Concrete design: a small pill/badge in the upper-right of the card.

| Tier        | Badge text            | Colour   |
|-------------|-----------------------|----------|
| T1          | "Direct match"        | green    |
| T2          | "Conjugation of ..."  | green    |
| T3–T4       | "Stripped: و‎+ال"     | blue     |
| T5–T6       | "Stripped: ـه"        | blue     |
| T7          | "Root-based: كتب"     | amber    |

The `Word` model returned by `SearchManager` does not currently carry the
tier — it'll need a new field like `MatchProvenance { source, strippedClitics,
extractedRoot }` attached per-result.

**2. Show the stripped clitics when any were removed.**
For queries like وبالمدرسة, explicitly render the decomposition as
و + ب + ال + مدرسة. This does two things at once: it teaches learners how
the morphology decomposed, and it builds trust in the search (they can see
*why* مدرسة came back for a different-looking query).

Where to put it: a secondary line below the main word, in a lighter weight,
with each clitic highlighted. On tap, an info tooltip explaining what each
clitic means (و = "and", ال = definite article, etc.).

**3. Multi-candidate display for homographs.**
Even after the ranking fix, words like بيت or ذهب have multiple equally
valid dictionary senses. The cascade currently returns one; the UI should
display all candidates ranked, with the top pick expanded by default. The
`directArabicLookup` in the repository already returns a List — it's
`SearchManager` and the UI that collapse to a single winner. Stop doing that.

Rendering: a stack of result cards. First card full-size, rest collapsed
to one line each ("also found: بَيَّتَ — to plan overnight"). Tap to expand.

**4. Make the extracted root (T7) a tappable link.**
When T7 fires and returns extractedRoot = "كتب", render it as a styled
chip or link. Tap → opens a screen listing every lexicon entry whose
`root` column contains كتب (sorted by common-first). This is THE killer
feature for Arabic learners — root-browsing is how Arabic dictionaries
historically worked (Lane's Lexicon, Hans Wehr), and your DB already has
the `root` column indexed for it.

### P1 — important but deferrable

**5. Conjugation paradigm panel on T2 hits.**
When a query resolves via T2 (e.g. user typed يكتبون and cascade returned
كَتَبَ), the detail page should show the full paradigm for كَتَبَ —
past-huwa through jussive-hum, 31-ish forms — with the specific matched
cell (3mp-present) highlighted. Data source: the `conjugations` table,
filtered by `base_word_id = result.lexiconId`. Group by tense, render as a
table. This is where the 306k-row conjugations population finally pays
off at the UI layer.

**6. Per-token breakdown for sentence input.**
`SearchManager._searchArabic` already handles multi-token queries with
per-token resolution. The UI probably renders the merged result set without
showing the structure. Proposal: when the input has >1 token, render a
horizontal chip row at the top showing each token → its best lemma,
then the merged results below. Makes the app useful for glossing
news headlines and Quran verses, not just single-word lookup.

**7. Tier-coloured result list accent.**
A subtle 2–3px coloured left border on each card matching the tier badge
colour. Instantaneous visual scanning — users can see "all green, high
confidence" vs. "mixed amber/blue, fuzzy day" at a glance.

### P2 — polish

**8. Recent searches** on the empty search screen. Pull from the L2 cache
(see Part B) ordered by `last_accessed DESC LIMIT 20`.

**9. "Did you mean?" for weak T7 hits.** If cascade lands at T7 and the
resolved form's root confidence feels low (e.g. the extracted root has
fewer than N lexicon entries), surface a "did you mean: X?" strip above
the results.

**10. Debug overlay** showing tier + timing per query, gated behind
`kDebugMode`, pinned to the corner. Useful during viva demos if anyone
asks "how fast is it" — they can see it live.

### Implementation sequence I'd suggest

1. Extend `Word` (or create `SearchResult`) with a `MatchProvenance` field
   populated from `StemResult`. Touches model + repository + manager.
2. P0 #1 (tier badge) — pure UI change, quickest to ship.
3. P0 #2 (clitic decomposition) — UI + minor localisation work.
4. P0 #3 (multi-candidate) — refactor `SearchManager` to stop collapsing T1
   hits to a single Word.
5. P0 #4 (root link + browse screen) — new screen, new repository query
   (already exists as `exactRootLookup`).
6. P1 items thereafter, in whichever order aligns with what you can demo.

---

## Part B — Hybrid cache schema

"Hybrid caching" in mobile-dictionary context means **RAM + persistent
disk**, with write-through semantics and LRU eviction at both levels. The
current `CacheManager` is RAM-only, so every cold-start loses all search
history and the first ~20 queries of a session pay full cascade cost.

### Design

```
                    ┌─────────────────────────────┐
  SearchManager ──▶ │  L1 (RAM)                   │  hit: ~1µs
                    │  LinkedHashMap<String, ...>│
                    │  size-bounded LRU, 500 max  │
                    └──────────┬──────────────────┘
                               │ miss
                               ▼
                    ┌─────────────────────────────┐
                    │  L2 (disk, sqflite)         │  hit: ~3–8ms
                    │  search_cache table         │
                    │  time-bounded LRU           │
                    └──────────┬──────────────────┘
                               │ miss
                               ▼
                    ┌─────────────────────────────┐
                    │  Cascade (T1 → T7)          │  hit: 1–30ms
                    └─────────────────────────────┘
```

### L1 (RAM)

Already mostly correct — keep `CacheManager` as a `LinkedHashMap<String,
List<Word>>`, which gives you insertion-order iteration for LRU at O(1)
per op. One change: currently it's unbounded (or bounded by a value I'd
need to double-check). Set a hard cap — 500 entries is plenty; at an
average of maybe 2 KB per result list that's ~1 MB of RAM. On put, if
size > cap, `remove(keys.first)`.

Key = `CacheManager.normaliseKey(query)` — already implemented correctly
(strips diacritics/tatweel/alef variants).

### L2 (disk) — new table in the same sqflite DB

```sql
CREATE TABLE IF NOT EXISTS search_cache (
  query_key       TEXT PRIMARY KEY NOT NULL,   -- normalised query string
  result_ids      TEXT NOT NULL,               -- JSON array of lexicon.id
  tier_source     TEXT,                        -- 'T1' / 'T2' / ... for telemetry
  clitics         TEXT,                        -- stripped clitics (if any)
  extracted_root  TEXT,                        -- for T7 hits
  last_accessed   INTEGER NOT NULL,            -- unix epoch ms
  created_at      INTEGER NOT NULL,            -- unix epoch ms
  hit_count       INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_cache_access ON search_cache(last_accessed DESC);
CREATE INDEX IF NOT EXISTS idx_cache_hits   ON search_cache(hit_count DESC);
```

Notes on schema choices:
- `result_ids` as JSON text rather than a separate join table. You only
  ever read the full list, never query into it, so JSON beats the joins.
- `tier_source`, `clitics`, `extracted_root` duplicate info from
  `StemResult` — optional, but handy for two things: (a) populating the
  tier badge from cache without re-running the cascade, and (b) later
  analytics if you want to see "what percent of user queries hit T7?"
- `hit_count` lets you pre-warm L1 with the most-used entries on startup,
  not just the most-recent.

### Read path (pseudocode)

```dart
Future<List<Word>> cachedSearch(String query) async {
  final key = normaliseKey(query);

  // L1
  final l1 = _ramCache.get(key);
  if (l1 != null) return l1;

  // L2
  final l2 = await _diskCache.get(key);
  if (l2 != null) {
    _ramCache.put(key, l2);                       // promote
    await _diskCache.touch(key);                  // bump last_accessed + hit_count
    return l2;
  }

  // cascade
  final fresh = await _runCascade(query);
  _ramCache.put(key, fresh);
  await _diskCache.put(key, fresh);               // write-through
  return fresh;
}
```

### Write-through + eviction

- **L1 put:** `LinkedHashMap.remove(keys.first)` if size exceeds 500.
- **L2 put:** `INSERT OR REPLACE INTO search_cache ...`.
- **L2 purge:** run on app start (not every put — too much I/O):
  ```sql
  DELETE FROM search_cache
  WHERE last_accessed < (strftime('%s', 'now', '-30 days') * 1000)
    AND hit_count < 3;
  ```
  Keeps "core vocabulary" (high hit count) forever, sweeps out one-off
  lookups after 30 days.

### Pre-warm on cold start

Your current `preWarm()` pulls `getCommonWords()` from the lexicon and
seeds L1. Extend it with a second pass that hydrates L1 from L2's
most-hit entries:

```sql
SELECT query_key, result_ids FROM search_cache
ORDER BY hit_count DESC, last_accessed DESC
LIMIT 100;
```

This makes the second launch feel instantaneous even on queries that
weren't in the common-words seed — e.g. the user's personal vocab.

### Where "hybrid" goes beyond just RAM+disk

Two extra axes worth mentioning for the FYP chapter, even if you don't
implement them all:

- **Key hybrid: raw query AND normalised form.** Currently L1 keys on
  normalised form, which is correct. If you ever want to surface the
  user's literal input in recents, store both the raw and normalised
  forms.
- **Value hybrid: per-token AND per-phrase cache.** Sentence searches
  decompose into tokens; caching each token individually gives massive
  hit rates on the second sentence that shares any vocabulary with the
  first. Already implicitly supported by `_cachedDirectLookup` but worth
  stating explicitly in the report — it's one of the things that
  separates a naïve string cache from a hybrid one.

### What to cite in the FYP

- **Locality of reference** — classic Denning (1972) and Belady (1966).
  Justifies LRU choice.
- **Two-tier / multi-level caching** — Smith (1982) *Cache Memories*
  survey, or any modern textbook (Patterson & Hennessy) for the general
  architecture principle.
- **Write-through vs. write-back** — same references; you're
  write-through, which is right for a read-heavy dictionary workload.
- **Mobile cache sizing** — no single canonical reference; cite any
  Android/iOS developer documentation on memory pressure and the
  reasoning that 500-entry RAM caps ~1 MB, well under the low-memory
  kill thresholds.

---

## What's done vs. what's next

Done in this pass:
- ✓ T1 lexicon `ORDER BY` flipped (noun preferred over rare verb homographs)
- ✓ T2 conjugations `ORDER BY` flipped (common base-verb beats rare paradigm collisions)
- ✓ `stemmer_eval_report.html` re-run: 92/92 with expanded homograph group

Parked for next session (flag these when you're ready):
- ☐ `Word` / `SearchResult` refactor to carry `MatchProvenance`
- ☐ `CacheManager` — bound L1 size, add L2 table + read/write/purge paths
- ☐ P0 UI changes in order (tier badge → clitic decomposition → multi-candidate → root link)
- ☐ Lexicon data tuning for ورد / ذهب and other dual-common homographs
  (set `is_common` / `frequency` for the preferred sense manually)
