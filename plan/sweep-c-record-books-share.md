# Sweep C — phone recording, audiobooks, share extension

Scope: `Features/Recording/`, `Services/Recording/`, `Services/Audiobooks/`, `SkriftShare/`,
`Services/Capture/CaptureInboxDrainer.swift`, `Features/Audiobooks/ReadAlongView.swift`.
Method: static read only, no build/run. Read `plan/perf-sweep.md` first — none of its R90–R94 items
live in this area (they're Mac editor / list / AppPaths / SkriftApp); this sweep doesn't repeat them.

## Findings, ranked

### 1. `AudiobookCloudSync.localAlignmentSignature` full-decodes every alignment sidecar on the main actor, on every reconcile — including every bookmark tap
`Skrift_Native/SkriftMobile/Services/Audiobooks/AudiobookCloudSync.swift:611-620` (`localAlignmentSignature`)
calls `BookAlignmentStore.fileAlignment` (`Skrift_Native/SkriftMobile/Services/Audiobooks/BookAlignment.swift:219-225`)
for every audio file of a synced book — `Data(contentsOf:)` + `JSONDecoder().decode(FileAlignment.self,...)`
of the WHOLE sentence list (per-word karaoke times for every book sentence; the Odyssey case elsewhere in
this file is 7506 sentences). `AudiobookCloudSync` is `@MainActor` (line 19), so this decode runs
synchronously on the main thread, once per file, every time `sendAlignments` (line 641) runs inside
`reconcileOnce` (loop at :250-283).//
**What happens and when:** `reconcile()` runs on launch and foreground (`SkriftApp.swift:152,210`), on every
debounced CloudKit-import sweep (`CloudSyncMonitor.swift:158`), AND on every single bookmark add/remove while
reading/listening — `AudiobookPlayerView.swift:482` and `ChaptersBookmarksSheet.swift:97` call
`AudiobookCloudSync.bookmarksChanged`, whose doc comment claims "the full reconcile is serialized + cheap
when nothing else changed" (`AudiobookCloudSync.swift:311-313`) — that claim is false for a synced book with
a large aligned text.
**Cost:** main-thread stutter proportional to the book's total alignment JSON size, on the same interaction
(bookmark tap) the user does most often while actually using the reader.
**The tell:** the sibling function `localTranscriptSignature` (`AudiobookCloudSync.swift:421-432`) was
already fixed for exactly this bug — its comment says outright "frontierStats = the two scalars this
signature needs, cache-served — this used to full-decode every sidecar per reconcile, on main." The
alignment twin, written to mirror it (line 610's own comment: "mirrors `localTranscriptSignature`'s shape
exactly"), never got the same treatment.
**Fix:** give `BookAlignmentStore` a `frontierStats`-shaped cheap read (fileIndex, verdict, sentence count,
source count — everything `cloudSignaturePart()` needs) that reads a small cached stamp instead of decoding
`sentences`/`words`, the same way `BookTranscriptStore.frontierStats` does.
**Confidence:** high.

### 2. `BookAlignmentRunner.mergeSentences` is O(n²) in sentence count
`Skrift_Native/SkriftMobile/Services/Audiobooks/BookAlignment.swift:723-747`. For every incoming sentence,
`result.indices.filter { ... }` (line 732) linearly scans the WHOLE accumulated `result` array for a
different-text time overlap. Called once per `(file, text)` pair from `mergeAndFinish`, growing `result` as
each text's sentences are folded in.
**What happens and when:** every book attach/re-attach and every schema-heal re-align (the schema bumps at
:104-124 mean every already-attached book re-aligns once per code update). `BookTextActivity`
(`BookAlignment.swift:251-280`) exists specifically because a re-align "had NO surface at all" and looked
"frozen" (line 254's own comment cites a 12-minute re-align on a 13-hour book) — that's this function's
neighborhood.
**Cost:** quadratic in a file's sentence count; runs off-main (`Task.detached`) so it doesn't freeze the UI
directly, but it's a real chunk of the wall-clock the progress UI has to paper over.
**Fix:** since collisions only matter between *different* texts and sentences are naturally time-ordered,
keep `result` sorted by `start` and binary-search/two-pointer the overlap check instead of a full scan.
**Confidence:** medium (the O(n²) shape is certain from the code; how much of the observed 12-minute re-align
it accounts for vs. the aligner itself is not measured here).

### 3. `AudiobookSession` is a `@Published`/`ObservableObject` singleton the phone already knows how to avoid
`Skrift_Native/SkriftMobile/Services/Audiobooks/AudiobookSession.swift:17-30` — `isActive`, `book`,
`isPlaying`, `currentTime`, `rate`, `sleepUntil`, `sleepAtChapterEnd` are all `@Published` on one
`ObservableObject`. `installTimeObserver` (line 392) ticks `currentTime` every 0.5 s
(`AVPlayer.addPeriodicTimeObserver`, line 392), and every `@Published` write fires `objectWillChange` for
every subscriber regardless of which property it reads — the player screen re-renders whole on every tick,
every play/pause, every rate/sleep change.
**Contrast:** `LiveRecordingService.swift:17-24` was deliberately rewritten to per-property `@Observable`
specifically to kill this cost ("the previous whole-screen re-render at ~30/s was a real cost on a warm
A15"), but the audiobook player's own always-on class was never migrated to the same pattern.
**Cost:** lower frequency (2 Hz, not 30 Hz) than the bug LiveRecordingService already fixed, but the same
mechanism, on a screen (the book player) that's live for hours at a time.
**Fix:** migrate `AudiobookSession` to `@Observable` with per-property tracking, same as
`LiveRecordingService`.
**Confidence:** medium (SwiftUI's actual diffing softens `ObservableObject` blanket-invalidation somewhat;
the mechanism is real, the magnitude is unmeasured here).

### 4. `SharePayloadLoader` loads multi-select photos/audio one attachment at a time, fully sequential
`Skrift_Native/SkriftMobile/SkriftShare/SharePayloadLoader.swift:227-264` (`loadAudio`) and `:345-370`
(`loadImages`) each `for provider in providers { ... await ... }` — every `loadFileRepresentation`/
`loadDataRepresentation` + downsample is awaited to completion before the next attachment starts. Multi-select
sharing is explicitly supported (comment at :86-88: "activation allows 10").
**What happens and when:** a 10-photo or multi-clip share sheet action.
**Cost:** total load time is the SUM of 10 sequential decode+downsample round trips instead of running
concurrently, inside the share extension's tight ~120 MB / short-lifetime budget the same file is otherwise
careful about (see the `downsampledJPEG` comment at :340-344).
**Fix:** run the per-provider loads in a `TaskGroup` (bounded concurrency, e.g. 3-4 at once, to respect the
memory ceiling) instead of a serial `for await` loop.
**Confidence:** medium (extension memory ceiling makes full parallelism risky, so the fix needs a bound, not
just a naive `TaskGroup`).

### 5. `LiveRecordingService`'s tap callback spawns two `Task { @MainActor }` closures per audio buffer
`Skrift_Native/SkriftMobile/Services/Recording/LiveRecordingService.swift:1020-1030` — every ~85 ms buffer
(4096 frames @ 48 kHz, ~12/s) spawns one `Task { @MainActor … self.level = lvl; pushWaveform(lvl) }` (line
1021) and, when live captioning is on, a second `Task { await TranscriptionService.shared.feedStream(out) }`
(line 1030).
**Cost:** ~24 Task allocations/sec for the life of every recording. Low absolute cost at this rate (this file
is otherwise carefully tuned — 4 Hz display timer not 20 Hz, self-pacing caption polling, per-property
`@Observable`), but it's the one per-buffer allocation left in an otherwise buffer-conscious tap.
**Fix:** batch the level push and the stream feed onto the existing display-timer cadence instead of a Task
per tap callback, or coalesce consecutive buffers before hopping actors.
**Confidence:** low (this is a minor, already-mitigated-by-design cost, listed for completeness — not where
the user-visible slowness is).

### 6. `MemoSaver.recoverStuckTranscriptions` scans `repository.allMemos()` twice
`Skrift_Native/SkriftMobile/Features/Recording/MemoSaver.swift:882` and `:888` — one `for memo in
repository.allMemos() where ...` to release user-edited stuck memos, then a second full `repository.allMemos()
.filter { ... }` for the real recovery set.
**Cost:** launch-time only, O(2N) instead of O(N) over the memo corpus — negligible in absolute terms next to
finding #1, listed as a cleanup, not a real hotspot.
**Fix:** one pass building both lists.
**Confidence:** high (trivially readable from the code), impact: low.

## Not flagged as bugs here (audio-session/route territory — orchestrator only)

`LiveRecordingService.swift`'s route-change/interruption/rebuild machinery (lines ~1037-1478) is extensive
and touches category/BT/mic-selection policy directly — per the brief, any problem there is
**"hardware — orchestrator only."** Read in full; found no NEW static issue beyond what's already documented
in the file's own extensive comments (every rebuild path is off the render thread, backoff-bounded, and
self-re-arming). Not re-litigating it here.

## Elegance / structure, not measured as hot

- No `FetchDescriptor` or `NSRegularExpression` misuse found anywhere in this area's files (grepped clean) —
  those P4/P6-shaped bugs from `perf-sweep.md` don't recur here.
- `MemoSaver.swift` (998 lines) and `BookAlignment.swift` (1355 lines) are large but not tangled — each
  reads as one coherent responsibility (persistence+transcription orchestration; alignment store+runner)
  with clear `// MARK:` seams already in place. Splitting either would be organizational, not a bug fix.
