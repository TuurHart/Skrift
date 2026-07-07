# Journal & retrieval plan — P8 (On This Day · timeline/map · semantic related-notes · search)

Planned 2026-07-06 (Fable survey session), for a next Opus session to execute. Roadmap node **P8**
(lane "Journal & Search", currently `planned`). This is the north-star backbone: *"a years-old
thought resurfaces next to today's."* Unclaimed as of writing — note-editing, audiobooks, and the
live-sync/Bonjour-removal handoff are owned by other sessions (collision map at the bottom).

> ✅ **GATE UPDATE (Tuur, 2026-07-07): parallel build green-lit** on branch
> `claude/youthful-wozniak-a79a3b`, merged via PR. Conflict-free chunks (1–3, new files only) are
> BUILT; **UI chunks (4–8) still wait for the other lanes to merge first** (tab bar / memos list /
> detail view — see the collision map). Mock signed off 2026-07-06; research done.

## Scope (v1, phone-only)

1. **On This Day** — memos from this calendar date in prior years (±3-day window when the exact
   date is empty). Pure date math over `Memo.createdAt`; no ML.
2. **Timeline/calendar + map** — presentation over existing `MemoMetadata` (already carries
   `latitude`/`longitude`, `placeName`, weather — `Models/MemoMetadata.swift`).
3. **Semantic "Related notes"** — top-k cosine over on-device embeddings, shown on memo detail.
4. **Semantic search with context filters** — a "Related" section under the existing exact-match
   results, plus filter chips over data we already have: person / place / month / source-kind.
   People remember fragments of context ("that thing about pricing, on a walk, in spring"), not
   keywords.
5. **Threads** (user-signed-off 2026-07-06) — from any memo, its related set ordered
   *chronologically*: the arc of an idea, with the **first-mention** date called out ("first
   mentioned 14 Feb"). A sort-order away from the related() API — the cheapest feature that
   delivers the north star directly.

**Platforms (user-locked 2026-07-07): build the brain shared, ship the UI phone-first.** The whole
engine layer (protocol, Gemma engine, gist, chunker, cosine/query scoring) lives in
`Skrift_Native/Shared/Retrieval/` from day one — the P0 shared-naming mechanism, compiled by BOTH
apps; Foundation+CoreML only, no UIKit, and CoreML-LLM runs on macOS 15+ (the bake-off spike
literally ran it on the M4). Only the SwiftData row + sweep wiring + views are per-app. v1 UI =
iPhone; the iOS app already runs on iPad (CloudKit sync was device-verified iPhone↔iPad), so add
an iPad layout eyeball to chunk 8. Mac surfaces + the vault lens = Phase 2 below.

## Locked decisions (don't re-litigate; re-open only if the spike gate fails)

- **Engine: ✅ DECIDED BY BAKE-OFF (2026-07-07, Mac spike): EmbeddingGemma-300M at dim 512 via the
  `CoreML-LLM` Swift package** (github.com/john-rocky/CoreML-LLM, v1.9.0). Measured on the fixed
  10-query EN/NL eval (`Skrift_Native/spikes/EmbeddingBakeoff/` — results in its README):
  EmbeddingGemma **10/10 top-1, margin +0.37, cross-lang 3/3, finds buried tail content, ~5
  ms/embed**; Apple's `NLContextualEmbedding` **5/10, margin +0.07** (anisotropy — everything
  ~0.85 cosine), cross-lang 1/3, misses buried tails → **eliminated, don't revisit**. Facts for
  the port: 295 MB runtime download (reuse the model-download UX), 99.8% ANE, iOS 18+ =
  SkriftMobile's existing deployment target, `encode(text:task:dim:)` with `.retrievalQuery` /
  `.retrievalDocument`, license = Gemma ToU (already our posture via the Mac's Gemma). **Pick dim
  512 at load and never switch dims on a live instance** (dim-switching was flaky in the spike;
  one dim = 100% stable). Keep the `EmbeddingEngine` protocol + `modelRev` anyway (rev bump →
  sweep re-embeds; zero migration code).
  - *Memory rule (iPhone 13 = 4 GB):* never run the embedder concurrently with ASR — the sweep
    runs when idle, and the engine idle-unloads.
- **Grain (user-flagged 2026-07-06): gist vector + body chunks, in v1.** Truncating a long memo at
  ~500 chars would hide its tail from retrieval, and the model's ~512-token window forces
  splitting anyway — so chunk, don't truncate. (Validated by the bake-off: for a query about a
  long memo's buried tail, the tail chunk ranked #1 while the full-memo vector ranked #7.) Per memo: ONE gist vector (title + summary if
  present + placeName + people + tags) for identity, PLUS body chunks split at sentence
  boundaries every ~150–200 words (long conversations and quote-rambles are exactly the memos
  that matter). **Strip `**Name:**` speaker headers before chunking** — embed spoken bodies only
  (same lesson as the desktop's conversation-tagging fix, `dda494d` C2). A memo's relevance = max
  over its vectors; results dedupe by memo. Store the chunk's char range — later enables "jump to
  the matching part". The sweep also materializes each memo's matched person keys (via the shared
  `Sanitiser`) so the search Person chip has something to filter on. Exclude trashed memos.
  Audiobook *quote captures* are memos → included. Book sidecar transcripts are not memos →
  naturally out.
