# Scenario probes — 40 adverse-conditions traces against SPEC.md (2026-09-22)

Companion to `plan/extraction/scenarios.md` (50 real-life traces, already run — not repeated
here). This pass hunts by CONDITION CLASS instead of user story: TIME, SCALE,
STORAGE/NETWORK, PERMISSIONS, TEXT, CONCURRENCY. Read from the worktree at the code-audit
branch. Paths: `M/` = `Skrift_Native/SkriftMobile`, `D/` = `Skrift_Native/SkriftDesktop`,
`S/` = `Skrift_Native/Shared`. Verdicts: COVERED Cn / PARTLY / UNCOVERED / CONTRADICTED.

---

## The scenarios

### TIME

**T1. Two devices sync a note while their clocks are skewed a few minutes apart (no NTP, or a stale Mac clock).**
- v1: the Mac write-back LWW guard is `existing.enhancedAt > now` where `now` is THIS device's
  clock, not the timestamp's own device (`D/Pipeline/Ingest/MacCloudWriteBack.swift:102`,
  comment "Part B" acknowledges only same-device races). A fast-clocked device's enhancement
  stamp can sit in a slow-clocked device's future forever, so the slow device refuses every
  write-back from the fast one — sync wedges one-way until the clocks agree.
- Owner: two devices with slightly different clocks still converge.
- Verdict: UNCOVERED (R28 flags a related skew gap in `names.json` ties only; this is the
  memo-enhancement write-back guard, untouched by that fix).
- Clause: C252 (below). Fixture: two in-memory contexts, one clock offset +6 min; golden: the
  skewed device's write-back still lands once its own stamp is newer than the row it's replacing.

**T2. DST changes mid-recording (clocks fall back an hour at 03:00 during a 90-minute take).**
- v1: `elapsed = accumulated + Date().timeIntervalSince(segmentStart)`
  (`M/Services/Recording/LiveRecordingService.swift:1433-1434`) — `Date` arithmetic is UTC-
  instant based, immune to the local wall-clock repeating an hour.
