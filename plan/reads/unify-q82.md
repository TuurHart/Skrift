# Q82 — one shared implementation, phone and Mac (read 2026-09-30)

Rule from Tuur (2026-09-30): the Mac matches the phone where they differ, and the code lives once in `Skrift_Native/Shared/`. Paths below are under `Skrift_Native/`. Order of work: 6, 13, 9, 11, 8, 12.

## 6. Word highlight / karaoke

| | Phone | Mac |
|---|---|---|
| Which word is playing | an INDEX. Raw body: `Karaoke.activeWordIndex(timings, at:, hint:)` (`SkriftMobile/Features/MemoDetail/NoteBodyView.swift:415-445`). Polished body: index into `alignedTimes` from `Karaoke.wordTimes` (`:419-430`, built `:503-526`). No alignment: `t / duration * wordCount` (`:433`) | a FRACTION. `NoteBody.karaokePlayback` (`SkriftDesktop/Features/Review/NoteBody.swift:165-172`) turns `Karaoke.activeCount(times:)` into `count / displayedWords`; the text view multiplies it back by the STORAGE word count and rounds (`BodyTextView.swift:514-518`). Aligned on EVERY body evaluation (~20 Hz), never cached |
| How it is painted | read words dim, playing word accent, upcoming words normal (`NoteBodyView.swift:447-472`) | first N words bright, the rest 40% (`BodyTextView.swift:529-535`). No accent word |
| Tap a word | Raw body: `Karaoke.seekTime(forWord:)` (`:614`). Polished body: `local / wordCount * duration` (`:607-611`), although the highlight above uses the alignment | `Karaoke.seekTarget(wordIndex:times:...)` on the aligned times (`NoteBody.swift:173-176`, click `BodyTextView.swift:977-985`) |
| Raw vs polished rule | decided by "is there a polished binding" | always aligned |
| No timings | proportional by `duration` | highlight proportional, tap seeks to 0 |

Also on the phone and already right: voice-note speaker turns (`MemoDetailSupportTypes.swift:64`), quote block (`CaptureQuoteViews.swift:83`), tap-to-seek on both (`MemoPageView.swift:900`, `CaptureQuoteViews.swift:64`). They read the exact sidecar index and stay as they are.

Behaviour differences to remove: (1) Mac paint = phone paint; (2) Mac highlight is an index, not a rounded fraction; (3) the phone's polished tap seeks by proportion while its highlight uses the alignment; (4) one rule for exact vs aligned vs proportional; (5) the Mac re-aligns 20x a second.

Shared implementation: `Shared/Pipeline/KaraokeTrack.swift` — `KaraokeTrack(displayedWords:timings:duration:)` picks EXACT (word count equals the timed count, the sidecar index is the word), ALIGNED (`Karaoke.wordTimes`), else PROPORTIONAL; answers `activeIndex(at:)` and `seekTime(forWord:)`; `KaraokeTrackCache` rebuilds it only when the words change; `KaraokeRole` (read / playing / upcoming). `KaraokeMap` (word ranges in text) moves from the phone target into `Shared/Pipeline/` so the Mac's `Coordinator.wordRanges` stops being a twin.

## 13. Search by meaning

| | Phone | Mac |
|---|---|---|
| Search box | exact matches, then a RELATED section (`SkriftMobile/Features/MemosList/MemosListView+Derived.swift:133-149`, drawn `MemosListView.swift:582-610`); scores from `JournalIndexService.searchScores` (`SkriftMobile/Services/Embeddings/JournalIndexService.swift:103`), floored by `relatedResults` (`:166`, `RetrievalTuning.searchFloor`) | exact matches only (`SkriftDesktop/Features/Shell/AppModel.swift:84-95`, `SidebarView.swift:733-740`). `ConnectionsIndexService` (`SkriftDesktop/App/ConnectionsIndexService.swift`) has `relatedScores` but no `searchScores`; nothing calls `EmbeddingIndex.search` |
| What gets embedded | `JournalIndexService.snapshots` (`:190-210`): polished copy-edit, else transcript, plus the typed annotation; title = user title, else the Mac's | `ConnectionsIndexService.snapshot` (`:158-171`): `sanitised ?? enhancedCopyedit ?? transcript`; no annotation; Mac title only |
| Floor / limit / exact exclusion | `relatedResults`: floor `searchFloor`, best first, limit 8, exact hits dropped | none (no search) |

