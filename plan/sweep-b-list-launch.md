# Sweep B — phone/iPad notes list, app shell, launch/foreground, mobile sync

Scope: `SkriftMobile/Features/MemosList/` (MemosListView.swift 1,784 lines, WayOutView.swift),
`SkriftMobile/App/`, `SkriftMobile/Services/` (excl. Recording/, Audiobooks/), plus
`Shared/Pipeline/MemoLifecycle.swift`, `Shared/Pipeline/NoteConsent.swift`,
`Shared/UI/NoteCardView.swift`, `Shared/UI/NotesListModel.swift`.

Baseline already on record — cited, not repeated: `plan/perf-sweep.md` (static, 2026-09-23,
rows P1/P2/P4/P7 + R90–R94/C276–C280) and `plan/perf-measured.md` (Time Profiler, Dev 172,
2026-09-25, FAST-state trace). Every "still open" row below was re-verified against today's
source, with current line numbers where they moved.

## Findings

| # | file:line | kind | what / when | cost | fix | conf |
|---|---|---|---|---|---|---|
| 1 | `MemosListView.swift:493,910-915` | SLOW | `enhancedTitleByMemoID` is an uncached computed `Dictionary` built from the full `enhancements` query; read per-row inside `ForEach` (line 493) | O(rows × enhancements) per render — still open, R92/C278, lines moved from :462 | Hoist into `Derived`/`derived` (line 1162) alongside `groups`/`flatIndex`, computed once | high |
| 2 | `MemosListView.swift:494,1150-1153` | SLOW | `searchFadingIDs` rebuilds a `Set` from `lifecycle.fading.map` on every access; read per-row (line 494) while searching | O(rows × fading) per render while searching — still open, R92/C278 | Same: fold into one derived pass | high |
| 3 | `MemosListView.swift:846-895` | SLOW | `filterChips` reads `chipCounts[chip]` (line 852) inside `ForEach(QueueFilter.allCases)`; `chipCounts` (889-895) is a computed property, so it fully re-executes on **each of the 4 chip iterations** — 3 `memos.filter` passes + `ProcessPile.unrated` + a fresh `enhancedMemoIDs` rebuild, every time | up to ~16 full-corpus passes per render of the chip row (every list render/keystroke) | Compute `chipCounts` once as a local `let` before the `ForEach`, not as a property read inside it | high |
| 4 | `MemoLifecycle.swift:88-105`, `MemosListView.swift:472,1134,1141-1144,1152` | SLOW | `lifecycle` (1134) is an uncached computed property wrapping `MemoLifecycle.partition(memos)`, itself calling `backlinkedIDs(in:)` (a full-corpus link scan). It's read twice per render (`filtered` at 1142/1144, `searchFadingIDs` at 1152) **plus** `listContent` independently calls `MemoLifecycle.backlinkedIDs(in: memos)` again at line 472 for `clockLine` | ≥3 full corpus + link scans per render, not 1 | Cache `partition`/`backlinkedIDs` results once in `derived` and reuse for both the fade split and the clock line | high |
| 5 | `NotesRepository.swift:164-170`, called from `MemoDetailView.swift:1278` | SLOW | `allTags()` re-fetches every live memo via a sorted SwiftData `FetchDescriptor` (`allMemos()`) then rebuilds+sorts a tag-count dict; called inline as `library: repository.allTags()` in a view initializer, no caching | **Measured**: `plan/perf-measured.md` shows `NotesRepository.allTags()` at 160 incl. samples (2.0% of main thread) during ordinary typing — it re-runs every re-render of that section, per keystroke | Cache tags with invalidation on tag-write, or hoist to a `@State`/`.onAppear`-computed value instead of an inline call | high |
| 6 | `AssetMaterializer.swift:67`, `NotesRepository.swift:131-132` | SLOW | `captureMissing` calls `repository.allAssets()`, an unscoped `FetchDescriptor<MemoAsset>()` — faults every audio/photo blob into memory | runs every launch + every foreground; still open, R91/C277 (line numbers unchanged) | Scope with `propertiesToFetch`, matching `materializeMissing` 20 lines above it | high |
| 7 | `Shared/Model/AppPaths.swift:19-23` | SLOW | `recordingsDirectory` runs `FileManager.createDirectory` (mkdir+stat) on every access; 99 call sites across the repo | still open, R93/C279, unchanged lines | Create once at bootstrap; make the accessor a `static let` | high |
| 8 | `SkriftApp.swift:120-139,192-219` | SLOW | Ten main-actor sweeps (MemoDeduper, AssetMaterializer, PhotoTextIndexer, ReminderScheduler, one-clock migration, FadingSweep, NamesCloudSync, VocabularyCloudSync, PolishPromptsCloudSync, AudiobookCloudSync) fire unconditionally and fully re-derive on every launch **and** every foreground, no checkpoint | still open, R94/C280 — lines moved from :108-203 to :120-139 (launch) + :192-219 (foreground) | Record a high-water mark (last-seen memo count/timestamp) per sweep; no-op when nothing changed | high |
| 9 | `MemosListView.swift:1171-1183` vs `Shared/UI/NotesListModel.swift:20-29` | INELEGANT | `groups(from:)` hand-rolls the exact same `order`-array + `bucket`-dict day-grouping loop that `NotesListModel.dayGroups(_:dayLabel:)` already implements generically for exactly this purpose — the shared helper exists and isn't used here | duplicated logic; a future grouping-rule fix has to be made twice | Replace `groups(from:)`'s body with a call to `NotesListModel.dayGroups(filtered) { MemoDate.group(groupDate($0)) }` | high |
| 10 | `MemosListView.swift:1415-1497,1531,1534` | INELEGANT | `statusPill`, `captureGlyph`, `voiceGlyph`, `videoGlyph`, `bookGlyph`, `quoteText`, `photoThumb`, `hasTranscript`, `hasPhoto` (~90 lines) are dead: `MemoCard.body` (1345-1351) only renders `NoteCardView(model: cardModel)` since the "m2 adapter" migration (comment at 1341-1344, dated 2026-08-19). Grepped — no other reference anywhere in the file | ~90 dead lines in an already 1,784-line file | Delete | high |
| 11 | `MemosListView.swift` (whole file) | INELEGANT | 1,784 lines: root layout branching, 4 header variants (`macStyleHeader`/`headerRow`/`verbRow`/`processRow`/`filterChips`), the List content, `MemoRow`/`MemoCard`, `SortFilterSheet`, `NotesBottomChrome`, iPad helpers (`SelectableCard`, `RecordPresentation`) all in one file | hard to navigate/review; the one place a real fix (findings #1-4) has to land is buried among unrelated UI chrome | Split into `MemosListView+Header.swift`, `MemosListView+Row.swift` (Row/Card), `SortFilterSheet.swift`, `NotesBottomChrome.swift` | med |
| 12 | `WayOutView.swift:29-33,39,111,113` | SLOW | `fading` is an uncached computed property wrapping `MemoLifecycle.partition(liveMemos)`; read ≥3× per render (`total`, `!fading.isEmpty`, `ForEach(fading)`) | 3× the fade/backlink corpus scan per render of the shelf sheet — same bug class as #4, but a rarely-opened sheet, not the hot list | Compute once as a local `let` in `body` | med |
| 13 | `MemosListView.swift:903-905,890,900,1141,1194` | SLOW | `enhancedMemoIDs` (a `Set` built from the full `enhancements` query, lazy filter+map) is itself a computed property called independently from `chipCounts`, `processPile`, `filtered`, and `relatedDisplay` — up to 4 separate rebuilds per render | compounds finding #3; O(enhancements) rebuilt 4× instead of once | Compute once per render pass and thread through, same as `derived` | med |

## For Tuur

The list's per-row math (#1, #2, #4) is the known R92 bug, not yet fixed — it just moved
lines when other code shifted around it. New this pass: the **filter-chip row recomputes
its own counts once per chip** (#3), which is worse than R92 in shape (a ForEach over a
ForEach's derived data) even though the row itself is small (4 chips) — still up to a
dozen extra full-corpus scans per render. The one genuinely new *measured* hit is
`NotesRepository.allTags()` (#5) — it shows up in the actual typing trace, not just static
reasoning, so it's worth fixing even though the call site lives in `MemoDetailView`, not
this area's own view.

Counts: 13 findings — 9 SLOW (2 measured/refined-from-known, 5 still-open known, 2 new),
4 INELEGANT (1 duplicated-logic, 1 dead-code, 1 file-size, folded into the confidence read
of the others).