- Owner: the recording's duration and photo offsets are unaffected by the clock change.
- Verdict: COVERED (no clause needed — verified, not assumed; the DST risk is real for anything
  using `Calendar.current` on wall time, this code path doesn't).

**T3. Two archive-bound bare-picture captures land in the SAME repeated local hour during a DST fall-back, each with no title.**
- v1: both get `timestampStem(for:)` = `yyyy-MM-dd-HHmmss` in `.current` timezone
  (`S/Export/ExportProfile.swift:102-108`); if the two absolute instants render to the same
  local string, `VaultWrite.assess` tries the plain stem then falls to
  `VaultName.disambiguated` (`S/Export/VaultWrite.swift:256-260`) — a UUID-suffixed second
  filename, not an overwrite.
- Owner: neither capture's file clobbers the other.
- Verdict: COVERED C54 (collision → disambiguate, generic, not date-aware but sufficient).

**T4. A phone's clock is wrong by a year (`recordedAt` lands far in the future) — a stuck watch, a corrupted NTP sync, airplane mode with a manually-set clock.**
- v1: `MemoLifecycle.clockStart` = `max(recordedAt, keptAt ?? .distantPast)`
  (`S/Pipeline/MemoLifecycle.swift:31-33`); `age(of:at:)` = `now.timeIntervalSince(clockStart)`
  with no clamp (`:192-194`). A future `recordedAt` makes `age` permanently negative, so
  `isFading`/`sweepDue` never fire — the note never reaches Fading, never auto-trashes, and
  syncs that way to every device (it's a CloudKit field, not a local artifact).
- Owner: a bad clock is a note that ages oddly, not one that lives forever unrated.
- Verdict: UNCOVERED (C89 states the clock rule but assumes `recordedAt` is trustworthy).
- Clause: C253 (below). Fixture: corpus `voice-en-recordedat-future` (`recordedAt` = +400 days);
  golden: `age` clamps to 0, note ages normally from `now` once noticed.

**T5. A duplicate pair (same memo id, two rows) has one row's `lastEditedAt` bumped into the future by a skewed clock.**
- v1: `MemoDuplicates.keeper` ties break on content score first, then
  `am.lastEditedAt > bm.lastEditedAt` (`S/Pipeline/MemoDuplicates.swift:38`) — a bogus-future
  edit stamp wins the tie over a genuinely more recent, correctly-clocked edit on the other row.
- Owner: the keeper is the one he actually touched last, not the one with the broken clock.
- Verdict: UNCOVERED (C48 says "alive > most content > latest edit" and inherits this risk
  verbatim; no skew guard anywhere in the keeper rule).
- Clause: C254 (below). Fixture: two rows, id equal, content-score tied, one `lastEditedAt`
  6 months in the future; golden: TBD once D-skew is decided (flag for Tuur, not a silent default).

**T6. A note recorded at 23:58 local is exported for the first time by the Mac, which is in a different timezone than where it was recorded (he travelled with the phone still on Lisbon time, Mac stayed on Lisbon time too, but the SAME bug applies to a future multi-timezone household).**
- v1: the phone's own export uses `dateFormatter` with no explicit `timeZone` → the EXPORTING
  device's current zone (`M/Services/Export/MemoExporter.swift:165-172`); the Mac derives
  `date:` from the phone-sent ISO string sliced `prefix(10)` (`S/Export/Compiler.swift:37-38`,
  `D/Pipeline/Export/CompilerBridge.swift:69`) — a UTC-anchored slice if the phone encodes
  ISO8601 in UTC. A note recorded 23:58 in a positive-offset zone can slice to the NEXT day on
  the Mac while the phone would show the SAME day.
- Owner: `date:` in the frontmatter reads the same wherever it's exported from.
- Verdict: CONTRADICTED — this is exactly SPEC's own C64/D13 ("needs-verdict"), traced fresh
  here from the code rather than asserted; confirms the required-difference R15 is real and
  still open. No new clause — flagging that D13 blocks this, not a documentation gap.

**T7. A single continuous recording runs 3 hours (a long walk, a lecture) with live caption off.**
- v1: no `maxRecordingDuration`/duration-cap constant anywhere under
  `M/Services/Recording/`, `M/Features/Recording/` (grepped, none found); the stop-pass
  transcription is one-shot per C222 (`TranscriptionService.swift` has no chunk path for an
  ordinary memo — only the audiobook lane chunks at 180 s, `S/…` book pipeline). A 3-hour
  file goes to the ANE whole.
- Owner: a very long note transcribes without stalling the phone or silently truncating.
- Verdict: UNCOVERED (C100/C101 describe the ASR tail order, not a length bound; C106's
  180 s-chunk resumability is scoped to audiobooks only).
- Clause: C255 (below). Fixture: none yet (needs a real 3 h corpus audio file or a synthetic
  PCM generator); check = one-shot transcribe of a 3 h file completes without OOM on-device,
  memory logged.

### STORAGE/NETWORK

**N1. Disk fills up mid-recording.**
- v1: `installRecordingTap` writes every buffer with `try? file.write(from: out)`
  (`M/Services/Recording/LiveRecordingService.swift:808`) — any write error, `ENOSPC`
  included, is silently swallowed; no disk-space check exists in the file; `stop()` only
  catches a fully-empty file (`:543`), not a partial one that started fine and then failed.
- Owner: never loses audio, whatever the disk does mid-take.
- Verdict: CONTRADICTED — this is C99 itself, already `⚠ required difference (D4, issue #14)`
  in SPEC.md:432 ("never ever ever"); traced fresh here to confirm the code-level mechanism
  (silent `try?`) behind that open item, not a new finding.

**N2. iCloud storage is full for a week (memo sync, not audiobooks).**
- v1: `CloudSyncMonitor` only tracks `isSyncing` off CloudKit event start/end
  (`M/Services/CloudSyncMonitor.swift`), never inspects `event.error` — a `CKError.quotaExceeded`
  on the memo mirror is invisible; the ONLY quota-aware code is the separate raw-CloudKit
  audiobook transport (`M/Services/Audiobooks/AudiobookCloudSync.swift:55-58`); `Memo.syncStatus`
  is set `.waiting` at creation and never flipped to `.synced` anywhere outside demo-seed code
  — a confirmed-dead field.
- Owner: told his notes aren't syncing and why.
- Verdict: UNCOVERED C145 (SPEC already proposes C145 for "sync health visible" from the 50-
  scenario pass, needs-verdict D48; this confirms the mechanism is exactly as bad as assumed
  there — no new clause, strengthens the existing one with the dead-field citation).

**N3. iCloud is signed out, then back in with a DIFFERENT account.**
- v1: no occurrence anywhere in `Skrift_Native` of `CKAccountChanged`, `accountStatus`,
  `NSUbiquitousIdentity` or `ubiquityIdentityToken` (repo-wide grep, zero hits); neither app
  observes the account-change notification or checks `CKContainer.accountStatus`.
  `NSPersistentCloudKitContainer` silently re-points at the new account's private zone.
- Owner: told his data now belongs to a different iCloud account, not a blank app.
- Verdict: UNCOVERED — no clause anywhere addresses an account switch.
- Clause: C260 (below). Fixture: none (device/account test); check = an account-change
  notification surfaces a blocking notice before any write happens against the new zone.

**N4. CloudKit auth token expires mid-sweep (memo pipeline, not audiobooks).**
- v1: `notAuthenticated` is handled only in the audiobook path
  (`M/Services/Audiobooks/AudiobookCloudSync.swift:59-61`); `MemoCloudReconciler.swift:167-171`
  catches generically (`outcome.ingestFailures += 1; Logger.error(...)`) with no `CKError`
  discrimination — indistinguishable from a transient network blip.
- Owner: a real auth problem tells him to re-sign-in, not just "sync stalled".
- Verdict: PARTLY C168/R40 — R40 already pre-registers "a failed sweep is logged and shown"
  as required, and C168 states "no swallowed error"; this confirms the swallow is real but the
  fix is the SAME clause, not a new one.

**N5. The app-group share inbox nears its 200-tombstone cap.**
- v1: `CaptureInbox.write` is error-aware (atomic write, logged failure, honest retry copy per
  C201, `M/Services/Capture/CaptureInbox.swift:196-208`); the cap (`tombstoneCap = 200`, `:347`)
  is a ring buffer — `removeFirst` drops the OLDEST tombstone once exceeded (`:359`), which
  could in principle let a very old already-deleted entry re-import if its tombstone ages out
  before 200 newer ones accumulate (unlikely at real usage rates, but the guard is a count, not
  a guarantee).
- Owner: nothing from the inbox ever silently duplicates.
- Verdict: COVERED C201 — mechanism matches the clause; the ring-buffer edge is a theoretical
  corner, not flagged as a gap.

**N6. The vault folder (external drive) or the archive repo folder (deleted from disk) goes unreachable mid-export.**
- v1: same mechanism for both destinations — `VaultWriter.commit` writes via
  `NSFileCoordinator` + `.atomic` and throws on failure (`S/Export/VaultWrite.swift:369-379`);
  the interactive Mac path catches and surfaces a toast
  (`D/Features/Shell/ProcessingCoordinator.swift:321-339`); the mobile path returns `.noVault`
  when the bookmark won't resolve (`M/Services/Export/ObsidianPublisher.swift:143`) — both
  destinations share the same bookmark-resolve + coordinator code. The unattended background
  re-export sweep, though, only LOGS the failure ("vault now stale for this note") with no
  user-facing surface (`D/Pipeline/Ingest/MemoCloudReconciler+Wiring.swift:167-183`), for
  either destination.
- Owner: an unmounted drive or a deleted archive folder is found out eventually, not silently
  swallowed forever, whichever destination it is.
- Verdict: PARTLY C168 — the interactive path is honest, the background sweep path is exactly
  the swallowed-error shape C168 forbids, for both vault and archive.
- Clause: amend C168 to name the re-export sweep explicitly (it currently reads as covering
  "any write surface" but the code shows one write surface opting out). Fixture: unmount /
  deleted-folder simulated via a revoked bookmark mid-sweep; check = a UI surface (not just a
  log line) shows the stale note for both destinations.

**N7. A photo/PDF asset uploads but never finishes downloading to another device (stuck, not just slow).**
- v1: `MediaSyncState.of` (`M/Services/CloudSyncMonitor.swift:166-175`) and `ImageEmbed`
  (`M/Features/MemoDetail/CaptureQuoteViews.swift:111-134`) DO distinguish present /
  downloading ("Downloading from iCloud…") / missing, based on `hasAsset` vs file-on-disk —
  the common "still arriving" case is handled well. But `.downloading` has no timeout or
  stuck/failed sub-state: an asset whose upload silently failed looks identical to one that's
  mid-transfer, forever.
- Owner: eventually told a picture is never coming, instead of an infinite spinner.
- Verdict: PARTLY C190 (asset materialisation "never overwrites, refreshes on byte count" says
  nothing about a transfer that never starts).
- Clause: C261 (below). Fixture: none yet (needs a stuck-CKAsset harness); check = a
  `.downloading` state older than N hours degrades to a distinguishable "couldn't fetch" state.

### SCALE

**S1. The phone list holds 2,000 notes.**
- v1: `MemosListView` queries via `@Query(filter:, sort: \.recordedAt, order: .reverse)` with
  no `fetchLimit` (`M/Features/MemosList/MemosListView.swift:62-63`); `NotesRepository.allMemos()`
  / `allMemosIncludingTrashed()` likewise build an unlimited `FetchDescriptor<Memo>`
  (`M/Services/NotesRepository.swift:53-58, 182-186`); `filtered`/`groups(from:)` then
  filter+sort+day-bucket the WHOLE array on every body evaluation (`MemosListView.swift:1144-1174`).
- Owner: the list opens fast at 2,000 notes, not just at today's ~106-note corpus size.
- Verdict: UNCOVERED (no clause states a scale target; C1's method doesn't rewrite views).
- Clause: C256 (below). Fixture: corpus seeded ×20 (2,000 synthetic rows); check = list
  first-paint time logged, no full-array re-sort per keystroke in search.

**S2. 300 photos in one note.**
- v1: `MemoAsset` carries no per-memo count cap (`S/Model/MemoAsset.swift`, whole file);
  `MemoMetadata.imageManifest` is an unbounded `[ImageManifestEntry]?` with no size guard at
  any of its ~25 construction sites (`S/Model/MemoMetadata.swift:23`). Blobs are kept off the
  `Memo` row precisely so the hot list query doesn't fault them in, which softens read cost but
  doesn't cap growth.
- Owner: an extreme note (a whole photo album voice-narrated) doesn't wreck sync or the editor.
- Verdict: UNCOVERED — C13/C14 describe marker semantics, not a volume ceiling.
- Clause: C257 (below). Fixture: corpus `pic-three-hundred` (300-entry manifest); check = editor
  scroll stays responsive, CloudKit push completes, no marker/manifest desync.

**S3. A 40 MB PDF is shared or dropped in.**
- v1: `CaptureInboxDrainer.copyItem`s the file straight into `AppPaths.recordingsDirectory`
  with no size check (`M/Services/Capture/CaptureInboxDrainer.swift:376-396`); the only size
  gate found (512,000 bytes) applies to the `.md/.txt`-as-body path, not `.file`/PDF
  (`:359-362`); `AssetMaterializer` inserts it as `MemoAsset(kind: .document, blob: data)` with
  no size guard (`:133`), and neither it nor `MemoCloudIngest.swift` handles a CloudKit
  asset-too-large `CKError`.
- Owner: a big PDF either syncs or tells him it can't — never a silent stall.
- Verdict: UNCOVERED (C73 covers PDF ingestion shape, not size; C168's "no swallowed error"
  doesn't reach this path since nothing throws here to swallow).
- Clause: C258 (below). Fixture: `cap-file-pdf-40mb`; check = an oversize asset surfaces a
  named refusal instead of a memo that never finishes syncing.

**S4. A 9,000-word wall of text is pasted into a typed note and processed.**
- v1: `PolishPrompts.copyEditTokenBudget` = `min(8192, max(1024, tokens*1.5))`
  (`S/Pipeline/PolishPrompts.swift:48-65`) caps output at ≈6,000 words regardless of input
  size; the code comment there documents this exact case — the escrow refuses the loss and
  ships the RAW body unedited, matching C32's truncation rule.
- Owner: a very long paste degrades to "unedited", not garbled or cut mid-sentence.
- Verdict: PARTLY C32/C150 — the truncation guard IS the documented behaviour, but nothing
  tells HIM a 9k-word note silently skipped copy-edit (no UI distinction between "nothing to
  improve" and "too big to touch"); C150's per-block chunking (D45) would fix this but is typed
  text, which C7/D7 exempts from paragraphing, not from the chunker itself — unclear if C150
  covers typed notes too.
- Clause: amend C150 to state whether it applies to typed walls, not just voice. Fixture:
  `typed-wall-9k`; check = shipped body differs from raw once C150 lands.

**S5. Fifteen devices each produce a duplicate row for the same memo id (a corrupted sync loop, hypothetically).**
- v1: `MemoDuplicates.keeper(of:)` is one `.min` pass over the whole group
  (`S/Pipeline/MemoDuplicates.swift:29-40`); `canonicalRows` groups by id via `Dictionary(grouping:)`
  first (`:44-52`) — O(n) in the group size, no pairwise comparison, no assumption of exactly 2
  copies.
- Owner: however many stray copies pile up, one keeper wins and the rest are inert.
- Verdict: COVERED C48 (the keeper rule scales as designed; T5 above is the one real gap in it
  — the skew-tie case, not the count).

**S6. The names roster grows to 400 people.**
- v1: `Sanitiser.Overrides.init` builds the alias map once per note in O(roster)
  (`S/Naming/Sanitiser.swift:62-101`); linking then runs one regex pass per LINKED alias over
  the note text (`:144-220`) — cost is roster-size × text-length, not mention × roster, and
  ambiguous (shared) aliases are tracked in an explicit `Set` (`:88`) rather than silently
  cross-matching.
- Owner: a big roster doesn't make note-opening noticeably slower or link the wrong Bruno.
- Verdict: COVERED — no clause states a scale target, but the mechanism holds at this size by
  inspection, worth a corpus check: fixture `roster-400` + a note mentioning 5 names; check =
  linking time doesn't regress vs. the current small roster.

**S7. A note ends up with 50 tags (12 auto-suggested, accepted and re-accepted over several sessions plus manual adds).**
- v1: `TagMatcher` enforces the C178 cap (10 matched + 5 spoken) only at SUGGESTION time
  (`S/Pipeline/Tags/TagMatcher.swift:18-25`); the editor's manual add path dedups but never
  counts (`M/Features/…/TagEditorSheet.swift:176-177`); `Memo.tags` itself is an uncapped
  `[String]` (`S/Model/Memo.swift:63`); the list row and the frontmatter `tags:` YAML list both
  iterate the full array with no truncation (`MemosListView.swift:1402`, `S/Export/Compiler.swift:138-139`).
- Owner: tags never crash or silently drop, but a 50-tag note is also never stopped from
  happening even though C178 clearly means ~15 to be the practical ceiling.
- Verdict: PARTLY C178 — the auto-suggestion cap is real, the manual-add path has none, so the
  clause's intent (a manageable tag set) is only half-enforced.
- Clause: C259 (below). Fixture: `typed-fifty-tags`; check = editor/export both cope, and
  decide whether a manual cap should exist (Tuur's call — "the tag UI gets a revamp" C241 may
  be where this lands).

### PERMISSIONS

**P1. Microphone access is revoked in Settings WHILE a recording is running.**
- v1: no `AVAudioSession.recordPermission`/`AVAudioApplication` check anywhere in
  `LiveRecordingService.swift` or `S/Recording/RecordingCore.swift` (grepped, none); a
  Settings-revoke fires the generic interruption notification, handled identically to a phone
  call: `.began` shows "Interrupted — recording resumes when it's over"
  (`M/Services/Recording/LiveRecordingService.swift:928`); since no `.ended` ever arrives, the
  rebuild ladder retries forever and settles on "Waiting for the mic — keeping what's recorded
  so far" (`:1148, 1163`) — a message promising a return that permission denial makes impossible.
- Owner: told to go fix permissions, not left waiting on a mic that's never coming back.
- Verdict: UNCOVERED (C221's route-change survival doesn't distinguish a permission revoke
  from a hardware route change).
- Clause: C262 (below). Fixture: sim test flipping mic permission mid-`AVAudioSession` active;
  check = the UI switches to a "microphone access was turned off" state, not the generic wait copy.

**P2. Photos library access is denied.**
- v1: both importers route through system pickers (`PHPickerViewController`,
  `UIImagePickerController`) that work without library authorization and never prompt for it
  (`M/Features/Import/VideoImportPicker.swift:87-96`, comment: "we never PROMPT"); the one
  direct `PHPhotoLibrary.authorizationStatus` check gates a best-effort EXIF-date lookup and
  falls back to `nil` silently if denied.
- Owner: importing a photo never needs a permission dialog at all.
- Verdict: COVERED — architecturally sidesteps the permission; no save-to-Photos path exists
  to need the reverse check.

**P3. Notifications (reminders) permission is denied or later revoked.**
- v1: `ReminderSheet.set()` requests authorization, sets `deniedAuth = !granted`
  (`M/Features/MemoDetail/ReminderSheet.swift:106-116`), but writes `memo.remindAt = date`
  UNCONDITIONALLY before the async grant check resolves (`:107`); `ReminderScheduler.run`
  never calls `getNotificationSettings`/checks authorization before scheduling — it just
  `try?`s `center.add(request)` (`M/Services/ReminderScheduler.swift:59-90`). A denied or later-
  revoked permission leaves `remindAt` set and the note showing "reminder set" while nothing
  will ever fire.
- Owner: told the reminder won't fire, not shown a lie.
- Verdict: UNCOVERED (C92 "each device derives its own alarm" assumes permission is granted).
- Clause: C263 (below). Fixture: `ReminderPlan` test with `UNAuthorizationStatus.denied`;
  check = the note surfaces "reminders are off" instead of a scheduled-looking date.

**P4. Face ID fails three times on a locked note.**
- v1: `LockGate` uses `LAPolicy.deviceOwnerAuthentication` (not `...WithBiometrics`)
  (`S/Session/LockGate.swift:26-34`), which gets the OS's native passcode fallback after
  repeated Face ID failures for free; `canAuthenticate()` refuses to let a note be locked at
  all on a device with no passcode set (`:66-70`), preventing a permanent brick; on any
  failure `unlock()` returns `false` and the placeholder stays with a retry button
  (`M/Features/MemoDetail/MemoDetailView.swift:1014-1039`).
- Owner: never permanently locked out of his own note.
- Verdict: COVERED C213.

**P5. Camera access is denied when opening the in-recording photo sheet.**
- v1: no `authorizationStatus`/`requestAccess` check anywhere in
  `M/Services/Recording/PhotoCaptureService.swift` or the camera sheet in `RecordView.swift:448`
  (grepped, none); `configure()` builds the capture session regardless and `try?`s the device
  input (`:56`) — on denial the session runs with no input, `isReady` is still set `true`
  (`:68`), and a shutter press just fails silently in the photo-output delegate (`:182`) with
  no feedback, unlike `CameraImagePicker` which delegates fully to system UI.
- Owner: told the camera is off, not left tapping a shutter that does nothing.
- Verdict: UNCOVERED (C222 "the camera is an on-demand sheet" says nothing about a denied state).
- Clause: C264 (below). Fixture: sim with camera permission denied, in-recording sheet opened;
  check = a denied-state view replaces the dead live preview.

**P6. The Mac's TCC microphone prompt is dismissed/ignored rather than answered.**
- v1: `LiveRecordingSession.start()` sets `phase = .starting`
  (`D/Features/Shell/LiveRecordingSession.swift:98`) then directly `await`s
  `AVCaptureDevice.requestAccess(for: .audio)` inside `MacRecorder.start()`
  (`D/Engines/MacRecorder.swift:163-181, 532-538`) with no timeout or race wrapper — an
  unanswered system prompt leaves the await pending indefinitely, `phase` stuck at `.starting`.
- Owner: the Record button recovers or explains itself, not hangs forever.
- Verdict: UNCOVERED (C224 lists the TCC-denial path — "typed refusal + Open Settings" — but
  only for an answered denial, not an ignored prompt).
- Clause: C265 (below). Fixture: `-recordcheck` variant that never answers the mic prompt;
  check = a timeout (e.g. 15 s) flips `phase` to a recoverable error state.

### TEXT

**X1. Emoji inside a roster name (e.g. "Bruno 🔥").**
- v1: `Sanitiser`'s word matcher builds `\b<alias>\b` via `NSRegularExpression`
  (`S/Naming/Sanitiser.swift:748-756`); ICU `\b` is a word/non-word transition, and an emoji is
  a non-word character followed by more non-word text at the boundary — no transition fires,
  so the alias silently never matches anywhere. `VaultName.stem` only strips
  `/ \ * " < > : | ? # ^ [ ]` (`S/Export/VaultWrite.swift:120-130`), so the filename side is fine.
  SAME character class also breaks a title that is ONLY emoji ("🎉🎉🎉"): the archive's
  `slug()` keeps only `isLetter || isNumber` (`S/Export/ExportProfile.swift:77-98`) — every
  character drops, `slug` is empty, correctly falls back to `timestampStem`. But the
  Obsidian-profile `VaultName.stem` does NOT strip emoji (only the forbidden-char set above),
  so a vault export would write `🎉🎉🎉.md` verbatim — inconsistent with the archive
  profile's stricter behaviour, though not a crash.
- Owner: a name he registered links whatever characters are in it; a sane filename either way,
  not one profile behaving differently from the other.
- Verdict: UNCOVERED (linking) / PARTLY C165 (filename — states ONE rule, the two profiles
  quietly diverge on emoji).
- Clause: C266 (name linking, below); amend C165 to state the emoji filename case explicitly.
  Fixture: roster entry `"Bruno 🔥"` + corpus note mentioning him; `typed-emoji-title`;
  golden: linked like any other name, and the same fallback filename behaviour in both profiles.

**X2. Right-to-left text (Arabic/Hebrew) in a transcript.**
- v1: `NoteTitle.clip` is grapheme-safe (`S/Model/NoteTitle.swift:24-35`, no mid-cluster cuts).
  But `Paragrapher.endsSentence` only recognises ASCII `. ? !`
  (`S/Pipeline/Paragrapher.swift:136-139`) — Arabic `؟` and other RTL sentence punctuation
  never end a sentence, so RTL voice notes under-segment into fewer, longer paragraphs than
  the same content would in English.
- Owner: an Arabic/Hebrew note paragraphs like an English one would.
- Verdict: UNCOVERED (C20 states the pause+sentence-end rule without a language-scoped
  terminator set).
- Clause: C267 (below). Fixture: corpus `voice-ar-paragraphs` (or Hebrew) with RTL punctuation;
  golden: breaks land at RTL sentence ends too.

**X3. A 200-character single unbreakable "word" (a URL blob) pasted into a note.**
- v1: `NoteTitle.clip` explicitly handles no-whitespace text — falls to a documented hard cut
  rather than an empty title (`S/Model/NoteTitle.swift:26-34`); the wall-break rule
  (`S/Pipeline/PolishPrompts.swift:96-114`) treats an unbroken blob as one giant "sentence" and
  emits it whole — no crash, just no break.
- Owner: doesn't crash or garble; a slightly odd single-block paragraph is acceptable.
- Verdict: COVERED C25/C34 — traced fresh, holds.

**X4. A transcript that is only punctuation ("... -- ,,, ???").**
- v1: both the phantom guard (`S/Pipeline/BPEMerge.swift:86-93`) and the shrink guard
  (`S/Pipeline/PolishPrompts.swift:123-128`) count "words" via whitespace-split — `"..."`,
  `"--"`, `",,,"`, `"???"` each count as one word, giving wordCount 4 (> the phantom guard's
  `<= 3` threshold), so it's NOT dropped as noise. `firstTranscriptLine`
  (`M/Models/MemoDisplay.swift:34-45`) only checks non-empty-after-trim, unlike
  `Memo.parseTagInput`'s letter/digit requirement (`S/Model/Memo.swift:263-291`) — so the title
  ladder never falls through to "Note"/"Voice note" and the note titles itself literally
  `"... -- ,,, ???"`.
- Owner: an ASR garbage take gets a sane fallback title, not literal punctuation.
- Verdict: UNCOVERED (C25's title ladder assumes the first line is prose).
- Clause: C268 (below). Fixture: corpus `voice-en-punctuation-only`; golden: title falls to
  "Voice note".

**X5. A literal `[[usual]]` typed by hand, not a memo-link.**
- v1: `MemoLinkSyntax`'s regex strictly requires `\[\[memo:<UUID>\|...\]\]`
  (`S/Model/MemoLinkSyntax.swift:14-15`); plain `[[usual]]` never matches, so `exportRewrite`
  leaves it untouched and it passes straight into the exported markdown as literal `[[usual]]`
  — a real (likely broken) Obsidian wikilink the user never intended. `Sanitiser.nonProseRanges`
  does correctly protect it from name-scanning (C82's quote/code/link exclusion), so it isn't
  corrupted further, just exported as unintended link syntax.
- Owner: typed double-brackets that aren't a real link don't become one in the vault.
- Verdict: UNCOVERED — no clause addresses hand-typed bracket syntax that collides with the
  memo-link glyph.
- Clause: C269 (below). Fixture: `typed-literal-double-brackets`; golden: escaped or left as
  plain text on export, never a bare `[[word]]` Obsidian would try to resolve.

**X6. A tag containing YAML-hostile characters (`: `, `#`, `"`).**
- v1: `Memo.splitTagInput` only requires a letter/digit present after stripping `#`
  (`S/Model/Memo.swift:280-291`) — `"foo: bar"` or `foo"bar` pass straight through. `Compiler.compile`
  writes tags UNESCAPED (`y.append("  - \(t)")`, `S/Export/Compiler.swift:139`), unlike
  `summary:` which goes through `yamlQuoted()` (`:320-323`). A tag with `: ` turns
  `- foo: bar` into a YAML MAPPING inside the list instead of a string — silently corrupting
  the `tags:` block's type for any YAML parser, including the archive's own
  `vault_index.py`.
- Owner: a tag with odd characters exports as a harmless string, never breaks the file's YAML.
- Verdict: UNCOVERED (C93 defines the split rule, not export escaping; C130 requires the
  archive-bound frontmatter to parse with `vault_index.py` but this bug also hits the vault
  profile).
- Clause: C270 (below). Fixture: `typed-tag-yaml-colon`, `typed-tag-yaml-quote`; golden: tags
  quoted like `summary:` whenever they need it.

**X7. A note's first body line is literally `---`.**
- v1: `VaultStamp.frontmatter()` finds the CLOSING delimiter as the first `---` line AFTER the
  opening one (`S/Export/VaultStamp.swift:181-186`); since Skrift's own frontmatter block never
  contains a bare `---`, this correctly resolves to the real closing delimiter before any stray
  `---` in the body — stamp detection is unaffected. The only side effect is presentational: a
  body opening with `---` renders as a Markdown horizontal rule in Obsidian, silently eating
  the user's literal three dashes.
- Owner: the stamp still works; losing three literal dashes to a rendered rule is a cosmetic
  surprise worth knowing about, not a data-safety issue.
- Verdict: COVERED C193 (stamp mechanism holds) / flag the cosmetic render side-effect only,
  no clause needed.

### CONCURRENCY

**Q1. Process pressed on the iPad while the Mac's batch run is already polishing the same note.**
- v1: `PolishCenter.canPolish`/`busyMemoID` (`M/Services/Polish/PolishCenter.swift:149-159,
  226-233`) is an in-process, single-DEVICE guard ("one note at a time, device-wide") added
  after two in-app taps corrupted one MLX run — it says nothing about another device.
  `BatchRunner`'s only guard, `bodyEditedMidRun()`
  (`D/Pipeline/BatchManager/BatchRunner.swift:111-120,147-151,168-174`), detects a LOCAL edit
  to the same row, not a concurrent enhancement from another device. `MemoEnhancement` itself
  carries no processing lock, only `enhancedByDeviceID`/`enhancedAt` for after-the-fact LWW.
- Owner: two devices don't both spend a run on the same note with one silently thrown away.
- Verdict: UNCOVERED (C38 "the Mac processes only enhanceStatus != .done" says nothing about
  a concurrent iPad run against the same row).
- Clause: C271 (below). Fixture: simulated concurrent enhancement writes, same memo id, both
  `processedAt` set within the same second; golden: TBD — a visible conflict, not silent loss
  (parallels C242's conflict model).

**Q2. Two share-drain triggers fire close together (launch + foreground transition).**
- v1: `CaptureInboxDrainer.isDraining` is a `@MainActor`-isolated static `Bool`
  (`M/Services/Capture/CaptureInboxDrainer.swift:35,86-88`); the check-then-set has no `await`
  between them, so actor isolation makes it atomic against re-entrant calls within the app.
- Owner: no clip processed twice just because two triggers landed close together.
- Verdict: COVERED C201.

**Q3. Export pressed twice fast on the same note.**
- v1: `PublishCoordinator.exportNow`/`ObsidianPublisher.publish` are fully synchronous,
  main-actor, no `await` inside (`M/Features/MemoDetail/MemoDetailView.swift:693-719`,
  `M/Services/Export/ObsidianPublisher.swift:131`) — SwiftUI can't deliver a second `Button`
  action until the first returns; the content-hash ledger (`VaultWrite.swift` `ExportLedger`,
  `assess`/`commit`) is a documented backstop even if it somehow raced. Same synchronous shape
  on the Mac (`D/Pipeline/Export/VaultExporter.swift:74`).
- Owner: a double-tap never double-writes or corrupts the file.
- Verdict: COVERED C55/C194.

**Q4. A recording is started while a book is playing.**
- v1: no explicit "pause the book" call at `LiveRecordingService.start()`, unlike
  `AudioPlayerModel.play()` which explicitly pauses the book to avoid a stutter
  (`M/Services/AudioPlayerModel.swift:71-95`); instead `AudiobookSession` observes
  `AVAudioSession.interruptionNotification` and refuses to resume while
  `LiveRecordingService.isRecordingActive` is true
  (`M/Services/Audiobooks/AudiobookSession.swift:549-585, 620-636`). Every record entry point
  (FAB, widget/Control Center intent, Siri) funnels through the same foregrounded
  `RecordView`/`LiveRecordingService`, so there's no background-race entry. One residual gap:
  the interruption notification is async, so `AudiobookSession.isPlaying` can briefly still
  read `true` after recording has begun — cosmetic, not a data race (only one process holds
  the hardware session).
- Owner: never hears the book and his own voice recorded together.
- Verdict: COVERED C225.

**Q5. The Mac app is quit (Cmd+Q) mid-export.**
- v1: `VaultWriter.writeAtomic` wraps `Data.write(options: .atomic)` (temp-then-rename) inside
  `NSFileCoordinator` — genuinely atomic (`S/Export/VaultWrite.swift:451-460`); but the ASSET
  copy branch, `writeAsset`, calls `FileManager.copyItem(at:to:)` straight to the final
  destination inside only a coordinator block (`:391-410`) — `NSFileCoordinator` coordinates
  OBSERVERS, it does not make `copyItem` itself atomic. A kill mid-copy can leave a
  half-written image/audio asset at its real vault path, unlike the markdown file which can't
  land half-written.
- Owner: a killed export never leaves a corrupt picture file sitting in the vault.
- Verdict: PARTLY C55 ("writes are atomic and file-coordinated" — true for the .md, not for
  asset copies).
- Clause: amend C55 to require the SAME temp-then-rename atomicity for asset writes, not just
  the note file. Fixture: kill test mid-`writeAsset`; golden: no partial file at the final path,
  ever (temp file only, cleaned up or resumed).

**Q6. The phone is killed mid-drain of an image/text/url/file share entry (not audio/video — that loss window is already known, see the 50-scenario probe #19).**
- v1: unlike the audio/video branches (which delete-before-import), the image/url/text/file
  branches reuse `entry.id` as the memo UUID and insert-THEN-delete: `repository.insert(memo)`
  before `CaptureInbox.delete(entryDir:)`
  (`M/Services/Capture/CaptureInboxDrainer.swift:529, 531`). A kill between insert and delete
  just leaves an orphaned inbox entry the dedup check
  (`CaptureInboxDrainer.swift:280-283`, `repository.memo(id:) != nil`) safely no-ops on the
  next drain. A kill BEFORE insert (mid image-copy, `:429-449`) leaves the entry untouched,
  safely retried.
- Owner: nothing shared is lost for these four types, whatever the kill timing.
- Verdict: COVERED C147/C201 for these four types specifically — confirms the audio/video
  finding from scenario #19 is narrower than "any kill during a drain loses data"; the other
  four types were already safe by construction.


---

## Summary table

| # | Scenario | Verdict | Clause |
|---|---|---|---|
| T1 | Clock skew between devices (LWW write-back guard) | UNCOVERED | C252 |
| T2 | DST change mid-recording | COVERED | — |
| T3 | DST fall-back timestamp-filename collision | COVERED | C54 |
| T4 | Phone clock wrong by a year (`recordedAt` future) | UNCOVERED | C253 |
| T5 | Duplicate keeper tie-break skewed by a bad clock | UNCOVERED | C254 |
| T6 | `date:` phone vs Mac near midnight | CONTRADICTED | C64/D13 |
| T7 | A 3-hour recording, one-shot transcription | UNCOVERED | C255 |
| N1 | Disk full mid-recording | CONTRADICTED | C99/D4 |
| N2 | iCloud storage full for a week | UNCOVERED | C145 (proposed) |
| N3 | iCloud signed out, different account signed in | UNCOVERED | C260 |
| N4 | CloudKit token expired mid-sweep | PARTLY | C168/R40 |
| N5 | App-group inbox nears the 200-tombstone cap | COVERED | C201 |
| N6 | Vault/archive folder unreachable mid-export | PARTLY | C168 (amend) |
| N7 | A synced asset stuck mid-download, never arrives | PARTLY | C261 |
| S1 | 2,000 notes on the phone list | UNCOVERED | C256 |
| S2 | 300 photos in one note | UNCOVERED | C257 |
| S3 | A 40 MB PDF share | UNCOVERED | C258 |
| S4 | A 9,000-word typed paste, processed | PARTLY | C32/C150 |
| S5 | 15 devices' worth of duplicate rows | COVERED | C48 |
| S6 | A names roster of 400 people | COVERED | — |
| S7 | 50 tags on one note | PARTLY | C259 |
| P1 | Mic permission revoked mid-recording | UNCOVERED | C262 |
| P2 | Photos access denied | COVERED | — |
| P3 | Notifications (reminders) denied | UNCOVERED | C263 |
| P4 | Face ID fails 3× on a locked note | COVERED | C213 |
| P5 | Camera denied during in-recording capture | UNCOVERED | C264 |
| P6 | Mac TCC mic prompt dismissed/ignored | UNCOVERED | C265 |
| X1 | Emoji in a roster name / emoji-only title | UNCOVERED / PARTLY | C266 / C165 (amend) |
| X2 | Right-to-left text paragraphing | UNCOVERED | C267 |
| X3 | A 200-char unbreakable word | COVERED | C25/C34 |
| X4 | A punctuation-only transcript | UNCOVERED | C268 |
| X5 | A hand-typed literal `[[usual]]` | UNCOVERED | C269 |
| X6 | YAML-hostile characters in a tag | UNCOVERED | C270 |
| X7 | Note body's first line is `---` | COVERED | C193 |
| Q1 | iPad Process vs Mac batch on the same note | UNCOVERED | C271 |
| Q2 | Two share-drain triggers close together | COVERED | C201 |
| Q3 | Export pressed twice fast | COVERED | C55/C194 |
| Q4 | Recording started while a book plays | COVERED | C225 |
| Q5 | Mac quit mid-export (asset copy atomicity) | PARTLY | C55 (amend) |
| Q6 | Phone killed mid-drain, non-audio/video types | COVERED | C147/C201 |

Counts: COVERED 13 · PARTLY 6 · UNCOVERED 19 · CONTRADICTED 2.

---

## Uncovered / contradicted — proposed clause texts

Time:

- C252 [auto] The Mac's write-back LWW guard compares an existing row's `enhancedAt` against
  THIS device's own clock, not the writing device's; a fast-clocked device's stamp can outrun
  a slow-clocked device's `now` and get permanently protected from a legitimately newer write.
  Guard against clock skew directly (bounded skew tolerance, or a monotonic/logical clock
  component) rather than trusting raw wall time across devices. || check: two in-memory
  contexts, one clock offset +6 min; the skewed device's write-back still lands once its own
  stamp is newer than the row it's replacing.
- C253 [auto] `MemoLifecycle.age` clamps at 0: a `recordedAt` (or `keptAt`) in the future never
  produces a negative age, so a bad-clock note ages normally from `now` once anyone opens the
  app, instead of living off the fade clock forever. || check: corpus
  `voice-en-recordedat-future`; `age` clamps, `isFading` fires on schedule from discovery.
- C254 [auto] (needs Tuur's call, [tuur]) `MemoDuplicates.keeper`'s "latest edit" tie-break is
  skew-aware: a `lastEditedAt` more than some bound (proposed 24 h) ahead of `now` at
  comparison time is not trusted as "latest" over a plausible peer. Default TBD.
  || check: two rows, content-score tied, one `lastEditedAt` 6 months in the future; the
  plausible one wins.
- C255 [auto] An ordinary (non-audiobook) recording longer than some bound (proposed 60 min)
  transcribes in bounded chunks, same 180 s-chunk resumable mechanism as the audiobook lane
  (C106), not one ANE call over the whole file. || check: a synthetic 3 h PCM file transcribes
  without a memory spike logged above the audiobook lane's own ceiling.

Storage/network:

- C260 [auto] An iCloud account CHANGE (sign-out then sign-in as someone else) is detected
  (`CKAccountChanged` / `accountStatus`) and blocks writes against the new zone until the user
  is shown which account Skrift is now pointed at. || check: an account-change notification
  fires a blocking notice before the next local write reaches CloudKit.
- C261 [auto] A synced asset (`MemoAsset`) whose download has been pending longer than some
  bound (proposed 6 h with network available) degrades from "Downloading from iCloud…" to a
  distinguishable "couldn't fetch this picture" state, never an indefinite spinner.
  || check: a `.downloading` `MediaSyncState` older than the bound renders differently from a
  fresh one.

Scale:

- C256 [tuur] The phone notes list stays responsive at real scale (proposed target: 2,000
  live notes, first paint under 1 s on the iPhone 13); either a fetch limit / windowed load or
  a measured proof that the full-table `@Query` holds at that size. || check: corpus seeded
  ×20; list first-paint time logged.
- C257 [auto] A memo's `imageManifest`/asset count has a stated ceiling (proposed 200) enforced
  at capture/import time, past which further photos are refused with a named reason rather
  than accepted silently into an unbounded array. || check: corpus `pic-three-hundred`; import
  past the ceiling is refused, not silently appended.
- C258 [auto] A shared/imported document over a stated size (proposed 100 MB, under CloudKit's
  per-asset ceiling with headroom) is refused at drain time with a named reason, never copied
  in and left to fail invisibly at sync. || check: `cap-file-pdf-40mb` succeeds; an
  over-ceiling fixture is refused honestly.
- C259 [auto] `Memo.tags` enforces the SAME cap as `TagMatcher`'s auto-suggestion (10 matched +
  5 spoken, C178) at every mutation site, not just suggestion generation — manual add is
  refused or prompts a swap past the cap. || check: `typed-fifty-tags`; manual add past the
  cap is refused, editor and export both stay bounded.

Permissions:

- C262 [auto] A microphone permission REVOKED while a recording is active is distinguished from
  a route change: the recorder detects the revocation (not just an unresolved interruption) and
  shows "microphone access was turned off" with a Settings link, never the generic "resumes
  when it's over" wait copy. || check: sim test flipping mic permission mid-session; the UI
  state differs from a plain interruption.
- C263 [auto] Reminder scheduling checks `UNUserNotificationCenter` authorization before
  writing `remindAt`; a denied or revoked permission shows "reminders are off" on the note
  instead of a scheduled-looking date that will never fire. || check: `ReminderPlan` test with
  `.denied`; the note's reminder UI reflects the real authorization state.
- C264 [auto] The in-recording camera sheet checks camera authorization before presenting a
  live preview; a denied state shows a named "camera access is off" view instead of a dead
  preview whose shutter silently does nothing. || check: sim with camera permission denied;
  sheet renders the denied state, not a live-looking dead preview.
- C265 [auto] The Mac's mic-permission request during Record has a timeout (proposed 15 s); an
  unanswered TCC prompt flips the record button to a recoverable error state instead of hanging
  `.starting` indefinitely. || check: `-recordcheck` variant that never answers the prompt;
  `phase` recovers after the timeout.

Text:

- C266 [auto] The name-matching word boundary tolerates a non-letter character (emoji,
  combining mark) inside a registered alias: matching is whole-word against LETTER/DIGIT
  boundaries, not ICU `\b`, so an alias like "Bruno 🔥" still links. || check: roster entry
  with an emoji, corpus note mentioning them; links like any other name.
- C267 [auto] `Paragrapher.endsSentence` recognises RTL and other non-ASCII sentence
  terminators (Arabic `؟`، Hebrew equivalents, full-width punctuation), not just `. ? !`.
  || check: corpus `voice-ar-paragraphs` (or Hebrew); breaks land at RTL sentence ends.
- C268 [auto] The title ladder's "first body line" step requires a letter or digit present
  (same test as `Memo.parseTagInput`), else it falls through to "Note"/"Voice note" rather than
  titling the note with raw punctuation. || check: corpus `voice-en-punctuation-only`; title
  falls to "Voice note".
- C269 [auto] A hand-typed `[[...]]` that isn't a valid `[[memo:<uuid>|...]]` link is left as
  plain text and never exported as unescaped Obsidian wikilink syntax the user didn't intend
  (escape or leave verbatim as prose, decided once). || check: `typed-literal-double-brackets`;
  export never contains a bare `[[word]]` Obsidian would try to resolve.
- C270 [auto] Tag values are YAML-quoted on export exactly like `summary:` (`yamlQuoted()`)
  whenever they contain `: `, `#`, `"` or start/end with whitespace, so the `tags:` block
  never silently changes YAML type. || check: `typed-tag-yaml-colon`, `typed-tag-yaml-quote`;
  both parse as plain strings in the list.

Concurrency:

- C271 [tuur] Two devices polishing the same memo concurrently (iPad Process vs Mac batch) is
  modelled like C242's conflict handling, not silent LWW overwrite: the loser's run is either
  prevented (a synced in-progress flag on `MemoEnhancement`) or surfaced as a conflict, never
  thrown away with no signal. Default TBD — mock first, same family as C242. || check:
  simulated concurrent enhancement writes to the same memo id within one second; the losing
  run is visible somewhere, not silently gone.

Amendments to existing clauses (no new number):

- Amend **C150** to state explicitly whether the per-block copy-edit chunking applies to long
  TYPED walls (S4) as well as long voice notes, or whether typed text's C32 truncation is
  accepted as final. Currently ambiguous.
- Amend **C165** to state the emoji-only-title case: both export profiles should degrade the
  same way (fall back to the timestamp/ID stem), not just the archive profile. (X1)
- Amend **C168** to name the background re-export sweep explicitly — `MemoCloudReconciler+Wiring.swift`'s
  `reexportEdited` logs a stale-vault failure with no UI surface, the one write path that
  currently opts out of "no swallowed error." (N6, and N4's CloudKit-auth case shares the
  same sweep.)
- Amend **C55** ("writes are atomic and file-coordinated") to cover asset COPIES, not just the
  markdown file — `VaultWrite.writeAsset`'s `FileManager.copyItem` is not wrapped in the same
  temp-then-rename atomicity `writeAtomic` gives the `.md`. (Q5)

---

## Fixtures to add

Corpus (`test-fixtures/corpus/notes/`):

- `voice-en-recordedat-future` — `recordedAt` +400 days (T4)
- `voice-en-punctuation-only` — ASR garbage transcript, no letters (X4)
- `voice-ar-paragraphs` (or Hebrew) — RTL sentence terminators, timed pauses (X2)
- `typed-emoji-title` — title is only emoji (X1)
- `typed-literal-double-brackets` — hand-typed `[[usual]]`, no UUID (X5)
- `typed-tag-yaml-colon`, `typed-tag-yaml-quote` — tags with `: `/`"` (X6)
- `typed-fifty-tags` — 50 tags, mixed auto+manual (S7)
- `typed-wall-9k` — 9,000-word typed paste (S4)
- `pic-three-hundred` — 300-entry image manifest (S2)
- `cap-file-pdf-40mb` — oversize PDF share (S3)
- roster entry with an emoji name + a mentioning note (X1)
- `roster-400` + a note mentioning 5 names (S6)

Unit/harness tests without a corpus note:

- `MacCloudWriteBackTests` clock-skew case, offset device clocks (T1)
- `MemoDuplicates` tie-break with a future `lastEditedAt` (T5)
- `MemosListView`/`NotesRepository` seeded ×20 for a 2,000-row list timing check (S1)
- `ReminderPlan` test with `.denied` authorization (P3)
- sim tests: mic permission revoked mid-session (P1), camera denied in the record sheet (P5)
- `-recordcheck` variant with an unanswered Mac TCC prompt (P6)
- kill test mid-`VaultWrite.writeAsset` (Q5)
- simulated concurrent iPad/Mac enhancement writes, same memo id (Q1)
- CKAccountChanged simulation (N3) — device/account test, no unit harness owns this yet
- stuck-`CKAsset` harness for a `.downloading` state that never resolves (N7)