- **Storage: derived-local, never synced.** New `@Model MemoEmbedding { memoID, chunkIndex,
  charStart, charEnd, vector: Data, textHash, modelRev, updatedAt }` (chunkIndex 0 = the gist
  vector) in a **second `ModelConfiguration(cloudKitDatabase: .none)`** — one container, two
  configs, disjoint schemas. Each device re-derives; zero CloudKit cost. If mixed configs
  misbehave in practice (SwiftData quirk territory), the sanctioned fallback is a fully separate
  second `ModelContainer` just for `MemoEmbedding` — equivalent semantics, zero risk to the
  synced store.
- **Index maintenance: sweep-based invalidation**, not per-write hooks. On app foreground, after a
  memo save, and (if handy) on the CloudKit-import notification: for each memo compare
  `textHash(gist)` vs stored; re-embed mismatches. Robust against every write path, including
  polish arriving from the Mac.
- **Query: brute-force cosine via Accelerate/vDSP.** 512-d × even 10k memos is milliseconds. No
  vector DB, no ANN.
- Related notes: k=4, similarity floor start at 0.55 → **calibrate in chunk 3**, don't trust the
  prior. Search "Related" section: only when the query has ≥2 words or exact hits < 3; top 8 above
  floor, minus exact hits.
- **On This Day / timeline / map ship even if the semantic gate fails** — they need no embeddings.
- **Corpus = Skrift memos only; the vault is NEVER the index source in v1.** The memo is the one
  source of truth; exports are projections (STANDALONE_PLAN locked model: Mac + Obsidian =
  optional sinks). Indexing the vault would double-index our own exports. A later opt-in **"vault
  lens"** (the decided "pull-for-search" mode) may add vault notes read-only, tagged
  `source: vault`, deduped by skrift-id, excluding `<vault>/Skrift/` — gated on security-scoped
  folder access + File-Provider placeholder handling (the audiobook-import bug class).
- **Juxtapose, don't judge.** Evolution features arrange the user's own words side by side (old vs
  new, same cluster); no sentiment/stance/mood inference anywhere. Vault-side edits stay in the
  vault (edit-guard divergence is by design): Skrift shows what you *said*, the vault holds what
  you *curated*. Publish stays one-way.
- **Retention & pruning (user-locked 2026-07-06):** the permanent corpus = importance-rated memos —
  the rating is the curation act (it already gates Mac sync). Unrated memos are provisional:
  auto-prune (backlog idea i2) may remove them after its review flow. Two safety nets, both in
  i2's spec: pruning happens only via the user-approved review, and it's suppressed while the app
  hasn't been opened in a while — an unopened app can't prune, so a returning user's backlog is
  safe. The index sweep deletes orphaned `MemoEmbedding` rows; threads/lookbacks span whatever
  survives. If space ever forces a choice, prune audio before text.
