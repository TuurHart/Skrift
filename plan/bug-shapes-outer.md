# Bug-shape sweep, round 2 — the outer subsystems (SPEC.md C248)

Covers what the first sweep (`plan/bug-shapes.md`) did NOT reach: `SkriftMobile/Services/Audiobooks/**`
+ `Features/Audiobooks/**`, `Shared/Retrieval/**` + Connections (both apps), `SkriftMobile/Features/MemoDetail/**`,
`SkriftDesktop/Features/Review/**`, Recording (`SkriftMobile/Services/Recording/**` + `Shared/Recording/**`),
the lifecycle/launch sweeps, and the first sweep's three explicit follow-ups (fading-conveyor rated/unrated
coverage, diarization sidecar-vs-store parity, `transcriptMarkersInjected`'s single-writer point). Same
13 shapes as the brief (1-10 from the first sweep + 11 concurrent-sweep reentrancy, 12 stale-key cache,
13 UI state outliving its model). Every CANDIDATE below was verified by reading the write site and at
least one caller/read site — never asserted from a grep hit or memory.

Four clusters were swept in parallel (three by dispatched agents, one directly): Audiobooks;
Retrieval/Connections/MemoDetail; Desktop Review/Recording; and lifecycle+launch sweeps +
the three follow-ups (done directly, not delegated).

---

## Cluster A — Audiobooks (`Services/Audiobooks/**` + `Features/Audiobooks/**`, 40 files, 12,781 lines)

### Shape 11 — concurrent re-entrancy
Read `BookBackgroundScheduler.swift` + `BookTranscriptionJob.swift` in full.

| Site | Verdict | Note |
|---|---|---|
| `BookTranscriptionJob.start(book:)` | SAFE | `if activeBookID == book.id, isRunningOrPaused { return }` no-ops a duplicate start; a different book cancels first — single global job by design. |
| `BookBackgroundScheduler.handle` | SAFE | Only resumes the book active when backgrounded; `done` flag + main-actor hop prevents double `setTaskCompleted`. |
| `chunkTask` lifecycle in `run()` | SAFE | One chunk task in flight; `cancelInFlightChunk()` is nil-safe. |

No candidates.

### Shape 12 — cache/index keyed by something that changes
Read `BookAlignment.swift` (1355 lines), `AlignedSentenceSource.swift`, `ChunkFusion.swift`, `ChapterDetector.swift`.

- SAFE. `FileAlignment.transcriptSignature` is recomputed/compared every call; 5 schema bumps force re-align on old sidecars. `attach()` never trusts the cache.
- SAFE. `epubSignature` is documented as unused for staleness — confirmed no caller branches on it.
- SAFE. `AlignedSentenceSource.sentences` takes `isFresh` as a parameter computed fresh by both callers.
- SAFE. `detectedChapters` is explicitly invalidated to `nil` on transcript removal and stripped in `sanitizedForSync()`.

No candidates.

### Shape 13 — UI state outliving its model
Read `ChaptersBookmarksSheet.swift`, `AudiobookSession.swift`, `AudiobookLibraryView.swift`, `SyncedAudiobooksView.swift`, `AudiobookPlayerView.swift`.

| Site | Verdict | Note |
|---|---|---|
| `ChaptersBookmarksSheet.bookmarksList.onDelete` | SAFE (unreachable) | Multi-index aliasing bug in theory, but no `EditButton`/`editMode` exists in this sheet's parent chain — swipe-to-delete only ever yields a single-element `IndexSet`. |
| `AudiobookSession.book` after `AudiobookLibraryView.delete(_:)` | SAFE | Guards `session.book?.id == book.id` → `endSession()` before removal. |
| `AudiobookSession.book` after "Remove from this iPhone only" | SAFE | Same guard present, with a comment explaining why. |
| **`SyncedAudiobooksView.row` "Remove download" (line 66)** | **CANDIDATE** | see below |

### Shape 1 — silent empty result
Greps: `return []` → 16, `?? []` → 16, `?? ""` → 18 (all triaged), `try?` → 98 (spot-checked on write/decode paths).

| Hit | Verdict | Note |
|---|---|---|
| **`Bookmark.swift:46-50`** | **CANDIDATE** | see below |
| `BookTranscriptStore.load` | SAFE | Decode failure → `nil` → caller re-transcribes from source audio (self-healing). |
| `BookAlignmentStore.fileAlignment` | SAFE | Same self-healing shape. |
| `AudiobookCloudSync.reconcileOnce` receive loop (line 210) | SAFE | Per-record skip; retried every reconcile. |
| `AudiobookCloudSync` send-side (line 252-253) | SAFE | Corrupt remote record treated as "needs updating," overwritten with local's known-good state. |
| `BookBundle.readManifest`/`unpack` | SAFE | Decode failures propagate as thrown `BundleError`s. |
| **`AudiobookCloudSync.receiveTranscripts` (line 472-486)** | **CANDIDATE** | see below |

### Shapes not reached (Audiobooks)
2 (two-lists gap, no audiobook-specific pair checked), 3 (only the known bookmark-sync case reviewed),
5 (broader "pending" sweep not attempted beyond `isTranscribing`), 6 (only bookmark sync + `detectedChapters`/`epubFilenames` checked), 9 (`TranscriberFactory.make()` sits outside this scope).
Shape 4 (7 hits, all read, all SAFE — unique-by-construction lookups). Shape 8: `ChunkFusion.fuse` +
`AlignedSentenceSource.asrFallback` read in full, both correct-by-design.

