# Q62 — 116 built-and-tested, never-called functions: WIRE IN or DELETE?

Source: `plan/periphery.md` "Test-only CHECK (116)" (each has a dedicated unit test, zero production caller). Grouped by feature, 15 groups, all 116 accounted for. First-commit dates are **file-level** (`git log --follow --diff-filter=A`) — the commit that introduced the file, not necessarily that exact line; fast enough to read in one sitting, not exact per-line archaeology.

Pick **WIRE IN** or **DELETE** per group (delete takes its tests too — pre-approved per group by picking DELETE).

## The 15 groups — pick one

| # | Group | Count | Suggested |
|---|---|---|---|
| 1 | v2 rewrite draft scaffolding (today's queue, Q11/14/21/26/29) | 12 | WIRE IN — later queue items consume these |
| 2 | Tag system (parse / complete / match / scan) | 6 | SPLIT — see notes |
| 3 | Vault export write path (stamp + writer) | 3 | WIRE IN if unread fields are real, else DELETE |
| 4 | Name-linking (Sanitiser) | 5 | WIRE IN if real gap, else DELETE |
| 5 | Audiobooks — alignment, ePub, capture math, chapters | 39 | MIXED — see notes, biggest group |
| 6 | Karaoke / word-timed highlight | 4 | DELETE candidate — check Karaoke UI first |
| 7 | Language sync | 1 | WIRE IN — sounds like a real gap |
| 8 | Journal "Looking back" | 1 | DELETE candidate |
| 9 | Notes-list core (dupes/lifecycle/spine/queue) | 12 | MIXED — see notes |
| 10 | Paragrapher | 3 | DELETE candidate — old variants |
| 11 | Conversation turns (speaker transcript + style) | 9 | WIRE IN — likely real gaps |
| 12 | Recording pipeline (save/filter/log/core/arrival) | 8 | DELETE candidate — diagnostics/dead branches |
| 13 | Retrieval / embedding search | 4 | WIRE IN — search UI may be missing |
| 14 | Significance / importance UI | 1 | DELETE candidate |
| 15 | Export pipeline (Obsidian) | 8 | WIRE IN — some look like real missing verbs (PDF, quote-card) |

---

## 1. v2 rewrite draft scaffolding — 12
What it was for: today's session's own draft code for the v2 core rewrite (spec C-series), written ahead of the queue item that wires it in — same pattern as Q58/`NamesStore.pruneOldTombstones`.

- Function `isC203Legacy(sharedContentData:madeAt:)` — `Skrift_Native/Shared/BodyV2/BodyNormaliseMigration.swift:67` — 2026-09-24 "Q14: shared BodyNormaliseMigration (detect v1, rewrite, remap name offsets, local ledger + undo, C203 skip)"
- Function `remap(_:from:to:)` (NSRange) — `.../BodyNormaliseMigration.swift:148` — same commit
- Function `remap(_:map:)` — `.../BodyNormaliseMigration.swift:152` — same commit
- Function `remap(_:from:to:)` ([AmbiguousOccurrence]) — `.../BodyNormaliseMigration.swift:160` — same commit
- Nested function `record(for:)` — `.../BodyNormaliseMigration.swift:217` — same commit
- Function `undo(id:bodies:ledger:now:)` — `.../BodyNormaliseMigration.swift:309` — same commit
- Enum `BodyV2.Source` (speech/typed/shareCapture) — `Skrift_Native/Shared/BodyV2/BodyV2.swift:25` — 2026-09-24 "Q11: body v2 draft beside v1 (marker regex/writer, placement, C19/C20, C170 thumbnail)"
- Property `deviceID` — `Skrift_Native/Shared/Model/EditConflict.swift:43` — 2026-09-24 "Q29 draft: shared edit-conflict model (per-device heads + edit vector)"
- Property `memoID` — `.../EditConflict.swift:60` — same commit
- Function `contentVisible(locked:unlockedThisSession:)` — `Skrift_Native/Shared/Session/NoteVisibility.swift:11` (periphery cites the enum line 10) — 2026-09-24 "Q21: add the shared NoteVisibility predicate, wire LockGate.isLocked through it"
- Function `dayGroups<T>(_:dayLabel:)` — `Skrift_Native/Shared/UI/NotesListModel.swift:20` — 2026-09-24 "Q26: shared NotesListModel + MemoDate move (draft 1/n)"
- Enum `NotesListModel.PillRule` — `.../NotesListModel.swift:35` — same commit

**Recommendation: WIRE IN.** Not stale — these are this wave's own in-progress drafts, dated today, named by their own queue item. Confirm each has a follow-up queue item (Q22/Q27/Q30-ish) before flipping to DELETE.

## 2. Tag system — 6
What it was for: how a note's `#tags` get parsed, typed-ahead, matched, and cross-checked against the vault's real tag list. Three eras of code.

- Function `parseTagInput(_:)` — `Skrift_Native/Shared/Model/Memo.swift:300` — 2026-06-06 "native Phase 1: SwiftData data model + names store/sync"
- Struct `TagRules.Fold` (reported twice, same line) — `Skrift_Native/Shared/UI/TagRules.swift:48` — 2026-09-24 "Q28: shared TagRules (split/fold) + fix Memo.splitTagInput # bug"
- Enum `TagComplete` — `Skrift_Native/Shared/Pipeline/TagComplete.swift:8` — 2026-07-16 "feat(desktop): inline #tags in the note body — Obsidian-style completion popup"
- Enum `TagMatcher` — `Skrift_Native/Shared/Pipeline/Tags/TagMatcher.swift:9` — 2026-06-06 "desktop(native): Phase 5b — deterministic tags (NLTagger)"
- Enum `VaultTagScanner` — `Skrift_Native/Shared/Pipeline/Tags/VaultTagScanner.swift:10` — 2026-06-07 "desktop(native): B3 — scan the vault for a real tag whitelist"

**Note:** Q28 (today) says it fixed a bug "IN `Memo.splitTagInput`" — that's a different, presumably-still-live function than `parseTagInput` above; worth Tuur confirming `parseTagInput` is really the superseded one, not a sibling still in use. TagComplete/TagMatcher/TagRules/VaultTagScanner read like a real, shipped feature (inline typeahead) that memory says landed 2026-07-16 — if so, this being test-only-uncalled is surprising and worth a second look before deleting.

## 3. Vault export write path — 3
What it was for: the shared engine that stamps and writes a note into the Obsidian vault (built 2026-07-26, "ONE vault-write engine").

- Property `touchedAt` — `Skrift_Native/Shared/Export/VaultStamp.swift:53` — 2026-07-26 "feat(🖥️📱): the exported-note stamp — a contract, not an implementation detail"
- Property `audioURL` — `Skrift_Native/Shared/Export/VaultWrite.swift:314` — 2026-07-26 "feat(🖥️): ONE vault-write engine — the Mac exports through it (chunk 1b)"
- Property `attachmentsWritten` — `.../VaultWrite.swift:315` — same commit

**Recommendation:** these are result-struct fields on a function (`VaultWrite`'s write call) that IS used in production — only these specific fields go unread outside tests. WIRE IN if the export UI should surface attachment counts/touch time; otherwise DELETE just the fields (not the write path).

## 4. Name-linking (Sanitiser) — 5
What it was for: the core `[[Name]]` linking engine (2026-06-06, desktop Phase 5a).

- Property `ambiguous` ([AmbiguousOccurrence]) — `Skrift_Native/Shared/Naming/Sanitiser.swift:34` — 2026-06-06 "desktop(native): Phase 5a — name-linking (non-blocking sanitise)"
- Property `silenced` (Set<String>) — `.../Sanitiser.swift:53` — same commit
- Function `nameSpans(inRaw:people:...)` — `.../Sanitiser.swift:221` — same commit
- Function `plainOccurrences(of:in:)` — `.../Sanitiser.swift:544` — same commit
- Function `unlinkToSpoken(_:people:)` — `.../Sanitiser.swift:664` — same commit

**Recommendation:** `unlinkToSpoken` sounds like the reverse of a shipped "unlink a name" feature (memory: name-unlink mock signed off) — check if that UI calls a different helper first. Others (`ambiguous`/`silenced` fields, `plainOccurrences`) look like diagnostic surface for the sanitiser's own decisions — WIRE IN if a "why was this linked" UI exists or is wanted, else DELETE.

## 5. Audiobooks — alignment, ePub, capture math, chapters — 39
What it was for: read-along text/audio alignment (`AlignmentCore`, `EPubParse`, `BookAlignment`), quote-capture window math (`CaptureMath`), and chapter detection — the 2026-06/07 audiobook build-out.

- `AlignmentCore.Result` and its nested `WordTime`/`MatchedRange`/`TranscriptSpan`/`BookSpan` diagnostic fields (18 properties: `end`, `direct`, `sourceFile`, `bookWordEnd`, `start`, `end`, `wordStart`, `wordEnd`, `preview`, `sourceFile`, `wordStart`, `wordEnd`, `preview`, `coverageTranscript`, `anchorCount`, `monotonicFraction`, `largestUnmatchedTranscriptSpans`, `largestUnmatchedBookSpans`) — `Skrift_Native/Shared/Pipeline/AlignmentCore.swift:88-138` — 2026-07-21 "feat(shared): AlignmentCore — transcript ↔ book-text word alignment"
- `EPubParse` fields: `id`, `title`, `sourceFile`, `fragment`, `drm`, `title` — `Skrift_Native/Shared/Pipeline/EPubParse.swift:89,500,501,502,513,516` — 2026-07-21 "feat(📖 EPUB lane): EPubParse — pure ePub → book-text extractor (spike 4)"
- Function `alignIfNeeded(bookID:)` (re-align branch) — `Skrift_Native/SkriftMobile/Services/Audiobooks/BookAlignment.swift:581` — 2026-07-22 "feat(📖 spike 6): BookAlignment.swift — contract types, store, runner, sentence assembly"
- `CaptureMath` constants/functions: `replayLookback`, `windowExtensionStep`, `minimumSpan`, `proposal(now:duration:)`, `proposal(now:in:)`, `transcriptionBuffer(for:duration:)`, enum `CaptureMath` itself, `isSentenceEnd(_:)`, `inForwardSnapThreshold`, `snap(words:...)`, `rambleBody(transcript:)`, `attributionPreview(author:book:chapter:)` — `Skrift_Native/SkriftMobile/Services/Audiobooks/CaptureMath.swift:16,20,25,36,43,63,73,227,266,306,351,372` — 2026-06-11 "feat(mobile): audiobook player + library + retroactive quote capture (lane audiobook-mobile)"
- Function `headings(in:globalOrigin:)` — `Skrift_Native/SkriftMobile/Services/Audiobooks/ChapterDetector.swift:340` — 2026-07-11 "feat(books): transcript chapter detection + engine-path efficiency"
- Function `audioURL(of:)` — `Skrift_Native/SkriftMobile/Services/Audiobooks/Audiobook.swift:519` — 2026-06-11 same lane commit as CaptureMath

**Recommendation:** biggest group, needs Tuur's own eyes most. The `CaptureMath` cluster (12 items, whole constants + most of the quote-capture math) reads like an entire ALTERNATE quote-capture implementation next to the one actually wired — worth checking there isn't a live duplicate before deleting either. `AlignmentCore`/`EPubParse` diagnostic fields: WIRE IN only if a coverage/debug view is wanted (per memory's "no-bad-information" doctrine, coverage gaps already degrade display elsewhere) — otherwise DELETE.

## 6. Karaoke / word-timed highlight — 4
What it was for: which word is "live" during audio playback (2026-07-06 correctness audit).

- Function `activeWordIndex(_:at:)` — `Skrift_Native/Shared/Pipeline/Karaoke.swift:17`
- Function `activeWordIndex(_:at:hint:)` — `.../Karaoke.swift:30`
- Function `activeCount(times:currentTime:)` — `.../Karaoke.swift:110`
- Function `normalize(_:)` — `.../Karaoke.swift:118`
— all 2026-07-06 "fix(desktop): correctness audit — upload off-main I/O, conversation tagging, word-timed karaoke"

**Recommendation: DELETE candidate.** Two overloads of `activeWordIndex` plus a `hint`-based variant smells like an optimisation pass that never got swapped in over the one actually called. Check the live karaoke view's call site first.

## 7. Language sync — 1
What it was for: syncing the transcription-language setting from the Mac (2026-07-26).

- Function ending `now: Date = Date()) -> Outcome` (LanguageSyncCore's sync entry point) — `Skrift_Native/Shared/Pipeline/LanguageSyncCore.swift:29` — 2026-07-26 "fix(🎙️): the Mac gets a transcription Language setting, and it SYNCS"

**Recommendation: WIRE IN.** This is the actual sync-outcome function for a feature memory confirms shipped — if it's untested-in-production, the feature may be calling an inline copy instead of this shared core. Worth a second look, not a straight delete.

## 8. Journal "Looking back" — 1
What it was for: the mobile Journal tab's "on this day" provider (2026-07-07).

- Property `date` (on a Lookback entry) — `Skrift_Native/Shared/Pipeline/LookbackProvider.swift:29` — 2026-07-07 "feat(mobile): Journal tab v1 — Looking back + calendar + map (P8 chunk 5, to the signed mock)"

**Recommendation: DELETE candidate** unless Looking-back is still on the roadmap as unshipped — check FEATURES.md's Journal row first.

## 9. Notes-list core (dupes/lifecycle/spine/queue) — 12
What it was for: the shared rules behind the one-list IA — which memo "wins" when duplicated, when a note fades/purges, its spine status text, and the Process queue's filters.

- Function `canonicalRows(_:)` — `Skrift_Native/Shared/Pipeline/MemoDuplicates.swift:46` — 2026-07-13 "fix(sync): Mac sweep is duplicate-tolerant — shared MemoDuplicates keeper rule"
- Function `touch(_:now:)` — `Skrift_Native/Shared/Pipeline/MemoLifecycle.swift:40` — 2026-07-18 "feat(lifecycle): the shared Fading rulebook + keptAt (phase 1)"
- Function `fadeEntersAt(_:)` — `.../MemoLifecycle.swift:76` — same commit
- Function `daysUntilSweep(_:now:)` — `.../MemoLifecycle.swift:81` — same commit
- Function `purgeDue(_:now:)` — `.../MemoLifecycle.swift:127` — same commit
- Function `goneAt(_:)` — `.../MemoLifecycle.swift:135` — same commit
- Function `name(for:)` (Station) — `Skrift_Native/Shared/Pipeline/MemoSpine.swift:169` — 2026-07-21 "feat(shared): the spine ① — one derived status per note"
- Function `chipText(for:now:)` — `.../MemoSpine.swift:186` — same commit
- Function `peekSentence(for:backlinked:now:)` — `.../MemoSpine.swift:195` — same commit
- Function `waiting(memos:enhancedIDs:)` — `Skrift_Native/Shared/Pipeline/ProcessPile.swift:20` — 2026-07-23 "fix(iPad chrome): the note bar survives portrait, Process runs the real pile"
- Function `done(memos:enhancedIDs:)` — `.../ProcessPile.swift:38` — same commit
- Function `matches(_:_:enhancedIDs:)` — `.../ProcessPile.swift:54` — same commit

**Recommendation:** `touch`/`fadeEntersAt`/`daysUntilSweep`/`purgeDue`/`goneAt` are the CORE lifecycle-clock functions memory says are locked and live ("one-clock lifecycle, VERIFIED + MERGED 2026-07-23") — if periphery says no caller, either the app calls differently-named equivalents (duplication) or the clock runs through a path periphery's static scan can't see (e.g. a protocol witness). Don't delete blind — WIRE IN or re-verify the live call site first. `MemoSpine`/`ProcessPile` functions look like a second, unused variant of status/queue logic next to whatever IS wired — DELETE candidates once confirmed unused.

## 10. Paragrapher — 3
What it was for: splitting a raw transcript into paragraphs (2026-06-19, an early build).

- Function `paragraphed(words:...)` — `Skrift_Native/Shared/Pipeline/Paragrapher.swift:44`
- Function `paragraphed(transcript:words:...)` — `.../Paragrapher.swift:76`
- Function `paragraphed(text:sentencesPerParagraph:)` — `.../Paragrapher.swift:120`
— all 2026-06-19 "transcription: paragrapher (built+demoed) + chunk leading-context (de-garble seams)"

**Recommendation: DELETE candidate.** Three overloads of the same verb from the earliest paragraphing pass — memory says "paragraphs single-sourced" since (live-transcription project). Likely superseded by whichever one IS called; the other two are dead scaffolding.

## 11. Conversation turns (speaker transcript + style) — 9
What it was for: parsing `**Name:**` speaker headers and styling them into the turn gutter (2026-07-13 → 2026-07-27, "E1 SHIPPED + Tuur-confirmed").

- Function `isAttributed(_:)` — `Skrift_Native/Shared/Pipeline/SpeakerTranscript.swift:116` — 2026-07-13 "refactor(shared): ONE SpeakerTranscript — the shared Sanitiser stops forking (Board C1)"
- Function `parseWithPreamble(_:)` body line — `.../SpeakerTranscript.swift:126` — same commit
- Function `withPreamble(of:_:)` — `.../SpeakerTranscript.swift:90` (periphery cites blank line 87 just above it) — same commit
- Function body line inside a joined-turns helper — `.../SpeakerTranscript.swift:139` — same commit
- Function body line inside a rebuild-turns helper — `.../SpeakerTranscript.swift:159` — same commit
- Struct `SpeakerTurnStyle.Turn` property `bodyRange` — `Skrift_Native/Shared/Pipeline/SpeakerTurnStyle.swift:69` — 2026-07-27 "feat(🗣️): the turn header leaves the paragraph — E1 gutter, a spine per voice"
- Function `turns(in:people:)` — `.../SpeakerTurnStyle.swift:85` — same commit
- Function `slots(forParsedNames:people:)` — `.../SpeakerTurnStyle.swift:113` — same commit
- Function `label(for:)` — `.../SpeakerTurnStyle.swift:127` — same commit

**Recommendation: WIRE IN if real.** Memory confirms the E1 gutter shipped and is device-confirmed working — if `SpeakerTurnStyle.turns`/`label`/`slots` truly have no caller, the shipped view must call an inlined copy. Re-verify the live call site before deleting; this is core-feature code, not scaffolding.

## 12. Recording pipeline (save / filter / log / core / arrival) — 8
What it was for: turning a finished recording into a saved+transcribing memo, filler-word stripping, dev logging, the shared recording-core helpers, and the Mac's arrival-path hooks.

- Function `saveAndTranscribe(tempURL:duration:photos:)` — `Skrift_Native/SkriftMobile/Features/Recording/MemoSaver.swift:552` — 2026-06-06 "native Phase 2: recording + transcription"
- Property `removedCount` — `Skrift_Native/SkriftMobile/Models/FillerFilter.swift:29` — 2026-07-11 "feat(memos): opt-in filler-word strip (um/uh/hmm) at transcript save"
- Function `drain()` — `Skrift_Native/SkriftMobile/Services/DevLog.swift:62` — 2026-06-12 "fix(mobile/recording): P0 tap-install crash … + DevLog dev file logging"
- Function `encoderSettings(for:)` — `Skrift_Native/Shared/Recording/RecordingCore.swift:18` — 2026-07-28 "feat(🎙): the Mac records too — option B, and one shared core"
- Function `filename(id:ext:)` — `.../RecordingCore.swift:29` — same commit
- Function `elapsedLabel(_:)` — `.../RecordingCore.swift:48` — same commit
- Struct `RecordingCore.Meter` — `.../RecordingCore.swift:58` — same commit
- Property `inert` (static Hooks default) — `Skrift_Native/SkriftDesktop/Pipeline/Ingest/ArrivalPath.swift:39` — 2026-07-28 "feat(🎙): the arrival path leaves the view — so a broken mic can't hide a broken pipeline"

**Recommendation: mostly DELETE candidates.** `drain()` looks like a test-only flush hook for `DevLog` (reasonable to keep FOR tests, i.e. leave alone / not a real "unused" bug). `RecordingCore.Meter`/`encoderSettings`/`filename`/`elapsedLabel` are shared helpers the Mac-recording rebuild may have inlined instead of calling — check before deleting since MacRecorder was "REBUILT" per memory. `inert` is a legitimate test-double default, fine to leave.

## 13. Retrieval / embedding search — 4
What it was for: the P8 on-device semantic search index (2026-07-07).

- Property `createdAt` — `Skrift_Native/Shared/Retrieval/EmbeddingIndex.swift:16`
- Property `searchFloor` (static, 0.25) — `.../EmbeddingIndex.swift:28`
- Function `search(_:)` async — `.../EmbeddingIndex.swift:156`
- Function `rowCount(for:)` — `.../EmbeddingIndex.swift:172`
— all 2026-07-07 "feat(mobile): P8 retrieval engine — EmbeddingGemma index, sweep, queries (chunks 1-3)"

**Recommendation: WIRE IN.** `search(_:)` with a `searchFloor` threshold is exactly what a search box would call — if there's no search UI wired to it, that's a plausible real gap (a whole feature built, never surfaced), not dead code. Worth Tuur checking if search is missing from the app today.

## 14. Significance / importance UI — 1
What it was for: the "one importance control" warm-fill mix (2026-08-12).

- Enum `SignificanceWarmFill` — `Skrift_Native/Shared/UI/SignificanceWarmFill.swift:16` — 2026-08-12 "refactor(⚖️): ONE importance control, and the warm-fill mix finally comes from Palette"

**Recommendation: DELETE candidate** unless the importance control's live code still computes the warm-fill mix inline instead of through this shared enum (in which case WIRE IN to finish the "ONE control" consolidation the commit describes).

## 15. Export pipeline (Obsidian) — 8
What it was for: turning a Memo into Markdown/plaintext/PDF/quote-card and fanning it out to the vault (2026-06-21, mobile Phase 2).

- Function `markdown(for:author:enhancement:)` — `Skrift_Native/SkriftMobile/Services/Export/MemoExporter.swift:38`
- Function `plainText(for:people:)` — `.../MemoExporter.swift:46`
- Function `plainText(for:)` — `.../MemoExporter.swift:53`
- Function `pdf(for:people:)` — `.../MemoExporter.swift:182`
- Function `quoteCardImage(for:people:)` — `.../MemoExporter.swift:228`
— all 2026-06-21 "phase2: MemoExporter — Memo → Obsidian MD / txt / PDF / quote-card"
- Function `linkedTranscript(_:)` — `Skrift_Native/SkriftMobile/Services/Export/MemoLinking.swift:33` — 2026-06-21 "phase2: on-device name-linking (MemoLinking) — re-derive [[Name]] for export"
- Struct `PublishCoordinator.Summary` — `Skrift_Native/SkriftMobile/Services/Export/PublishCoordinator.swift:37` — 2026-06-21 "phase2: PublishCoordinator — Obsidian sink fan-out (policy + paired-mode gating)"
- Function `publishAll()` — `.../PublishCoordinator.swift:155` — same commit

**Recommendation: WIRE IN for `pdf`/`quoteCardImage`/`publishAll`.** Memory confirms quote-card and the four-export-destination work shipped later (2026-08-28) — these June originals may be the pre-consolidation versions the later work replaced. Check the shipped export sheet's call sites before deleting; `plainText` has two overloads (`for:people:` vs `for:`), one is likely dead scaffolding.

---

## Method note
Periphery's packed CHECK list gives file:line only, no symbol name or kind — each line above was read from source to name the actual declaration (function/property/struct/enum) at or immediately after that line. Dates are the file's first commit, not necessarily the line's — several files (e.g. `AlignmentCore.swift`, `EPubParse.swift`) have had one commit total so file-date = line-date there; files with many commits (`MemoLifecycle.swift`, `Sanitiser.swift`) may have had the specific flagged line added later than the file-creation date shown.