- **Journal becomes the third tab**: Notes · Library · **Journal** · Settings. ⚠️ Another lane is
  REMOVING the "Highlights (soon)" placeholder tab (Tuur, 2026-07-06) — land Journal AFTER that
  merges and add `.journal` to whatever `AppTabView` looks like then; same end state either way.
  P6's Highlights feed + Daily Review later land as *sections inside Journal*, not a fifth tab. Surfaces per the mock: Looking-back cards + mini-calendar + map preview on Journal
  home, full calendar + map pushed from it, Related card on detail, Matches+Related in search
  (search stays in the Notes tab).
- **Looking back generalizes On This Day** (the corpus only starts 2026-04, so a literal
  on-this-day is empty until 2027): spaced lookback cards at 1/3/6/12 months, highest-importance
  note of each window, empty windows hidden — a literal "On this day, <year>" card tops the list
  once prior-year history exists.

## Architecture (files to create)

Shared brain — `Skrift_Native/Shared/Retrieval/` (compiled by BOTH apps, Foundation+CoreML only):
- `EmbeddingEngine.swift` — `protocol EmbeddingEngine { func embed(_ text: String, isQuery: Bool) async throws -> [Float]; var modelRev: String { get } }` + a deterministic `MockEmbedder`
  for tests (hash-seeded vectors). Keeps the unit-test scheme asset-free (established pattern).
