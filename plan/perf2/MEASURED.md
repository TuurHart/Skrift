# Speed sweep 2 — measured on the iPhone 13 (2026-10-05)

Build: Skrift Dev 178, Debug config compiled with `SWIFT_OPTIMIZATION_LEVEL=-O` (App Store speed), launched with
`-perfLibrary` (Q313: 2,000 notes, 676 assets, 150 people, never synced). Traces in `.queue/perf/b178/`
(`1-cold-launch.trace` App Launch; `2-flow.trace` Time Profiler, 421 s, Tuur driving with live narration).
Numbers are main-thread busy time of SkriftMobile (1 ms samples). Analysis scripts: scratchpad tp.py / tp2.py / win.py
(parse `xctrace export` time-profile; per-second main busy; top inclusive app frames per window).

| moment (Tuur's words) | main thread busy | top app frames | causes (SUMMARY.md #) |
|---|---|---|---|
| cold launch | 4.11 s "Initial Frame Rendering" (App Launch); 4.5 s main busy in 0-7 s | AssetMaterializer.captureMissing 1,433 ms (captureFiles 1,210, fileSize 637, lstat self 926); allMemos 791; FadingSweep 366; recoverStuckTranscriptions 330; MemosListView.body 644 | 5, 1 |
| open a long note ("fast" by feel, but) | 1-3 s per open (40-47 s: 2.9 s; 59-66 s: 3.8 s) | MemoPageView.body closure #2 → recomputeBacklinks 1,609 / ladderTitle 1,222 → NoteTitle.firstLine 976, NoteSnippet.plain 684, Backlinks.targets 464, loadRelated 400 | 2, 3 |
| tap a related note: "slides in from the right and freezes halfway" | 80-85 s: 2.0 s | pager scrollTo across the LazyHStack of all memos + MemoPageView body + EditConflict | 2 (swipe disabled 2026-07-16, pager kept) |
| type a sentence, press Done: "took a while" | 95-100 s: 2.9 s | editor 715 ms, MemosListView.derived/filtered (list behind the editor), EditConflict 123 | 10, 1 |
| search "morning": "letters spawn one by one, ~5x slower than typing"; clearing slow | 105-125 s: ~10 s for 7 letters + clear | MemosListView.body → derived 2,884 → filtered 1,338 → listRows/matchesSearch | 4, 1 |
| home screen 5 s and back: "froze for a second" | 125-140 s: ~4 s | AssetMaterializer.captureMissing 680, list layout (UICollectionView sectionIndex 473), allMemos 219 | 5 |
| stop a 25 s recording: "froze" | 165-175 s: 6.4 s | MemosListView.body/derived 2,295, MemoLifecycle.backlinkedIDs 774 (Backlinks.targets 728) | 1, 8 |
| open Books, open a book: "pretty alright" | 178-190 s: 2.7 s | AudiobookLibraryView.row → BookNotesJoin.counts 879 → Memo.metadata decode 664; ReadAlongModel.reloadIfNeeded 536 → FileTranscript decode 357 | 1 (D-B2a), 8 (D-B1) |

Caveat: the perf seed gives ~1,540 voice notes an audioFilename with no file on disk; AssetMaterializer's per-launch
stat cost may differ when files exist. The fix item must re-measure with files present.
Recording itself (140-165 s) kept the main thread quiet. Mac not measured yet.

## After Q314-Q317 (build 179, same phone, same perf library)

| moment | before (b178) | after (b179) | how |
|---|---|---|---|
| cold launch, first frame | 4.11 s | 1.73 / 1.52 / 1.67 s (3 runs) | App Launch template, `.queue/perf/b179/1-cold-launch-{1,2,3}.trace` |
| main thread after first frame (launch sweeps) | ~1.4 s AssetMaterializer + FadingSweep + recover* on main | 24 ms on main in the 12 s after first frame | Time Profiler in the same traces |

Left in the 1.5 s: UIKit first commit of the Notes list (UpdateCollectionViewListCoordinator, MemosListView.body ~0.5 s).
Note open, related-note hop, Done after typing, search, return from home, Stop and Books need Tuur's flow again (Q319).

### Flow re-run on b179 (Tuur, 2026-10-05 22:05, `.queue/perf/b179/2-flow.trace`)

| moment | b178 | b179 | what is left |
|---|---|---|---|
| open 5 notes (+ back) | ~4,700 ms in MemoPageView over the opens; 1-3 s per open | ~1,330 ms MemoPageView over 5 opens; ~8.7 s main total incl. the list behind | closing a note calls `repository.save()` (MemoDetailView onDisappear), and `save()` bumps `memoSetVersion` even with no changes, so every close rebuilds the list base (allMemos 1,008 ms, ListDerivedCache.base 967 ms). Tuur: "small stutter when I open and close" |
| type, Done | 2.9 s | ~2.0 s | each commit's save bumps the version: list base + hidden AudiobookLibraryView.body re-run behind the editor. Tuur: "lags a little after a space" |
| search 'morning' + clear | ~10 s | ~3 s ("seems faster") | typing more in search still costs list diffing: ListDiffable.sectionIndex 1,894 ms + row closures over 120-155 s |
| scroll fast 20 s | not isolated | 15.4 s main busy in 20 s | self-sizing list cells: preferredLayoutAttributesFitting → hostSizeThatFits 3.9 s, cell creation 4.5 s (Tuur: felt fine) |
| Stop a recording | 6.4 s | ~4.3 s | list + page + Books body re-run after the save |
| record start | freeze at start in the past | no freeze (Tuur) | — |

### Flow on b181 (Q314-Q324, Tuur 2026-10-06, `.queue/perf/b181/2-flow.trace`, tool `plan/perf2/tools/flow.py`)

Total main-thread busy over the 7-min recording: b178 50.1 s, b179 67.6 s (longer flow), **b181 22.9 s**.

| moment | b178 | b179 | b181 | Tuur |
|---|---|---|---|---|
| scroll fast | — | ~15.4 s / 20 s | ~4.1 s / 10 s (cell self-sizing left) | "pretty smooth, pretty impressive" |
| open notes | 1-3 s each | ~0.3 s each + list rebuild on close | ~0.2 s each, no close rebuild | "opens quick" |
| type + Done | 2.9 s | ~2.0 s | ~1.8 s | "works" |
| search + clear | ~10 s | ~3 s | ~3 s (list derive + batch updates) | "quick; short lag removing letters" |
| Stop a recording | 6.4 s | ~4.3 s | ~2.8 s (full rebuild after the insert) | "way faster" |

## Mac (2026-10-06, optimised Dev build, -perfLibrary, `.queue/perf/mac1/2-launch.trace`)
Launch with the library already seeded: main thread busy ~2.8 s in the first 8 s (MemoCloudReconciler.reconcile 651 ms,
sweep 430 ms), then idle (6 ms in the next 80 s). Interactive moments (sidebar clicks, typing, search, playback)
need Tuur driving — the Mac UI may not be automated (feedback_no_mac_ui_tests).
