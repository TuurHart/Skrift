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