- `GemmaEmbedder.swift` — EmbeddingGemma via CoreML-LLM (port from the spike's `Engines.swift`):
  lazy load, dim 512 fixed at load, idle-unload after ~60s (desktop lesson: never leave a model
  pinned).
- `MemoGist.swift` — pure `compose(…) -> String` + sentence-boundary chunker + `textHash`
  (testable, platform-neutral).

Per-app wiring — `Skrift_Native/SkriftMobile/`:
- `Models/MemoEmbedding.swift` — the local-only @Model. **Vector as `Data`** (float32 LE) — the
  SwiftData Codable-struct-attribute trap is real (traps on read-back; see CLAUDE.md gotcha).
- `Services/Embeddings/EmbeddingIndex.swift` — actor: `sweep(repository:)` (batched 25, background
  QoS, resumable — mirror `BookTranscriptionJob`'s pattern), `related(to:k:) -> [(Memo, Float)]`,
  `search(query:) -> [(Memo, Float)]`, `thread(for:) -> [Memo]` (= related above floor, sorted by
  date ascending; `.first` is the first mention). Filter chips need no index work — they predicate
  on existing `MemoMetadata`/names fields before scoring.
- `Features/Journal/…` — UI after the mock gate only.
- Tests: `SkriftMobileTests/EmbeddingIndexTests.swift` (MockEmbedder: upsert/invalidate/related/
  search ordering), `MemoGistTests.swift`.

## Gotchas already paid for in this repo

- Do **NOT** add fields or models to the CloudKit config (`NotesRepository.swift:32–37`) — the prod
  CloudKit schema deploy (Stz020) is still pending; perturbing the synced schema now compounds it.
- Asset download needs visible status — reuse the model-status UX pattern (like the ASR download
  bar), and it feeds P11e "graceful model download" for App Review.
- Simulator unit tests must not depend on downloadable NL assets → real-embedder checks live behind
  a DEBUG launch flag, not the unit suite.

## Chunks (commit per chunk; verify per chunk; sim = iPhone 17)

0. **BAKE-OFF GATE — ✅ DONE 2026-07-07 (Fable, Mac spike `Skrift_Native/spikes/EmbeddingBakeoff/`).**
   Winner: **EmbeddingGemma-300M dim 512** — 10/10 top-1, margin +0.369, cross-lang 3/3, buried
   tail found (tail@1 vs full@7 — which also validates the chunking decision with data). Apple's
   NLContextualEmbedding failed the bar (5/10, margin +0.073) — eliminated. Port `Engines.swift`
   + `Eval.swift` from the spike into the app (protocol + Gemma engine + the eval as a DEBUG
   `-embedSpike` flag). Remaining on-device residue (fold into chunk 8): one `-embedSpike` run on
   the iPhone 13 for load time / speed / memory only — quality is settled.
1. ✅ **BUILT 2026-07-07** (Fable, branch `claude/youthful-wozniak-a79a3b`): `MemoEmbedding` in its
   OWN local container (`EmbeddingStore` — the sanctioned separate-container shape, so the
   contested `NotesRepository` is untouched), `Shared/Retrieval/` (protocol + `MockEmbedder` +
   `MemoGist` gist/chunker/hash), `GemmaEmbedder` (CoreML-LLM package added to mobile
   project.yml). 14 unit tests green.
2. ✅ **BUILT 2026-07-07**, deliberately narrower than planned: hash-diff sweep + orphan cleanup +
   per-memo saves (resumable) in `EmbeddingIndex`; foreground trigger via
   `JournalIndexService.sweepSoon` (SkriftApp scenePhase). **INERT by default** — requires
   `journalIndexEnabled` (UserDefaults, set by the future Journal UI's consent flow) AND the model
   already on disk, so merging can't trigger a surprise 295 MB download. Post-save/CK-import
   triggers + the Settings toggle land with the UI chunks.
3. 🟡 **Query API BUILT 2026-07-07** (`search`/`related` max-cosine over gist+chunks, scores only —
   UI applies floors/k/date-sort; thread = `related` sorted by date at the call site). **OWED:**
   the calibration harness (DemoDataSeeder score histogram → replace the provisional
   `RetrievalTuning` floors) + first-mention helper — fold into chunk 6.
4. **MOCK GATE — ✅ SIGNED OFF 2026-07-06.**
   `Skrift_Native/SkriftDesktop/mocks/journal-retrieval.html` — all five surfaces + the "Build
   notes — locked decisions" block. Tuur approved enthusiastically; the tab question resolved via
   the Highlights-removal lane (Journal becomes the third tab). The mock IS the spec — build to
   it; if Tuur requests tweaks later, iterate the mock first, then the SwiftUI.
5. ✅ **BUILT 2026-07-07** — Journal tab v1 to the signed mock: Looking back (On-this-day +
   spaced lookbacks, `LookbackProvider`, journal axis = `recordedAt`), mini + full calendar with
   dot density, Places map with clusters; Journal replaces the Highlights tab slot. `-seedJournal`
   + `-openJournal` flags; 7 unit tests; home screen sim-screenshot verified against the mock.
   OWED: device eyeball (incl. pushed Calendar/Map screens) on the next Dev build.
6. ✅ **BUILT 2026-07-07** — search "Related · similar in meaning" section under the exact matches
   (debounced async, engine warm-up on first keystroke, floor + exact-exclusion + the existing
   filter sheet applied at render), ThreadView (arc + first-mention pill + "this note" seed
   marker, sheet from the ⋯ menu, rows open via MemoOpenBridge), `-mockJournalIndex` +
   `-initialSearch` + `-threadDemo` screenshot/UITest flags. Sim-verified: zero-substring query
   surfaces both pricing memos; thread renders the two-node arc. **Deviations (deliberate):**
   filter CHIPS not built — the merged list already has a SortFilterSheet (place/date/toggles)
   that prefilters Related too; person/kind additions to that sheet + the calibration histogram
   move to chunk 8's device pass.
7. ✅ **BUILT 2026-07-07** — Related card in the note footer (editor pages), styled after the
   "Linked from" section: up to `relatedK` sparkle rows (tap → pager jump via `onOpenMemo`) + the
   "View thread · first mentioned <date>" CTA (sheet). Hidden when nothing clears the floor or the
   index is inactive. `-journalMemoDemo` screenshot route; sim-verified on the seeded pricing
   memo. NOTE: conversation/capture pages keep the legacy layout without the footer — the card
   reaches them when those pages migrate to the editor architecture (note-editing phase 2).
8. Device pass on the iPhone 13 (Dev build): backfill duration + memory on the real corpus, jetsam
   watch, asset-download UX. Then FEATURES.md rows + roadmap flip (P8 → done via Huginn) + fold
   this doc per the docs-lean rule.

## Fast-follows (named, user-approved 2026-07-06 — build right after chunk 8 if momentum allows)

- **Then vs Now** — a journal card juxtaposing an old memo with a recent same-cluster memo far
  apart in time ("a year ago you thought X — last week you said Y"). Pure juxtaposition, no
  interpretation (see locked decisions). Needs only `related()` + a time-gap filter.
- **Voice search** — mic button on the search field → existing one-shot ASR → same semantic query
  path. It's a voice-first app; asking your journal out loud is the native gesture.

## Phase 2 — Mac + the vault lens (user-requested 2026-07-07; after v1 ships)

The vault is where the YEARS live: Skrift's corpus starts 2026-04, so "a years-old thought
resurfaces" only becomes literally true in 2027 — unless the vault lens lands. Indexing the vault
gives Looking back / Then-vs-Now / search years of pre-Skrift fuel on day one. Privacy is already
settled by the locked Obsidian model: the app's own on-device code reading the vault is FINE
("pull-for-search" is a decided mode); embeddings never leave the device.

- **Mac first** (natural home: the vault is a local folder — no bookmarks, no placeholders, fast
  disk): Journal/search surfaces over the Mac's store using the same `Shared/Retrieval/` engine,
  plus the vault corpus: index `<vault>/**/*.md` EXCLUDING `<vault>/Skrift/` (our own exports;
  dedupe by skrift-id frontmatter as backstop), strip frontmatter + `[[wikilink]]` syntax in the
  gist, note date = frontmatter `created:` else file date. Vault docs are a parallel corpus
  (path/title/date/vectors), tagged `source: vault` in results.
- **Phone vault lens after**: reuse the ObsidianPublisher's vault folder access (security-scoped
  bookmark) for reads; handle File-Provider placeholders (un-downloaded iCloud files — the
  audiobook-import bug class); the index stays derived-local per device.
- **Vault location (Tuur, 2026-07-07):** the vault moves to iCloud Drive (Obsidian's own iCloud
  folder — on the Mac `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/<vault>`) replacing
  lapsed Obsidian Sync. Safe because writes are per-file disjoint: Mac edits, phone publish is
  create-only, iPad reads. Operational notes: Skrift desktop's vault path setting must be updated
  after the move; "Optimize Mac Storage" must be OFF (evicted placeholders would break the
  exporter/tag scan); vault audio copies now count against iCloud storage. Move order: disconnect
  the lapsed Obsidian Sync pairing on EVERY device first (never two sync engines on one vault),
  backup, force-quit Obsidian everywhere, copy into iCloud Drive → Obsidian, verify on all
  devices, re-point Skrift, then retire the old folder.

## Later, on the same substrate (not v1)

Book influence pages (per audiobook: captured quotes + the memos semantically downstream of them —
feeds P6) · Ask-your-memos (RAG over this index) · weekly "how my thinking evolved" digest
exported to Obsidian · P6 Daily Review ranking by embedding diversity. The index is the enabler;
build it once, well.

## Collision map — ALL CLEAR (re-assessed 2026-07-07 evening; branch merged with origin/main)

No lanes are active anymore; chunks 5–8 are UNBLOCKED:
- **Bonjour removal + live-sync: LANDED on main** (merged into this branch cleanly; full suite 495
  tests green). `MemosListView` is free → chunk 6 goes.
- **Highlights-tab removal: never happened** — that chat didn't land it, so chunk 5 does the swap
  itself: `AppTabView.Tab.highlights` → `.journal`, `HighlightsComingSoonView` → the Journal home
  (exactly the mock's IA).
- **note-editing** (`claude/gracious-easley-e3fc96`): merged NOTHING — it's spec/plan docs only.
  MemoDetail is unowned today, so chunk 7 can build on the current detail view; expect a small
  rebase when the NEdit editor rebuild eventually lands (keep the Related card self-contained).
- **SharedKit dedup (landed on main 2026-07-07)**: moved MemoMetadata/WordTiming/etc. into
  `Shared/` — no P8 impact (snapshot code compiles unchanged) and MORE shared substrate for
  Phase 2's Mac adoption.

## Kickoff prompt for the executing session

> Read `JOURNAL_RETRIEVAL_PLAN.md` at the repo root and execute it chunk by chunk. FIRST confirm
> the ⛔ gate at the top is cleared (Tuur has green-lit building + signed off the mock) — if not,
> stop and ask. Start with chunk 0 (the bake-off gate) and STOP for a decision if it fails.
> Decisions in the plan are locked — don't re-open them. Commit per chunk with explicit paths,
> run the sim test suite per chunk, respect the mock gate (chunk 4) and the collision map
> (chunks 5–7). Today's state of the other lanes may have changed — re-check `git branch -a` +
> `backlog.md` before chunks 5–7.