### CANDIDATES — Audiobooks

**A1 — `receiveTranscripts` latches "applied" without verifying the download landed**
`Skrift_Native/SkriftMobile/Services/Audiobooks/AudiobookCloudSync.swift:472-486` sets
`defaults.set(record.transcriptSignature, forKey: appliedKey)` unconditionally after
`try? await transport.download(...)`. Its two siblings both learned this lesson already:
`receiveEpubs` (line 570-592) only latches after checking `!landed.isEmpty`; `receiveAlignments`
(line 680-722) explicitly cites a 2026-07-23 device catch ("the old unconditional latch meant the
iPad never retried") and now gates on `allFresh`. `transport.download`'s own implementation
(`CloudKitAudiobookTransport.swift:122-142`) confirms per-record failures are only logged, so a
routine, non-throwing partial download still latches "applied" here.
- What the user does: nothing wrong — a routine per-record CloudKit hiccup during a transcript pull.
- What they get: that book's read-along/chapter-detection transcript never lands on this device,
  permanently — the top-of-function guard returns immediately on every future reconcile.
- What they should get: the same landed-file verification `receiveEpubs`/`receiveAlignments` do.
- Fix location: `AudiobookCloudSync.swift:472-486` (reference: `receiveEpubs:570-592`, `receiveAlignments:680-722`).
- SPEC clause: C218 ("an applied-marker records what it produced") — this is the one sync function
  where that isn't true. Recommend a BUGS.md row, twin of R42/R43.

**A2 — corrupt local `bookmarks.json` silently wipes real bookmarks on the next edit**
`Skrift_Native/SkriftMobile/Services/Audiobooks/Bookmark.swift:46-50`:
```swift
func load(bookID: UUID) -> [AudiobookBookmark] {
    guard let data = try? Data(contentsOf: fileURL(bookID: bookID)),
          let list = try? JSONDecoder().decode([AudiobookBookmark].self, from: data) else { return [] }
    return list.sorted { $0.position < $1.position }
}
```
`add()`/`remove()` both call `load()` then unconditionally `save()` the result. A decode failure
(truncated write, disk hiccup, a future field change — `AudiobookBookmark` has no schema version,
unlike `FileTranscript`/`FileAlignment`) returns `[]`, indistinguishable from "no bookmarks yet."
The next add/remove persists that empty list back, permanently discarding every prior bookmark.
Unlike transcript/alignment sidecars (recomputable from source), bookmarks are pure user input
with no other copy on-device.
- What the user does: nothing wrong — a transient disk write interruption corrupts `bookmarks.json`
  for a book they've bookmarked before; they later add/remove any bookmark on it.
- What they get: every prior bookmark for that book vanishes, replaced by the one just added.
- What they should get: a decode failure distinguished from "no file" — never silently overwritten.
- Fix location: `Bookmark.swift:46-50` (compounds at `add`:56-66, `remove`:68-75).
- SPEC clause: none for the local store specifically (C218 covers the *sync* blob — R42's already-pinned
  finding one layer up). Recommend a BUGS.md row alongside R42.

**A3 — `SyncedAudiobooksView`'s "Remove download" is missing the session-end guard its sibling has**
`Skrift_Native/SkriftMobile/Features/Audiobooks/SyncedAudiobooksView.swift:66` calls
`AudiobookCloudSync.removeDownload(bookID: book.id)` directly. `AudiobookLibraryView.swift:184-187`
(same action, reached from the library's own delete-confirm sheet) was deliberately written with
`if session.book?.id == book.id { session.endSession() }` first. `removeDownload` deletes local
audio files unconditionally; `AudiobookSession.loadFile` guards file-existence for a *new* load,
but nothing ends a session whose file is already loaded/playing when it vanishes underneath it.
- What the user does: opens Settings → Synced audiobooks and removes the download of the book
  currently open/playing.
- What they get: audio deleted while the player still thinks it's the active session — playback
  stalls or the next seek silently pauses, with no user-facing explanation.
- What they should get: the same `session.endSession()` guard the library's identical action has.
- Fix location: `SyncedAudiobooksView.swift:66` (reference: `AudiobookLibraryView.swift:184-187`).
- SPEC clause: C218 covers the sync contract generally but not this ordering — spec hole; recommend
  a BUGS.md row.

---

## Cluster B — Retrieval / Connections / MemoDetail

Full read: `Shared/Retrieval/RetrievalGate.swift`, `Shared/Retrieval/EmbeddingIndex.swift` (grounding),
both `ConnectionsPanel.swift` (desktop + mobile), all 17 files in `SkriftMobile/Features/MemoDetail/`.

### Shape 7 — twin copies (priority)
| Site | Verdict | Note |
|---|---|---|
| Row model, sort pill, rail/flat rows, why-chips, consent gate, hide-list | SAFE | Structurally identical, phone-tokened styling only. |
| **Mobile `ConnectionsPanel.load()` vs desktop `ConnectionsModel.refresh`** | **CANDIDATE** | see B1 below |
| **`JournalIndexService.sweepSoon` catch (mobile) vs `ConnectionsIndexService.sweepSoon` catch (desktop)** | **CANDIDATE** | see B2 below |
| `SignificanceCircles.swift` mobile vs desktop | SAFE | Both thin wrappers over the shared `SignificanceCirclesView`/`SignificanceScale`; only tokens differ. |

### Shape 12/13
| Site | Verdict | Note |
|---|---|---|
| `RetrievalGate.swift` | SAFE | Pure state-derivation enum, no persisted index. |
| `EmbeddingIndex.sweep`/`vectorCache` | SAFE | Content-hash keyed (not timestamp/mtime) — an edit/re-polish correctly forces re-embedding; mixed-model-rev rows excluded from scoring rather than scored as garbage. |
| `KaraokeMap.swift` | SAFE | Pure stateless, no cache. |
| `NoteBodyView.Coordinator.wordRanges`/`alignedTimes` | SAFE | Rebuilt whenever `bodyText != loaded`, correctly guarded off mid-typing. |
| **`SpeakerTurnsView.editingIndex`/`draft` (lines 26-27)** | **CANDIDATE** | see B3 below |

### Shape 1
| Site | Verdict | Note |
|---|---|---|
| **`CaptureVoiceAnnotate.stopTapped` (lines 154-181)** | **CANDIDATE** | see B4 below |
| Everything else (`?? []`, `?? ""`, `try?`) across the 17 MemoDetail files | SAFE | Legitimately-nil display fields or documented fallbacks. |

### Shapes 2,3,4,5,6,8,9,10,11 — swept, no new candidates
Shape 4: `enhancements.first` (`MemoDetailView.swift:1725`) SAFE — `@Query` is sorted
`enhancedAt, order: .reverse`, so `.first` is genuinely newest. Shape 5: traced the
`sweeping`/`sweepProgress` transient-nil hypothesis in both index services — SAFE, both set
synchronously with no suspend point between them. Shape 11: `EmbeddingIndex` is an `actor`,
so concurrent `sweep()` calls serialize. Shape 9: N/A to this scope. Shapes 2, 3, 6, 8, 10: read/grepped
(`ReminderSheet`, `TagEditorSheet`, `MemoLinkPickerSheet`, `SpeakerAssignSheet`, `NoteAccessoryBar`,
`CaptureQuoteViews`, `PDFTextDisclosure`, `MarkupQuickLook`, `DestinationRowStyle+Phone`,
`ConversationMockView`) — nothing found, not claimed exhaustively clean.

### CANDIDATES — Retrieval/Connections/MemoDetail

**B1 — iPad Connections panel silently caps to 4 rows, killing "Show all N"**
`ConnectionsPanel.swift:556-560` (mobile): `.prefix(RetrievalTuning.relatedK)` (= 4) on the stored
`related` array. Desktop's `ConnectionsModel.refresh` (`ConnectionsPanel.swift:87-99`, desktop)
has no such prefix — stores every row above `relatedFloor` unbounded, caps only at *display* time
via `cappedRelated`/`relatedKMac` (= 7). The iPad panel's own view code (line 199) still carries
the "Show all N" logic verbatim and a doc comment claiming parity (line 183) — but `related` can
never exceed 4, so `related.count > 7` is never true; `RetrievalTuning.relatedK` looks copy-pasted
in from the separate, intentionally-small footer "Related" card (`MemoDetailView.swift:1454`).
- What the user does: opens the iPad Connections panel on a note with >4 semantically related notes.
- What they get: only the 4 closest ever appear; "Show all N" never renders; visibly fewer
  connections than the Mac shows for the same note.
- What they should get: the same unbounded fetch as desktop, capped only at display time.
- Fix location: `SkriftMobile/Features/MemoDetail/ConnectionsPanel.swift:560` — drop the `.prefix`.
- SPEC clause: none citing Connections row-count parity; recommend a BUGS.md row (C247 class —
  an empty/wrong cell in the desktop/mobile "how many related rows" comparison).

**B2 — a failed sweep is invisible on iPad/iPhone; desktop already fixed this**
`SkriftMobile/Services/Embeddings/JournalIndexService.swift:63-66` — catch block only
`DevLog.log(...)`, no observable state set. Desktop's `ConnectionsIndexService.swift:122-124`
does the log equivalent **plus** sets `lastError`, which the desktop `ConnectionsPanel.swift`
reads in two places (`gate` line 525-531, `noConnections` line 608-616) to swap "No connections
yet" for "Connections unavailable" + the error text. Mobile `ConnectionsPanel.swift`'s
`gate`/`emptyState` reference no error state at all (confirmed by full read).
- What the user does: nothing wrong — any transient embedding-engine/disk error during a
  background sweep, iPad or iPhone.
- What they get: "No connections yet" (or a perpetual "Finding connections…") forever,
  indistinguishable from an honestly-empty note, zero diagnostic trail in the UI.
- What they should get: the same `lastError` surfacing the Mac panel already has.
- Fix location: `JournalIndexService.swift:63-66` (add an observable error property); consumed at
  `SkriftMobile/Features/MemoDetail/ConnectionsPanel.swift`'s `gate`/`emptyState` (lines 443-471, 479-483).
- SPEC clause: the no-bad-info rule (memory `feedback_no_bad_information`); recommend a BUGS.md
  row citing C247.

**B3 — `SpeakerTurnsView`'s in-progress text edit isn't invalidated when turns reshape**
`SpeakerTurnsView.swift:26-27` — `editingIndex: Int?` / `draft: String` are raw positional state
into `turns`, which is recomputed fresh every render from `SpeakerTranscript.parse(memo.transcript)`
(`MemoDetailView.swift:1537`) — not cached, so any transcript mutation reshapes it immediately.
Two in-scope paths mutate `memo.transcript` in ways that shrink/reorder `turns` while
`SpeakerTurnsView` keeps the same view identity (no `.id(turns)` anywhere): `assign()`
(`MemoDetailView.swift:1648-1667`, re-fuses adjacent same-speaker turns) and `mergeTurn(at:into:)`
(line 1613-1619). Neither resets `editingIndex`/`draft` on reshape — unlike `NoteBodyView`, which
explicitly guards its own load-rebuild with `draftDirty`/`isFirstResponder` for exactly this race
(P0 2026-07-10, cited in that file's own comments).
- What the user does: starts editing one turn's wording (unsaved, focused), then — without
  dismissing — taps a different turn's name to rename/merge via `SpeakerAssignSheet`.
- What they get: if the new `turns.count` ≤ old `editingIndex`, the row silently stops rendering
  and the unsaved draft is lost; if the count still covers that index but the turn shifted, the
  STALE draft renders over a DIFFERENT turn, and committing (`commit()`, line 178-182) writes the
  wrong turn's stale text into the transcript.
- What they should get: the pending edit commits before the reshape or is explicitly dropped with
  the index cleared — never silently misapplied.
- Fix location: `SpeakerTurnsView.swift:26-27` (state) + `MemoDetailView.swift:1648-1667`/`1613-1619`
  (the mutating paths) — add an `onChange`-style reset/commit-before-reshape.
- SPEC clause: none for turn-edit/reshape ordering — matches the task's shape-13 description
  verbatim. Recommend a BUGS.md row.

**B4 — a silent (empty) voice-note annotation reports success anyway**
`CaptureVoiceAnnotate.swift:154-181` (`stopTapped`) — `addedThisSession = true` and
`Haptics.success()` fire unconditionally at the end of the `Task`, regardless of whether `text`
ended up empty (silent clip, or transcribe throws, swallowed by `try?`, with an empty live
caption too). Nothing is written to `memo.annotationText`, the audio file is deleted, and the UI
still signals success.
- What the user does: records a voice annotation that comes out silent, or hits a transcription
  engine failure.
- What they get: a success haptic + "Add another," no error, note unchanged — the take is gone
  with no indication it didn't land.
- What they should get: success signaled only when `text` was non-empty and actually saved;
  otherwise a "didn't catch that" state.
- Fix location: `CaptureVoiceAnnotate.swift:170-179` — gate on `!text.isEmpty`.
- SPEC clause: none specific to this capture path; same family as C75/C76 (no silent husks).
  Recommend a BUGS.md row.

---

## Cluster D — Lifecycle sweeps + launch sweeps + the three follow-ups (done directly)

Read in full: `Shared/Pipeline/MemoLifecycle.swift`, `SkriftMobile/Services/FadingSweep.swift`,
`SkriftDesktop/Features/Shell/LifecycleSweepScheduler.swift` (+ its `MacFadingSweep`),
`SkriftDesktop/Pipeline/WayOutRules.swift`, `SkriftMobile/App/SkriftApp.swift`,
`SkriftMobile/Services/NotesRepository.swift` (trash/purge section), `AssetMaterializer.swift`,
`MemoDeduper.swift`, `PhotoTextIndexer.swift`, plus the diarization sync chain
(`DiarizationStore.swift`, `DiarizationSidecar.swift`, `MemoCloudIngest.swift`,
`MemoCloudReconciler.swift`, `MemoSaver.swift`'s diarize/transcribe paths).

### Follow-up 1 — fading-conveyor rated/unrated coverage → SAFE (verified)
Traced both conveyors end to end. Desktop `JournalView.refresh` (line 92-93) computes
`trashedMemos = rows.filter { $0.deletedAt != nil }` over ALL rows (rated or not) and passes it
as `WayOutColumn(deleted:)` (`JournalView.swift:284`); `fading:` is `MemoLifecycle.partition(rows).fading`,
which by construction (`neverFades` returns `true` for `NoteConsent.isRated`) can only ever contain
unrated memos. Mobile `WayOutView.swift:18` mirrors this exactly: `@Query filter: deletedAt != nil`
is unfiltered by rated status. So: a rated memo never auto-fades (by design — "rating it keeps it
forever"), but if a user manually trashes one, it shows in "Recently Deleted" on both apps with no
gap. No candidate — this is complete coverage, correctly matching the doctrine
(`MemoLifecycle.swift`'s own header comment).

### Follow-up 2 — diarization sidecar-vs-store parity → CANDIDATE (two-layer bug, D1 below)

### Follow-up 3 — `transcriptMarkersInjected`'s single-writer point → SAFE, with a doc-accuracy note
Confirmed two writers: `MemoSaver.swift:822` (`runTranscription`, sets the flag from
`result.markersInjected`) and `MemoSaver.swift:930-965` (`diarizeIntoTurns`, which re-injects
`[[img_NNN]]` markers via `ImageMarkers.insert` at line 945 when speakers are split over a memo
with photos — but never touches `transcriptMarkersInjected`). This IS a second, silent writer path
in the sense the follow-up worried about. However: the flag's only real consumer in the whole repo
is `MemoDisplay.thumbnailPhotoFilename` (`MemoDisplay.swift:138`), and that function's FIRST branch
already parses `[[img_` markers directly out of the transcript text when present — the boolean flag
only matters for the markerless-transcript fallback case. Since `diarizeIntoTurns` only skips
setting the flag on a path that leaves real markers in the transcript, `thumbnailPhotoFilename`
still resolves correctly today; confirmed the deliberate "no markers on append" design
(`MemoSaver.swift:608-615`, `imageManifest: []` passed intentionally) doesn't hit this either.
So: no observable user-facing bug today. Separately: `Shared/Pipeline/ImageMarkers.swift:5`'s doc
comment claims "the Mac injects them for its own ingests (`transcriptMarkersInjected` tells the
Mac not to re-inject)" — a repo-wide grep for `transcriptMarkersInjected` found no desktop
production code that actually reads the flag to gate anything; the Mac's own `ASRPostProcess`-based
injection (via its own `TranscriptionService`) computes its own `markersInjected` fresh per-run and
never consults the phone's flag. Worth a doc correction, not a functional fix.

### Shape 11 — SkriftApp launch/foreground double-fire → SAFE (verified, deliberately idempotent)
`SkriftApp.swift` fires a `.task { MemoDeduper.run; AssetMaterializer.run; PhotoTextIndexer.run;
ReminderScheduler.run; MemoLifecycle.runOneClockMigrationOnce; FadingSweep.run }` block on view
appear (lines 114-133), and `.onChange(of: scenePhase)` fires nearly the same set again on
`.active` (lines 182-203) — a known SwiftUI cold-launch pattern where scenePhase can transition to
`.active` around the same time the root `.task` fires. All of these callee functions are
synchronous, `@MainActor`-isolated, with no internal `await` — so MainActor serializes them; there
is no true data race, only a possible back-to-back double-run. Every one of them is independently
documented and verified idempotent: `FadingSweep`/`MacFadingSweep` ("idempotent — a note another
device already swept is simply no longer live here"), `MemoDeduper` (re-run finds nothing left to
dedupe), `AssetMaterializer` (skips existing files/up-to-date assets — see D1 below for where that
skip logic itself has a gap), `MemoLifecycle.runOneClockMigrationOnce` (UserDefaults-flag-gated).
`PhotoTextIndexer` is the one function in this chain with real async work spanning an `await`
(Vision OCR), and it carries its own explicit `private static var running` reentrancy guard
(`PhotoTextIndexer.swift:19-22`) — direct evidence the codebase already knows to guard exactly this
shape when it matters, reinforcing that the others' lack of a guard is deliberate (nothing to
race) rather than an oversight. No candidate.

### NotesRepository trash/purge — SAFE
`purgeExpiredTrash` (`NotesRepository.swift:244`) runs from `SkriftApp.init` (before any `.task`
fires) and correctly depends on `MemoLifecycle.purgeDue`, which requires an already-valid
`trashSeenAt` stamp; unseen trash (not yet stamped by `FadingSweep.run`, which runs later in the
same launch) is naturally excluded this launch and picked up next time — correctly ordered per the
v3 "no note dies unseen" doctrine documented in the same file.

### CANDIDATE — D1: diarization sidecar/store parity has two independent gaps

**Layer 1 — `AssetMaterializer`'s staleness check is byte-count-only, so a same-length content
change never re-syncs.**
`SkriftMobile/Services/AssetMaterializer.swift:122-136` (`captureFile`, shared by audio/photo/
document/wordTimings/diarization assets):
```swift
if let asset = existing[filename] {
    guard asset.byteCount != size, let data = try? Data(contentsOf: fileURL(filename)) else { return false }
    ...
}
```
A diarization sidecar rewrite that happens to encode to the same byte length as what's already
synced (e.g. renaming a speaker slot from a 5-character name to a different 5-character name —
`"Tiuri"` → `"Sarah"`, `slotNames["0"]` unchanged length either side of the rename, `turnSlots`
already `nil` from a prior rename so the field-presence doesn't shift either) is silently never
re-uploaded — `captureFile` returns `false`, `AssetMaterializer.captureMissing` never marks the
row dirty, and no fresh `MemoAsset` blob reaches CloudKit. The codebase already uses content
hashing elsewhere for exactly this class of staleness check (`Shared/Retrieval/MemoGist.swift`,
`Shared/Export/VaultWrite.swift`, `VaultStamp.swift`) — byte-count here is a narrower, avoidable
substitute.

**Layer 2 — even when a fresh asset DOES arrive, the Mac only ever adopts diarization ONCE per row.**
`SkriftDesktop/Pipeline/Ingest/MemoCloudIngest.swift:210-228` (`adoptLateDiarization`, the ONLY
writer of `pf.diarizationSegments`/the Mac's own `diar_<id>.json` sidecar — confirmed via repo-wide
grep, no other call site exists):
```swift
static func adoptLateDiarization(memo: Memo, pf: PipelineFile, ...) -> Bool {
    guard memo.deletedAt == nil,
          pf.diarizationSegmentsJSON?.isEmpty ?? true,   // ← only when EMPTY
          ...
```
Its own doc comment calls this "the diarization twin of `adoptLateWordTimings` — same CloudKit
race, same once-only read at ingest." That's correct for the race it was built for (an asset that
arrives a beat late during initial sync), but the guard also means: once the Mac has adopted a
memo's diarization ONE time, it can NEVER adopt it again — a later phone-side re-diarize
("Split speakers" pressed again with a different target count, which rewrites both
`memo.transcript` and the sidecar wholesale, `MemoSaver.swift:930-965`) or a speaker rename
(`learnVoice`, `MemoDetailView.swift:1671-1688`, which updates the sidecar's `slotNames`) is
invisible to the Mac forever after the first heal, independent of whether Layer 1's byte-count
check would have caught the upload. `DiarizedSegment` (`Shared/Model/DiarizedSegment.swift`) carries
no name — only `speaker: Int, start, end` — so the display names the Mac's own
`diar_<id>.json` sidecar holds (used, per its file header, "to later ENROLL a speaker's voice from
the Mac review screen ... WITHOUT re-diarizing") can only ever reflect whatever the phone's
slotNames looked like at the moment of the Mac's FIRST successful ingest of that memo.
- What the user does: renames a misidentified speaker on the phone (or re-splits with a different
  speaker count) on a memo the Mac already ingested once.
- What they get: the Mac's own diarization sidecar — and any future Mac-side enroll-from-sidecar
  flow built against it — silently keeps the OLD segment/name data forever; no error, no retry,
  no indication the two devices have diverged.
- What they should get: per C45 ("Late assets... heal on the next sweep"), a genuinely changed
  diarization asset should re-adopt, not just an asset arriving for the first time.
- Fix location: `SkriftMobile/Services/AssetMaterializer.swift:122-136` (hash- or content-based
  staleness, not byte-count) and `SkriftDesktop/Pipeline/Ingest/MemoCloudIngest.swift:210-228`
  (the once-only guard needs a real "is this newer/different" check, not "is mine empty").
- SPEC clause: C45 ("Late assets... heal on the next sweep; a heal never overwrites Mac-made data").
  No existing R-line covers this (checked R1-R43); recommend a new required difference alongside
  R34/R35 (the diarization/timings asset-carrying family).

---

## Cluster C — Desktop Review + Recording

Full reads: `NoteMeasure.swift`, `RecordingCore.swift`, `UnratedNotePane.swift`,
`RecordingActivityManager.swift`, `LiveCaptionEngine.swift`, `NoteBody.swift`, `AudioController.swift`,
`ReviewHelpers.swift`, `PhotoCaptureService.swift`, `RecordingIntentBridge.swift`,
`SignificanceCircles.swift`, `NoteToolbar.swift`, `TagSuggestPanel.swift`, `CaptureViews.swift`.
Deep targeted reads (start/stop/route/interrupt/save paths): `LiveRecordingService.swift`
(~600/1502 lines), `NoteDisplayView.swift` (~250/626), `NoteProperties.swift`, `NoteActions.swift`,
desktop `TranscriptionService.swift`, `LiveRecordingSession.swift`. `BodyTextView.swift` (1566
lines) and `ConnectionsPanel.swift` (desktop) were grep+spot-checked only (shape 7 there is
Cluster B's job).

### Shape 11 — recording start reentrancy → SAFE, unusually hardened
Read `prestart`/`startFast`/`startRetrying`/`start()` (lines 280-465) + all five recovery-notification
handlers (route/interruption/engine-config/media-services/foreground, lines 862-1165) in full.
`startInFlight`, `prestartAbandoned`, `Self.isRecordingActive` guards sit at every entry point, each
citing the specific device trace (b115/b117/b119) that produced it; all notification observers
register `queue: .main` + `MainActor.assumeIsolated`, serializing handlers. "The one file in scope
that reads like it already went through this exact audit once." No candidate.

### Shape 12 — cache keyed by something that changes → SAFE by construction
`NoteMeasure.column(width:panelWidth:)` is a pure function, no cache/stored keyed state at all.

### Other shapes swept, no new candidates
Shape 1: SwiftData `(try? ctx.fetch(...)) ?? []` sites SAFE (schema-throw class, per first sweep);
`AudioController.swift:40`'s `try? AVAudioPlayer` SAFE (documented tolerant-of-missing-file design);
`LiveRecordingService.swift`'s three session `try?` sites SAFE (each routes to the existing
route-rebuild recovery ladder) — **except the live-caption finalize candidate below.**
Shape 2: the pane/sweep gap folds into the shape-13 candidate below. Shape 3: no echo guards in
scope. Shape 4: 16 `.first` hits, all SAFE (single-route/fetchLimit-1/single-file-by-construction).
Shape 5: overlaps the shape-1 candidate (a merely-not-ready ASR read is indistinguishable from "no
more words spoken"); route/interruption handling correctly keeps "waiting" visually distinct from
"stopped." Shape 6: `NoteBody`'s inline-`#tag` write vs `NoteProperties`'s CloudKit mirror — both
views mounted unconditionally together, mirror always has a live subscriber, SAFE. Shape 7:
`NoteActions.hasParts` requires ALL THREE enhancement parts non-empty (with a comment explaining
why "any part" would be wrong) — the CORRECT version of the first sweep's `hasContent`
OR-based `voice:` ladder bug; corroborates that finding, not new. Shape 8: `BodyTextView.swift:1020`
`modelString`'s `tv.textStorage` fallback structurally matches the shape but `NSTextView.textStorage`
is force-created by AppKit with no found teardown path — SAFE (defensive-only). Shape 9:
`LiveRecordingService`'s `tapInputUID` correctly reset at teardown, re-set at every install — SAFE.
Shape 10: `RecordingActivityManager`'s `startedAt`/`pausedAt`/`status` — every writer is the only
mutation site, every call site reachable — SAFE.

### Not reached
`BodyTextView.swift`'s naming/suggestion-picker internals (~1400-1566) not read line-by-line —
sampled only. `ConnectionsPanel.swift` (desktop) checked only for shapes 1/3/4. `PhotoCaptureService`'s
`pendingOffsets`/delegate-callback ordering noticed as a possible shape-4/10 risk (two captures'
`didFinishProcessingPhoto` callbacks arriving out of order) but not verified — would need a device
trace; flagged as a follow-up, not a candidate.

### CANDIDATES — Desktop Review/Recording

**C1 — a failed final transcribe silently drops the last words of an edited live recording**
`Shared/Recording/LiveCaptionEngine.swift:277-288` (`finishParts`):
```swift
if let transcribe, !streamBuffers.isEmpty, let merged = Self.concatenate(buffers: streamBuffers) {
    finalSegment = ((try? await transcribe(merged)) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
```
`transcribe` throws `ASRError.notInitialized` whenever the model has idle-unloaded mid-stream — the
code's own comment: "a throw here reads to the engine exactly like a nil transcriber." `try?` turns
that into `""`. This matters because of the caller: `SkriftDesktop/Features/Shell/LiveRecordingSession.swift:137-164`.
When the user edited the settled caption mid-take (`draft.everEdited`), stop deliberately SKIPS the
normal full-file re-ASR (the whole point of the fast-stop design) — it takes `finalTail` straight
from `finishParts()`, writes `pf.transcript`, sets `.done`, and explicitly no-ops the batch-runner's
re-ASR hook (line 146: "BatchRunner must never re-ASR an edited take"). `LiveRecordingFinalize.transcript`
with an empty `finalTail` just returns the settled text (proven by `LiveRecordingDraftTests.swift:155`).
So a transient ASR idle-unload at the exact moment Stop is pressed on an edited take — documented as
a real, expected ~1s-window occurrence, not hypothetical — permanently and silently drops up to the
20s rotation interval's worth of unrotated speech, with NO fallback available (re-ASR is forbidden
on this path by design) and a log line that fires BEFORE the transcribe attempt and unconditionally
reads as success (`LiveCaptionEngine.swift:307-313`). The same swallow recurs at line 319
(`rotateIfNeeded`), feeding `draft.settledText` — equally unrecoverable here.
- What the user does: edits the live caption mid-take on the Mac (a supported, encouraged flow),
  hits Stop right as the model happens to idle-unload.
- What they get: a note permanently missing its last sentence or two, marked `.done`, no indication
  anything went wrong.
- What they should get: finalize retries/reloads the model before giving up, or logs the failure
  and flags the note for a corrective re-ASR pass instead of `.done`.
- Fix location: `Shared/Recording/LiveCaptionEngine.swift:281` (+ line 319); caller
  `SkriftDesktop/Features/Shell/LiveRecordingSession.swift:141-143`.
- SPEC clause: C101 ("Live caption seeds the note; the stop-pass file transcription is the truth")
  is nearest, but the edited-take path explicitly forgoes that stop-pass, leaving `finishParts`
  as the only safety net with no clause covering its failure. Recommend a new clause/BUGS.md row.

**C2 — the automatic 60-day fading sweep can trash the exact unrated note open on screen, and the pane never notices**
`SkriftDesktop/Features/Shell/LifecycleSweepScheduler.swift` runs `MacFadingSweep.run()` on every
`didBecomeActive`, deliberately using a FRESH `ModelContext` because (its own comment, lines 79-84)
"a CloudKit import writes the persistent STORE but doesn't refresh an already-registered context's
cached rows." An unrated memo past 60 days untouched gets `deletedAt = now` written via that separate
context. An unrated memo has no `PipelineFile`, so it's shown via `UnratedNotePane`
(`RootView.swift:100-106`), which fetches its own `Memo` copy ONCE on `.task(id: memoID) { load() }`
(`UnratedNotePane.swift:67,81-105`) and never checks `deletedAt`, before or after load — no `@Query`,
no notification, nothing that reloads it when the sweep writes via the other context. Repo-wide grep
for `NSManagedObjectContextDidSave|autosaveEnabled|mergePolicy` found zero hits — confirming contexts
don't auto-merge here. Concretely: user opens an old untouched unrated memo (already fading), leaves
it open, switches apps and back (any `didBecomeActive`). The sweep fires and trashes it on its own
context; the pane's cached object never refreshes, keeps rendering as a normal editable note. The
sidebar's `@Query` (which DOES filter `deletedAt == nil`) has already dropped it — a visible split
brain: gone everywhere else, still live and editable in the one place being looked at. Further edits
via `UnratedNotePane.commit()` (`try? mainContext.save()`) risk silently losing to the sweep's
conflicting write (shape 1, compounding). Also a shape-2 angle: `RootView`'s switch treats "no
`PipelineFile`" as meaning only "this is unrated" when it can also mean "just got trashed" — the two
lists were never checked against each other.
- What the user does: nothing wrong — has an old unrated note open, briefly loses/regains app focus.
- What they get: the note moves to Recently Deleted everywhere except the pane they're looking at,
  which behaves as if nothing happened; further edits risk being lost or landing on a note the rest
  of the app considers gone.
- What they should get: the pane re-checks `deletedAt` on `didBecomeActive`/sweep-completion (or
  uses a live `@Query`) and either bounces to its existing "may have been removed" state
  (line 71-79) or flags the note as pending trash.
- Fix location: `SkriftDesktop/Features/Review/UnratedNotePane.swift:81-113`; root-cause interaction
  at `SkriftDesktop/Features/Shell/LifecycleSweepScheduler.swift:85-92` and `RootView.swift:94-106`.
- SPEC clause: C89 governs the sweep's timing, not what happens to an already-open view on the swept
  note; C90 ("trash is soft everywhere... a trashed note shouldn't render as a normal one") is
  violated. No clause covers the currently-open-view case — recommend a new clause/BUGS.md row.

---

## Consolidated candidates, ranked by user impact

1. **C1 — a failed live-caption finalize silently drops the last sentence(s) of an edited Mac
   recording, permanently, with no fallback.** Marked `.done`; the log even reads as success.
   `Shared/Recording/LiveCaptionEngine.swift:281,319`. No clause covers `finishParts` failure.
2. **C2 — the automatic fading sweep can trash the exact unrated note open in the review pane;
   the pane keeps rendering it as live and lets you keep editing a note the rest of the app has
   already recently-deleted.** `SkriftDesktop/Features/Review/UnratedNotePane.swift:81-113` +
   `LifecycleSweepScheduler.swift`. Violates C90.
3. **D1 — diarization sidecar/store parity is broken two ways**: `AssetMaterializer`'s byte-count
   staleness check misses same-length content changes, AND the Mac's `adoptLateDiarization` only
   ever adopts once per memo, so a later phone-side rename or re-split never reaches the Mac at
   all, independent of the first bug. `AssetMaterializer.swift:122-136`,
   `MemoCloudIngest.swift:210-228`. Violates C45; no existing R-line covers it.
4. **B2 — a failed Connections-index sweep is invisible on iPhone/iPad**: desktop already fixed
   this exact shape (`lastError` + UI copy swap); mobile only DevLogs, so "No connections yet"
   is indistinguishable from "the sweep is broken." `JournalIndexService.swift:63-66`.
5. **B3 — `SpeakerTurnsView`'s in-progress edit can silently drop or, worse, commit onto the
   wrong turn** when a rename/merge reshapes the turn list underneath an open inline edit.
   `SpeakerTurnsView.swift:26-27` + `MemoDetailView.swift:1648-1667`.
6. **A1 — `receiveTranscripts` is the one of three near-identical audiobook sync functions that
   skips the landed-file check its siblings added after a real device incident** — a partial
   download latches as fully applied and never retries. `AudiobookCloudSync.swift:472-486`.
7. **A2 — a corrupt local `bookmarks.json` silently wipes a book's real bookmarks** on the very
   next add/remove (no schema versioning, unlike the sibling transcript/alignment sidecars).
   `Bookmark.swift:46-50`.
8. **B1 — the iPad Connections panel is hard-capped to 4 rows**, a stale copy-paste from an
   unrelated smaller UI element; "Show all N" is dead code and the panel visibly under-shows
   connections the Mac shows for the same note. `ConnectionsPanel.swift:560` (mobile).

Also found, lower blast radius: **A3** (`SyncedAudiobooksView`'s "Remove download" missing a
session-end guard its sibling call site has), **B4** (`CaptureVoiceAnnotate` signals success on a
silent/failed voice-annotation take, losing it with no indication).

**Verified SAFE, not just unreached** (worth recording so a future sweep doesn't re-spend budget
here): fading-conveyor rated/unrated coverage is complete on both apps (no gap);
`transcriptMarkersInjected` has a real second silent writer but its sole consumer already tolerates
it, so no live bug today (doc-comment inaccuracy only); the `SkriftApp` launch-task /
`scenePhase.active` double-fire on cold launch is real but every callee is independently verified
idempotent, and `PhotoTextIndexer`'s explicit reentrancy guard shows the codebase already knows to
protect this shape when protection is actually needed; `NotesRepository.purgeExpiredTrash`'s launch
ordering relative to `FadingSweep` is correct; the recording-start state machine
(`LiveRecordingService.swift`) is unusually hardened against reentrancy, citing specific prior
device incidents at every guard.

## Not reached (honest gaps across all four clusters, follow-up-worthy)
Audiobooks shapes 2/3/5/6/9 (partial). Retrieval/Connections/MemoDetail shapes 2/3/6/8/10 in the
smaller sheets (`ReminderSheet`, `TagEditorSheet`, `MemoLinkPickerSheet`, `SpeakerAssignSheet`,
`NoteAccessoryBar`, `CaptureQuoteViews`, `PDFTextDisclosure`, `MarkupQuickLook`,
`DestinationRowStyle+Phone`, `ConversationMockView` — all read, nothing found, not exhaustive).
Desktop Review: `BodyTextView.swift`'s naming/suggestion-picker internals (~1400-1566) sampled only;
`ConnectionsPanel.swift` (desktop) checked only for shapes 1/3/4; `PhotoCaptureService`'s
`pendingOffsets`/callback-ordering flagged as a possible shape-4/10 risk needing a device trace, not
verified either way.