Behaviour differences: the Mac has no search by meaning; the two snapshot builders disagree on body precedence, annotation and title.

Shared implementation: `Shared/Retrieval/SemanticSearch.swift` — `SemanticSearch.results(scores:excluding:floor:limit:)` (the phone's `relatedResults` rule over ids) and `SemanticSearch.snapshot(id:userTitle:enhancedTitle:summary:polished:transcript:annotation:place:tags:)` (the one body/title precedence). The Mac gets `ConnectionsIndexService.searchScores` and a RELATED section under its exact matches.

## 9. Notes-list core (fading, duplicates, way-out shelf)

| | Phone | Mac |
|---|---|---|
| Same-id duplicate rows | readers see clones (`NotesRepository.allMemos()`, `SkriftMobile/Services/NotesRepository.swift:53`); only `MemoDeduper` heals them | every reader runs `MemoDuplicates.canonicalRows` (`SkriftDesktop/Features/Journal/JournalView.swift:81-88`, `MemoCloudReconciler.swift:58`) |
| Countdown colour on the shelf | `daysUntilSweep` / `trashDaysRemaining` (`SkriftMobile/Features/MemosList/WayOutView.swift:248-253`) | inline `ceil(x / 86_400)` (`SkriftDesktop/Features/Journal/WayOutColumn.swift:179-190`) |
| Bring back | `WayOutView.bringBack` (`:270-275`) | `WayOutRules.bringBack` (`SkriftDesktop/Pipeline/WayOutRules.swift:170-176`), same body |
| Shelf order | `orderedByImminence` (`:279-285`); deleted with nil date last | `fadingOrdered` / `deletedOrdered` (`WayOutRules.swift:180-190`); nil date first |
| One-liner | `WayOutView.oneLiner` (`:296-299`) | `WayOutRules.oneLiner` (`:124-135`) |
| `purgeDue`, `fadeEntersAt` | phone only (purge on the phone's seen-clock; the fading dot) | Mac has no Memo purge by design (`MacCloudDeleteSync.swift:15`) |
| `MemoSpine.chipText/peekSentence` | not used | used by the Mac peek sheet only |

Behaviour differences to remove: the phone list shows duplicate clones the Mac hides; two copies each of bring-back, shelf order, one-liner and the urgency threshold.

Shared implementation: `Shared/Pipeline/WayOut.swift` — `bringBack`, `fadingOrdered`, `deletedOrdered` (nil date last), `oneLiner`, `daysLeft(until:)`, `isUrgent`. Both apps' old entry points forward to it. The phone's display readers (Notes list, Journal home/calendar/map) go through `MemoDuplicates.canonicalRows` via `NotesRepository.canonicalMemos()`; `allMemos()` stays raw because `MemoDeduperTests.testDivergentSameIdRowsAreLeftAlone` asserts both rows come back. Deliberate platform differences kept and named: Mac has no Memo purge; phone has no peek sheet.

## 11. Conversation turns

| | Phone | Mac |
|---|---|---|
| Colour slot | `SpeakerTurnStyle.slots` (shared, `MemoPageView.swift:804`) | `SpeakerTurnStyle.turns` (shared, `BodyTextView.swift:659`) — already one rule |
| Naming a speaker | `MemoPageView.assign` (`SkriftMobile/Features/MemoDetail/MemoPageView.swift:905-925`): by slot, else replaces the literal `**old:**` header text, then merges adjacent turns; copy-edit untouched | `SplitSpeakers.nameSpeaker` (`SkriftDesktop/Pipeline/BatchManager/SplitSpeakers.swift:117-129`): relabels every turn whose header RESOLVES to the same person, on transcript and copy-edit |
| Other speakers for "move this line" | own list in the turn view | `SplitSpeakers.otherSpeakers` (`:101-111`), identity-based |

Behaviour difference: the phone matches header text, so `**[[Tiuri Hartog]]:**` then `**Tiuri:**` is two speakers to it and one to the Mac.

Shared implementation: `Shared/Pipeline/SpeakerNaming.swift` — `SpeakerNaming.rename(_:displayed:to:people:turnSlots:slot:)` (slot-aware when a slot map lines up, else identity match, then merge adjacent) and `otherSpeakers(than:in:people:)`. Both apps call it; the Mac's `nameSpeaker` and the phone's `assign` keep only their storage writes.

## 8. Looking back

| | Phone | Mac |
|---|---|---|
| Cards | `JournalHomeView.reload` (`SkriftMobile/Features/Journal/JournalHomeView.swift:160-185`): "Important lately" first, its ids excluded from the lookbacks, the Then vs Now pair excluded too | `JournalView.lookbackColumn` (`SkriftDesktop/Features/Journal/JournalView.swift:326-334`): only the pair excluded; no important card |
| Then vs Now window + candidates | `JournalIndexService.thenVsNow` (`SkriftMobile/Services/Embeddings/JournalIndexService.swift:136-153`) | `JournalView.deriveThenVsNow` (`:112-140`), a line-for-line copy |
| Card date | `Entry.date` (`LookbackCard`, `JournalHomeView.swift:423-435`) | recomputes `journalDate(memo)` |

Behaviour difference: the Mac shows a note in a lookback card that the phone would have shown under "Important lately".

Shared implementation: `LookbackProvider.river(for:now:pair:showImportantLately:)` returns `{important, entries}` with the one exclusion rule; `ThenVsNow.window(now:)` + `ThenVsNow.recents(...)` hold the window and recents selection both apps duplicated. Mac keeps no important card (no signed Mac mock for it; `mocks/journal-desktop.html` has none), so it passes `showImportantLately: false` and the Mac's exclusion stays pair-only, stated in one flag rather than two copies of the rule. `Entry.date` stays phone-only: the Mac card prints `journalDate(memo)`, which is the same value.

## 12. Recording helpers

| | Phone | Mac |
|---|---|---|
| Encoder settings | inline dictionary, `SkriftMobile/Services/Recording/LiveRecordingService.swift:878-883` | writes through its own capture path, not `RecordingCore.encoderSettings` |
| Input level | private `rms` (`LiveRecordingService.swift:1607-1615`, ×12) | `RecordingCore.level` |
| Waveform window | `waveform` array capped at 40 (`:1693-1696`), padded in `RecordView.swift:863-866` | `RecordingCore.Meter` (12 bars) |
| Timer label | `RecordClock.string` `%d:%02d` (`SkriftMobile/Features/Recording/RecordView.swift:598-603`) | `RecordingCore.elapsedLabel` (adds `h:mm:ss` past an hour) |
| File name | `"memo_\(id.uuidString).m4a"` typed out ~8 times (`MemoSaver.swift:76,136,162,234,266,461,694`; `RecordingRecovery.swift:133`) | `RecordingCore.filename()` |

Behaviour differences: a phone recording past an hour reads "62:10", the Mac "1:02:10"; the settings, gain and file name live twice.

Shared implementation: `RecordingCore` (exists, `Shared/Recording/RecordingCore.swift`). The phone calls `encoderSettings`, `level`, `Meter(width: 40)`, `elapsedLabel`, `filename`. `Meter` gains a width so both apps run the same window logic.

## Not changed, named

Sidebar exact-match search differs (phone `Memo.matches(query:)`, Mac `AppModel.matchesSearch` — title, transcript, summary, OCR): outside the six groups, listed for a later item.
