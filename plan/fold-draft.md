# Fold draft — paste into SPEC.md and BUGS.md

Source: `plan/scenarios-capture.md` (capture-path probe) + 10 data-loss sweep reports, merged in
`plan/data-loss.md`. Numbering checked against the live files at time of writing: SPEC.md's
Required-differences table already runs through **R69** (names probe) and Open-decisions through
**D96**; SPEC.md's clause list already runs through **C260**; BUGS.md's own D-namespace (§1) runs
through **D4**. New numbering below starts one past each of those, NOT at the R61/C261/D96 the
task brief guessed before this session's own R61-R69/C254-C260/D96 landed.

---

## §1 New required-difference rows — paste into SPEC.md's Required-differences table

| # | v1 does (file:line) | v2 must | corpus note or test name | clause |
|---|---|---|---|---|
| R70 | editor commit silently blanks the raw transcript on an empty edit (`NoteBodyView.swift:1182-1190`) and the Mac's polished copy-edit on the SAME path with no guard at all (`NoteBodyView.swift:1173-1175`, `MemoDetailView.swift:1738-1748` `polishedBinding` setter) | an empty commit asks first, or the prior text is kept recoverable | `editor-clear-raw`, `editor-clear-polished` | C261 (new) |
| R71 | closing an active recording (X tap) discards the in-progress audio and every captured photo with zero confirmation (`RecordView.swift:502-505` → `LiveRecordingService.cancel()` + `PhotoCaptureService.discardAll()`) | closing with meaningful captured audio/photos confirms first, like a saved note's delete | `close-active-recording-with-photos` | C262 (new) |
| R72 | append races the original transcription pass unordered — `MemoDetailView.swift:92` "Add recording" has no gate on `transcriptStatus`, and whichever `repository.save()` in `MemoSaver.swift:573-671`/`:792-837` lands second wins outright over the other's already-deleted clip; a failed audio merge on append (`MemoSaver.swift:602`) silently keeps only the text, no log | append gates on / waits for `transcriptStatus != .transcribing`, or writes are version-stamped; a failed merge logs and surfaces, never silently drops the audio | `append-during-original-transcribe-race`, `append-merge-fails-audio-lost` | C223 (existing — violated) |
| R73 | `recoverStuckTranscriptions` (`MemoSaver.swift:864-880`) has no `transcriptUserEdited` check and can blindly re-run plain transcription over a diarized/hand-edited note killed mid-append | recovery never runs over a `transcriptUserEdited` memo | `kill-mid-append-on-diarized-note` | C263 (new) |
| R74 | `ImageMarkers.insert` (`Shared/Pipeline/ImageMarkers.swift:40-60`) reverses marker order when two entries tie on the same nearest-word position | manifest order preserved on a tie, none merged | `pic-during-pause-two-shots`, `pic-burst-same-offset` | C13 (existing — violated) |
| R75 | a `.transcribing` memo orphaned when its owning device is gone can never self-heal — `MemoSaver.swift:860-862`'s `ownsForRecovery` gates recovery to `recordingDeviceID == nil \|\| == thisDevice`, and `Shared/Model/DeviceID.swift` is local-only, never synced | a time-based fallback lets any device adopt an orphan `.transcribing` memo older than N days, or a Mac-side backstop | `stuck-transcribing-orphaned-device-gone` | C264 (new) |
| R76 | a widget/Siri "Record" tap on a never-opened install is silently dropped: `SkriftApp.swift` shows onboarding, not `RecordView`, and `RecordingIntentBridge`'s pending-start flag has no expiry (unlike `prestart()`'s 8s sweep) | the pending intent either fast-paths into recording once onboarding completes, or the drop is surfaced | `widget-tap-before-first-open` | C100 (existing — violated) |
| R77 | `Shared/Export/VaultWrite.swift:391-407` `writeAsset` `.file` branch unconditionally `removeItem`s then `copyItem`s an existing vault attachment with no ownership/stamp check — inside the SHARED engine both apps and C54 treat as protected | attachments route through the same ownership check the markdown lane already uses | new fixture, same shape as D3 test but targeting `VaultWrite.swift` not `VaultExporter.swift` | C58 (existing — violated; new instance, distinct file from D3) |
| R78 | corrupt on-disk JSON is silently adopted as empty and written back over the real file: `Audiobook.swift:500-504,556-601` (mobile `library.json` — loses the WHOLE audiobook library) and `SkriftDesktop/Models/AppSettings.swift:150-176` (Desktop `settings.json` — loses `customVocabulary`/`archiveRoot`/`noteFolder`/`prompts`, non-atomic write too) | a file present-but-undecodable is never treated as "fresh install empty"; the corrupt file is preserved and recovery surfaced, same doctrine as C50 for `names.json` | `corrupt-library-json`, `corrupt-settings-json` | C265 (new — generalizes C50's rule beyond names.json) |
| R79 | delete-person strips `voiceEmbeddings` at tombstone time (`Shared/Naming/NamesStore.swift:86-94`'s tombstone constructor never carries them forward, contradicting C259) and fires with zero confirmation on any of 4 entry points (`PersonEditorView.swift:218-223`, `PersonDetailView.swift:116-120` iOS; `PersonEditor.swift:102-109`→`SettingsView.swift:55-59` Mac) | the tombstone carries voiceEmbeddings per C259; deleting a person confirms first, like every other destructive gesture in both apps | `delete-person-no-confirm`, `tombstone-keeps-voiceprint` | C259 (existing — violated) + C266 (new, confirm gate) |
| R80 | custom vocabulary additions made offline on two devices: `CustomWordsView.swift:39-43,63` saves a load-time snapshot as a full-array overwrite, and the underlying `Shared/Pipeline/VocabularySyncCore.swift:43-48` sync is whole-list LWW with no merge — only the empty-list edge case is guarded | a concurrent addition on two offline devices is never silently dropped; merge additively like `names.json` aliases, or surface a conflict | `vocab-concurrent-offline-add` | C267 (new) |
| R81 | "Remove download" on a synced audiobook has no upload-in-progress check (`SyncedAudiobooksView.swift:66-67`, unlike `AudiobookSyncSheet` which does track `transfer`) and can delete the only copy of not-yet-uploaded audio | removing a synced audiobook's local download only frees storage once its upload to iCloud has completed | `remove-download-mid-upload` | C268 (new) |
| R82 | audiobook bookmark deletion is inconsistent and sometimes multi-delete: `AudiobookPlayerView.swift:467-483`'s fold-gutter tap removes every bookmark within ±0.5s of the tap with one ambiguous "Unfolded" toast; `ChaptersBookmarksSheet.swift:95-98` (swipe) and `:266-268` (iPad long-press) both delete with no confirm | removing a bookmark removes exactly the one nearest the tap and always confirms which/how many were removed; matches every other book-scoped delete's confirm | `bookmark-delete-near-tie`, `bookmark-swipe-no-confirm` | C269 (new) |
| R83 | `BookImportSheet.swift:118-144` `unpack()` checks `alreadyHave` once at offer time and never re-verifies at unpack time; a concurrently-synced copy of the same book is silently overwritten, no diff/hash check | re-check `alreadyImported` immediately before unpack, or diff file hashes before overwrite | `book-import-toctou-overwrite` | C270 (new) |
| R84 | `CaptureInboxDrainer.swift:150` (video), `:221` (audio), `:383-403,531` (file) delete the inbox entry BEFORE the import call is confirmed to succeed; on failure the shared content lands in plain `temporaryDirectory`, never revisited, no error surfaced | the inbox entry is retried, never silently discarded, until import actually succeeds | `capture-import-fails-after-inbox-delete` | C271 (new) |
| R85 | `WallPrinter.swift:79-84` `printCard()` clears the note's "already printed" ledger stamp BEFORE `tryDrain()` confirms the reprint reached the printer | a manual reprint keeps the prior `printedAt` stamp until the reprint itself succeeds | `reprint-fails-loses-history` | C272 (new) |
| R86 | `MarkupQuickLook.swift:77-80`'s `.updateContents` mode writes Markup edits into the SAME file as the original photo, no copy taken first — the un-annotated original is gone permanently | copy the source aside (or a second `MemoAsset` blob) before presenting `.updateContents` | `markup-overwrites-original` | C273 (new) |
| R87 | `CaptureVoiceAnnotate.swift:176` deletes the voice-annotation audio unconditionally after transcription, even when both live caption and the full ASR pass returned empty text; a success haptic fires anyway | a capture whose transcription yields no text is kept (or the user is told) until saved or explicitly discarded | `voice-annotation-empty-transcript-kept` | C274 (new) |
| R88 | locked notes lose protection the moment they're trashed: `WayOutView.swift:169,329,375-401,407-434` render a locked note's title/transcript/photos with no auth, and none of the 3 delete entry points (`MemosListView.swift:483-488,516-518,1089-1091`) check `memo.locked` first; `copyTranscript`/`copyableText` also bypass the lock | a locked note in Recently-Deleted/Fading shows the same "Locked note" placeholder MemosListView already shows, or is excluded until unlock; copy is gated too | `locked-note-in-fading-shelf`, `locked-note-copy-bypass` | C161 (existing — violated) |
| R89 | `NotesRepository.swift:259-268` `save()`'s second consecutive SwiftData failure only `DevLog`s, never reaches the UI — the central persistence chokepoint for every mutation in the app | a second consecutive store-save failure is a visible error, matching C168's letter for "store" | `store-save-fails-twice` | C168 (existing — violated) |

---

## §2 New clauses — paste into SPEC.md's clause list

- C261 [auto] An editor commit that nets to empty (raw transcript or the Mac's polished copy) never lands silently; it confirms first or keeps the prior text recoverable. || check: `editor-clear-raw`, `editor-clear-polished`. — data-loss sweep aa7e6a5c/a381c992
- C262 [auto] Closing an active recording with meaningful captured audio or photos confirms before discarding, the same as a saved note's delete. || check: `close-active-recording-with-photos`. — data-loss sweep a90a385a
- C263 [auto] Transcription recovery after a kill never runs over a `transcriptUserEdited` memo. || check: `kill-mid-append-on-diarized-note`. — scenarios-capture #15
- C264 [auto] A `.transcribing` memo orphaned on a now-gone device is eventually adoptable by any device, or a Mac-side backstop resolves it — it never gets stuck forever. || check: `stuck-transcribing-orphaned-device-gone`. — scenarios-capture #20
- C265 [auto] A locally-cached JSON file (library.json, settings.json — anything not names.json/bookmarks.json, which C50/C218 already cover) that fails to decode is never adopted as empty and never written back; the corrupt file is preserved and recovery surfaced. || check: `corrupt-library-json`, `corrupt-settings-json`. — data-loss sweep af2965fa/ad17c703
- C266 [auto] Deleting a person confirms first, like every other destructive gesture in both apps. || check: `delete-person-no-confirm`. — data-loss sweep a6ee1934/ad17c703
- C267 [auto] A vocabulary/word-list edit merges with the latest synced state at write time, or re-reads immediately before saving, rather than saving a load-time snapshot; a concurrent addition on two offline devices is never silently dropped. || check: `vocab-concurrent-offline-add`. — data-loss sweep a6ee1934/a479987
- C268 [auto] Removing a synced audiobook's local download only frees storage once its upload to iCloud has completed; a still-uploading book's local copy cannot be removed. || check: `remove-download-mid-upload`. — data-loss sweep a9edcbf4
- C269 [auto] Removing a bookmark removes exactly the one nearest the tap and always confirms which/how many were removed; it is not exempt from confirmation because it's small. || check: `bookmark-delete-near-tie`, `bookmark-swipe-no-confirm`. — data-loss sweep a9edcbf4/a679e2cf
- C270 [auto] A shared-book import re-checks it isn't already in the library immediately before unpacking, not just at offer time. || check: `book-import-toctou-overwrite`. — data-loss sweep a679e2cf
- C271 [auto] A capture-inbox entry is deleted only after its import into a memo is confirmed to succeed; a failed import is retried, never silently discarded. || check: `capture-import-fails-after-inbox-delete`. — data-loss sweep af2965fa
- C272 [auto] A manual reprint keeps a note's prior `printedAt` stamp until the reprint itself succeeds; a failed reprint must not erase that the card was printed before. || check: `reprint-fails-loses-history`. — data-loss sweep a5e06d3a
- C273 [auto] A photo annotated with Markup keeps its un-annotated original recoverable; markup is never a destructive in-place overwrite. || check: `markup-overwrites-original`. — data-loss sweep a381c992
- C274 [auto] A capture whose transcription yields no text is kept (or the user is told) until the note is saved or explicitly discarded, never deleted on a silent success haptic. || check: `voice-annotation-empty-transcript-kept`. — data-loss sweep ac24e468

---

## §3 New open decisions

97. **D97 How long before an orphaned `.transcribing` memo is adoptable by any device.** A phone that died mid-recording and was later replaced leaves a `.transcribing` memo no device can ever pick up (R75/C264). Default: any device may adopt after 7 days, or the Mac always may (it's never "replaced").
98. **D98 Confirm threshold for closing an active recording.** R71/C262 — confirm on every X-tap, or only above a floor (mirrors the existing 0.4s auto-discard floor for Stop)? Default: confirm whenever `elapsed >= 1s` or any photo was captured; below that, discard silently as today.
99. **D99 Whether "Remove download" should offer a "keep syncing in background, remove after" option** instead of a hard block while an audiobook upload is in flight (C268). Default: hard block — simplest, matches "nothing of his is lost silently."

---

## §4 BUGS.md §1 additions (data loss)

- [ ] **D5 · Closing an active recording discards it with no confirm.** `RecordView.swift:502-505`
      → `LiveRecordingService.cancel()` + `PhotoCaptureService.discardAll()`. One tap of the X
      deletes the in-progress recording and every captured photo, permanently, zero dialog. Common,
      easy-to-mistap gesture. SPEC R71.

- [ ] **D6 · Editor commit silently blanks the raw transcript or the Mac's polished copy.**
      `NoteBodyView.swift:1182-1190` (raw → nil) and `:1173-1175` (polished → `""`, no guard at
      all); write side is `MemoDetailView.swift:1738-1748`'s unconditional `polishedBinding` setter.
      A select-all-delete in the editor wipes the note or the Mac's AI work product with nothing
      shown. SPEC R70.

- [ ] **D7 · Append races the original transcription and can silently drop text or audio.**
      `MemoDetailView.swift:92` "Add recording" has no gate on `transcriptStatus`;
      `MemoSaver.swift:573-671` vs `:792-837` both write `memo.transcript` unordered — whichever
      `save()` lands second wins, and the loser's clip is already deleted. A merge failure at
      `MemoSaver.swift:602` separately drops the audio silently, keeping only text. SPEC R72.

- [ ] **D8 · `recoverStuckTranscriptions` can overwrite a diarized/hand-edited transcript.**
      `MemoSaver.swift:864-880` has no `transcriptUserEdited` check; only reachable via a kill
      during an append on an already-diarized note. SPEC R73.

- [ ] **D9 · The shared `VaultWrite.writeAsset` deletes a vault attachment it doesn't own.**
      `Shared/Export/VaultWrite.swift:391-407`, `.file` branch — unconditional `removeItem` then
      `copyItem`, no ownership check. Same shape as D3 but INSIDE the engine both apps and C54
      treat as the protected lane, not the Desktop-only `VaultExporter.swift`. SPEC R77.

- [ ] **D10 · Corrupt JSON caches are adopted as empty and written back over the real file.**
      `Audiobook.swift:500-504,556-601` (mobile `library.json`, loses the whole audiobook shelf)
      and `SkriftDesktop/Models/AppSettings.swift:150-176` (Desktop `settings.json`, non-atomic,
      loses custom vocab/archive root/prompts on the next autosave after a torn write). SPEC R78.

- [ ] **D11 · Delete-person has no confirm and strips voice enrollment at tombstone time.**
      `PersonEditorView.swift:218-223`, `PersonDetailView.swift:116-120` (iOS);
      `PersonEditor.swift:102-109` (Mac) — one click, no dialog. The tombstone built in
      `NamesStore.swift:86-94` never carries `voiceEmbeddings` forward, contradicting C259. SPEC R79.

- [ ] **D12 · Custom vocabulary additions made offline on two devices can silently lose one.**
      `CustomWordsView.swift:39-43,63` (load-time snapshot overwrite) and
      `Shared/Pipeline/VocabularySyncCore.swift:43-48` (whole-list LWW, no merge). SPEC R80.

- [ ] **D13 · "Remove download" can delete the only copy of a not-yet-uploaded audiobook.**
      `SyncedAudiobooksView.swift:66-67` never checks upload-in-progress before deleting local
      audio, unlike the sibling `AudiobookSyncSheet` which does track `transfer`. SPEC R81.

- [ ] **D14 · A capture-inbox entry is deleted before its import is confirmed to succeed.**
      `CaptureInboxDrainer.swift:150` (video), `:221` (audio), `:383-403,531` (file) — on import
      failure the shared content lands in a plain temp file nothing revisits; zero UI error. SPEC R84.

- [ ] **D15 · Markup overwrites the original photo in place, no backup.**
      `MarkupQuickLook.swift:77-80`'s `.updateContents` mode writes markup edits into the SAME file
      as the original; once used, the un-annotated original is gone permanently. SPEC R86.

- [ ] **D16 · Voice-annotation audio is deleted even when transcription yields no text.**
      `CaptureVoiceAnnotate.swift:176` — deletes unconditionally after transcription, even on a
      confirmed-empty pass; a success haptic fires anyway. SPEC R87.

- [ ] **D17 · A shared-book import's already-have check is stale by unpack time.**
      `BookImportSheet.swift:118-144` checks `alreadyHave` once at offer time, never re-verifies;
      a concurrently-synced copy of the same book is silently overwritten. SPEC R83.

- [ ] **D18 · A `.transcribing` memo orphaned on a now-gone device can never self-heal.**
      `MemoSaver.swift:860-862`'s recovery gate + `Shared/Model/DeviceID.swift` (local-only, never
      synced) — a wiped/replaced phone permanently locks out that memo's transcription. SPEC R75.

- [ ] **D19 · A widget/Siri Record tap on a never-opened install is silently dropped.**
      `SkriftApp.swift`'s onboarding gate vs `RecordingIntentBridge`'s pending-start flag, which
      has no expiry (unlike `prestart()`'s 8s sweep). SPEC R76.

---

## §5 BUGS.md §2 additions (wrong behaviour, not loss)

- [ ] **Locked notes are fully readable once trashed.** `WayOutView.swift:169,329,375-401,407-434`
      render a locked note's title/transcript/photos with no auth; none of the 3 delete entry
      points (`MemosListView.swift:483-488,516-518,1089-1091`) check `memo.locked` first, and
      `copyTranscript`/`copyableText` copy a locked note's raw transcript with one tap. SPEC R88.

- [ ] **`NotesRepository.save()` swallows a second consecutive failure.** `NotesRepository.swift:
      259-268` retries once, then only `DevLog`s — no rating/delete/restore/name-link/Mac-polish
      write reaches the UI as an error on persistent failure. SPEC R89.

- [ ] **`ImageMarkers.insert` reverses marker order on a position tie.**
      `Shared/Pipeline/ImageMarkers.swift:40-60` — two photos in one pause, or a fast burst, land
      in reversed manifest order. Violates C13. SPEC R74.

- [ ] **Bulk multi-select delete has no confirmation.** `MemosListView.swift:1031-1035,1044-1051` —
      a stray tap while N notes are selected trashes all of them, no "Delete N notes?" dialog.
      Reversible (soft delete), so low severity, but no safety net.

- [ ] **`importAudioClipsAsync` deletes every source clip even when one was unreadable.**
      `MemoSaver.swift:171-172` — `mergeAudioSync` (line 208) skips a corrupt clip with only a
      DevLog, but its source file is still deleted with the good ones; the merged memo silently
      lacks that clip's content.

---

## §6 Confirmed still open, already tracked (not re-rowed)

- **D1** (`Shared/Naming/NamesStore.swift:50,28-33`) — re-confirmed by `a479987` (Shared) and
  `a6ee1934` (Settings+Names).
- **D2** (`SkriftDesktop/.../ProcessingCoordinator.swift:368-380` + `BatchRunner.swift:47-66,
  103-107`) — re-confirmed by `ad17c703` (Desktop); `a283505d` (mobile Recording) confirms this
  shape does NOT reproduce in `TranscriptionService.swift` — D2 stays Desktop-only.
- **D3** (`SkriftDesktop/.../VaultExporter.swift:233-234,268-269,294-295`) — re-confirmed by
  `ad17c703`, now three lanes in that file (was two when last recorded).
- **D4** (`LiveRecordingService.swift:433`) — re-confirmed by `a283505d`.
- **R42/R59** (`AudiobookBookmarkSyncCore.swift:41`; `Bookmark.swift:46-66`; `AudiobookCloudSync.
  swift:472-486` `receiveTranscripts` unverified) — re-confirmed and traced end-to-end by `af2965fa`
  (Services/Audiobooks), including the exact LWW-stamp mechanism that makes R42 permanent.
- **BUGS §2 "A person added on the phone can never be linked"** (`NamesListView.swift:202`,
  `aliases: []`) — re-confirmed by `a6ee1934`, which also surfaces a sharper reading: on a
  canonical NAME COLLISION, this same call silently wipes the EXISTING person's real aliases, not
  just leaves the new person alias-less. Same fix (seed/merge in `AddPersonView.save()`), worth
  noting when scheduled since the collision case is a live data-loss path, not just a dead link.
- **C163** (destination-change leaves the old exported vault file behind) — re-confirmed by
  `ad17c703`: `MacCloudMetaSync.setDestination` still only flips the field, no cleanup triggered.

---

## §7 Summary for Tuur

The sweep found three shapes repeating across both apps: silent races on the same field (append
vs. re-transcribe, editor commit vs. Mac polish), corrupt-file-adopted-as-empty-then-saved-back
(now hit library.json and settings.json, on top of the already-known names.json and
bookmarks.json), and missing confirm dialogs on genuinely destructive one-tap actions (closing an
active recording, deleting a person, removing an audiobook download). The worst is closing an
active recording — `RecordView.swift:502-505` — one tap of the X permanently deletes the whole
in-progress take and every photo with zero confirmation, on an ordinary, easy-to-mistap gesture.
20 new required-difference rows (R70-R89), 14 new clauses (C261-C274), 3 new decisions
(D97-D99), 15 new BUGS §1 bullets, 5 new BUGS §2 bullets.
