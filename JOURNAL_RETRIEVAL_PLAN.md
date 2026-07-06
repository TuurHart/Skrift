# Journal & retrieval plan — P8 (On This Day · timeline/map · semantic related-notes · search)

Planned 2026-07-06 (Fable survey session), for a next Opus session to execute. Roadmap node **P8**
(lane "Journal & Search", currently `planned`). This is the north-star backbone: *"a years-old
thought resurfaces next to today's."* Unclaimed as of writing — note-editing, audiobooks, and the
live-sync/Bonjour-removal handoff are owned by other sessions (collision map at the bottom).

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

Desktop gets none of this in v1; the engine is written so it can later move to `Shared/`.

## Locked decisions (don't re-litigate; re-open only if the spike gate fails)

- **Engine: `NLContextualEmbedding`** (Apple NL framework, iOS 17+), Latin-script multilingual
  model — one model covers the user's English/Dutch mix. Sentence vector = mean-pooled token
  vectors, L2-normalized, float32. Read `dimension` from the model at runtime (~512), never
  hardcode. ⚠️ API surface + quality are **unverified** — that's chunk 0's job.
- **Grain: one vector per memo.** Gist string = title + (summary if present, else first ~500 chars
  of polished-else-raw body) + placeName + linked person names + tags, capped ~800 chars (the model
  truncates long input anyway). Per-paragraph chunking is v2. Exclude trashed memos. Audiobook
  *quote captures* are memos → included. Book sidecar transcripts are not memos → naturally out.
- **Storage: derived-local, never synced.** New `@Model MemoEmbedding { memoID, vector: Data,
  textHash, modelRev, updatedAt }` in a **second `ModelConfiguration(cloudKitDatabase: .none)`**
  — one container, two configs, disjoint schemas. Each device re-derives; zero CloudKit cost.
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
- **Retention corollary:** retrieval assumes the in-app corpus is permanent. Any future auto-prune
  (backlog idea i2) must never delete exported, significant, or in-thread memos — prune *audio*,
  never text.
- **No new tab.** The dimmed "Highlights (soon)" tab in `AppTabView` is reserved for P6
  (Commonplace Book). Proposed surfaces (the mock decides): On-This-Day card atop the Notes list,
  a Journal (calendar/map) view behind a Notes-header button, Related card on detail, Related
  section in search results.

## Architecture (files to create, `Skrift_Native/SkriftMobile/`)

- `Services/Embeddings/EmbeddingEngine.swift` — `protocol EmbeddingEngine { func embed(_ text: String) async throws -> [Float]; var modelRev: String { get } }` + a deterministic `MockEmbedder`
  for tests (hash-seeded vectors). Keeps the unit-test scheme asset-free (established pattern).
- `Services/Embeddings/ContextualEmbedder.swift` — the `NLContextualEmbedding` impl: lazy load,
  `hasAvailableAssets` / `requestAssets` handling, mean-pool + normalize. Idle-unload after ~60s
  (desktop lesson: never leave a model pinned).
- `Services/Embeddings/MemoGist.swift` — pure `compose(memo) -> String` + `textHash` (testable).
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

0. **SPIKE GATE (~1h).** `ContextualEmbedder` + a DEBUG launch flag `-embedSpike` that embeds and
   prints cosines for: an EN/EN same-topic pair, an EN/NL translation pair ("I biked to the
   office" / "Ik ben naar kantoor gefietst"), and an unrelated pair. Run on sim. **Pass = clear
   margin (same-topic ≫ unrelated) and the EN↔NL pair lands near the EN/EN one.** Record the
   numbers in this doc. Fail → fallback decision: `NLEmbedding.sentenceEmbedding` (weaker,
   per-language) or ship items 1–2 only and defer semantic. Don't build past a failed gate.
1. `MemoEmbedding` + second local ModelConfiguration + `MemoGist` + `EmbeddingIndex` upsert/
   invalidate with `MockEmbedder`. Unit tests green (`xcodebuild test -scheme SkriftMobile …`).
2. Sweep job wiring: foreground + post-save triggers, batched, resumable, idle-unload. Tests for
   hash-invalidation (edit gist → re-embed; untouched → skipped).
3. Query API (`related` / `search` / `thread` + first-mention) + **calibration harness**: seed via
   `DemoDataSeeder`, print the score histogram (DEBUG flag), pick the related/search/thread floors
   from data. Tests for ordering + floors + thread chronology.
4. **MOCK GATE (blocking).** One HTML mock in `Skrift_Native/SkriftDesktop/mocks/` (repo
   convention) covering all five surfaces — On-This-Day card, Journal (calendar/map), Related card,
   search with filter chips, **Thread view** (chronological arc + "first mentioned" header); Tuur
   signs off before any SwiftUI. The signed mock IS the spec.
5. Journal v1: On This Day + calendar/timeline (+ map if signed off). Metadata only. UITest seed
   (`-seedJournal`) with back-dated memos; screenshot-verify.
6. Search "Related" section + filter chips (person / place / month / kind) in `MemosListView`
   search, and the Thread view (reached from a memo's Related card / context menu). ⚠️ Rebase
   after the Bonjour-removal lane lands — it edits `MemosListView.swift` too.
7. Related-notes card on memo detail. **LAST — only after the note-editing lane merges** (it owns
   `MemoDetail`). Build against the rebuilt detail view.
8. Device pass on the iPhone 13 (Dev build): backfill duration + memory on the real corpus, jetsam
   watch, asset-download UX. Then FEATURES.md rows + roadmap flip (P8 → done via Huginn) + fold
   this doc per the docs-lean rule.

## Fast-follows (named, user-approved 2026-07-06 — build right after chunk 8 if momentum allows)

- **Then vs Now** — a journal card juxtaposing an old memo with a recent same-cluster memo far
  apart in time ("a year ago you thought X — last week you said Y"). Pure juxtaposition, no
  interpretation (see locked decisions). Needs only `related()` + a time-gap filter.
- **Voice search** — mic button on the search field → existing one-shot ASR → same semantic query
  path. It's a voice-first app; asking your journal out loud is the native gesture.

## Later, on the same substrate (not v1)

Book influence pages (per audiobook: captured quotes + the memos semantically downstream of them —
feeds P6) · vault lens (opt-in read-only vault indexing, see locked decisions) · Ask-your-memos
(RAG over this index) · weekly "how my thinking evolved" digest exported to Obsidian · P6 Daily
Review ranking by embedding diversity. The index is the enabler; build it once, well.

## Collision map (2026-07-06)

- **note-editing** (`claude/gracious-easley-e3fc96`): owns MemoDetail/editor → chunk 7 waits.
- **Bonjour removal / live-sync** (`claude/xenodochial-mclaren-9361b9`): owns Settings/Onboarding/
  MemosListView/MemoDisplay edits right now → chunk 6 rebases after it lands.
- **audiobooks** (third chat): player area — no overlap.

## Kickoff prompt for the executing session

> Read `JOURNAL_RETRIEVAL_PLAN.md` at the repo root and execute it chunk by chunk. Start with
> chunk 0 (the spike gate) and STOP for a decision if the gate fails. Decisions in the plan are
> locked — don't re-open them. Commit per chunk with explicit paths, run the sim test suite per
> chunk, respect the mock gate (chunk 4) and the collision map (chunks 6–7). Today's state of the
> other lanes may have changed — re-check `git branch -a` + `backlog.md` before chunks 6–7.
