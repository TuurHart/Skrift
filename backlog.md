# Skrift — Backlog

Deferred ideas and features, captured during the 2026-06 overhaul planning so they're not lost. Not scheduled — pull from here when ready.

## ⭐ CloudKit-only sync epic — retiring Bonjour (2026-07-06, on `main`)

Building CloudKit as the sole phone↔Mac transport, then deleting Bonjour. Plan in
`~/.claude/plans/do-all-the-work-lively-sedgewick.md`. Phases 1–3 built + committed; verify-first.

**Device test session (2026-07-06, Dev, CloudKit-only both ends):**
- ✅ **B — memo round-trip**: phone → Mac (via CloudKit, Bonjour off) → enhance → `MemoEnhancement`
  write-back → phone shows "✦ Polished on your Mac". Title + polish confirmed. PASS.
- ✅ **C — Bonjour retired UX**: phone Settings has no Pair-a-Mac (just "iCloud sync"); no stale
  "Waiting" pill. PASS.
- 🔧 **A/D — names + vocab looked broken, were mostly UI/timing**: the name DID sync (landed in the
  Mac's `names.json`) but the **Mac Names settings list didn't live-refresh**, and edits only pushed
  the carrier on app foreground, not on edit. FIXED (`23a2eb1`/`79975a7`): phone pushes
  NamesCloudSync/VocabularyCloudSync on edit; Mac Names list reloads on `.namesDidChangeFromSync`.
  Re-test owed.

**Feature requests / parity gaps from the session:**
- ✅ **DONE — "significance" → "Importance" on the Mac**: the review label + a11y label + Settings help
  now read "importance" (internal `Significance*` symbols unchanged), matching the phone. (`SignificanceCircles`, `SettingsView`).
- ✅ **DONE — rename discoverability**: the phone person editor's Full-name help now says "Change it to
  rename this person" when editing an existing person (`PersonEditorView`).
- ⬜ **Mac Names screen should match the phone's** person UI (look + interaction parity) — BIG, mock-first.
- ⬜ **Mac in-place name-linking should match the phone**: on the phone a linkable word ("Will") shows
  dotted/tappable immediately on the raw transcript; on the Mac the dotted suggestions only appear
  **after enhance** (the sanitise pass), and aren't as interactive. Want parity (immediate, tappable). BIG.

**Still owed in the epic:** Phase 2a (off-main CloudKit reconciler I/O), Phase 4 (deploy prod CloudKit
schema + device round-trip), Phase 5 (delete the Bonjour code — held until CloudKit-only is signed off).

**Test session 2 (2026-07-06 later — after push-on-edit + Mac Names redesign):**
- ✅ **A/D re-verified**: a deleted person + custom words both synced phone→Mac (CloudKit LATENCY, not
  instant); ✅ B re-confirmed (memo round-trip + polish back). CloudKit-only sync is effectively verified.
- 🐛→✅ **FIXED — rename was genuinely blocked**: the phone Names list opens `PersonDetailView` (voice +
  delete ONLY, no name/alias editing; the full `PersonEditorView` was reachable only from the review flow).
  Added an **Edit** button on `PersonDetailView` → opens the editor (build 28).
- 🐛→✅ **FIXED — stray vertical line down the phone Names list**: `PersonRow` used `.overlay(Divider()…)`,
  which renders a full-height VERTICAL divider (iOS-26 SwiftUI quirk) → replaced with a 0.5pt `Rectangle` rule.
- ⬜ **NEW — live bidirectional editing (Apple-Notes-style)**: a MANUAL edit on the Mac (note body / title)
  does NOT sync back to the phone — only the enhance-time `MemoEnhancement` write-back does. User wants
  "edit anywhere, syncs everywhere". Needs a debounced write-back on Mac-side edits. BIG-ish.
- ℹ️ **Latency expectation**: CloudKit is seconds (with silent push), not Apple-Notes-instant; push-on-edit
  helps but CloudKit propagation + the Mac's import-triggered reconcile add delay. Partly inherent.

## 🐛 Post-0.2.0 prod findings (2026-06-26, after promoting prod to build 22) — TRIAGE

User hit these on the freshly-promoted PROD apps. Diagnoses below; fixes owed (do on Dev, verify,
re-promote — don't hot-patch prod).

1. **Phone memo won't sync to Mac; phone stuck "syncing…".** Most likely root: the **prod CloudKit
   PRODUCTION schema was never deployed** (all on-device testing was on Dev, per the data-safety rule,
   so only the Development schema exists). The phone's `NSPersistentCloudKitContainer` can't push to a
   container whose Production schema lacks the record types → `isSyncing` hangs. **Action (no code):**
   CloudKit Dashboard → `iCloud.com.skrift.mobile` → compare Development vs **Production** record types
   → **Deploy Schema Changes** (now includes `MemoEnhancement`). THEN, for the Mac to *receive* phone
   memos, the prod Mac needs **Settings → cloudKitMacSync ON** (opt-in, OFF by default). I under-sold
   this as "polish-only" earlier — it's the whole prod CloudKit path. ⚠️ Confirm by dashboard check.
2. **"Waiting" sync pill is stale.** `Memo.statusKind` returns `.waiting` for `significance>0 &&
   syncStatus != .synced` — but `syncStatus` is the **Bonjour/HTTP upload** state, not CloudKit. With
   CloudKit the spine, the pill is misleading. **Fix:** drive the pill off CloudKit sync state (or drop
   Waiting/Synced for non-Bonjour users). `MemoDisplay.statusKind`.
3. **Name added on the phone isn't recognised in a note (e.g. "IJsbrand").** ROOT: `AddPersonView`
   (`NamesListView.swift`) saves `upsert(canonical:, aliases: [], short:)` — **empty aliases** — and the
   shared `Sanitiser` matches ONLY by `p.aliases` (no implicit canonical alias). So a phone-added person
   is unlinkable. NOT a capitalization issue (matching is `.caseInsensitive`). **Fix:** seed the alias
   from the name on add (the new `PersonEditorView` already does `if aliases.isEmpty { [name] }`; apply
   the same in `AddPersonView`), and/or make the `Sanitiser` treat the canonical's key as an implicit
   alias (broader; affects desktop). Existing IJsbrand needs an alias added after the fix.
4. **Can't select a word in the transcript and "add as name".** Task-1 added tap-a-RECOGNISED-name →
   resolve, but NOT select-arbitrary-text → add-person/alias (the desktop has it via `onAddName`/
   `onAddAlias`). **Fix:** a UITextView selection → "Add as new person / alias of…" action in
   `TranscriptEditor`. Compounds #3 (no way to fix IJsbrand inline today).
5. **Desktop shows EVERY note as a conversation; no re-transcribe button.** A note is a "conversation"
   when its transcript has **≥2 `**Name:**` headers** (`SpeakerTranscript.parse`), and the note-detail
   **Re-transcribe is hidden for conversations** (`NoteActions.canRetranscribe = … && !isConversation`)
   → can't undo it from the detail. **Workaround NOW:** right-click the note in the **sidebar** →
   **Re-transcribe** (that menu item is NOT conversation-gated, `SidebarView.swift:527`). **Investigate:**
   why do the notes carry turn markers — stale diarized output baked into the stored transcript? (cf.
   `project_conversation_namelinking` "brackets on every mention"). May need a bulk un-diarize/re-transcribe.

## ✅ Phone polished-text display — STANDALONE Phase 4 (2026-06-26, BUILT + sim-verified)

The Mac→CloudKit polish (`MemoEnhancement`) is now VISIBLE on the phone — the thing the user was
waiting on to "see results" of the round-trip. Built to `mocks/phone-polished-display.html`.

- **One editable body, starts from the polish — no toggle** (user decision, mirrors the Mac). When a
  `MemoEnhancement.hasContent` exists for an ordinary monologue memo, the detail body shows the Mac's
  copy-edit; name tiers + tap-resolve (task 1) apply to it. Edits write `MemoEnhancement.copyedit` +
  stamp provenance (this phone, now) → sync as the source of truth.
  - **No clobber** — verified in code: the Mac only processes `enhanceStatus != .done`
    (`ProcessingCoordinator.needsProcessing`); a done memo is never auto-re-polished. **No drift** —
    raw transcript = the contract input, polished(+edits) = the output; nothing re-derives polished
    from raw once it exists.
- **Title chooser** = a compact bottom sheet (Suggested / From-the-recording / your own) — solves the
  PARKED phone title-UI problem (the desktop's two-card chooser is cramped on a phone). The detail
  title defaults to the Mac's suggestion when no user title is set.
- **Summary card** + **"✦ Polished on your Mac" provenance caption**.
- **PROPORTIONAL karaoke** on the polished body (word timings pin to the RAW words; the polish rewrites
  them, so v1 tracks progress, like the Mac). **⭐ FAST-FOLLOW owed:** re-align polished words → raw
  timestamps (token diff: unchanged words inherit exact time, new ones interpolate; mostly-deletions →
  mostly-exact) for word-exact karaoke + "scrub to a word in the polished text and fix it by ear."
- Files: `MemoDetailView` (macPolish/polishedBinding/summaryCard/title chooser/provenance),
  `TranscriptBodyView`+`TranscriptEditor` (polished binding + proportional karaoke),
  `NotesRepository.enhancement(forMemo:)`. Verified on the iPhone 17 sim (`-seedPolished` +
  `PolishedDisplayUITests`). Mobile 498 unit tests green. **Owed:** device eyeball; the list row
  could also prefer the enhancement title (detail does); proportional-karaoke device eyeball.
- **Drive-by fix:** `MemoDate.label`/`group` used `Calendar.isDateInToday/isYesterday` (wall-clock,
  ignored the injected `now`) → the date tests were non-deterministic across midnight. Switched to a
  day-delta against `now` (identical in prod, deterministic in tests).

## ✅ Phone in-place name-linking (2026-06-25, BUILT + sim-verified)

Built the Mac review's name-linking as an iPhone touch surface, to the signed-off interactive
prototype `Skrift_Native/SkriftDesktop/mocks/phone-name-linking.html` (its "Build notes — locked
decisions" are the spec). The phone keeps the transcript **RAW** and re-derives tiers on demand —
the mobile↔Mac contract (phone sends RAW, Mac links names) is **untouched**.

- **Shared engine:** `Sanitiser.nameSpans(inRaw:)` (+ `NameSpan` in `Shared/Naming/NameMatch.swift`)
  — a sibling to `process()` that records linked/suggested/ambiguous/plain spans over the RAW text
  (no `[[brackets]]` written), reusing the SAME `Overrides`/first-mention/`suggestedOccurrences`
  machinery → tiers can't drift from what `process()`/the export links. 9 parity tests.
- **Persistence:** additive `Memo.nameResolutionsData` JSON blob (CloudKit-safe) →
  `NameResolutions{unlinkedNames, namePicks}`; `linkName`/`keepNamePlain`/`clearNameResolution`.
  Uniform model: link = `namePicks[alias]=canonical`, keep-plain/unlink = silence (`""`), undo = clear.
- **UI (always-editable transcript):** 4 tiers styled in place (linked solid #9d8ff7 / suggested tan
  dotted / ambiguous accent-wash+purple-dotted / plain-kept faint dotted); tap a name → native
  confirmationDialog (candidates / New person… / Keep as plain text; linked → Switch person when
  shared / Unlink+Undo-toast / Open card). "People in this note" chip bar. Editable `PersonEditorView`
  (Full name/Aliases+demo/Short/Voice). Tap detects the name (layoutManager rect) then resigns first
  responder so the keyboard yields — robust on UITextInteraction; editor stays always-editable.
- **Verified** on the iPhone 17 sim (`-seedNameLinking` route + `NameLinkingUITests`): detail tiers,
  resolve sheet, chip sheet, person editor all screenshot-checked. Mobile 498 unit tests green.
- **Owed:** device eyeball; conversation (`SpeakerTurnsView`) tap-to-resolve is monologue-only for now
  (conversations already render alias-display links via the conversation linker).

## 🐛 Audiobook import — MP3 rejected as "not a playable audiobook" (2026-06-24, FIXED)

User imported a valid MP3 audiobook part ("Made to Stick-Part02.mp3", 36.6 MB, 76:14 per
Files) via the normal in-app audiobook add → got **"That file doesn't look like a playable
audiobook."** Root cause: every `AVURLAsset(url:)` in the audiobook path was built **without**
`AVURLAssetPreferPreciseDurationAndTimingKey`. For MP3s (VBR rips, large ID3 tags) AVFoundation
estimates duration lazily and returns **0 / indefinite**, so `AudiobookImporter.importSingleFile`'s
`guard tags.duration > 0` threw `.unreadable`. m4b/m4a imported fine (the two existing library books),
which is why only the MP3 failed. **Fix:** `AudiobookImporter.makeAsset(url:)` helper sets the precise
key; used in `readTags`, the multi-file duration loop, and both `AudiobookSession` AVPlayerItem builds
(precise timing also tightens MP3 seek + read-along word alignment). **⚠️ Device verify owed** — fixed on
Linux, no sim gate here; build+install Skrift Dev and re-import the same MP3.

**Ultracode sweep (2026-06-24) — same anti-pattern, 3 more sites fixed, 1 refuted.** Fanned out
agents over every `AVURLAsset`/duration site repo-wide, classified each for MP3-reachability +
whether precise timing changes correctness, then adversarially verified. Confirmed + fixed:
- `QuoteCaptureProcessor.exportSpan:369` (**HIGH**) — quote-span export off an MP3 book drifts late
  (no duration guard → silent mis-alignment of the core audiobook-capture feature).
- `MemoSaver.appendAudio:486` (**MED**) — appending a recording to a memo imported from an MP3
  misplaces the splice offset + writes a wrong merged duration (the `base` asset).
- `RunFile.swift:58` (**MED, DEBUG `-chunksim`**) — bare sync `.duration` on an MP3 returns
  0/indefinite → chunk loop never runs; switched to precise async `load(.duration)`.
Refuted / left alone: `RunFile.swift:81` (the `-chunksim` A/B harness deliberately shows real
AVAssetExportSession behavior); all `IngestService` + `AudioMetadata` + video-import + test sites
(video/AAC-only or metadata-only — not MP3-reachable; not blanket-edited). **⚠️ Device verify owed.**

## 🐛 Audiobook import — recurrence, DIFFERENT root cause (2026-07-05, FIXED + device-verified)

Same "doesn't look like a playable audiobook" symptom on the Frankl multi-part rip — but NOT the
precise-timing bug above. Devlog diagnostics (`copiedBytes=10227234 duration=0.0`) + Mac forensics
proved parts 08+09 are **100% null bytes** (hollow files from a failed 2022 bulk copy — no audio
exists in them; unrecoverable, re-rip to fill). One bad part rejected the WHOLE book, while Bound
silently imported broken zero-length chapters. Fixes (`AudiobookImporter`, build 25, device-verified):
- **Resilient multi-part import** — skip unreadable parts, import the rest, alert "Imported with
  skipped parts" naming each file (never a silent gap, never a whole-book reject).
- **`robustDuration`** — AVAudioFile frame-count fallback when `load(.duration)` returns 0.
- **`materializingCopy`** — coordinated read + `startDownloadingUbiquitousItem` so an un-downloaded
  iCloud/File-Provider pick can't copy a placeholder (the other latent cause of this symptom).
Devlog lines `SKIPPED (unreadable)` + `copiedBytes=` now say WHICH failure it was, ending the
guess-loop. User owes: re-rip parts 08/09; optional hollow-file scan of the Books folder.

## Device-testing feedback — 2026-06-21 (6 live notes, pulled + verified)

Pulled from the dev phone via the **App Group container** (`group.com.skrift.mobile.dev` →
`Library/Application Support/default.store`, live, 83 MB, modified during the pull). ⚠️ **The
`pull-phone-feedback` skill's documented path (`com.skrift.mobile.dev` per-app container) is STILL the
06-12 stale orphan** — confirmed again this round; the live store is in the App Group container and is only
reachable with `devicectl --domain-type appGroupDataContainer` when the CoreDevice service tunnel is up
(it was, this time). 6 non-deleted notes (matched what the user saw in-app); 65 soft-deleted tombstones
ignored. Second-agent verify done. Raw dump at `.claude/memos_dump.txt`.

### P0 — 🐛 DATA-LOSS BUG: append after clearing a pasted note deletes the WHOLE note
**The bug the user "ran into."** Lost a ~3-minute note. **Exact repro (load-bearing details):** (1) start a
**new note**; (2) **paste** text into the body; (3) decide you don't want it and **delete/clear** that
pasted text; (4) **append** to the note with the **+ button**. → the append commits, and *then the whole
note gets deleted* ("your whole note gets deleted after it's added"). Destruction is in the **append-commit
path on a note whose body was paste-then-emptied**, not in the paste or delete step. User: "something we
couldn't have caught… this is strange behavior." → **P0, reproduce + fix first.** (memo 06-21 11:12)

**🔎 INVESTIGATION 2026-06-21 (static read + unit probe) — MemoSaver EXONERATED; suspect = CloudKit.**
Traced every delete path: all three (`softDelete`/`delete`/`permanentlyDelete`,
`NotesRepository.swift`) are DevLog-logged and fire ONLY from explicit user actions (detail ⋯ Delete,
list swipe) or the trash-retention purge — there is **no auto-delete-of-empty-notes** anywhere, and
`recoverStuckTranscriptions` only re-transcribes. The append path
(`MemoSaver.appendRecordingAsync`) re-fetches the memo, handles an empty existing transcript
(`existing.isEmpty ? newText : …`), and never deletes. New regression test
`testAppendAfterClearingBodyKeepsMemoAndLandsText` (clear body → append) **passes** (451/451 unit) →
the append path is safe. The store moved to a **CloudKit-backed** `NSPersistentCloudKitContainer`
(iPhone↔iPad private-DB sync) since this feature era — the prime suspect is a CloudKit remote-change
import deleting/merging the record, which a CloudKit-OFF unit store can't reproduce.
**Instrumentation added** (`5c…`): caller-frames breadcrumb on `softDelete` + a "editor cleared body
→ transcript=nil" timeline marker, so a device repro is conclusive — **if the note vanishes with NO
delete line in `devlog.txt`, it's CloudKit, not our code.** **OWED (needs user): device repro** of
new note → paste → clear → append → pull `devlog.txt`; also confirm whether the lost note is in
**Recently Deleted** (recoverable) and whether the iPad was syncing at the time.

### P1 — 🐛 Diarization / speaker-ID does not survive backgrounding (hypothesis) + ✨ wants a progress bar
Same session, "conversation" mode, 2 speakers. **(a) ✨ FEATURE (loved — "I love this"): a progress bar
while identifying speakers.** Diarization runs long enough that the user backgrounded the app waiting — the
duration itself is a data point. **(b) 🐛 BUG (unconfirmed — user *thinks*):** "it was identifying speakers
for a long time, then I switched out of the app and then I **think** it stopped. Just didn't anymore."
Hypothesis: the speaker-ID `Task` dies on app suspension — **same class as the 06-17 stuck-transcription
bug** (fire-and-forget `Task` can't survive suspend), but on the diarization path. Keep the "user thinks"
hedge — not a verified repro. The progress bar (a) would also surface whether (b) is a true stall vs. just
slow. (memo 06-17 20:20)

**✅ BUILT 2026-06-21 (awaiting device-eyeball).** (b) **Keep-alive + relaunch recovery** mirroring the
06-17 stuck-transcription fix: new additive `Memo.pendingDiarizationTarget: Int?` (0=Auto, N=forced) set
before `MemoSaver.diarizeExisting` and cleared on completion; a kill mid-identify leaves it set →
`recoverStuckDiarizations()` (new, scoped like `recoverStuckTranscriptions`: own-device, audio +
word-timings present) re-runs it once per launch from `SkriftApp`. "Split speakers" now also runs under a
`BackgroundTask.run` UIKit assertion so brief diarizations survive backgrounding without a relaunch.
(a) **Honest progress** (no fake % — FluidAudio's `processComplete` is opaque): the `.identifying` banner
now shows a ticking `· m:ss` elapsed (`DiarizationStatus.labelWithElapsed`, driven by a `TimelineView`) +
a "this can take a while — it keeps going if you leave" subtitle. **15/15 MemoSaverTests green** (2 new
recovery tests: re-runs a stuck memo + skips non-in-flight). OWED: device-eyeball the elapsed readout +
a real background-mid-diarize → return/relaunch cycle.

### P1 — 🔎 CONFIRM: transcription engine now "always warm", much faster, NOT eating battery — what changed?
User noticed (in **prod AND dev**) the engine is now always warm, "way faster," and "not really taking
batteries." Tone is pleased-but-suspicious — "something changed… what happened?" **Action: confirm what
changed (likely the pre-warm booster / always-warm path), confirm it's intentional, and verify it isn't
silently draining battery in some state.** File-and-document, not just log as praise. (memo 06-20 12:33)

### ✨ Auto-stop live captions on a timer — ✅ BUILT 2026-06-22 (build 19)
Feature idea (2026-06-22): for a long recording you don't need live captions the whole time — after N
seconds, auto-drop live captioning (record + waveform + `.m4a` keep going; transcript comes from the
one-shot pass at stop). Saves battery on long messages. **Decided:** a **Setting**, default **1 minute**
(user: "default one minute, that's great"). **Built:** Settings → "Stop live captions after: Never / 30s /
1 min / 2 min" (`@AppStorage("liveCaptionAutoOffSeconds")`, shown only when Live transcription is on);
`RecordView` watches `service.elapsed` and calls the existing `setLiveTranscription(false)` once past the
limit (`autoOffFired` guards re-fire if you tap captions back on). **Transient** — it never flips the sticky
`liveTranscription` preference; `LiveRecordingService.start()` re-seeds from the pref each recording so a
long recording's auto-off can't silence the next. The toggle button + caption now reflect the EFFECTIVE
state (`liveTranscription` made `@Published`; RT tap reads `tapLive`, so race-free). 455/455 unit green.
**Device-eyeball owed** (sim has no real recording). May drop the setting later if it doesn't earn its keep.

### P2 — ✨ Share a PDF into Skrift and have it persist as a source
User tried to share a PDF to Skrift via the share sheet and "have it live in there" — couldn't. Wants a PDF
to **persist as an imported source** (parallels the existing share-to-import audio/video path), not a
one-shot read. Extends the planned **"Unified source taxonomy"** (PDF is already a listed source type — see
below) → make PDF a first-class shareable/importable source. (memo 06-20 10:52)

**✅ BUILT 2026-06-21 — MVP (persist + open), awaiting device-eyeball.** Shares a PDF (or any document)
into Skrift via the share extension and persists it as a `.file` capture: the share-extension activation
rule gains `NSExtensionActivationSupportsFileWithMaxCount`; `SharePayloadLoader.loadFile` copies the doc
out of the provider (no in-memory load); `ShareViewController.completeFile` bypasses the annotation sheet
(mirrors the video path) → writes a `"file"` inbox entry (`CaptureInboxEntry.fileName`/`fileDisplayName`);
`CaptureInboxDrainer` copies the doc into the recordings dir (`file_<memoUUID>.<ext>`, reinstall-safe
relative path in `SharedContent.filePath`) → a `.file` capture memo; `Memo.sharedFileURL` resolves it; the
detail shows a doc card with **Open** → `quickLookPreview`. `permanentlyDelete` now also drops the doc
blob. 455/455 unit green (new drain test). **PINNED for later (user):** PDF as a full text-extracted /
readable source (PDFKit → transcript → name-link/enhance/Obsidian; read-along surface). **OWED:** device
test — share a PDF from Files/Books → confirm the capture + Open. (Share sheet can't be exercised on the sim.)

> **⚠️ P0 REFRAMED 2026-06-21 (user correction) — NOT a deletion, the APPENDED TEXT didn't land.**
> The note was **never deleted** (hence not in Recently Deleted): it stayed, but was **empty after the append
> recording stopped** — the appended text never landed. So this is the **append-transcription path**, the
> same family as the 2026-06-10 "append silently adds NO text" fix, NOT CloudKit/deletion. The
> `testAppendAfterClearingBodyKeepsMemoAndLandsText` test passes because its seeded transcriber returns text
> → the logic is correct **when transcription returns something**; on device the append clip is coming back
> **empty**. The note ends up blank only via: the `audioURL` guard bailing, the engine returning no text
> (silent-restore branch, no Error pill), or the landed text being clobbered by the editor's stale empty
> buffer. `appendRecordingAsync` now logs each branch (start/transcribe-outcome/no-text/failed/landed) +
> the existing "editor cleared body → nil" marker catches a post-append clobber. DEV build **(15)** pushed
> 2026-06-21. **OWED (user):** repro append → I pull `devlog.txt` to see which branch fires.

### P2 — 🎨 Audiobook reading-mode: bookmark icon placement follow-up (post build-14)
Refinement on the just-built reading-mode bookmark UX. Currently the bookmark icon "is still at the bottom"
with awkward negative-space margin. Want it **inline with the "selected text" button, far left** — bookmark
becomes part of the selected-text affordance: tap it to **visualize the bookmarked text and toggle it
on/off** (save/unsave per selection). i.e. bookmark state is per-selection + visualized, not a global bottom
button. (memo 06-19 21:38)

**✅ MOCK (`mocks/audiobook-bookmark-fold.html`) → BUILT 2026-06-21 (build 16).** Clarified on a device call:
the real pain was that the purple margin glyph **wasn't tappable to remove** (the bottom "Mark" button only
toggled at the playhead). Shipped the **page-corner-fold** model: in `ReadAlongView` each line now has a
full-height **tappable left gutter** — tap to fold (bookmark this sentence's global position), tap again to
unfold (remove); the liked `bookmark.fill` marker stays as the indicator + the faint line tint. The bottom
**Mark button is removed** from `AudiobookPlayerView.utilityRow` (`markButton`/`toggleMark`/`isCurrentSpotMarked`
deleted; new `toggleBookmark(atGlobal:)` wired via `onToggleBookmarkAt`). Tap the TEXT still seeks; the TOC
sheet's Chapters/Bookmarks tabs still jump (unchanged). 455/455 unit green. **Trade-off:** bookmarking an
**un-transcribed** (audio-only, no read-along text) book now has no affordance — flag if a fallback is wanted.

**🔧 build 17 fix (device feedback on 16):** tapping never REMOVED a bookmark — the remove matched within
±2 s of the sentence START, but a bookmark sitting elsewhere in a long passage (e.g. dropped at the
playhead) never matched. Fixed: the reader passes the tapped line's whole GLOBAL span and the parent lifts
any bookmark **inside that span** (`toggleBookmark(inSpan:)`), so it removes the exact one the line shows.
Also switched the gutter from a nested `Button` to a single **`SpatialTapGesture`** on the line (left of
text = fold/unfold, text = seek) so the tap is reliable in the scroll view. Mock
(`mocks/audiobook-bookmark-fold.html`) re-aligned to the app's marker and redeployed.

**🎨 build 18 (user: "i want the dog ear, it's a good idea"):** swapped the marker from the bookmark glyph
to an actual **folded page corner** — a `DogEar` Shape (right-angle at the line's top-leading, hypotenuse
TR→BL) filled accent with a soft shadow, scale-in transition on fold; the faint tint stays. Mock restored
to the matching dog-ear (clip-path triangle). Toggle logic unchanged (span-aware + spatial-tap). Build 18.
Device-eyeball owed.

**✅ BUILT 2026-06-22 (build 20) — active-line bookmark affordance.** Bookmark *creation* is now gated to the
**active (white, now-playing) line**, which shows a **hollow dog-ear OUTLINE** in its gutter as the affordance
("you can fold THIS spot" — fixes the invisible-gutter discoverability gap; matches "mark where you are as you
listen"). Tap the outline → fills. **Removal stays tap-the-filled-marker** (confirmed: "retapping it removes
it" — any filled dog-ear taps off). Non-active, unbookmarked lines have no gutter marker and a gutter tap
just seeks. Consequence (user-confirmed): you can only CREATE at the playback spot; to mark a line read ahead,
tap it to seek there first. `ReadAlongView.line` — `isCurrent` drives the outline (`DogEar().stroke`) + gates
the spatial tap to `marked || isCurrent`. 486/486 unit green. Device-eyeball owed.

### P2 — 🧱 EPIC: note-editing experience needs its own focused sprint
> 📌 **PINNED FOR A FRESH CHAT (2026-06-22).** The user wants to start this as its own session. Resume here:
> read the design thinking + the A/B/C fork + the B1-vs-B2 title question below, then go MOCK-FIRST.
> Recommendation on record: **option B** (re-found the body on a natively-scrolling text view), likely
> **B2** (pinned title only; tags/significance scroll with the body). First step in the fresh chat = mock
> **B1 (Notes-style, title scrolls away) vs B2 (pinned title)** side by side for the user to pick.

"The editing of the notes in the app is… not a very good experience." User wants a **focused, holistic
study of note-editing** (Apple Notes as the bar, maybe better apps too) as its **own separate sprint** —
not piecemeal. **Concrete first item — ⚠️ the 06-21 memo's "tags" was an ASR mishear of "TEXT"
(clarified 2026-06-22):** **text SELECTION doesn't auto-scroll.** Double-tap to select → drag the end
handle DOWN → the note doesn't scroll with the drag, so you can't extend the selection past what's on
screen. That's the real annoyance. Plus the wider pass: body editor, significance, photos, speaker turns.
(memo 06-21 11:22 + 06-22 clarification)

**↩︎ CORRECTION 2026-06-22.** The earlier "comma-separated tags" quick win was built off the MIS-HEARD word
("tags" should've been "text") — the user never asked for it. **KEPT anyway** (user: "the comma is actually
nice… we can keep that"); `Memo.parseTagInput` stays, easily reverted on request. The `FlowLayout` does NOT
have a scroll bug. The real text-selection-autoscroll issue above is the actual ask and belongs to THIS
sprint, not a one-off.

**🧠 DESIGN THINKING 2026-06-22 (pre-mock).** Framing: a Skrift note = a **transcript** (editable text +
inline `[[img]]` + speaker turns + title/tags/significance + capture quote), NOT a freeform doc → bar =
"native text-editing *mechanics* (Apple Notes) + keep the transcript richness." **Root-cause diagnosis:** the
editable body `TranscriptEditor` is a `NonScrollingTextView` (UITextView, scrolling OFF, offset pinned 0)
inside the page's one outer ScrollView — a deliberate unified-scroll trade (text + images + metadata in one
flow) that is ALSO why native editing breaks: a non-scrolling textview can't autoscroll a selection drag
(the reported bug), can't run the magnifier/edge handles, can't keep the caret in view while typing (the old
"paste jumps to top" hack = same wound). **Central fork:** A) bridge — manually drive the outer ScrollView
to follow selection/caret (cheap stopgap, hand-reimplements UIKit one behavior at a time); **B) re-found the
body on a natively-scrolling UITextView** with title/tags/significance as a scrolling header + TextKit image
attachments → selection/magnifier/edit-menu/undo/caret-follow all free (**recommended**); C) full TextKit 2
rich editor (overkill, transcripts don't need formatting). **Experience layer (fork-independent):** a
keyboard accessory toolbar (none today — biggest "native" jump), undo/redo, a real tag CHIP editor with
autocomplete from existing tags (the actual "select a lot" need = pick not retype), smart paste.
**Must-not-break:** inline images · edit/play/read mode swap (`TranscriptBodyView`) · karaoke · capture-quote
protection · speaker-turn editing · `transcriptUserEdited` trust flag · save-now. **Path:** (optional) ship
A as a stopgap; then the real sprint MOCK-FIRST on B + toolbar + tag editor. Awaiting user direction.

**🔬 STUDY 2026-07-06 (fresh-eyes code audit — sprint kicked off; roadmap node `NEdit`).** Confirms fork B
and adds the PERF story (code-derived; device magnitudes unprofiled):
1. **Per KEYSTROKE:** the page re-evals and runs the full `Sanitiser.nameSpans` regex scan 2–3×
   (`MemoDetailView.transcriptNameSpans` is an uncached computed property read in several places) +
   `context.save()` (disk + CloudKit churn) + a full-document TextKit relayout (self-sizing
   `sizeThatFits`) → typing cost O(note length × roster size), on-main.
2. **During PLAYBACK:** `AudioPlayerModel`'s 0.05 s timer republishes `currentTime` at 20 Hz through the
   whole page tree; tap-to-seek karaoke (default ON) is one SwiftUI `Text` PER WORD re-diffed per tick.
3. **Mode swaps** (edit↔karaoke) rebuild the body and even change inline image sizes (editor attachment
   cap 320 pt vs `ImageEmbed` fixed 160 pt — a visible jump when Play starts on a photo note).
Scar tissue of the non-scrolling choice: `NonScrollingTextView` offset pin, selection carry-over,
`sizeThatFits` clamps, THREE karaoke renderers (single-Text attr + FlowLayout word grid +
SpeakerTurns' own pair) + `KaraokeWordLayout`. Missing table stakes (grep-verified): keyboard accessory
bar, undo/redo UI, find-in-note, photo tap→viewer, Dynamic Type (all fonts fixed-size).
**KEY MOVE (sharpens B):** ONE scrolling UITextView renders edit AND karaoke — the highlight is
attribute painting on the same textStorage (changes at word rate, not 20 Hz), tap-to-seek = character
hit-test, find = `isFindInteractionEnabled`, undo = native; deletes the mode swap + both monologue
karaoke renderers. Metadata (tags/significance/summary/quote block) = header content inside the scroll
(B1: title in-flow too / B2: title pinned). Free wins during the rebuild: UITextView find, native undo
(+ accessory buttons), Writing Tools on AI-capable devices (NOT the iPhone 13), Dynamic Type, photo
tap→QuickLook (reuse the capture path), selection→"Save highlight" hook (feeds P6 quote cards). Also:
tapping a tag chip DELETES it silently (`removeTag`) — the chip editor must fix that. Perf hygiene
regardless of fork: debounce transcript saves (~1 s idle + end-edit + disappear), memoize nameSpans by
(text, people, resolutions), keep player ticks out of the page body. Conversations (`SpeakerTurnsView`)
keep their surface for now — phase 2.

**✅ REVIEW 1 DECIDED 2026-07-06 (mock v2 = the spec → `Skrift_Native/SkriftDesktop/mocks/note-editor-redesign.html`).**
LOCKED: **B2 — pinned title** (slim title row + ✦ chooser under the nav; rationale = swipe-between-memos context).
Accessory bar = **undo · redo · find · photo-at-caret · Done** (no play-from-caret, no append). **"Save highlight"
DROPPED** (user: never seen it, not necessary — plain system edit menu). Find-in-note: yes. **Summary card joins the
scrolling header** (chips → importance → summary → body) — the app already shows it for Mac-polished memos
(`MemoDetailView.summaryCard`); ⚠️ if a polished memo is NOT showing its summary on the phone today, that's a BUG —
check in the bugs chat. NEW asks from review: (1) **accessory bar restyled** to the app's language (floating glass
pill matching the player — user: system strip "doesn't fit the style, not as clean"); (2) **compact player pill** —
the old ~112 pt bar "takes up way too much space, blocks out the note" → one 44 pt row (play · ±10 s · scrubber+times
· rate), whole-pill scrub target, page dots → transient "3 / 7" while swiping. Mock fidelity note: chips/importance
render schematic — build matches the real app. ~~STILL TO SIGN OFF: the accessory restyle + the compact player direction~~
**✅ REVIEW 2 2026-07-06 — BOTH SIGNED OFF ("that's about it"); icon nit fixed (crisp SVG stand-ins in the mock,
SF Symbols on device: arrow.uturn.backward/.forward · magnifyingglass · camera). THE SPEC IS COMPLETE →
`mocks/note-editor-redesign.html`. Build green-lit as soon as the user's bug-fixing chat wraps.**

**🔍 FEATURE-GAP SURVEY 2026-07-06 (other note apps vs Skrift; knowledge-based).** Already have or already
planned: pins/folders/nested-tags/smart-folders (P5), highlights-feed/quote-cards/daily-review (P6), person
pages/backlinks (P7), journal/on-this-day/map/calendar/semantic-search (P8), ramble→to-do/bullets polish modes
(P4c), share-IN captures (C3), find-in-note + undo + photo-viewer + Dynamic Type (NEdit spec). **Real gaps
proposed (awaiting user pick):** (1) **share a note OUT** — md/text (+audio) share sheet; phone today only
copies the transcript — fold into the NEdit build (S); (2) **word count / duration stats** in ⋯ (S, fold in);
(3) **photo OCR** — on-device Vision text-in-photos → searchable + copyable (M, feeds P8d later);
(4) **note reminders** — "note to self" → local notification at a time (M); (5) **FaceID-locked notes** (M,
fits the privacy brand); (6) **live checklists** — render/toggle `- [ ]` lines, pairs with P4c + Obsidian tasks
(M); (7) **note↔note [[links]] + backlinks** — people-links exist; extend to memos, enriches the vault (M-L,
P7-adjacent); (8) **in-app document scan** — VisionKit → PDF capture (S-M); (9) **audio trim/delete-section
with transcript sync** — beyond Voice Memos; differentiator-grade (L, later). **Rejected as off-north:**
collaboration/shared notes, templates, publish-to-web, handwriting, note colors, typewriter modes.
Strategic note: iOS 18+ Apple Notes/Voice Memos transcribe natively now — don't chase generic parity; win on
context + names + audiobooks + karaoke + Obsidian + privacy. **USER 2026-07-06: their native transcription
quality is far below Parakeet's — transcription QUALITY is the moat; keep it front of positioning.**

**✅ SURVEY DECIDED 2026-07-06 — ALL shortlist items APPROVED** (share-out, word count, photo OCR, reminders,
FaceID lock, checklists, memo↔memo links, doc scan; audio-trim PARKED after explanation; rejected list confirmed
rejected). **HARD RULE (user): every feature ships on BOTH apps — model/logic in `Skrift_Native/Shared/`, thin
per-platform UI; phone and Mac run the same code wherever possible.**

**🏗 BUILD PLAN — frozen 2026-07-06; EXECUTION STARTED 2026-07-07 (bug chat wrapped, user green-lit).** Spec =
`mocks/note-editor-redesign.html`. Commit + verify per chunk (sim tests both apps; device eyeball for editor
feel); update FEATURES.md + roadmap in the same commits.
**Progress: chunk 1 ✅ 2026-07-07** — `NoteBodyView` re-foundation built (scrolling text view + hosted
header/footer, karaoke = attribute painting, `PlayerClock` split ends the 20 Hz whole-page re-render, debounced
saves, memoized name-scan; `NonScrollingTextView` + `TranscriptBodyView`/`TranscriptEditor` + `KaraokeWordLayout`
DELETED; marker write-back normalizes to the writer's `%03d` — the OLD editor drifted `[[img_001]]`→`[[img_1]]`
on every edit, a latent bug caught by the new round-trip test). Unit suite green (489).
**Chunk 2 ✅ 2026-07-07 (chrome):** floating Skrift accessory pill (`NoteAccessoryBar` — undo·redo·find·
photo-at-caret·Done, SF Symbols, live undo-stack state), system **find-in-note** (`isFindInteractionEnabled`),
**compact one-row player pill** (~40 pt: play·±10s·scrubber-with-times·speed; whole scrub zone draggable; page
dots → transient "n / total" flash on swipe), **photo tap → QuickLook viewer** (caret-adjacent attachment),
**photo-at-caret insert** (PhotosPicker → manifest `photo_<id>_NNN.jpg` convention + `AssetMaterializer.capture`
for CloudKit), **share note OUT** (⋯ → markdown + audio file via share sheet; `MemoShare` unit-tested),
**word count · duration** as the ⋯ sheet title, **Dynamic Type** (editor body + attributed text scale via
UIFontMetrics). Unit 493 green; editor-cluster UI tests green.
**Chunk 3 ✅ 2026-07-07 (tags):** `TagEditorSheet` — chips with explicit ✕ (tap-a-chip no longer silently
deletes), comma input KEPT, autocomplete chips from every library tag (`NotesRepository.allTags`, most-used
first, prefix-filtered) — "pick, not retype".
**Chunk 4 ✅ 2026-07-07 (live checklists):** `BodyTransform` = the ONE raw⇄display transform (img markers +
`- [ ]`/`- [x]` line-start task prefixes → single attachment glyphs; indent stays text; byte-exact round-trip)
consumed by BOTH the attributed builder and the name-span offset mapper (they were drifting duplicates);
tap a checkbox → toggles in place (no keyboard) + commits immediately; typed task syntax materializes into
live checkboxes on end-editing; exports verbatim as Obsidian tasks. ⚠️ Desktop parity owed (hard rule) —
`BodyTextView` doesn't render tasks yet; tracked on NFeat.
**Chunk 5 ✅ 2026-07-07 (memo↔memo links):** raw syntax `[[memo:UUID|Title]]` (SHARED `MemoLinkSyntax` in
Shared/Model — both apps compile it); typing `[[` in the editor → searchable note picker → atomic link CHIP
(one attachment glyph — typing can't extend it); tap chip → pager jumps to that memo; **"LINKED FROM"
backlinks** section under the body (off-main scan, capped 6). EXPORT: the shared `Compiler` now rewrites the
syntax at its body choke point — phone publish resolves PRECISE stems (`[[<frozen-or-derived stem>|Title]]`
via ExportStateStore, rename-safe) so vault links actually land; any unresolved path falls back to readable
`[[Title]]` (Mac compiles get the fallback until its resolver is wired — owed). Mobile 505 + desktop 325
unit green.
**Chunk 5b ✅ 2026-07-07 (enhancement-safety — user question caught it):** two seams could corrupt memo-links:
(1) the Mac's Gemma copy-edit ran RAW over the syntax → now `MemoLinkSyntax.escrowForEditing` strips links to
plain titles before the LLM (the img-marker escrow's sibling) and `reattach` re-wraps them after (case-
tolerant); a title edited away ⇒ WHOLE body falls back to unedited (QuoteProtection pattern) — wired in
`EnhancementService.editProse` (+ title/summary prompts read escrowed text); (2) the SHARED Sanitiser could
name-link an alias INSIDE a link title (nested brackets) → memo-link ranges are now `nonProseRanges` — fixes
the Mac sanitise step AND the phone's export relink in one shared change. Mobile 508 + desktop 325 unit green
+ full desktop app builds.
**Chunk 6 ✅ 2026-07-07 (photo OCR):** `PhotoTextIndexer` — on-device Vision over every memo photo; text lands
on `ImageManifestEntry.text` INSIDE the synced metadata blob (additive → every device carries it, zero new sync
machinery). Idempotent sweep (nil = pending, "" = no text) on launch/foreground/sync-settle/photo-insert.
Search extracted to `Memo.matches(query:)` + now matches photo text AND the memo TITLE (pre-existing gap).
Verified with a REAL Vision pass over a rendered fixture (512 unit); Mac search-UI wiring owed. [1d4da6e]
**Chunk 7 ✅ 2026-07-07 (reminders — signed-off design):** `Memo.remindAt: Date?` on the SHARED model (additive
→ lightweight migration; ⚠️ prod CloudKit schema deploy needed at promotion). Reminder = DATA (syncs); alarm =
per-device — `ReminderScheduler` reconciles `UNUserNotificationCenter` from the field (pure `ReminderPlan`:
future+live only → past dates inert; moved dates re-add; unrelated notifications untouched) on
launch/foreground/sync-settle/set/clear. Notification tap → `MemoOpenBridge` opens the memo; foreground
banners. UI: bell CHIP in the header when set (tap = change/remove), ⋯ → "Remind me…", list long-press →
"Remind me…"; presets (This evening/Tomorrow/Next week) + graphical picker; auth on FIRST set, denial explained.
Mac reconciler owed (same UserNotifications API; data lands already). 516 unit + desktop 325 + desktop app
build green.
**Chunk 8 ✅ 2026-07-07 (locked notes — semantics as pinned):** `Memo.locked: Bool` on the SHARED model
(additive; syncs — lock once, locked everywhere; prod schema deploy needed). `LockGate` = per-device SESSION
unlock (device-owner auth: FaceID/TouchID/passcode; injectable for tests); backgrounding re-locks all (Apple
Notes behaviour). UI: list rows show title + 🔒 only (no preview/thumb); the DETAIL PAGE renders a locked
placeholder (title + 🔒 + Unlock) — the pager can't swipe past it, MemoOpenBridge lands on it, and the player
NEVER loads a locked memo's audio (gate-aware load + re-derive on unlock/relock). Lock = instant (needs a
passcode-capable device); REMOVING the lock needs auth. **Publish: locked ⇒ excluded** (`shouldPublish` guard,
tested); locking an already-published memo → honest "already in your vault" notice (Skrift never deletes vault
files). Honesty copy on the placeholder: "hidden, not encrypted". Mac gate owed (LocalAuthentication is the
same API). 520 unit + desktop 325 + desktop app build + UI cluster green.
**📱 DEVICE TEST ROUNDS 1–3 — builds 31→36, all 2026-07-07. ⭐ CONTINUE HERE.**
**ROUND-3 VERDICTS (build 35) + same-day fixes (build 36):**
- ❌→🔁 **P1#1 selection handles STILL WEIRD** ("weirder than before": handle refuses to move at the
  screen bottom while dragging; selection follows the viewport after keyboard-dismiss scroll; then
  snaps back). Devlog: ZERO churn events during the repro → round-2's churn fix held; remaining
  suspect = our per-frame hosted-subview frame writes fighting iOS 26's selection overlay
  (_UICursorAccessoryHostView). Build 36: frames assigned ONLY on change + a NEW probe
  `sel-during-scroll` (FR-inclusive — the round-2 probe was FR-gated and his repro keeps FR). If
  round 4 still jumps WITHOUT probe lines → pure overlay artifact → next step is restructuring
  (host header/footer outside the text view).
- ❌→🔁 **P1#3 doc-scan invisible AGAIN** — devlog `isSupported=true` proves capability; iOS 26 eats a
  2nd trailing item in ANY shape (separate items AND one group). Build 36: RELOCATED to the LEADING
  side next to Select. Sort-filter stays lone trailing. (Both toolbar UI tests green.)
- ❌→🔍 **P1#4 photo search "for sure not working"** — devlog shows the save-time sweep FIRED
  (`indexed 1` at 14:26) but "indexed" counted EMPTY results too. Build 36 logs per-photo OCR yield
  (`chars=N head='…'`) + per-query search hits (`search 'q' → N/M, K via photoText`). Also NOTE:
  photo text matches in the LIST search bar, not the in-note 🔍 find — clarify with user which he
  used. If devlog shows chars=0 on his text photo → Vision quality issue, different fix.
- 💥→✅ **NEW: markup ERASE crash** (draw → close → reopen → erase → app dies; crash
  `SkriftMobile-2026-07-07-142621.ips`): CoreAutoLayout main-thread assert — a PencilKit worker
  thread's dying CATransaction committed keyboard/selection-host layout off-main; our
  didUpdateContents chain was rebuilding the editor UNDER the live markup session. Build 36: the
  whole edit chain (re-mirror + OCR reset + thumbnail rebuild) DEFERRED to cover dismissal.
- ✅ **P2#7 camera dialog works** ("Take photo or choose from library — very good"); ✅ markup
  save-back persists ("it stays, very good"); ✅ P1#2 photo-tap fix confirmed (round 2).
- ❓ **P1#5 long-press** — user didn't know what it meant; explain: press-and-HOLD a note card in
  the memos LIST ~1 s → context menu (Remind me / Lock / Copy / Delete). Verdict owed.
**Original round-1 triage (builds 31→33) below for the record:**
LIKED ✓: compact player ("looks good"), player auto-hides for no-audio notes, tag editor ("way better, good
job"), undo buttons, paste-no-teleport, caret-above-keyboard, name resolve sheet + edit-mode semantics
("very good"), lock ("works, very cool"), reminders ("quite cool"), pinned-title ellipsis.
**P1 BUGS (all FIXED 2026-07-07, device verify owed in round 2):**
1. ✅ **Selection handles misbehave on scroll** (`600d9ef`) — diagnosed as styling/selection CHURN: SwiftUI
   re-evals storm during interactive keyboard dismiss and every updateUIView re-ran the FULL name-tier
   rewrite (unchanged spans) + a redundant selectedRange write = whole-doc reflow + iOS-26 selection-UI
   rebuild under live handles. Fixed: updateSpans skips unchanged spans; selectedRange written only when
   different; never restyle over a live selection. DevLog probes left in (inset writes, tier-restore moves,
   load rebuilds, sel-noFR changes) — if round 2 still shows jumps, the devlog names the event.
2. ✅✅ **Tap right of a photo opened the viewer** (`da3cfee`) — touch-point vs drawn rect;
   **DEVICE-CONFIRMED round 2** ("clicking next to the picture doesn't open it anymore — really nice").
3. ✅ **Doc-scan button invisible** (`81a7208`) — the button was a ToolbarItem nested TWO conditionals deep
   in ToolbarContentBuilder (the shape iOS 26 drops); both trailing buttons now live in ONE ToolbarItemGroup.
   Devlog probe "docScan: isSupported=…" proves capability vs toolbar in round 2.
4. ✅ **Photo-OCR search dead** (`461c55d`) — confirmed the sweep WORKS on device (devlog: "photoText:
   indexed 7" at 12:19); the gap was no trigger after a save, so in-session searches found nothing. The
   save paths (recording / awaitable / video import) now run PhotoTextIndexer after the metadata merge;
   integration test = save with rendered-text photo → searchable, real Vision. Handwriting quality = Vision's
   call, still watch.
5. ✅ **List long-press scrolled instead of context menu** (`5376a2f`) — the row's .onTapGesture fought the
   lift; the row is a plain Button now. New UI test long-presses row 0 and asserts the menu (green).
6. ✅ **Checkbox tap sometimes entered editing** (`da3cfee`) — same rect-based fix as #2: task glyph hit by
   drawn rect ±12 pt slop, caret snap irrelevant; geometry test.
**P2 FEATURES/POLISH (user-requested this round; code items BUILT 2026-07-07, device verify owed):**
7. ✅ 📷 offers TAKE PHOTO + library (`f5a16a3`) — confirmation dialog → system camera; both funnel into
   one caret-insert + CloudKit mirror + OCR path; sim stays library-only.
8. ✅ Checklist Return-continuation (`54fe2d4`) — Return in a task line = fresh unchecked item (mid-line
   splits); Return on an EMPTY item dissolves the box (Notes flow). 4 delegate-driven tests.
9. ✅ **Accessory bar v2 — SIGNED OFF (variant B) + BUILT + round-2 AMENDED 2026-07-07:**
   undo · redo | ☑ checklist-toggle (lights in a task line; un-tasks it) · 📷 · → memo-link
   (same picker as typing "[[") · 🔍 · Done. Round-2 verdict: checklist "super cool", link
   found + understood (Obsidian-style [[ ]]). ⋯ overflow REMOVED same day (user: not needed
   while there's space — it held only Find); revisit overflow-vs-SCROLL (user leans scroll,
   à la Notes) when scan/markup verbs arrive. Open (deferred): scan-into-this-note verb.
10. ✅ Draw on photos in-app (`fb7f5f4`) — QuickLook `.updateContents` wrapper (MarkupPreviewView):
    markup saves INTO the photo file → AssetMaterializer size-change re-mirror + OCR reset→rescan +
    mtime-keyed thumbnail rebuild. Shared-file captures get markup too (PDFs).
11. ✅ **Photo display-block — SIGNED OFF + BUILT 2026-07-07:** mid-sentence photos render as their
    own paragraph via TAGGED display-only newlines; raw keeps `[[img]]` mid-sentence (sync/export/Mac
    unchanged). Rule lives in `BodyTransform.imageBreaks` (one source for builder + displayRange).
    Hardening: reconstruct emits syntax only for real U+FFFC runs + typingAttributes scrubbed —
    inherited keys can't duplicate markers or eat a Return.
12. ⏳ Photo-viewer open animation (zoom) — still open; user re-flagged it round 2 ("something
    black comes up from the bottom"). Needs UIKit-driven presentation + `transitionViewFor`
    anchored to the attachment rect through the hosting boundary. Next in line.
**BY DESIGN (confirmed to user):** a SECOND typed mention of a linked name stays plain — one link per person,
first mention only (the locked naming model); re-scan happens on commit (~1 s) + restyles on end-editing.
**ANSWERED:** reminders are LOCAL notifications (not the Reminders app / EventKit), alarms fully offline;
only cross-device sync of the reminder needs iCloud.

**Chunk 9 ✅ 2026-07-07 (doc scan — THE WAVE IS BUILT):** `DocScanner` + `DocScanView` (VisionKit document
camera) — scan pages → ONE PDF via the existing C3 file-capture path (mirrors the share-drainer construction
byte-for-byte: `file_<uuid>.pdf`, SharedContent .file, empty audioFilename discriminator) → the scan is a
normal capture memo (file card + QuickLook + annotation) that syncs like any shared file; pages are OCR'd
on-device into `sharedContent.text` (capped 4 KB) so scans are FINDABLE from the memos search. Entry: a
`doc.viewfinder` toolbar button in the list — hidden on the simulator (the camera doesn't exist there; honest).
Scan → opens the new memo (MemoOpenBridge). 523 unit green (PDF page-count, real-Vision page read, capture
contract). Device eyeball owed
(selection drag / caret-follow / magnifier feel). **Name-tap mechanics changed (UI-test-driven find):** the
scrolling view's system text interactions swallow tap gestures (DevLog-proven), so names resolve via the
FOCUS-GAINING tap's caret (selection delegate, ±1 edge tolerance); while ALREADY editing, taps are plain caret
placement — resolve via the people row. Feels right in principle; confirm on device. Off-screen pager pages
can't a11y-hide hosted UIKit content on iOS 26 → they suffix identifiers ("-offscreen") instead. Chunks in order:
1. **Re-foundation (the editor):** scrolling UITextView page per spec (B2 pinned title; chips→importance→
   summary as in-scroll header), TextKit 2, `[[img]]` attachments, name-tier attributes, quote-protected
   captures. DELETE `NonScrollingTextView` + the 3-mode swap. **Karaoke = attribute painting** on the same
   textStorage (word-rate) + char-hit tap-to-seek. Perf: debounced saves (~1 s idle + Done/close), memoized
   nameSpans, player ticks out of the page body. Verify on a LONG memo: selection-drag autoscroll, caret-follow,
   paste, undo, magnifier.
2. **Chrome:** floating accessory pill (undo · redo · find · photo-at-caret · Done; SF Symbols),
   `isFindInteractionEnabled`, compact 44-pt player pill (whole-pill scrub; dots → transient "3/7"), photo
   tap→QuickLook (Live Text ⇒ copyable for free), Dynamic Type, **share note OUT** (md/text + audio),
   **word count/duration** in ⋯.
3. **Tag chip editor** + autocomplete from existing tags (fixes tap-a-chip-silently-deletes).
4. **Live checklists:** `- [ ]` / `- [x]` lines render as tappable checkboxes in the editor; toggle rewrites the
   line; round-trips verbatim to Obsidian tasks. (Pairs with P4c ramble→to-do later.)
5. **Memo↔memo links:** `[[` in the editor → memo-title autocomplete; store `[[memo:UUID|Title]]` in the raw
   text; exporter emits `[[Title]]` (resolving the CURRENT title) so it works in Obsidian; tap → open that memo;
   "Linked from…" backlinks section on detail. Shared linker in Shared/.
6. **Photo OCR:** Vision `VNRecognizeTextRequest` at photo save/import (background) → per-image text sidecar;
   folds into list search on phone AND Mac; copyable via the QuickLook viewer.
7. **Note reminders:** `Memo.remindAt: Date?` on the SHARED model (syncs via CloudKit like any field); the alarm
   is LOCAL per device — each device reconciles `UNUserNotificationCenter` pending requests from the synced field
   on sync-settle (CloudSyncMonitor hook); same framework on macOS. Set/clear from ⋯ + list long-press; tap the
   notification → open the memo.
8. **Locked notes:** synced `locked` flag; list long-press / detail ⋯ → Lock (Apple Notes idiom); open gated via
   `LocalAuthentication` (FaceID phone / TouchID-password Mac — shared gate); list shows title + 🔒, hides
   preview. **Semantics (user-clarified 2026-07-06): locked memos still SYNC via CloudKit** (appear on the Mac,
   locked there too) — **they're excluded from Obsidian PUBLISH only** (vault = plaintext .md on disk).
   Lock-after-export edge: Skrift never deletes vault files — it surfaces "already in your vault; remove it
   there if you want it gone." Unlock ⇒ publishes again next export. v1 = auth-gated UI, NOT per-note crypto
   (search + pipeline keep working) — stated honestly in Settings copy.
9. **Doc scan (phone):** VisionKit document camera → PDF → the existing C3 file-capture path (Mac views it like
   any shared file).
**DROPPED 2026-07-06:** audio trim / delete-a-section (was parked) — user: "the text is the main source; we
just edit the text. I don't think we need to edit the voice note itself." Off the plan entirely.

## ⭐ Standalone App Store push (2026-06-15) — see `STANDALONE_PLAN.md`

NEW DIRECTION: ship **SkriftMobile to the App Store as a standalone audiobook + notetaking app** that
works fully **without a Mac**. Full plan (phases 0–11, portability map, device/LLM matrix + Polish
spike, CloudKit/Obsidian sync architecture, competitor steal-list) lives in `STANDALONE_PLAN.md`.
Branch **`standalone`**. **Plan awaiting user sign-off before building.**

**LOCKED decisions:** $0.69 one-time, **NO IAP** (→ no cloud LLM cost, all on-device); **full-vision
v1**; internal sync = **CloudKit** (SwiftData CloudKit mode, NOT iCloud-Drive file sync → no
`filename 2.md` conflicts); Obsidian export = **one-way create-only publish** into a user-picked
vault folder (security-scoped bookmark, `Skrift/` subfolder, per-memo file ownership); on-device
**Polish = a gated spike** (lean Gemma, test on the real iPhone 13, ship only if it clears a hard
memory+quality bar, else no-polish); **three coexisting modes** (standalone / standalone+Obsidian /
paired-with-Mac) over one source of truth — Mac stays byte-compatible + opt-in.

**Build order:** Phase 0 `SkriftPipelineKit` (shared pure stages) → 1 CloudKit sync → 2 Export/Obsidian
publish → 3 de-Mac the UX  *(= standalone-capable core / earliest-shippable gate)*  → 4 Polish (spike
first) → 5 Organization (pins/folders/nested tags/smart folders) → 6 Commonplace Book + Daily Review
+ quote cards (the differentiator) → 7 People & backlinks → 8 Journal/map/On-This-Day + semantic
search → 9 audiobook player polish → 10 Apple Watch capture → 11 App Store readiness.

**⭐ PROGRESS (2026-06-18) — all on `main`, local/unpushed (branch `standalone` fast-forwarded in + removed):**
- ✅ **Phase 0** — shared naming engine in `Skrift_Native/Shared/Naming/` (shared SOURCE FOLDER, not SPM). Both apps green.
- ✅ **Phase 1a/1b** — Memo-row CloudKit sync; **device-verified** (iPhone→iPad, no Mac). iCloud capability + per-config container added in Xcode.
- ✅ **Phase 1c** — Memo audio/photos → CKAsset (`c5824eb`+`ec10bf5`). `MemoAsset` blob model (plain `Data`, no `.externalStorage` — CloudKit auto-CKAsset) + idempotent `AssetMaterializer`. **DEVICE-VERIFIED 2026-06-18** (image+audio iPhone→iPad).
- ✅ **Phase 1d** — word-timings + diarization sidecars sync (`026d4ca`) — new `MemoAsset` kinds → karaoke/speaker labels cross devices.
- ✅ **Phase 1e** — names + enrolled voices sync (`5ca7c1e`) — `NamesRecord` carrier + `NamesMerge` (LWW + voiceEmbedding union); `names.json`/Mac contract untouched.
- ✅ **Phase 1f** — custom vocabulary sync (`fddf690`) — `VocabularyRecord` carrier, LWW-by-modifiedAt (delete propagates).
- ✅ **Sync visibility** (`d49333b`) — `CloudSyncMonitor` → "Syncing with iCloud…" strip + "Downloading from iCloud…" image state; materialize-on-import (no foreground needed). ✅ **Vocab clobber fix** (`70a1058`) — fresh device won't wipe another's words.
- ✅ **Audiobook sync ENGINE** (`b0c7e41`, 1g/1h-i) — `AudiobookSyncRecord`/`AudiobookAsset` @Models + `AudiobookCloudSync` (enable/disable/reconcile; capture audio→CKAssets, materialize on receiver, position LWW, unshare keeps local audio). Reconciles against the untouched `library.json`. **Callable-only / NOT auto-wired** (inert until UI+policy). Mock **APPROVED + LOCKED**.
- **Test gate: 430/430 `SkriftMobileTests` green.** ⚠️ 1c–1f + sync-visibility device-verify rides along with any DEV reinstall. ⚠️ 10/40 UI tests pre-existing-broken on the iOS-26 sim — background task; **unit suite is the gate**.
- ✅ **CloudKit push + pull-to-refresh** (`63bf236`) — DEVICE-VERIFIED fast sync (seconds). Push capability added in Xcode; `aps-environment` committed to entitlements (`53451a6`, survives regen; prod=production). Pull-to-refresh on the Memos list runs the sweeps.
- ✅ **Version in About** (`c97a89d`) — reads real `CFBundleShortVersionString (CFBundleVersion)` (was hardcoded); bump per install to tell devices apart. Now build **(7)**.
- ✅ **Floating + debounced sync indicator** (`d1df31c`) — the "Syncing…" pill is an overlay (no layout shift) + debounced (no flicker during CloudKit bursts).
- ✅ **Sprint 2026-06-18:** double-transcription guard (`aab9e3f` — `Memo.recordingDeviceID`/`DeviceID`; receiver won't re-transcribe another device's `.transcribing` memo); Settings "iCloud sync — Up to date/Syncing…" line (`eb69fd3`); de-Mac toolbar gate (`b2460e2` — hide the ⟳ Mac sync button unless a Mac is paired); **audiobook sync toggle UI slice 1** (`e557de2` — library long-press "Sync this book" + `checkmark.icloud` glyph). **Test gate: 432/432.**
- ✅ **Per-book audiobook sync FUNCTIONALLY COMPLETE** (1g engine `b0c7e41` + 1h-ii UI slices `e557de2`/`33eefff`/`34a1fd6`/`19b8508`): toggle (library long-press + player ⋯), row states (synced ✓ / downloading spinner / download-available), "Syncing…" pill in the library, hands-off receive (reconcile on import-complete + pull-to-refresh), per-device **Remove download** (Apple Books model) + **Settings → Synced audiobooks** (size + Remove/Download/Stop-syncing), position LWW. **435/435 unit tests.** Build **(9)**.
- **Installable build (12)** on `main` (unpushed) — raw-CloudKit audiobook % + size sheet landed (build number now lives in `project.yml`, so `xcodegen generate` stops resetting it).
- 📌 **OPEN QUESTION (pinned 2026-06-18): offline conflict resolution.** Scenario: a week offline, notes taken + old notes edited on BOTH iPad + phone, then reconnect. Current behavior: **new notes = no conflict** (distinct per-device UUIDs, both kept — why we dropped `@Attribute(.unique)`). **Same note edited on both = last-writer-wins** per record (NSPersistentCloudKitContainer default; no crash, no "note 2" files, but one side's edit to that note can be silently lost). **Names/voices CONVERGE** (our `NamesMerge` re-merge: per-canonical LWW + voiceEmbedding union). Vocab = whole-list LWW; audiobook position = newest-play wins. **TO VERIFY:** exact NSPersistentCloudKitContainer merge granularity (per-record LWW vs per-property) — don't guess. **DECIDE later:** accept LWW (rare for a solo app) vs a "conflicted copy" safety net vs field-level merge w/ per-field timestamps.
- ✅ **DONE 2026-06-19 — raw-CloudKit audiobook AUDIO transfer (REAL %) + the "Turn it on" size sheet** (build **(12)**, 435/435 unit; commits `974abfd` transport · `08adbf5` rewire · `a353a49` determinate bar · `d012353` sheet · `e16531c` sweeps/build-12). Audio left the SwiftData `AudiobookAsset` blob (no % available) for a raw-CloudKit transfer: `AudiobookAudioTransport`/`CloudKitAudiobookTransport` write `AudiobookAudio` `CKRecord`+`CKAsset(fileURL:)` to the private-DB **default zone**; `CKModifyRecordsOperation`/`CKFetchRecordsOperation` `perRecordProgressBlock` → byte-weighted **DETERMINATE** per-book bar ("Uploading audio · 38%" / "Downloading · 61%"). Fetched by exact recordID (`ab_<bookID>_<index>`/`_cover`) → no queryable index. **No `CKQuerySubscription`** (the default zone wouldn't push one): the source stamps `audioUploadedAt` on the carrier → that @Model push (Core Data's zone) nudges the receiver's `reconcile` to fetch. **"Turn it on" sheet** `AudiobookSyncSheet` (mock screen 1, both menus): cover/title/**on-device size**/switch/live-% card/iCloud note. **BONUS done:** `CKAsset(fileURL:)` streams off-disk → no `Data(contentsOf:)` on main for large books (task #18). Wi-Fi default (`allowsCellularAccess=false`). `AudiobookAsset` @Model retained-but-dead (dropping a synced @Model risks a load fatalError; remove at prod promotion w/ a CloudKit dev-env reset). **Design verified vs current Apple docs** (coexistence-with-NSPersistentCloudKitContainer, fetch-by-id/no-index, perRecordProgressBlock, re-push trigger). **DEFERRED:** the cellular "Ready to sync · N MB" tap-to-pull affordance (`NWPathMonitor`). **⚠️ DEVICE-VERIFY OWED:** real iCloud — opt a book in on iPhone (watch the % climb), see it download on iPad with %; `AudiobookAudio` type auto-creates in DEV (no Dashboard step), needs a Deploy at prod promotion.
  - **Hardened after an adversarial code-review (9 confirmed → 5 fixed `b…`):** epoch-token guard so a late off-main progress callback can't leave a row stuck mid-bar; single-flight `reconcile` (re-run-coalesced) so overlapping triggers can't double-upload; re-fetch the live carrier after the upload `await` (don't write a `disableSync`-deleted @Model); atomic temp→rename asset copy (off-main copy vs main-actor folder ops); `unknownItem`-tolerant download (a missing part no longer discards the copies + retries forever).
  - **Known follow-ups (deferred, logged):** (#8) **playback-RATE-only changes don't sync** — LWW keys on `lastPlayedAt`, which `updateRate` doesn't bump; position (the headline) does sync. Fix later via a per-book `modifiedAt`-on-`Audiobook` (every mutator bumps it) rather than overloading `lastPlayedAt` (would reorder "recently played"). (#9) the Settings "Stop syncing"/"Download" rows wait on the CloudKit round-trip before updating — add an optimistic state/spinner. (#10) **unshare leaves a "phantom" entry on a device that received the entry but never downloaded the audio** — `disableSync` deletes the carrier + cloud audio but never removes a device's local `library.json` entry (correct for a device that HAS the audio → reverts to local-only; wrong for one that doesn't → empty unplayable book). Can't safely auto-GC in `reconcile` (can't tell a once-synced entry from a locally-imported one). Fix in sync-polish: track sync-provenance on the entry (or GC an entry with no carrier AND no local audio files). Narrow edge — both devices having the audio (the common case) is clean.
  - ✅ **"I want EVERYTHING to sync" (device-feedback 2026-06-19) — DONE, build (13):**
    (#11 ✅ `a6126e0`) cover refresh — `BookCoverCache.invalidate` after a download + `endBookTransfer`'s publish re-renders the row once `cover.jpg` lands; surfaced per-record upload/download failures so a dropped cover is visible.
    (#12 ✅ `b4b7214`) `BookTranscript` read-along text now syncs — `transcriptSignature` on the carrier (propagates even if transcribed AFTER syncing), sidecars ride the transport as `ab_<bookID>_t<i>`, receiver **re-stamps** the `signature` to its own audio so it's not stale; unshare deletes them, restore re-stamps. (+test)
    (#13/#8 ✅ `a6126e0`) position + rate — added `Audiobook.modifiedAt` (bumped by `updateProgress`+`updateRate`), reconcile LWW on `modifiedAt` not `lastPlayedAt`, so a **speed-only change syncs** without bumping the recents sort. (+test)
    **⚠️ DEVICE-VERIFY OWED (build 13):** opt a 2nd book in on the iPhone → cover, read-along transcript, position AND speed all appear on the iPad. Bookmarks-sync is still the next gap (separate from this batch).
- ⏳ **Then:** (a) rest of Phase 3 de-Mac — significance→**Importance** reframe (**needs a label nod**) + onboarding/Settings demote; (b) Phase 2 export/Obsidian + unify Compiler/TagMatcher/DTOs; (c) Mac→CloudKit (option A); (d) 10 pre-existing iOS-26 UI-test fixes (background chip). **Device-verify the audiobook sync** (real iCloud uploads, iPhone book → iPad).

**Decisions (resolved 2026-06-15):** (1) on-device name-linking = **YES** (phone still sends RAW; Mac
re-links identically via shared code → no double-link; alias-edit UI on phone mirrors Mac); (2) audio
sync = **CKAsset** (real audio on all devices); (3) Tier-C model = **opt-in** picker in Models tab,
default set by the spike; (4) min iOS = **26**; (6) Apple Watch = **deferred** (fast-follow). **STILL
OPEN: (5) folders model** — app-native vs Obsidian-subfolder — user thinking; don't build Phase 5 yet
(doesn't block 0–4). **Cross-app no-drift principle locked:** shared `SkriftPipelineKit` code + the
contract fixtures are the single source; deterministic re-derivation, never a one-sided "done" flag.
**Next after sign-off:** Phase 0 (`SkriftPipelineKit`) + schedule the Phase-4a model spike on the real
iPhone 13 (independent, longest-pole).

**Mock batch 1 (2026-06-15)** — 4 HTML mocks in `SkriftDesktop/mocks/standalone-*.html`. Status:
`models-polish` ⏸ **PARKED** (Polish behavior locked = title+summary+copy-edit mirroring Mac; held on
the mobile title-presentation UI — desktop's Suggested/From-recording chooser is wrong for a phone;
VERIFIED the Mac never syncs polished text back to the phone, so non-AI devices = raw). `export-obsidian`,
`onboarding`, `commonplace-book` await the user's reaction to their flagged design decisions.

## 🗺️ Roadmap history backfill (idea 2026-06-19; SEPARATE SESSION)

`roadmap/ROADMAP.html` is forward-looking (phases → ship). User wants to also fold in the **full past** —
"insane amounts" of history from the very start of Skrift — as a backward-looking timeline. Doable + its
own session. **Raw material (no vault — privacy):** `git log` back to the start (the spine), `archive/`
(old Electron/Python/RN apps preserved intact) + `archive/CLAUDE-electron-python.md` (pre-convergence
project doc), the memory files, the handoff docs (`*_HANDOFF.md`), `FEATURES.md`. **Shape:** mine into a
structured `HISTORY` array (date · era · what shipped · pointer to commit/doc) → render as a "past" view —
either a history lane flowing left into the future tree (one page) or a sibling timeline. Same data-driven
principle so it can't drift. **Usefulness for the agent:** additive — a curated structured index = fast
orientation ("why does X exist / what was tried before"); git + the ledgers stay the primary source. Leave
this breadcrumb so the dedicated session starts fast.

**UPDATE 2026-06-19:** the roadmap was rebuilt into an interactive metro-tree and now seeds this with a
**light history nod** — a `HISTORY` array (currently `mobile-native` + `desktop-native` converging into the
spine at P0) renders on the far left, flowing into the forward tree on one page. The full backfill = expand
that same `HISTORY` array (mine git/`archive/`/ledgers into dated eras) — the data-driven hook already exists,
so the dedicated session just fills it in. (User, when choosing the rebuild: "a dream, not structurally
directed yet" — so kept light for now, designed to grow.)

**UPDATE 2026-06-21 — staged material compiled:** read-only pass over the 3 external milestone snapshots
the user flagged (`~/Hackerman/archive/Skrift {…before frontend with hendri | …whisper AND parakeet | …before
starting the mobile app}`) → **`roadmap/HISTORY_BACKFILL.md`**. It has the sources, a verified
3-snapshot table, a draft 7-era timeline (Genesis→Whisper→v2-frontend-w/Hendri→Parakeet+significance→RN
mobile→native convergence→standalone), and how to extend the `HISTORY` array. **Not built** — user wants to
hold the backfill until the viz mechanics are locked (avoid rework). Key finding: the **live repo's own
779-commit `git log` (2025-10-18 → now) already holds the full narrative** — the snapshots just add human
milestone labels + the "Hendri" collaborator marker + preserved era artifacts. Start that session from the doc.

## 🎧 Audiobook player — reading-experience redesign (feedback 2026-06-18; ✅ MOCK SIGNED OFF + ✅ BUILT 2026-06-19)

### Device feedback — build 14 run (2026-06-19, triaged same session)
- ✅ **Play button "looked like a sphere"** → flat accent circle + soft glow (`2cc0412`).
- ✅ **Per-word karaoke underline disliked + made the now-line "jump over"** → dropped the per-word weight/underline;
  current sentence is just bright white (3-step ramp stays at the sentence level). Also kills the semibold reflow (`2cc0412`).
- ✅ **Transcription accuracy → SHIPPED `ASRConfig(melChunkContext: false)` (dual OFF)** after a two-language A/B sweep
  (desktop `-asrsweep`, pinned to the phone's FluidAudio commit `7f963cd` / v0.15.2 / parakeet-tdt-0.6b-v3):
  - **English-only clip** ("Do the Work" Intro): mel=off introduced one chunk-seam dup ("emotional emotional"); mel=on
    (default) cleaner. (First pass wrongly concluded "revert" from THIS clip alone.)
  - **Dutch clip** (3-min CC-BY-SA spoken-Wikipedia "Wijngaarden"): mel=on **drifts to its English prior** and garbles
    non-English — wrong years (1666/"twaalftig"/"veertien" vs correct 1986/1283/1451), mangled place-names ("Morenaars
    Graaf"/"Out-Alblas" → Molenaarsgraaf/Oud-Alblas), "Corneus Johan" → "Cornelius Johann". **mel=off fixes all of these.**
  - Verdict for NL/EN-mixed use: mel=off is the clear win on non-English (big accuracy gain, faster) but has a minor
    English seam cost — and the user is MOSTLY English. **Resolution: a Settings toggle** ("Language: English ↔
    Multilingual", `transcriptionMultilingual` @AppStorage, default **English** = mel-on = the v3 default).
    `TranscriptionService.ensureLoaded` reads it + REBUILDS the model when it flips. Multilingual = mel-off, which is
    **language-agnostic** — helps any non-English language v3 supports (German/French/Spanish/…), not just Dutch.
    **dualDecodeArbitration left OFF** — byte-identical to mel=off alone but ~2.7× slower in both tests.
  - Tooling kept: `-asrsweep <audio> [-truth]` (+ `-paragraph <audio>`). Both apps still pin FluidAudio to branch `main`
    → should pin a fixed version (drift risk). The garbled proper-nouns the v3 model just doesn't know (e.g. "Gods schok
    oem") are model limits, not config — out of scope.
- ✅ **iPad cold-launch didn't restore the phone's chapter-2 position** (live sync worked, fresh launch didn't) → real
  two-part race: `open()` read the local library.json position + raced the CloudKit import, and the iPad's first tick
  then LWW-poisoned the phone's update. Fixed: `open()` adopts a strictly-newer carrier position (writes it back), and
  `CloudSyncMonitor` re-seeks an open+paused session when a late import lands (`adoptSyncedPosition`). **DEVICE-VERIFY owed.**
- ✅ **Speed menu "froze first tap, fast second" — expected?** YES, benign: one-time process-wide cost of the FIRST
  SwiftUI `Menu` presentation (the `setRate` path is constant-cost). No fix. (Latent: `AudiobookLibraryStore.persist()`
  does a synchronous main-thread JSON write on every rate/progress change — move off-main someday; not the cause.)
- 👍 **Liked:** auto-recede chrome (read uninterrupted, pause appears when idle) · letter sizing.
- 🔧 **Paragraphing — BUILT + demoed (not yet wired into the UI).** `Models/Paragrapher.swift` (pure, 10 unit tests):
  hybrid — break a paragraph on a long pause AFTER a finished sentence, OR after `maxSentences` (default 4). Demoed on a
  real chapter via desktop `-paragraph`: **pause-only UNDER-segments steady audiobook narration** (the narrator barely
  pauses → one giant block at any 0.5–1.0s threshold); the **sentence cap is what gives audiobooks regular paragraphs**.
  So the hybrid is the right default (pauses catch real structure like bumper/credits; the cap handles dense narration).
  **DECISION OWED:** where to apply — read-along grouping / memo-detail display / stored+exported — and the
  threshold+cap. Not yet wired pending the user's pick. Unused FluidAudio `TextNormalizer`/ITN + `.dutch` hint still deferred.
- 🔧 **Chunk-seam robustness — BUILT (device-verify owed).** Root cause of `UndetectedED`/`WILLIM RAULF` garble: each 60s
  audiobook chunk transcribes from a COLD decoder with no preceding audio → its OPENING words mis-decode/mis-capitalise.
  Fix (`BookTranscriptionJob.transcribeChunk`): prepend ~2s of audio before each chunk as decode CONTEXT, then drop those
  lead-in words (word-time alignment preserved; chunkEnd behaviour unchanged so ChunkFusion's redo-tail still owns the
  trailing seam). First chunk has no lead. Verify on-device on the book where the garble appeared.
- 🔧 **Chunk-seam DROPPED-WORD / merged-sentence — FIXED (device-verify owed).** Device bug 2026-06-27
  ("Made to Stick", ch1 ~40:15): a long run-on sentence ("The creative genius… launch into a four-hour
  brainstorming **session.**") fills a 60s chunk, so `ChunkFusion`'s last sentence-start is > minProgress
  back → it took the **fallback** = keep ALL words + advance to the arbitrary `chunkEnd`. That cut lands
  MID-WORD: chunk A transcribes the boundary word from TRUNCATED audio (mis-decoded "session"→"summer",
  terminating period lost) yet KEEPS it, while chunk B drops it (starts before chunkEnd). The period-less
  word merges the two sentences → the giant un-split highlight block in the screenshot. **Fix:** the
  fallback now mirrors the sentence redo-tail at WORD granularity — drop the final word, rewind the
  frontier to its start so the next chunk re-transcribes it WHOLE (`ChunkFusion.fuse`); guard the tiny-step
  loop (accept the cut only when even the last-word rewind can't make minProgress). Also widened the
  lead-in drop tolerance 0.01→0.2s (`BookTranscriptionJob.transcribeChunk`) so the re-decoded frontier word
  survives cross-decode timing jitter instead of being dropped again. +2 regression tests in
  `ChunkFusionTests`. ⚠️ **xcodebuild test gate NOT run (fixed on Linux/web)** — run the SkriftMobile suite
  on the Mac, then device-verify on "Made to Stick".

✅ **BUILT 2026-06-19 (build 14, 439/439 SkriftMobileTests green; 8 commit-per-chunk steps `7d31b60`→`4bcca6e`).**
All 8 chunks landed to the mock: **(1)** tab-bar shell (`AppTabView`; Library/Settings out of the pull-to-refresh-eating
`.sheet`s) · **(2)** "significance"→**"Importance"** (control unchanged; internal symbols/`Memo.significance`/test-IDs/
contract key untouched) · **(3)** one-bar header + cover-tint ambiance + gradient play sphere + skip back-15/forward-30 ·
**(4)** reading mode (auto-recede never-while-paused, 3-step past/now/ahead ramp, current-WORD weight+underline, now-line
pinned upper-third, free-scroll + "Back to playing", column cap) · **(5)** "Aa" size+spacing persisted (themes dimmed,
fast-follow) · **(6)** bookmark "Mark" toggle + browse-only sheet + margin glyph · **(7)** "Add note" accent chip +
utility reflow (speed/sleep in) + read-along states (nudge / live transcribing-% / empty) · **(8)** sync-aware library
delete-confirm. **Tab bar verified on the iPhone 17 sim; player screens 3–7 owe a device eyeball (USER step — needs a
real book + transcript). Owed: light/sepia themes; a global cross-tab mini-player. NEXT → Phase 2 Export.**

✅ **Mock SIGNED OFF 2026-06-19** = `mocks/audiobook-player-reading-mode.html` (v4 — mock-first, refined via two
design-critique workflows + a rendered-pixel agent review; commits `92aee15`→`1700d4e`). **It IS the spec — build to
it.** **LOCKED:** tab-bar IA (Notes·Library·Highlights(soon)·Settings) · "significance"→**"Importance"** (graded,
renamed) · **Add-note** = centered accent chip in the utility row · **reading mode** = auto-recede after ~3–4s idle +
on scroll, tap to show, never while paused, ~250ms crossfade · now-line pinned upper-third + margin **bookmark glyph**
(add = action, sheet = browse-only) · "Aa" text settings (size + spacing v1, themes fast-follow) · floating play ·
cover-tint ambiance + monogram cover fallback · device-frame kept (vs siblings' bezel-less cards — flagged, user OK).
**Defaults on the 2 leftovers:** (a) delete keeps BOTH "Remove from all devices" (=disableSync) + "Remove from this
iPhone only" (=removeDownload, neutral) for a synced book; local-only = plain "Remove". (b) reading column capped
~60–68ch (no full-bleed on iPad). **SCOPE:** the mock is the FULL Phase-9a redesign; the near-term *slice* = tab-bar IA
+ cheap wins (delete-confirm, header compress, Importance, font size) → then Phase 2 Export; deeper reading-mode /
bookmark-model = Phase 9a proper.

The player is becoming a **read-AND-listen** surface (e-reader-like), not just a capture tool, so it
needs a reading-experience pass. **Process: NO building yet — talk it through → render HTML mocks
(`mocks/audiobook-player-*.html`) → user points/critiques → then build.** Research how good e-readers /
audiobook apps do this (Mobbin: Kindle, Apple Books, Audible, Libby, Spotify audiobooks, Snipd/Airr,
Readwise Reader, Speechify/Voice Dream; our north star = Bound). Mock against the existing redesign
(`mocks/audiobook-player-redesign.html`) — keep what works, evolve it.

1. **Compress the header (Henry).** Kill the "NOW PLAYING" label — it's wasted space. Pull the cover +
   title + author + current-chapter UP into ONE compact top bar (where NOW PLAYING is now), keeping the
   collapse chevron + ⋯ menu. Frees vertical room for the text. *(Quick, high-value; probably the first
   mock.)*
2. **More real estate for the text + a readable "rest."** Today the read-along lights the current line
   ("rotating bit") and the rest is faint. Keep the current-line/word highlight, but make the
   surrounding text more legible + give the text region more of the screen so you can **read ahead/behind
   like a page** (not a teleprompter). Idea: gentler dimming/higher contrast on non-current text +
   free-scroll with a "snap back to the playing position" affordance + auto-scroll that keeps the current
   line in view. Pairs with #1 + #6 (both free up space).
3. **Font-size control.** A font button — big-A/small-A (Aa) toggle or a stepper/slider, in a small
   text-settings sheet (e-reader pattern: Aa → font size, later line-spacing + light/sepia/dark reading
   theme). Put the Aa in the utility row (by speed/sleep) or ⋯. Persist per-app (`@AppStorage`). Start
   minimal = font size only; line-spacing/theme are easy follow-ons.
4. **Bookmark UX — make it book-like + fix the model.** In a real book a bookmark sits ON a page. Plan:
   a bookmark icon adds a **margin marker to the LEFT of the text** that scrolls/moves WITH the text, so
   you can scroll and see "this bit is bookmarked"; the bookmark list jumps to it. **Fix the current
   confusion:** the TOC sheet has Chapters + Bookmarks tabs where the *Bookmarks* tab ADDS a bookmark but
   *Chapters* NAVIGATES — inconsistent. Decouple **add bookmark** (an action/toggle at the current
   position) from **browse** (the sheet = navigation only; tap a chapter OR a bookmark → jump). Verify
   our `Bookmark` store positions map cleanly to text lines/offsets for the margin marker.
5. **Floating play button (consistency).** The memo-detail screen has a floating play button; the
   audiobook player should match it instead of the current inline transport. Care needed: the player has
   more controls (scrubber/skip/speed) than a memo — decide what floats (play/pause) vs stays.
6. **"Capture this" → smaller "Add note."** It's a big prominent pill (made sense when capture was THE
   point); now that it's also reading, it eats real estate. Rename **"Capture this" → "Add note"** (or
   "Take note"), shrink it, maybe relocate (freedom — e.g. a compact icon+label in the utility row).
   Keep it reachable; just not dominant. Research how note/highlight-capture apps place this (Snipd/Airr
   highlight button, Readwise).

7. **Library is finnicky — presentation + access (device-tested 2026-06-19).** The library is a
   `.sheet` (`MemosListView:130`), so **pull-to-refresh inside it just dismisses the sheet** (the swipe-
   down-to-close gesture wins) — you can't resync the way you can in Notes. And "how to access it / what
   to do there" feels unclear. Rethink: present it as a full-screen cover or a nav push (so pull-to-
   refresh works), or give it an explicit refresh affordance; reconsider the entry point. Folds into the
   player/library redesign (mock-first).
8. **Too easy to delete a book (device-tested 2026-06-19).** One swipe = gone, no confirm. Add a
   confirmation (and make clear whether it deletes local-only vs also stops syncing). Especially risky
   now that a delete + kept-sync leaves you needing to re-trigger a download.

**e-reader "what makes it good" (to fold into the mocks):** generous margins + line spacing, adjustable
font/size/theme, chrome that fades while reading, tap-zones, clear progress + chapter context,
distraction-free; for read-along specifically: highlight that doesn't fight readability + auto-scroll
with manual override + an easy "back to playing position." Owner action tomorrow: pull specific Mobbin
refs while building the mocks.

## ✅ MOSTLY DONE — Video-from-Photos import bugs (reported 2026-06-15; fixed 2026-06-15)

All three symptoms addressed + sim-verified (394 unit tests green; `VideoMemoUITests` green; row + detail
screenshots in `/tmp/skrift-video-shots`). Commits `d98b6fe` (playback) + `e2108dd` (glyph + snippet).
**Owed:** DEVICE-EYEBALL — the Dev build ("Skrift Dev", `com.skrift.mobile.dev`) is installed on the iPhone 13;
share a real video from Photos → confirm it PLAYS, shows the video glyph, and the thumbnail looks right. After
testing, pull `Documents/devlog.txt` from `com.skrift.mobile.dev` (DEBUG → DevLog works there) for the
`importVideo`/`processVideo` trace. ALSO STILL OWED (separate): re-test capture/share-into-Skrift on the
Release/TestFlight build now that App Groups (Release) is registered — a Release-build/device step.

Sharing a video from Photos → Skrift creates a memo, but THREE issues (device-reported, screenshots in chat):
1. ✅ **No audio playback — FIXED 2026-06-15.** Root cause was load TIMING, not format: a shared-video import
   inserts the memo and OPENS Memo detail immediately (`MemoOpenBridge`) while `processVideo`/`extractAudio`
   still runs async, so the detail player's first `load()` hit a not-yet-existent `memo_<id>.m4a` (`hasAudio=false`)
   and never re-fired (a normal recording/audio-import writes its file synchronously before insert, so they were
   unaffected). Fix: `MemoDetailView` reloads the player on `currentMemo.duration` / `transcriptStatus` change,
   guarded `!hasAudio` so an append never interrupts active playback (`reloadIfAudioMissing`). Format ruled out by
   a test: the extracted m4a loads in `AVAudioPlayer` with a real duration. (NOTE: `DevLog` is `#if DEBUG`-only,
   so the TestFlight/Release container has no `devlog.txt` — the pull can't work; diagnosed from code + sim.)
2. ✅ **Thumbnail/inline-image aspect — FIXED 2026-06-15 (device-confirmed the real cause was PORTRAIT).**
   UPDATE after device-eyeball: the distortion IS real for **portrait** video frames (the user's clip was a
   1080×1920 portrait). Root cause: `TranscriptEditor.imageAttachment` set the inline image's `NSTextAttachment`
   bounds to FULL width × a height capped at 320 — and `NSTextAttachment` scales the image to FILL bounds
   (no aspect preservation), so a tall portrait frame (aspect-height 613 > 320 cap) got crammed into a
   full-width × 320 box → **stretched wide** ("wider than it needs to be"). Fixed: when the height cap engages,
   shrink the WIDTH to keep the image's aspect. Pulled the actual device JPEG (1080×1920, PAR 1:1, person
   correctly proportioned) → confirmed extraction is fine; it was purely the editor's display sizing. The
   `-seedVideoMemo` frame is now PORTRAIT (circle stays round with the fix; was a wide ellipse before).
   (Original landscape-only investigation below was incomplete — landscape frames never hit the 320 cap, so
   they never distorted; that's why the synthetic landscape seed looked fine.)
   The 48×48 row thumb (`scaledToFill`+clip) and playing-mode `ImageEmbed` were already aspect-correct.
   ORIGINAL (landscape) finding — the row thumbnail does NOT squish:
   every display path already aspect-fills + clips (`photoThumb` 48×48 + the detail `ImageEmbed`), and the
   saved frame preserves aspect. PROVEN with `-seedVideoMemo` (a landscape 16:9 frame with a centered CIRCLE —
   it stays a perfect circle, not an ellipse, in BOTH the row thumb and the detail embed; screenshots
   `/tmp/skrift-video-shots`). The square thumb is a conventional center-crop, not a distortion. **What WAS
   broken (and is the likely culprit of the "looks wrong" screenshot): the untitled-row SNIPPET leaked the raw
   `[[img_001]]` marker** — a video transcript always opens with the frame marker, so it filled the whole snippet
   line. Fixed `MemoCard.snippet` to strip `[[img_NNN]]` markers (titled rows already used the marker-stripped
   `firstTranscriptLine`). (If the user's device frame genuinely distorts, suspect an anamorphic/non-square-PAR
   source — `representativeFrame` doesn't PAR-correct; unconfirmed, no repro.)
3b. ✅ **Source glyph BRIDGED TO DESKTOP + date fix — 2026-06-15 (device-reported follow-up).** The Mac still
   showed a synced video as mic + "Voice memo" (the marker was mobile-only) AND showed today's date instead of the
   video's filming date. Fixes: (a) phone uploads `sourceType` (additive `UploadMetadata` field); the Mac reads it
   → `PipelineFile.mediaSource` → a **unified `sourceDescriptor`** in `QueueDerivations` that drives BOTH the
   sidebar glyph AND the detail "source" label (so glyph+label always correspond) across the whole taxonomy
   (Voice memo/Video/Audiobook quote/Link/Image/Text/File/Apple Note); `IngestService.ingestVideo` sets the same
   marker for Mac-side video imports; `NoteProperties`/`NoteDisplayView` source labels now use it. (b) `UploadService`
   uses the phone's `recordedAt` for `pf.uploadedAt` (was upload-time → a Photos video showed "today"). Unit-tested
   (`UploadServiceTests.testIngestVideoUsesRecordedDateAndMarksSource`); 265 desktop UnitTests + full build green.
   NOTE: an ALREADY-synced video won't retroactively fix (ingested pre-fix) — re-sync to see it; the sidebar glyph
   can't be `-snapshot`'d (ImageRenderer/drop-catcher) so eyeball on the Mac.
3. ✅ **Video/source glyph (mobile) — ADDED 2026-06-15.** A video import is neither a share-capture (it HAS audio) nor a
   book-capture, so it had no source marker. Added `MemoMetadata.sourceType` (free-form String, additive/optional,
   value `"video"` via `MemoMetadata.Source.video`; set in `MemoSaver.processVideo` incl. the no-audio-track
   path) → `Memo.isVideoImport` → a `video.fill` leading glyph + a "Video" chip in the list row AND the detail
   header chips. **Mobile-only: NOT added to `UploadMetadata`** (the Mac contract is unchanged — the glyph is a
   phone concern; the full taxonomy on the Mac is still the deferred cross-app item). First entry of the deferred
   "Unified source taxonomy" (voice memo / URL / PDF / video / audiobook quote / Apple Note).

Foundation: read `MemoSaver.swift` (importVideo/processVideo/extractAudio/representativeFrame), the Memos list
row, the Memo-detail player. Gate: iPhone 17 sim build + device-eyeball (it's a device/share-extension flow).
NOTE: also re-test capture/share-into-Skrift generally now that App Groups (Release) is registered (it was
likely broken in prod before — same fix that revived custom-words persistence).

## Device-testing feedback — 2026-06-17 (1 bug-report memo recovered + a data-integrity finding)

Pulled from the dev phone (`com.skrift.mobile.dev`). **Two USB caveats this round** (see "Data-integrity
finding" below): devicectl's CoreDevice **service tunnel was down** (error 1011 — only cached `info details`
worked; every file/app/group call failed), and the per-app store reachable over AFC house-arrest turned out
to be a **stale orphan** frozen at 06-12. The bug report was recovered NOT from the store but by reading the
`wt_<uuid>.json` word-timing sidecars in the private container's `Documents/recordings` (AFC-readable) and
reconstructing the transcript. Raw audio also pulled to `/tmp/skrift-pull/memo_FE3DD029*.m4a`.

### P0/P1 — 🐛 BUG: a recording can get STUCK and never transcribe (no retry) — ✅ FIXED 2026-06-17 (auto-recovery; awaiting device re-test)
**Root cause (confirmed from independent evidence):** `runTranscription` runs in a fire-and-forget `Task`
that can't survive app suspension. The **06-16 23:30 recording (13.48s)** was a **cold-launch auto-record**
(devlog: launch + `record start` at the same instant, 23:30:23 — widget/Siri/deep-link), so the ASR model
wasn't loaded; after `record stop — duration=13.48s` the transcribe `await`s the model load, the app was
backgrounded (late night), the `Task` died → memo stranded at `.transcribing` forever (perpetual spinner =
*"not transcribing at all"*). Proof it never completed: **no `vocab: words=…` line and no `wt_<uuid>.json`
sidecar** for it (every transcribed memo has both). The user asked for *"a reset button or automatic reset."*

**Fix (user chose auto-recovery only — no new UI):** `MemoSaver.recoverStuckTranscriptions()`, called once
per launch from `SkriftApp` (`.task`, skipped on the seeded sim path). No transcription `Task` survives a
relaunch, so any memo still `.transcribing` at launch is orphaned by definition → re-run `runTranscription`.
Scoped to plain recordings/imports: `transcriptStatus == .transcribing && !audioFilename.isEmpty &&
!isBookCapture && <audio file exists>` — capture dictations stay owned by `CaptureDictation.resumePending`,
audiobook captures by `BookTranscriptionJob`. 2 unit tests added; **12/12 MemoSaverTests green on the iPhone 17
sim.** **OWED:** promote to TestFlight → the existing stuck prod memo recovers on next launch (user will
confirm); device-eyeball a fresh cold-launch-auto-record → kill → relaunch cycle.

### Feature — ✨ toggle to disable live transcription for long / battery-saving recordings — ✅ BUILT 2026-06-17 (awaiting device-eyeball)
From the same 56s memo: *"it should be possible to have a button (maybe top-right) that **turns off live
transcription** in case you want to go for a **long recording that needs to use less battery** — where you
just record it once and transcribe it afterwards."* The engine already supported `liveTranscription`
(off = record + waveform only, one-shot transcribe after stop) but it was only a buried Settings toggle.
**Built:** a top-right `captions.bubble`/`.slash` toggle on the record screen (`RecordView.topBar`,
`live-transcription-toggle`), bound to the same persisted `@AppStorage("liveTranscription")` as Settings
(sticky), applying mid-recording via `LiveRecordingService.setLiveTranscription` (tears the live stream
down / brings it up; keeps recording + waveform + `.m4a` write). Off-state shows a "Live transcription off
— transcribed when you stop" placeholder. 2 service unit tests; full app compiles; **37/37 tests green on
the iPhone 17 sim.** OWED: device-eyeball the toggle + off-placeholder + a real long-recording battery run.

### ⚠️ Data-integrity finding — live SwiftData store is NOT in the per-app container anymore
The store AFC house-arrest reaches (`com.skrift.mobile.dev` → `Library/Application Support/default.store`) is
a **stale orphan**: frozen at 2026-06-12 (mtime + max `ZRECORDEDAT`), 16 memos still marked not-deleted even
though the devlog shows a bulk soft-delete of ~18 of them on **06-15** and recordings on 06-16/17 — none of
which are in that file. The **prod** per-app store has no `ZMEMO` table at all. **Strong hypothesis:** when
App Groups landed (~06-12, capture items/widgets) the live store moved into the **App Group container**
(`group.com.skrift.mobile.dev`), orphaning the per-app store. AFC house-arrest **cannot** read App Group
containers — only `devicectl --domain-type appGroupDataContainer` can (and that needs the service tunnel up).
**TODO:** (1) confirm the live store path once the devicectl tunnel is back; (2) if confirmed, **update the
`pull-phone-feedback` skill** — it currently points at the now-orphaned `Library/Application Support/default.store`;
(3) the word-timing sidecar recovery trick (`wt_<uuid>.json` → join `word`s) is a reliable AFC-only fallback
worth baking into the skill.
**✅ RESOLVED 2026-06-21:** all three done. Live store confirmed in the **app group** container
(`group.com.skrift.mobile.dev` → `Library/Application Support/default.store`; tunnel was up, mtime fresh, 6
non-deleted notes matched in-app). Skill updated — pulls from `appGroupDataContainer`, sanity-checks
mtime/`ZDELETEDAT IS NULL`, and bakes in the `wt_<uuid>.json` sidecar AFC-fallback. The per-app store
remains the orphan; don't triage from it.

## ⭐ CONTINUE HERE — Conversation pipeline bug-hunt (2026-06-14)

WILD trace of the whole conversation/diarization → name-linking → Obsidian-export pipeline
(prompt `CONVERSATION_BUGHUNT_PROMPT.md`). 11 bugs confirmed (adversarially verified). **User
decisions LOCKED** (don't re-ask):
1. **Inline name mentions → `[[Canonical|spoken]]`** alias-display, EVERY mention (spoken word preserved).
2. **Turn headers →** FIRST mention full `[[Canonical]]`, every later turn by that speaker plain short `**Tuur:**` (no link).
3. **Merge consecutive same-speaker turns** = YES.
4. **Re-transcribe a diarized memo** = DISABLE (hidden for attributed transcripts).

**DONE (desktop, gated: 255 UnitTests + full `-skipMacroValidation` build green):**
- `Sanitiser.processConversation` — turn-aware linker (merge → first-canonical/rest-short headers → inline alias-display). `process` (monologue) unchanged.
- Pipe-aware link identity everywhere: `Sanitiser.linkTarget`/`hasCanonicalLink`/`linkDisplay`; `BodyTextView.person(matchingCore:)`; resolver first-mention checks (`applyResolvedNames`/`applyResolvedOccurrences`/`applyPartialOccurrences`); unlink/relink restore the SPOKEN word. (The forward-looking "pipe breaks the resolver" trap is closed.)
- `SpeakerTranscript.parse`/`mergeAdjacentTurns` ported to desktop; `isAttributed` line-anchored + ≥2-distinct-speakers (kills the `**Pros:**`/`**Cons:**` false-positive that skipped copy-edit on plain notes).
- `BatchRunner`: conversations → `processConversation`; Mac-diarize path emits PLAIN headers (linking unified at sanitise).
- Re-transcribe + Redo-copy-edit hidden for diarized memos (`NoteActions`, `SidebarView`); `ProcessingCoordinator.redo(.copyEdit)` keeps conversations verbatim.

**DONE (mobile):** `MemoSaver.diarizeIntoTurns` marks `transcriptUserEdited = true` (a low-ASR-confidence
conversation is no longer silently re-ASR'd → turns destroyed at Mac ingest); SpeakerFusion hardened
(stronger smoothing, nearest-BOUNDARY gap metric, post-fusion same-speaker merge).

**Owed / watch:** #4 mid-sentence mis-attribution is *improved* (boundary metric + stronger smoothing +
merge) but bounded by Sortformer quality — manual reassign stays the backstop; device-eyeball a real
Tiuri+Roksana take.

**Follow-ups found by the adjacent-surface hunt (2026-06-14) + the 2026-06-15 batch:**
- ✅ HIGH — Apple Note with ≥2 line-start bold headings misclassified as a conversation → preamble DELETED
  on export. Gated conversation routing on `sourceType == .audio` + preamble preserved (`8c5d9b6`).
- ✅ **Phone same-named-speaker collapse + wrong-voice enroll** — slot-aware rename/enroll via a per-turn
  `turnSlots` map (read fresh from the sidecar at tap), name-based fallback (`580acdc`, `083f223`).
- ✅ **Desktop review bold turn headers** — `**Name:**` renders bold (name) + dimmed `**`, kept in the
  model for export (`cbdb893`). NOTE: still styles ANY line-start `**word:**` (incl. a plain note's
  `**Pros:**`) — defensible markdown-bold, left as-is. Fully HIDING the `**` (vs dimming) is owed
  (NSTextView can't be snapshot-verified → mock-first); the read-only `BodyText.styled` path is unstyled.
- ✅ **Upload phone diarization segments + word-timings** (additive optional `wordTimings`/`diar` parts) →
  Mac karaoke + voice-enroll-from-phone unlocked; byte-compatible (`50bce3a`).
- ✅ **Transcribe a book off-charger** (`3920214`); **audiobook read-along sentence split → NLTokenizer**
  (`0a80da0`).
- ✅ **Custom-vocab over-correction** (device garble "Tuur Skrift Tiuri Tuur…") — trust guard tightened from
  "keep if ANY replacement trusted" to "keep ONLY if EVERY applied replacement trusted" (both apps,
  `VocabularyBooster`; `1170369`). One distant spotter-rescue now drops the whole boost → clean unboosted.
  Precise minSim/cbw tuning still FluidAudio-internal + device-only (DevLog + env knobs to sweep).
- ✅ **Book transcribe in the background** (overnight/charging) — `BookBackgroundScheduler` BGProcessingTask
  (`ade5dde`); benign failure (resumes from saved chunk). **DEVICE-TEST OWED** (no overnight run on the sim).
- **[feature, owed — THE remaining build] Desktop "name a speaker" review affordance.** Mock SIGNED OFF
  (`mocks/name-a-speaker.html`, 3 states: diarized turn cards → click "Speaker 2" → people-picker popover →
  relinked `[[Roksana]]` + "voice learned"). Backend (`embedSpeaker`/`addVoiceEmbedding`) built + proven; the
  phone now uploads the `diar` segments the Mac needs. Scope = Phase-7-size: a SwiftUI speaker-turns card view
  for conversation memos in `NoteBody`/`NoteDisplayView` (today the body is the flat `BodyTextView` NSTextView),
  the picker popover, and tap→relabel-all-that-speaker's-turns + `embedSpeaker`→`addVoiceEmbedding` wiring;
  snapshot-verify via `-snapshot`. Best built ON a device-verified conversation pipeline (rebuild + test the Mac
  Dev build first). When wired, re-validate the uploaded `turnSlots.count` vs the transcript before trusting it.
- **[low/latent] Phone `SpeakerTranscript.parse` not pipe-aware** (a Mac `[[Canonical|spoken]]` header
  doesn't round-trip to the phone today); speaker name containing `*` breaks the Mac header regex (~never);
  monologue `process()` skips demotion when short is empty (whitespace canonical). Fix opportunistically.

## ✅ RESOLVED — Custom words didn't persist on TestFlight (App Groups (Release) not registered)

User reported (2026-06-15, TestFlight build 1): add words in Settings → Capture → Custom words, leave +
return → list empty. **Worked in Dev, failed in TestFlight, same Swift code** → a Release signing/entitlement
issue, NOT the store (`CustomVocabularyStore`, `Services/Transcription/VocabularyBooster.swift`, plain
`UserDefaults.standard`, correct). **ROOT CAUSE:** the Release entitlements (`App/SkriftMobile.entitlements`)
DECLARE `group.com.skrift.mobile`, but the App Groups capability was only registered on the `.dev` app ids
(2026-06-12) — the Release id never got it (the "App Groups at prod promotion" step CLAUDE.md anticipated).
A declared-but-unprovisioned app-group entitlement leaves the Release build in an invalid-entitlement state
that silently breaks `UserDefaults` persistence. **FIX (device-confirmed working):** user checked
`group.com.skrift.mobile` under **App Groups (Release)** in Xcode Signing & Capabilities for the SkriftMobile
(+ SkriftShare + SkriftWidget) targets, re-archived → TestFlight. Custom words now persist. → also unblocks
capture/share-into-Skrift in prod (same App Group). Kept the defensive `.onAppear` reload (`a8d8ab7`).
LESSON → [[project_testflight]]. **Do NOT** move the store to an app-group suite — fix the provisioning.

## Name-link display = SHORT name (revised 2026-06-15)
User clarified: misheard names ("tyr"/"cherry"/"thierry" for "Tuur") must be NORMALISED, not preserved
verbatim. Inline conversation links now render `[[Canonical|short]]` (the person's short, e.g. "Tuur") for
every matched alias (`7a7bf8c`). A mishear only normalises if it's a registered alias of the person — add
via the desktop right-click **"Add '<word>' as → an alias of <person>"** (`BodyTextView` context menu →
`NoteDisplayView.addAlias` → `NamesStore.writeWithSmartBumps`), or fix at the source with custom vocab.
Open question if the user wants it: preserve GENUINE alternate nicknames (vs normalise everything) — would
need marking which aliases are "display" vs "mishear".

## North star — "see how my thinking evolved over time"
The eventual reason the app exists. When I add a note about a realization, surface related notes from across the years and lay them on a timeline ("you had a similar thought in 2019, it shifted in 2021, here's where you are now").
- **Backbone (reachable now, offline):** semantic search across the whole vault using local embedding models; retrieve + rank related notes; timeline UI. Mostly engineering, not model-limited.
- **Harder part (deferred):** having a local LLM *narrate* the evolution well — same quality ceiling as the stale-summary problem. Defer until local models are good enough.

## ⭐ Brain-dump 2026-06-15 (naming model + desktop diarization + summary gate) — triaged, brainstorm pending

From a desktop review session (screenshots in chat). Mix of bugs, features, and 2 design topics:

**BUGS**
- ✅ **Desktop wrongly diarized MONOLOGUES — FIXED 2026-06-15 (off-by-default + Flatten).** Root cause: the
  GLOBAL `settings.conversationModeEnabled` defaulted ON, so EVERY Mac transcription was diarized + Sortformer
  over-split single-speaker notes. Fixes: (a) `conversationMode ?? false` (default OFF — no more auto-split);
  (b) **"Flatten to monologue"** review-menu action (`ProcessingCoordinator.flattenToMonologue` +
  `SpeakerTranscript.flattened`) — strips `**Speaker N:**` headers → prose, clears diarization, re-enhances as
  a monologue (no re-ASR). 268 UnitTests + build green. ⏳ REMAINING (fast-follow): **per-note "Split speakers"**
  (on-demand opt-in diarize on desktop) — needs the diarizer wired into a per-note `ProcessingCoordinator`
  action (mirror the BatchRunner diarize block); deferred to keep this change low-risk. Capability isn't lost
  (phone diarizes conversations; the global flag still works if turned on).
- **Adding a new person doesn't relink existing note text.** Added "Bruno Aragorn" (alias "Bruno") in Names;
  the note's "Bruno" stayed plain (not `[[Bruno Aragorn]]`). Name-linking (Sanitiser) ran before the person
  existed; nothing re-links on add. Fix is entangled with the naming-model decision below (#design).

**FEATURES**
- ✅ **Summary only when the body is long enough — DONE 2026-06-15.** `BatchRunner` skips the Gemma summary when
  the body has < `AppSettings.summaryMinWords` words (default 75; a real setting, tunable). A manual "Redo
  summary" still forces it. Unit-tested (`testShortNoteSkipsSummary`).
- **Right-click → "Add new person" should open the Names settings tab** so you can fill in the rest (aliases,
  short, voice) instead of creating a bare name. Ties into the Names-UX redesign + the relink question.

**DESIGN — LOCKED 2026-06-15 (mock `mocks/opt-in-naming.html`, awaiting final sign-off → then build)**
Opt-in naming model. Detected names render PLAIN; a "People in this note" chip bar lets you tap the people
the note is ABOUT → those link + go in a `people:` frontmatter list. LOCKED rules:
- **One note, one link** — FIRST mention → `[[Canonical|short]]`, every later mention stays PLAIN alias
  (no link littering). The `people:` list carries the graph. (Changes today's conversation linker, which links
  EVERY inline mention → first-only.)
- **No pre-linking** — always start unlinked; user taps the chip. No auto-suggest.
- **Conversations: auto-link the matched speaker** (clearly a subject) — SAME one-link rule (first
  turn-header/mention canonical, rest plain).
- **Mac-only picking for now** — phone "pick people" parked (user working that side separately). Fits the
  phone-sends-RAW / Mac-links contract.
- **Open note only** — adding a person re-scans the OPEN note so they appear as a chip; NO global re-scan.
  (This is how the "added Bruno, text didn't relink" #4 + right-click #3 get resolved — deliberate tap, not auto.)
- **Names settings redesign** — replace the 3 cramped inline columns with a clean LIST (avatar · full name ·
  "aka" alias summary · voice) → tap a row → a labeled detail editor (Full name / Aliases / Short / Voice);
  the SAME editor opens from right-click "Add as a person" in a note. One editor, two doors.

  **BUILD STEPS (mock SIGNED OFF 2026-06-15 — verified what's NEW vs EXISTING against the code):**
  EXISTING, do NOT touch: monologue `Sanitiser.process` is ALREADY first-only (first→`[[Canonical]]`, rest→plain
  short); conversation turn HEADERS already first-only. NEW work only:
  1. ✅ **Opt-in gating (the core) — DONE 2026-06-15 (chunk 1).** `PipelineFile.aboutPeople: [String]` (additive).
     `Sanitiser.process`/`processConversation` take `aboutPeople: Set<String>?` (`gated` helper) — link ONLY those
     people; everyone else plain. EMPTY → links nobody; `nil` = ungated (engine tests). `BatchRunner` (both audio +
     capture paths) + `ProcessingCoordinator` (redo copy-edit) pass `Set(pf.aboutPeople)`. `unlinkedNames` still works.
  2. ✅ **Conversation inline → first-only — DONE 2026-06-15 (chunk 1).** `linkInline` now first-only per person with a
     SHARED `seen` across headers + bodies (two-pass: headers claim speakers, then bodies in document order). A
     speaker's single link is their turn header; later inline mentions demote to the short. Matched speakers auto-link
     regardless of `aboutPeople`. Gate: UnitTests 277 green (9 new: opt-in monologue/conversation, first-only inline,
     two-Jacks tap-one/tap-both) + full `-skipMacroValidation` build green. Conversation tests rewritten to one-link rule.
  3. ✅ **Review "People in this note" chip bar — DONE 2026-06-15 (chunk 3).** `Features/Review/PeopleChipBar.swift`
     in `NoteDisplayView.column` after `NoteProperties`. `Sanitiser.detectedPeople` → chips (plain/OFF by default);
     tap → `ProcessingCoordinator.toggleAbout` flips `pf.aboutPeople` + `resanitiseForNames` (re-link the body LIVE,
     deterministic no-LLM, recompile, save). ON = full name + accent ✓; OFF = `＋ short`. Conversations: matched
     speakers (`Sanitiser.matchedSpeakers`) render LOCKED-ON (auto-linked in their header, can't toggle off) — that's
     how "auto-link matched speaker" + the `people:` list land without seeding `aboutPeople`. Snapshot-verified all
     3 states (`-snapshot-people` PNG, matches mock); 3 detection unit tests. ("Someone else…" add-chip → chunk 4.)
  4. ✅ **`people:` frontmatter — DONE 2026-06-15 (chunk 2).** `Compiler.peopleLinks(in: body)` emits
     `people: [[A]], [[B]]` from the body's DISTINCT linked canonicals (reading order; img markers excluded;
     alias-display resolved to canonical). Derived from the rendered body (not `aboutPeople`) so it can't drift
     and auto-includes conversation matched speakers. Empty `people:` when nobody linked. +2 CompilerTests; gates green.
  5. ✅ **Names settings redesign — DONE 2026-06-15 (chunk 4).** `Features/Settings/PersonEditor.swift` (shared,
     labeled detail editor: Full name / Aliases + recognition demo / Short + link-display hint / Voice). `SettingsView`
     Names section is now a clean LIST (`nameListRow`: avatar · full name · "aka" aliases · voice) → tap a row → the
     editor; "Add person…" row → new. The SAME editor opens from a note's right-click "A new person…" (`addName` →
     pre-filled) + the chip bar's "Someone else…"; on save → `NamesStore.upsert(replacing:)` (rename-safe, carries
     voiceprints) + `coordinator.resanitiseForNames(open note only)` so the new person shows as a chip — no global
     re-scan. `NamesStore.delete` tombstones. Snapshot-verified (`-snapshot-names` panel 4, `-snapshot-person-editor`
     panel 3) + 3 upsert/delete/rename unit tests.
  **ALL 5 BUILD STEPS DONE 2026-06-15.** Gates each chunk: UnitTests 288 green (+21 over baseline) + full
  `-skipMacroValidation` build green. Review UI eyeballed via dedicated PNG snapshots (chip bar 3 states, names list,
  person editor) — all match the mock. Deploy desktop per [[feedback_desktop_dev_deploy]] (owed, prod idle).
  **Adversarial review pass (4-dimension workflow + verify) → 4 real fixes:** (1) `processConversation` ambiguity was
  computed over the WHOLE names DB, not the in-play (about ∪ speakers) set → tapping one of two same-alias people now
  links inline (matches `process`); (2) `people:` now filters to KNOWN PERSONS + skips `![[embeds]]` (a place/embed in
  an Apple-Note/capture body no longer pollutes the people graph) — `Compiler.compile(knownPeople:)` threaded through
  all production call sites incl. export; (3) `NamesStore.upsert` MERGES on an add-name collision instead of clobbering
  an existing person's aliases/voice; (4) `linkInline` demotes to the canonical when a person has no short. +3 tests.

  ⭐ **CONTINUE HERE (2026-06-16) — naming/sanitising RE-DERIVED FROM FIRST PRINCIPLES → ✅ DESIGN LOCKED in `NAMING_MODEL.md`.**
  A deep `/grill-me` session resolved the WHOLE solution from the job-to-be-done. **Read `NAMING_MODEL.md`** — it's the
  authoritative spec (supersedes `mocks/opt-in-naming.html` + shipped chunks 1–5). Headline: flip opt-in → **OPT-OUT**
  (auto-link known people, prune side-characters); recognition = **known-roster-only seeded from the `People/` folder**,
  new people added manually (no NER/LLM — must stay phone-portable); keep ONE body link (first mention) for the backlink
  **snippet** + keep `people:` frontmatter; **KILL** the chip bar + the per-occurrence resolver; click-a-name-in-the-prose
  popover replaces the chip bar; mistranscribed known names normalise (dotted + revertible). It's mostly DELETION + a
  default-flip, not new building. **Status (2026-06-16): design LOCKED + research-validated** (prior-art pass verdict =
  "sound as-is, build it"). Refinements folded into `NAMING_MODEL.md`: risk-tiered opt-out (auto-commit
  full/distinctive names, dotted-suggest common-word/ambiguous ones via a stoplist), aliases live in the PORTABLE DB
  (not the Obsidian note — phone may not use Obsidian), one-keystroke fuzzy add-picker; REJECTED the new-person hint
  (even deterministic). Plus NON-NEGOTIABLE build-guards (FP guards, skip audiobook-quote spans, re-scan on roster
  collision, frontmatter-canonical lockstep, fuzzy-vs-strict golden-set, date-sorted person view).
  **BUILD (2026-06-16, on `main`):**
  - ✅ **Chunk 1 — Sanitiser → opt-out + risk-tiering.** `aboutPeople` include-gate + `gated` DROPPED;
    `Sanitiser.process`/`processConversation` now link ALL known people by default (first mention,
    `unlinkedNames`-pruned). Risk-tiered via new `NameStoplist.swift`: full/distinctive names auto-commit;
    common-word / ≤2-char / ambiguous names → dotted **suggestions** in `Result.ambiguous`
    (`candidates.count` 1 = common-word, ≥2 = ambiguous), capitalization-guarded. `nonProseRanges` skips
    leading YAML / fenced+inline code / audiobook-quote spans (build-guard). Callers updated; opt-in tests
    rewritten opt-out + risk-tier + quote-span. **Gate: 288 UnitTests green + full app build green.** The
    `pf.aboutPeople` field + chip-bar/resolver wiring are now INERT — deleted in chunk 3.
  - ✅ **Chunk 2 — Roster seeding from `People/` titles.** New `PeopleFolderScanner` lists
    `<vault>/People/*.md` filenames (privacy: titles only, no contents, no AI); `NamesStore.seedRoster`
    upserts each new title (canonical = title; aliases = full title + first-name token), idempotent +
    non-clobbering + synced. Seeded before each processing run. **Gate: 295 UnitTests green + full app
    build green.**
  - ✅ **Chunk 3 — Delete + data-model flip.** Deleted `PeopleChipBar.swift` + `InlineResolver.swift`
    (model/banner/`ResolverPopover`) + the per-occurrence Sanitiser engine (`applyResolved*` /
    `applyPartialOccurrences` / `PartialChoice`/`PartialApplyResult` / `plainSlotMap` / `detectedPeople`
    / `matchedSpeakers`; kept `plainOccurrences` for the unlink popover). Unwired from
    `NoteDisplayView` + `BodyTextView` (the click-a-linked-name **unlink/change popover stays**).
    Data-model: dropped `PipelineFile.aboutPeople`, added the `namePicks` ambiguity-pick record;
    removed `toggleAbout` + the `-snapshot-resolver`/`-snapshot-people` modes. **Gate: 273 UnitTests
    green + full app build green.**
  - ✅ **Chunk 4 (the heavy one) — in-prose 3-tier UX.** ENGINE: `namePicks` (force-link / `""`
    silence) + `neverLink` refined to PRUNE→SUGGEST (unlinked name stays dotted + re-promotable),
    via a shared `Overrides` struct. UI (`BodyTextView` NSTextView): linked #9d8ff7 / suggested tan
    dotted / plain, model→storage offset-mapped past image markers; `SuggestionPopover` (state 2) +
    `LinkedNamePopover` (state 3). `NoteDisplayView` wires each decision → set-mutation +
    `resanitiseForNames` + undo toast. **Gate: 278 UnitTests green + full app build green; visual
    verified vs the mock via `-snapshot-naming`.** OWED: live in-NSTextView body eyeball after deploy.
  - ✅ **Chunk 5 — Robustness.** `RosterAudit` (`newlyAmbiguous`/`affectedFiles`) +
    `ProcessingCoordinator.rescanRoster` wired into `savePerson`: a fresh same-name collision
    re-derives every memo that auto-linked that name (→ dotted suggestion) + flashes the count.
    Matcher kept STRICT (whole-word + capitalization, no edit-distance fuzz — boost + manual-add
    cover mangles); `NamingGoldenTests` pins the tiering + prune/pick round-trip. Build-guards
    finalized (FP guards / non-prose skip / re-scan / frontmatter-lockstep / own-the-files ✅;
    date-sorted person view = Obsidian-side, deferred). **Gate: 286 UnitTests green + full app build green.**
  ✅✅ **ALL 5 CHUNKS DONE (2026-06-16).** The opt-out naming model is built, gated, committed on
    `main` (chunks 1–5: `67de42f`, `6d458e8`, `8ae5f4f`+`d7852c3`, `19979f8`, + chunk 5; fixes `3fc55a1`
    change-person force-link + `ba1c779` change-person scoped to same-name). Deployed to
    `/Applications/Skrift Dev.app`; `-naming-demo` flag seeds a self-consistent live example.
    Device-eyeballed by the user (change-person bug found + fixed). NOTE: a parallel session committed
    mobile work onto `main` mid-build (see `feedback_parallel_orchestration`) — recovered cleanly.

  **Naming — open questions (post-build review, 2026-06-16; answers logged, none blocking):**
  - ✅ Q1 DONE (`commit below`): monologue `process` existing-link check is now PIPE-TOLERANT —
    swapped the literal `occurrences(of: "[[Name]]")` for `linkOccurrences(of: canonKey)` (matches bare
    AND `[[Name|short]]`), so a piped link can never slip past into a 2nd link; removed the now-dead
    literal `occurrences` helper. Regression test `testExistingPipedLinkSuppressesSecondLink`. (Was
    latent-not-live; folded in as cheap insurance per the user.)
  - Q2 (edge): `nonProseRanges` skips only a LEADING audiobook quote (contract C1 guarantees `> ` at
    offset 0). A mid-body `>` blockquote (only from a hand-authored Apple-Note import) isn't protected →
    names inside auto-link. Optional: skip ALL `>`-line runs, not just leading. ⏳ optional.
  - Q3/Q4 (real limitation): `rescanRoster` re-derives the IN-APP `f.sanitised`/`ambiguousNames` + flashes;
    it does NOT rewrite already-EXPORTED vault `.md` (the user re-Exports). `affectedFiles` scans body
    links (`people:` is derived from them in lockstep, so they match). Per-note `namePicks` ARE preserved
    through the re-derive. ⏳ FOLLOW-UP: auto-re-export affected exported notes + also scan `people:` as a
    belt-and-suspenders.
  - Q5 (intent): `minAutoCommitLength = 3` → ≤2-char names suggest, 3+ auto-commit. INTENTIONAL — 3-char
    given names (Sam/Tom/Ben/Kim/Jan) are distinctive under whole-word+capitalization; the vocab-booster's
    ≤3–4-char flag was about FUZZY transcription spotting, not exact naming. One-line bumpable if FPs show.
  - Q6 (intent): the capitalization guard fires a dotted suggestion on a sentence-initial stoplisted word
    that's also a roster name ("Will you…"). ACCEPTED noise — it's a dotted SUGGESTION (no link written,
    one-click dismiss). A following-token/POS check is possible but adds heuristic FP risk; hold unless annoying.
  - Q7 (real friction) — DECIDED 2026-06-16: NOT NOW (user). A FREQUENT person whose name is on the stoplist
    (Mark/Rose/Max…) is dotted-suggested every memo (click-to-confirm), never auto-linked. The fix if it ever
    bites: a per-Person "treat as distinctive" override (opt out of the stoplist guard). Parked, not built.
  - Q8 (scale): the auto-link pass is O(people × aliases) whole-word regex + recomputes `nonProseRanges`
    per person (link-find + demote). Fine at hundreds; at thousands (lifelong/phone roster) it adds up,
    worse in `rescanRoster` over many files. ⏳ FOLLOW-UP if it slows: one alternation-regex/Aho-Corasick
    candidate pass + compute `nonProseRanges` ONCE per `process` (edits are localized).
  The grill detail below is kept as the audit trail.
  --- (original re-open framing, now resolved by NAMING_MODEL.md) ---
  User's call (do NOT narrow this to a bug fix): the "two Jacks" friction is a SYMPTOM that made the user question
  whether the entire naming/sanitising approach is the right shape. Next session = re-derive it from the
  job-to-be-done, NOT patch the chip. We may delete/replace large parts of what we just built — that's on the table.
  - **The trigger (symptom, evidence — not the task):** a note about two friends both named "Jack" shows two
    identical `+ Jack` chips; the chip MODEL ("note is about person X → link X everywhere, one-note-one-link")
    conflicts with the per-occurrence reality (different mentions = different people = the existing
    `Sanitiser.applyResolvedOccurrences`/`InlineResolver` resolver). The opt-in gate also stopped the resolver from
    auto-appearing on fresh notes. The signed-off mock only covered DISTINCT names → same-name is unspecified.
  - **First-principles questions to grill (the real agenda):**
    1. What JOB does name-linking actually do for the user in the vault? (find "all notes about X" / a people graph /
       …?) Everything else is downstream of this.
    2. Do we even need INLINE `[[links]]`, or does the `people:` frontmatter list ALONE deliver the job? (The mock
       itself says "the people: list carries the graph connection" → the inline first-canonical/rest-alias machinery,
       per-occurrence resolver, unlink/relink, alias-display may all be solving a non-problem.)
    3. Is the names DB + alias normalisation pulling its weight, or accidental complexity from "ASR mishears names"?
    4. Two-Jacks / per-occurrence disambiguation: real recurring need or over-engineered edge?
    5. Right layer & time for linking: Mac pipeline now vs tap-on-phone vs let Obsidian resolve at read-time.
  - **Process for next session (user-locked):** (1) deep `/grill-me` on the WHOLE solution (Claude interviews the user
    relentlessly to reach shared understanding); (2) research agents to hunt SIMPLER / better prior-art solutions
    (how do other tools link/disambiguate same-name entities — Obsidian plugins, Roam, Logseq, Tana, Reflect, etc.);
    THEN decide → mock → build. Re-read this block + `mocks/opt-in-naming.html` first.
  - **What's already SHIPPED (unaffected, on `main`, may be partly reverted after the rethink):** opt-in chunks 1–5
    (Sanitiser `aboutPeople` gate, first-only inline, `people:` frontmatter, chip bar, Names list→detail editor) +
    the adversarial-review fixes. All gated/tested/deployed; see the BUILD STEPS + review block above.

## Sync says "connected" but memos stay "Waiting" (2026-06-15)

Device-reported: Dev mobile → Dev Mac, Settings shows connected, memos keep saying Waiting.
**Diagnosis (from pulling the phone's prefs + Mac `lsof`):**
- The Settings green "Connection" dot showed **whenever a pairing was merely SAVED** (`MacConnection.load() != nil`)
  — NO live check. So it claimed "connected" even when the Mac was off / on another Wi-Fi / a stale port.
- The sync path had **zero logging** (a silent `catch {}` left memos Waiting) → undiagnosable.
- The user's Mac was running **TWO `Skrift Dev` instances** (PID from Xcode DerivedData on `:8000` + a 2nd from
  `/Applications`). Two instances share one bundle id → one SwiftData store → writes contend. GET health/files
  (reads) answered 200, but the upload **POST (write)** is the likely casualty → the phone leaves the memo Waiting.
  (CLAUDE.md already warns: "quit the running app first — a 2nd instance races the shared SwiftData store.")
**Fixes (committed):**
- Settings dot is now a **live `/health` probe** — green only when the Mac actually answers; amber + "unreachable"
  + a hint when paired-but-not-answering (`SettingsView.checkReachability`).
- **Sync is now DevLog-traced** (`SyncCoordinator` + `URLSessionMacTransport`): target host:port, eligible count,
  each `POST …/upload → HTTP <code>` (or the error), final `newlySynced`. Pull `devlog.txt` after a sync tap.
**Owed / user action:** quit the duplicate `Skrift Dev` Mac instance (keep ONE), ensure the phone is on the same
Wi-Fi (Mac is `192.168.50.111:8000`), then tap Sync — read the `sync:` trace to confirm. Possible follow-ups:
single-instance lock on the Mac; auto re-resolve the Bonjour host/port at sync when the saved one is unreachable
(self-heal a changed Dev port); manual-sync is by design (no auto-sync).

## Cross-app parity gaps (audited 2026-06-15 — 9-agent verify-vs-code sweep)

The desktop↔mobile split is overwhelmingly INTENTIONAL (phone records/captures → Mac processes/links/
enhances/exports). The audit (verified each `FEATURES.md` row against real code in both apps + a completeness
critic) found exactly **two real functional gaps** to bridge; everything else is by-design or already parity:

1. ✅ **DONE 2026-06-15 — Desktop list search + sort.** Added to the Mac sidebar: a text-search field
   (title/transcript/summary), a Newest/Oldest/Title sort cycle, and a "No matches" empty state, on top of the
   existing 3-way `QueueFilter`. `AppModel.matchesSearch`/`SidebarSort`/`visible` + `SidebarView.searchField`/
   `sortControl`/`noMatches`. Live-verified via `SidebarSearchSortUITests` (the sidebar can't be `-snapshot`'d —
   ImageRenderer can't render its `FilePromiseDropCatcher`/`dropDestination`; macOS XCUITest needs Automation
   permission enabled). Sort is a cycle BUTTON (not a Menu) on purpose — a Menu also breaks ImageRenderer.
2. ✅ **DONE 2026-06-15 — Mobile direct "Add voice" enrollment.** `VoiceEnrollView` now records a short
   on-device sample (`FeedbackRecorder` → FluidAudio `AudioConverter` 16 kHz → `VoiceEnroller.enroll` → embed +
   `NamesStore.addVoiceEmbedding` + sync) — the SAME pipeline the conversation speaker-naming path already used
   (was a "Got it" placeholder). ≥3 s guard (`SpeakerEmbedder.minSamples` 32 000 = 2 s); audio discarded after
   embedding. UI-probe-verified (`VoiceEnrollUITests` on the iPhone 17 sim — seeded "Bob Smith" → Add voice →
   real recorder renders; screenshot `/tmp/skrift-enroll-shots`). On the sim the SeededEmbedder stands in for the
   ANE; device-eyeball owed for a real wespeaker embedding.

Deferred-by-choice (intentional, not gaps; do only if symmetry wanted): desktop **Models tab** mirror
(`FEATURES.md` "Mac mirror = later"); **custom-vocab word-list sync** (per-device by design — the only
intentional contract data-exclusion); desktop **Send-feedback** port; desktop **auto-copy transcript**.
Doc drift fixed in the same pass (`FEATURES.md`): capture-items `➖/➖`→`✅/✅` (was the worst — implied a
shipped feature was unbuilt), diarize/voice-match/persist-segments/bold-headers mobile statuses corrected,
search/sort desktop `✅`→`🟡`.

## Other deferred items
- **Watched-folder ingest** — point Skrift at a folder (e.g. the Mac Voice Memos export) for zero-friction auto-ingest. (The overhaul keeps ingest simple: drag/picker + phone sync.)
- **Summary prompt quality** — summaries read stale / not in my voice. Dedicated prompt-tuning pass once the rest is stable.
- **Tagging matchable-subset + lemma expansion** — which vault tags are auto-matchable (flag-per-tag vs separate list) and conjugation/lemma handling. Being decided in the mobile-app chat; align the desktop to it.
- **Git housekeeping** — remove the empty `claude/competent-haslett-718d5a` worktree; finish mining `robustness-cleanup` for any remaining good fixes before deleting it.
- ✅ **DONE (2026-06-09, parallel-lanes batch)** — **Import VIDEO → transcribe (with the real recording date)** —
  both apps. Phone: PHPicker + share/open-in video UTIs → extract audio (`AVAssetExportSession`) + ONE frame
  thumbnail as `[[img_001]]`, `recordedAt` from the embedded creation date. Mac: `IngestService` detects video →
  extracts audio. Open-Q resolved: **audio-only + 1 frame thumbnail** (original video discarded). Original plan kept below.
  accept video files on the
  phone (e.g. self-recorded "life advice to myself" clips) and transcribe their audio.
  Plan: extend the import path to video UTIs (`CFBundleDocumentTypes` += `public.movie` /
  `public.mpeg-4` / `com.apple.quicktime-movie`; `AppURLHandler` → `MemoSaver`) and/or a
  Photos picker (`PHPickerViewController`, filter `.videos`). Extract the audio track via
  `AVAssetExportSession` / `AVAssetReader` → feed FluidAudio on-device.
  **The memo's `recordedAt` MUST come from the video's embedded creation date**
  (`AVAsset` `.creationDate` metadata, or `PHAsset.creationDate` from the library) — NOT the
  import time. Mirrors how the Mac reads the embedded m4a recording date. Open Qs: keep/attach
  the original video or audio-only? a frame thumbnail as a `[[img]]`? Desktop side:
  `UploadService` / ingest needs the same audio-extraction if videos sync to the Mac.

## Mobile ↔ desktop unification + mobile UX (2026-06-08 brain-dump)
Captured from a session brain-dump; parity audit done (file refs are on branch `native`).
Locked process for the UI items: spec → mock → build → XCUITest (feedback_native_ui_process).

### Decisions taken (this session)
- **Significance gates sync — flag-to-send / opt-in.** Add a per-memo significance value on
  MOBILE, mirroring desktop's slider (0–1.0, snap 0.1, labels Passing/Useful/Significant —
  `SkriftDesktop/.../NoteProperties.swift:118`, stored `PipelineFile.swift:90`). **Default 0 =
  stays on the phone; > 0 = eligible to sync to the Mac.** Persist it on `Memo` + send it in the
  upload metadata (NEW, additive/optional contract field) so the Mac pre-fills its slider.
  (User: "only if they have more than 0 significance are they suitable for transfer — I don't
  need to send stupid messages to the Mac.") NOTE: this flips today's behavior (mobile currently
  uploads ALL `waiting` memos unconditionally — `SyncCoordinator.swift:31`).
- ✅ **DONE (2026-06-09)** — **Liquid-glass playback bar.** Replaced the ghosting `LinearGradient`
  with a real iOS-26 Liquid Glass floating bar (`.glassEffect(.clear)` + `.safeAreaInset(edge:.bottom)`
  so transcript scrolls cleanly *under* it), and slimmed its vertical height. The iOS-18-target note
  below is OUTDATED — we run iOS 26 and use `glassEffect`. **Device gotcha (logged for the next chat):**
  the lensed look needs `.clear` (`.regular` reads frosted), and **Reduce Motion ON throttles Liquid
  Glass on A15** (user's phone — turn Reduce Motion OFF); the Simulator never renders specular/chromatic
  glass, so judge glass on-device only.

### Items
1. ✅ **DONE** — **Significance slider on mobile + sync gating** — slider + flag-to-send live; the
   2026-06-09 batch also fixed the list to show **no sync pill** for significance-0 (phone-only) memos.
2. ✅ **DONE (2026-06-09 batch)** — **Append-more-transcription to an existing note** — a visible top-right
   "+" button on memo detail (and the ⋯ menu) records more audio → transcribes → appends + merges audio. Mobile-led.
3. ✅ **DONE (2026-06-09)** — **Karaoke on mobile** (unification): word-level highlight + tap-to-seek
   during playback. Was: mobile stored word timings (`WordTiming.swift`/`WordTimingsStore`) but never
   rendered them. Device-verified ("karaoke and edit work well").
3.5 **Mobile delete/select UX** — ✅ swipe-to-delete DONE (native List `.swipeActions`, full-swipe
   commits, in `MemosListView`; verified 2026-06-12 status audit). Still open: a nicer
   drag-to-multi-select (Photos/Mail-style) to replace the Select button.
4. **Feedback/email in Settings** — NEITHER app has any feedback/contact mechanism today. Port from
   the user's **Shhhcribble** app at `/Users/tiurihartog/Hackerman/ShhcribbleiOS` →
   `ShhhcribbleiOS/Features/Feedback/` (explored 2026-06-08). Its module:
   - `FeedbackStore` — file-based `Documents/Feedback/<uuid>/{metadata.json, screenshot.png}`,
     items = {createdAt, transcript, note, hasScreenshot, durationSeconds, sentAt?}; CRUD + markSent.
   - `FeedbackRecorder` — dictate feedback (record→transcribe→keep TEXT, discard audio).
   - `FeedbackCaptureView` / `FeedbackListView` — capture (note + optional pasted screenshot + dictation)
     + list with "Sent ✓" badges.
   - `FeedbackMailComposer` — `MFMailComposeViewController` (MessageUI, `UIViewControllerRepresentable`);
     To: `tiurihartog@icloud.com`; subject/body = transcript+note+timestamp+device; attaches a `.zip`
     of the raw folders (via `NSFileCoordinator .forUploading`). `canSendMail()` guard.
   **Skrift port plan:** add a "Send Feedback" row in `SettingsView.swift` → a capture sheet (typed note
   + optional dictation REUSING Skrift's `TranscriptionService`/`LiveRecordingService` + optional
   screenshot) → `FeedbackStore` (mirror, file-based) → email via an MFMailComposer wrapper. Needs
   `UIFileSharingEnabled`-style access if we want Files visibility. Consider desktop later (unification).
   Recipient `tiurihartog@icloud.com` (configurable).
5. **Capture items** — the big deferred cross-app feature (share URL/text/image + annotate): mobile
   share-extension target + App Group + `attachments` multipart; desktop `UploadService` accepts a
   non-audio "capture" content type through pipeline/compile/export. (Also in root CLAUDE.md.)
6. **"Transcription a bit weird" on cold auto-start** — user UNSURE it's a real bug now; park / quick-
   check only (live caption catching up while the model loads mid-recording).

### Dev/prod separation — ✅ DONE (verified implemented 2026-06-09)
Both apps split by config: Debug = `com.skrift.{mobile,desktop}.dev`, **"Skrift Dev"**, own data container +
test vault; Release = the real **"Skrift"**. The 2026-06-09 session also fixed the desktop menu-bar NAME
(`PRODUCT_NAME` per config, since `INFOPLIST_KEY_CFBundleName` was being dropped) and installed prod "Skrift"
to `/Applications`. **Open follow-up:** inverted-color dev app ICON (both apps) so dev is unmistakable by icon too.
Original decision recorded below.

#### (original decision, 2026-06-08)
Goal: use Skrift for real (real recordings/notes/vault) while still iterating, with the
real data OS-guaranteed safe from dev churn. **Approach = bundle-ID split** (chosen):
- **Production** keeps the current bundle IDs (`com.skrift.mobile` / `com.skrift.desktop`)
  — the install already on the phone, real data preserved.
- **Dev** builds get `.dev` bundle IDs → a brand-new, SEPARATE OS data container; dev
  builds physically can't touch prod memos/recordings/names. macOS Dev defaults its
  export to the **test vault** (`~/Hackerman/Obsidian_LLM_Test_Vault`), never the real one.
- iOS `.dev` plumbing: own App Group (`group.com.skrift.mobile.dev`) + widget/shared
  bundle IDs + automatic signing (team 9W82X49JZS handles new IDs); dev Mac advertises a
  distinct Bonjour name so the dev phone pairs with the dev Mac.
- **Look = name only** ("Skrift Dev"), same icon (user's call).
- Implement via an xcodegen build configuration that overrides bundle ID + display name
  (+ App Group/Bonjour for dev); keep Release = production.
- **"Switch them out" = promote** dev code under the prod bundle ID; SwiftData migrates in
  place. SAFE BY CONSTRUCTION if model changes stay **additive** (defaults, like
  `significance: Double = 0`) → lightweight migration. Test the migration on a copy first.

### Unification audit (mobile vs desktop) — exists on ONE side only
- significance slider → desktop only (→ add to mobile, item 1)
- karaoke word-highlight → ✅ DONE on mobile (2026-06-09); was desktop-only
- per-memo sync gating → NEITHER (→ new, item 1)
- feedback/email → NEITHER (→ new, item 4)
- swipe-to-delete → NEITHER (→ mobile, item 3.5)
- deep settings (vault/author/model/prompts) → desktop only (intentionally NOT unified — Mac-side concerns)

## Features to implement (added 2026-06-09)
- **Direct "record a voice" enroll in Settings → Names & voices** — today the "Add voice" row is a
  status label only; voices enroll ONLY via conversation-mode naming. Add a tap-to-record-a-sample
  enroll flow so a Person can be given a voiceprint directly. (Tied to the embedding-cosine pivot —
  see `CONVERSATION_MODE_HANDOFF.md` §5.) Both apps (the Names & voices tab is on phone + Mac).
- ✅ **DONE (2026-06-09 batch)** — **Desktop Liquid Glass pass** — the Mac review transport bar is now a
  floating glass capsule (`.glassEffect(.regular)` on macOS 26 + `.ultraThinMaterial` fallback). Judge live;
  flip `.regular`→`.clear` for a more lensed look. Sidebar left opaque (could extend).
- **Re-ingest the ~30 old notes** from `~/Desktop/Skrift old notes/` — run the existing ingest over
  them (DO WITH the user: needs the prod desktop app quit for the shared-store race, and it writes
  into the REAL Obsidian vault).
- **In-app feedback → `backlog.md` (not just email)** — today dictated/typed feedback is emailed
  (mobile `Features/Feedback/FeedbackCaptureView.swift` → `FeedbackMailComposer`, recipient
  `tiurihartog@icloud.com`; desktop has none yet). Idea: route feedback straight into this
  `backlog.md` so ideas become triage-ready items without copy-paste. **Constraint:** `backlog.md`
  lives in the repo (Mac/dev side) — the phone can't write it directly. Options: (a) sync feedback
  phone→Mac like memos, then the Mac appends to a dedicated `## Inbox (from in-app feedback)` section
  here; (b) a small scheduled agent reads the feedback inbox/email and appends + lightly tidies into
  the right section; (c) the desktop feedback module writes locally. Open Q: append raw vs. have an
  agent dedupe/route into existing sections. Pairs with the feedback port (item 4 above).
- **Show downloaded models in phone Settings** — a Settings → "Models / Storage" section listing
  the on-device models (Parakeet ASR; the diarization + voiceprint models once enrolled): downloaded?
  size, version, and optional actions (re-download, delete to free space). The state already exists
  (onboarding download + the record-ready preload status, `RecordView.swift:271-292`) — surface it in
  `Features/Settings/SettingsView.swift`. **Unification:** desktop also downloads models (~600 MB ASR
  + ~9 GB Gemma) — mirror a Models/Storage view on Mac Settings (ties to the desktop model-unload
  idle-timer backlog item). Open Q: read-only display vs. management (delete/re-download).

## Follow-ups from the 2026-06-09 parallel-lanes batch
Most of the brain-dump shipped this batch (record-screen polish, list fixes, video import, desktop glass,
diarization-segment persistence) — see `FEATURES.md`. Remaining threads it opened:
- **Task A — auto-sync names after voice enrollment (REAL BUG, confirmed).** Naming a speaker enrolls the
  voiceprint into the phone's local `names.json` but **never auto-pushes** — it only reaches the Mac on a manual
  sync-button tap (`SyncCoordinator.syncAll` is the ONLY caller of `NamesSync`). So cross-device auto-match
  silently lacks the new voiceprint until a manual sync. Fix: fire a names-sync right after a successful enroll
  (tail of `VoiceEnroller.enroll` / `learnVoice`, or on memo-save / app-foreground), debounced + guarded on a
  paired Mac. The merge/UNION itself is correct (now covered by `SkriftDesktopTests/NamesSyncRoundTripTests`).
- **Task A — live device round-trip** (human-gated): enroll on phone → confirm it lands in the Mac `names.json`
  with the server running → process that person's clip on the Mac → confirm `VoiceMatcher` auto-labels them.
- **Task B — Mac "name a speaker" review UI** (build phase): mock done (`SkriftDesktop/mocks/name-a-speaker.html`,
  awaiting sign-off); backend done (segments persisted: `DiarizationSidecar` + `PipelineFile.diarizationSegments`).
  Owed: a conversation-turn renderer in `Features/Review/` + click-to-name → people picker → relabel `**[[Person]]:**`
  → `DiarizationService.embedSpeaker` + `NamesStore.addVoiceEmbedding`.
- **F3 live confidence-color** is a positional approximation (trailing 6 words = "settling") — FluidAudio's live
  path exposes no finalized/volatile flag. Revisit if/when it does, for true locked-vs-volatile coloring.
- **Inverted-color dev app ICON** (both apps) so dev is unmistakable by icon (not just name).
  ✅ DONE same day (Debug → `AppIcon-Dev`, RGB-inverted; both apps).

## Device-testing feedback — 2026-06-10 (12 memos + feedback note pulled off the dev phone)
User ran the full TESTING_2026-06-09.md pass. Transcripts pulled via `devicectl` from the dev container;
crash logs via `idevicecrashreport`. **PASSED:** title-on-rows ✓, sig-0-no-pill ✓, + append button exists ✓,
keyboard-dismiss ✓, inline photos ✓, caption scrollback ✓, video date ✓, desktop video ingest (via Finder) ✓,
glass bar acceptable ✓.

### P0 — ✅ ALL FOUR FIXED (2026-06-11 fix batch, merged + all tests green; awaiting device re-test)
Fixes in brief: (1) crash → caption is ONE AttributedString in a single Text (run-count pinned by test);
(2) append → .transcribing shown throughout, clip kept until text lands, retry-with-backoff, terminal
failure surfaces as Error pill, editor-clobber window closed; (3) tail cutoff → explicit AVAudioFile
close() finalizes the m4a before transcription reads it (same race also hit append clips); (4) Live
Activity → staleDate+keep-alive, "Recording interrupted" stale fallback, foreground orphan reaping.
PLUS: instant record (locked decision — every record entry auto-starts), Spotify ducks only on Play,
paste keeps scroll position, row swipe/long-press Copy, desktop editable summary, first-mention-only
name links (incl. conversation turn headers), desktop video thumbnail, drag-from-Photos promised files,
retranscribe clears stale segments, list-delete cleans the diar sidecar. Original P0 list below.
1. **CRASH mid-recording (3× today, one recording LOST).** All three .ips identical: SIGSEGV "stack size
   exceeded due to excessive recursion" in SwiftUI `ConcatenatedTextStorage.resolve` — the live caption is
   built as per-word concatenated `Text` runs (solid+volatile+photo tokens), so a long recording → thousands-
   deep `Text + Text` chain → stack overflow. Fix: build ONE `AttributedString` and render a single
   `Text(attributedString)` (constant depth). Crash files: `/tmp/skrift-crashes/SkriftMobile-2026-06-10-*.ips`.
2. **Append silently adds NO text** (3× repro, BROADER than the model-cold theory — verifier-corrected).
   Repros: (a) stopped the append recording before the ASR model loaded; (b) tried AGAIN with the model
   presumably warm — still no text; (c) appended after manually editing the note body — nothing added.
   `MemoSaver.appendRecordingAsync` merges audio but can silently add no text with no error. Fix: REPRODUCE
   first (all three sequences), then harden the whole append-text path — never silent-no-op, queue
   transcription when the engine isn't ready (status `.transcribing`), surface failures; regression tests
   for cold-model append and append-after-manual-edit.
3. **Tail of recording cut off after Stop** (BOTH dev + prod, intermittent): live caption had the full text,
   then the final one-shot file transcription replaced it WITHOUT the last bit. Likely a race: final
   transcribe reads the file before the writer flushes the last buffers, or stop truncates. Investigate
   `LiveRecordingService.stop` → final transcribe ordering. "This shit needs to be very robust."
4. **Live Activity doesn't end**: lock screen still showed "recording, 45min" long after stop+save. End/
   dismiss the activity reliably on stop (and on app foreground if stale).

### P1 — bugs (post-promotion ok)
- **Confidence colors wrong in practice**: "white text is supposed to be non-changing but it also changes" —
  the positional approximation visibly fails (re-transcription rewrites the 'solid' body too). Either find a
  real finalized signal or drop/soften the distinction.
- **Opening a memo stops Spotify**: audio session activates on note open (player setup) instead of on Play.
  Use `.ambient`/don't activate until playback; respect `.mixWithOthers` when idle.
- **Paste into note body teleports scroll to top** (mobile editor) — keep scroll position after paste.
- **Share-a-video from Photos doesn't list Skrift** (mobile): document types alone don't surface the app for
  videos in the share sheet — likely needs a share extension or different UTI handling. (Photos→file works.)
- **Desktop: drag direct from Photos app doesn't ingest** (works via Finder) — Photos drags provide promised
  file/`NSItemProvider`, not a file URL; accept promised files in the drop handler.
- **No video thumbnail seen — check BOTH apps** (verifier: source ambiguous). Desktop `ingestVideo` has no
  frame-grab by design → add one (mirror mobile). Mobile claims `[[img_001]]` — verify it actually renders
  on a real import.
- *(doc fix, not a bug: TESTING guide said the desktop glass play bar is at the BOTTOM — it's pinned at the TOP.)*
- **Desktop: summary not editable** in review.
- **Desktop: name-linking brackets EVERY mention** (user expects `[[Name]]` first mention only, alias after —
  the Sanitiser's design intent; verify what produced all-bracket output, possibly the conversation-turn
  headers or a regression).
- **`SkriftMobile.diskwrites_resource-2026-06-10-221621.ips`** — disk-writes resource warning; check what's
  writing heavily (likely model download or audio writes).

### Feature decisions — LOCKED 2026-06-10 (user sign-off)
1. **Feedback loop = plug-in-phone → Claude pulls + parses + triages into this file** (devicectl app-container
   pull, proven 2026-06-10). Email path dead. **Valid only while the user is the sole user** — revisit if the
   app ever gets other users. Skill: `.claude/skills/pull-phone-feedback/`.
2. **Share extension = build as FULL capture items** (not a video-only hack): share URL/text/image/video +
   annotate, share-extension target + App Group + `attachments` multipart + desktop capture content-type.
   **OWED TOMORROW: walk the user through what (if anything) must be set up in the Apple Developer portal /
   App Store Connect for the new extension target + App Group** (likely nothing manual — automatic signing
   team 9W82X49JZS auto-registers bundle IDs + App Groups for dev builds; explain + verify).
3. **Custom vocabulary** — GO. ✅ SPIKE DONE (2026-06-11): FluidAudio `main` (7f963cd, identical checkout in
   both apps) ships a full custom-vocab system — CTC word-spotting + rescoring (NeMo arXiv:2406.07096,
   "separate CTC encoder"; works with the Parakeet TDT 0.6B v3 both apps use). Neither app uses
   `SlidingWindowAsrManager` (its built-in `configureVocabularyBoosting` doesn't apply); both call
   `AsrManager.transcribe` directly → integrate like the CLI batch pattern: after `transcribe`, run
   `CtcKeywordSpotter.spotKeywordsWithLogProbs` over the same samples, then
   `VocabularyRescorer.ctcTokenRescore(...)`, take rescored text when `wasModified`. Cost: one extra
   ~97.5 MB HF model. Build next: Settings "Custom words" list (both apps) + the rescore pass in each
   transcriber.
4. ✅ **DONE (2026-06-11 batch)** — **Trash / 2-week retention** — all delete paths soft-delete (list +
   detail), "Recently Deleted" sheet, lossless Restore, startup purge ≥14 days. ✅ **DESKTOP MIRROR DONE
   2026-06-13** (`Pipeline/DesktopTrash.swift` + `PipelineFile.deletedAt` + `Features/Sidebar/RecentlyDeletedView.swift`):
   soft-delete keeps the working folder (lossless Restore), 14-day launch purge, trashed excluded from
   sidebar/queue/process + the phone's `GET /api/files/`; sidebar footer "Recently Deleted (N)" → restore
   sheet; `-snapshot-trash` verified; 236 unit + build green.
5. ✅ **DONE (2026-06-11 batch)** — **Auto-copy transcript** — opt-in Setting, default OFF; copies on
   transcription success incl. appends.
6. ✅ **DONE (2026-06-11 batch)** — **Front camera toggle** — flip button in CameraSheet; front hides
   zoom presets, pinch floored at 1×.
7. ✅ **DONE (2026-06-11 batch)** — **Click-`[[name]]`-to-unlink (desktop)** — built per signed-off mock:
   two scopes (this mention → alias as spoken; all mentions in note + persisted no-relink-on-reprocess via
   `PipelineFile.unlinkedNames`), undo toast, 15 tests. Note: single-mention unlink is a body edit (not
   persisted across re-transcribe) — by design, consistent with hand edits.
8. **Audiobook quote-capture** — direction written below; design after the current wave.
9. **Significance wall** — GO, threshold **≥ 0.8**; AirPrint; refine-gate before export; design with the
   audiobook session. ✅ The locked **circles UI is DONE (2026-06-11 batch, BOTH apps)** — 10 tappable
   circles per the signed-off mock (all three ≥0.8 wall cues, re-tap clears, tier labels); the wall
   PIPELINE (refine gate + print) remains the design-session item.

### Audiobook quote-capture — DESIGN LOCKED 2026-06-11 (grill session; supersedes the direction below)
Build-ready spec, every branch user-approved. **MOCK SIGNED OFF same day** ("wouww looks great, let's go").
✅ **BUILT 2026-06-11 (4-lane batch, all tests green, merged to native)** — see FEATURES.md "Audiobook
quote-capture" for the full capability×file map. Also in that batch: ✅ the resolver per-occurrence
INSTANT-apply fix (each pick renders immediately, document-order demotion, progress counter).
Owed from lane flags: device-test the capture flow end-to-end (grains/scrubber feel, ramble append,
Mac round-trip of a quote memo incl. quote protection + [[Author]] export).

#### Device-test results — 2026-06-11 23:00 — ✅ ALL FIXED same night (3-lane batch + polish, tests green)
Fixes: scrubber gesture rewrite (root cause: .contentShape applied AFTER .offset stacked both hit-zones in
the strip corner → 56pt latched per-handle targets, min-span clamp, pannable window w/ edge-bump); preload
on capture-open; post-ramble = review-first (green SAVED card w/ live appended text, resume ONLY on Save &
keep listening, button flips to "Add more"); single import affordance; MULTI-FILE BOOKS (multi-select →
one book, filename-ordered chapters, continuous cross-file playback, capture confined to one file —
cross-file spans flagged as a possible later enhancement); styled quote + attribution caption BOTH apps
(presentation-only, raw "> " preserved); desktop book glyph + "Audiobook quote · <Title>" source; list chip
truncation (all chips capped 220pt). POLISH: mini-player 104pt (~2×), 2h-idle session auto-end, Siri
"Resume my book in Skrift" (plain-AppIntent pattern). Owed: morning phone install + re-test (esp. scrubber
feel, folder import, AirPods re-insert recheck). Original findings below.

#### Morning re-test — 2026-06-12 (round 2)
**PASSED:** folder import → one book ✓ · scrubber handles respond ✓ · post-ramble review flow "way better" ✓
· styled quote + ch. attribution ✓ · in-note BOOK AUDIO playback loved ✓.
**New fixes:**
- **Chapter titles unreadable** (full filename per row): strip the files' longest-common-prefix + extension
  → "chapter_01"/"Chapter 1". Compare Bound's chapter list.
- **Mini-player bar grotesquely oversized** (Capture text wraps vertically; ORCHESTRATOR'S OWN MISS — scaled
  by arithmetic, never rendered): proper resize ~72-76pt, fixedSize/lineLimit(1) so wrap is impossible.
- **Capture screen round 2:** (a) grains/preview "always talking" — add explicit pause/mute + only sound
  while actively dragging; (b) span/pan semantics confusing — pan moved the SPAN with the window, span
  ended up "now+99s→now+256s" (future of the pause point!), labels relative-to-now unreadable → labels in
  BOOK TIME (or chapter time), pan moves WINDOW only, add "back to pause point" jump; (c) long quote text
  not scrollable on the sheet; (d) pressing Capture yanked AirPods from the Mac (session activation —
  don't activate audio for grains until first drag).
- **Edit book AFTER import:** title + author + cover (⋯ menu in the player — user expected it there; keep
  Chapters in the menu too, add "Edit book details" sheet; cover pick from Photos/Files).
- **P0 RECORDING ROUTE STILL BROKEN (worse):** memo recording with AirPods → pull out → recording DIES (no
  fallback to phone mic — the earlier restart-without-tap-reinstall fix is insufficient on device, the
  flagged format-mismatch follow-up is the likely cause); re-insert → still dead AND THE AUDIOBOOK STARTED
  PLAYING (AirPods auto-play remote command hit AudiobookSession while a recording was supposedly active).
  Fix: reinstall the tap with the new route's input format on EVERY route change; AudiobookSession must
  IGNORE remote-play while a recording is active (session priority).
- Bookmarks: user considered, DECIDED AGAINST (linking back into books = complexity/fragility). Skip.

#### Round-2 re-test — 2026-06-12 — ✅ P0 FIXED (validate-before-install + own-activation echo filter + stale-format check), DevLog shipped (Documents/devlog.txt, devicectl-pullable), swipe-down player + tap-cover-to-edit. CAPTURE DESIGN STILL PAUSED. Owed: device re-test w/ devlog pull.
- **P0 CRASH: first tap of Record crashed the app** (fresh install, round-2 build). Crash log pull attempted
  to /tmp/skrift-crashes2 (check SkriftMobile-2026-06-12-*.ips; if absent, pull next plug-in via
  idevicecrashreport). Suspects: instant-record path or the new route-change tap-reinstall init.
- **P0 DIAGNOSED (crash log SkriftMobile-2026-06-12-081100.ips, kept in /tmp/skrift-crashes3): BOTH
  morning failures are ONE bug — the round-2 route fix itself.** NSException → SIGABRT in
  `LiveRecordingService.installRecordingTap` ← `rebuildTapForCurrentRoute` ← `handleRouteChange`
  (AVFAudio InstallTapOnNode raise). First record tap: session-activation fires .categoryChange →
  rebuild installs a tap with an invalid mid-transition input format (0 Hz/0 ch) or double-installs →
  abort. AirPods pull: same path = app CRASHED (user read it as "stopped recording"). FIX DIRECTION:
  (a) ALWAYS removeTap before install; (b) VALIDATE input format (sampleRate>0 && channelCount>0)
  before installTap — NSExceptions are uncatchable from Swift, preconditions are the only defense;
  retry on a short delay while the route settles; (c) ignore route events caused by our OWN session
  activation (.categoryChange at start); (d) build WITH the dev file-logging item so the fix is
  verified from traces, not vibes.
- **P0 STILL BROKEN: AirPods pull-out stops the recording** (started with AirPods → pulled → recording
  stopped). The tap-reinstall fix did NOT hold on device. NEXT: stop guessing — add DEV-BUILD FILE LOGGING
  (user explicitly asked): a ring-buffer log file in the app container (os.Logger mirror or simple appender;
  recording/route/session events), pullable via devicectl like the feedback skill → diagnose from REAL traces.
- **Capture tool still confusing — STOP REBUILDING (user decision): design pause.** Next session = sit down
  with the user / produce interaction mocks for the capture-adjust flow BEFORE more code. No more iteration
  batches on CaptureMomentView until the design is agreed.
  - **🧠 DESIGN THINKING 2026-06-22 (for that paused session — overlaps the note-editing sprint's selection
    primitive).** Direction the user is leaning: **pull capture INTO the reader via in-place text selection**
    (highlighter / Kindle model) instead of a separate capture screen — select a passage → small menu
    (Highlight · Note · Bookmark), stay on the page. Keep Skrift's edge (the **voice ramble**) as a
    LIGHTWEIGHT inline bar (talk while staying on the page; grab the quote audio behind the scenes), not a
    full screen. **Bookmark vs Note = same gesture, different keepsake:** a bookmark is a *breadcrumb*
    (stays in-book, jump-back, throwaway); a note is a *souvenir* (becomes a memo → sync → tags/significance
    → Obsidian, permanent). Don't merge the entities; unify the gesture. **Missing middle tier = a plain
    HIGHLIGHT** (save the passage's words, no ramble) — the literal highlighter act, between bookmark (a
    point) and note (a voice capture). Possible unified model to MOCK: **"Marks"** = bookmarks + highlights
    (a point OR a text span; both in-book, both jumpable) and **"Notes"** = a mark you've talked over →
    promoted to a memo (bookmark = mark w/ no text; highlight = mark w/ text; note = highlight + your voice).
    Mock-first; shares the selection mechanic with the note-editing sprint.
- **Bar at bottom: looks good now** ✓.
- **Full player (big-thumbnail screen): add swipe-down to close.** Also: user still couldn't change the
  cover ("still needs to be able to be changed") — Edit-book-details shipped in round 2 under the ⋯ menu;
  either they tested before finding it or discoverability is poor → check + consider a tap-on-cover edit
  affordance.

#### (original findings)
**WORKED:** import (single file + manual title/author confirm) ✓ · play + mini-player + nudged FAB ✓ ·
capture E2E ✓ · ramble append ✓ · circles + Will-sync line ✓ · sync to dev Mac ✓ · **QUOTE PROTECTION
held — the book quote came through enhancement untouched** ✓.
**P0 fixes (capture UX):**
- **IN/OUT scrubber handles barely respond / freeze**; dragging toward IN makes OUT jump (gesture grabs
  the wrong/nearest handle; persisted across audio-route changes, so it's the gesture system, not routes).
- **Post-ramble flow wrong ×2**: the book auto-resumed IMMEDIATELY on recorder dismiss (user couldn't
  review what they spoke) AND the record-thoughts button stayed big/purple (rambleAdded state never
  showed). Fix: no auto-resume after a ramble — resume only on "Save & keep listening"; show the
  ramble-added state + the appended text for review.
- **Span can't extend past the proposed 30s window** — the micro-scrubber window must PAN (scroll
  left/right beyond the initial span) so IN/OUT can be placed further back/forward.
- **First-capture transcription slow** — preload the transcriber the moment the capture screen opens
  (second capture was instant; warm-model). 
- **Multi-file books unsupported**: many audiobooks are file-per-chapter (the user's is ~30 mp3s); Bound's
  importer multi-selects a whole folder as ONE book ("the selector in Bound is way better"). Import must
  accept multi-select/folder → one book, files = chapters in order. *Verifier nuance: Bound's PICKER UX
  itself is the model (Select All over a chapter folder, one obvious flow) — not just the capability;
  the scrubber bug presented as PROGRESSIVE freezing (handles fully unresponsive on later attempts), so
  the gesture fix must address freeze, not only wrong-handle grabs.*
- **Two import affordances in the Library** (big dashed row + toolbar +): keep ONLY the toolbar +.
**P1 presentation:**
- **Memos-list capture row: the book chip overflows off-screen** (long book title; needs truncation).
- **Quote styling missing in the note body (BOTH apps)**: shows as plain "> " lines — no italics, no
  quote bar, no chapter/author attribution → "looks like I recorded twice". Render the C1 blockquote
  styled (italic + bar) with an attribution caption derived from C2 metadata (presentation-layer; the
  real `[[Author]]` line stays export-time).
- **Desktop source wrong for captures**: shows "Voice memo" + mic glyph; should be an audiobook-quote
  source (book glyph) when C2 bookTitle is present — sidebar + properties. (NOT a sync bug: the C2 book
  metadata arrives fine — the phone derives its book glyph from it; the desktop just never does.)
- **Backlog (capture-items umbrella): unify the SOURCE taxonomy across both apps** — voice memo / URL /
  document-PDF / video / audiobook quote / Apple Note — consistent glyphs + labels everywhere (user:
  "all the sources should be done well"). 
- **Mini-player bar ~2× vertical height** (user, 2026-06-11 late): buttons too small to hit comfortably;
  it only shows during an active session so it can afford the space. Apply post-merge (fix-lane owns the file).
- **Mini-player AUTO-HIDE after idle** (user, 2026-06-11: "I'm always listening to one book or another —
  the player will be there always"): the bar must end its session automatically after X paused time
  (start ~2h idle, + on app launch when last-played is >~6h old; constants flippable). Zero loss: progress
  persists per-book; reopening from the Library resumes exactly. Post-merge pass, with the 2x-height tweak.
- **Siri: "play/resume my book in Skrift"** — an App Shortcut that resumes the last-played audiobook.
  SAFE SHAPE per this repo's SIGTRAP history: plain `AppIntent` + `openAppWhenRun` (like
  StartRecordingIntent), NOT an audio-playback intent; opens the app + resumes playback. Phrases:
  "Resume my book in Skrift", "Play Skrift book". (True background-start via AudioPlaybackIntent = later
  experiment, device-tested carefully.)
- Watch: scrubbing while another device held the AirPods felt entangled with the route (audio yanked
  from Mac to phone) — recheck after the gesture fix lands.
1. **Skrift IS the player** for actively-mined books — model it on **Bound** ("there isn't a feature
   there I don't like"): Files/iCloud import, library w/ covers + sort, per-book resume, speed, sleep
   timer, embedded m4b chapters, background playback + lock-screen transport. One book at a time moves in.
2. **One memo per capture** (NOT a per-book note): each capture = quote block + ramble + book metadata in
   frontmatter; full existing pipeline applies (significance, sync, enhance, export). A generated
   per-book index note is a possible later export-side addition.
3. **Capture gesture = RETROACTIVE**: one Capture button (in the full player AND the mini-player) pauses
   the book and proposes span [now−30s → now]; the ~15s **micro-scrubber** adjusts IN (and OUT), with
   **snippet audio scrubbing** in v1 (hear grains as you scrub; DaVinci-style varispeed = v2 polish).
   **Sentence-snap OUTWARD** on both edges (sloppy markers always yield whole sentences). Optional
   long-press marker-in for the foresight case if it falls out cheap.
4. **Transcription = span-on-demand ONLY** (marked range ±~20s buffer through Parakeet, seconds-fast).
   Whole-book indexing explicitly REJECTED ("I don't see the point").
5. **Quote audio = the memo's audio** (span extracted to the memo .m4a) → playback/karaoke/sync/export
   toggle all work for free; you can hear the author from Obsidian. **Ramble = the append flow**
   (A-dominant: record-your-thoughts is the big button on the capture sheet; "Save & keep listening"
   secondary; book auto-pauses during ramble, resumes in place after).
6. **Metadata from file tags at import** (title/author/chapters; one editable confirm screen only if
   missing). Chapter per capture derived from marker position. Capture itself asks NOTHING.
7. **Export**: italic quote block + attribution "— [[Author]], *Book*, ch. N". `[[Author]]` is written
   as a literal wikilink AT EXPORT ONLY — authors NEVER enter the names DB (would pollute alias matching).
8. **Enhancement protects the quote — option (b) from day one**: strip quote block behind an anchor
   (image-marker pattern), copy-edit ONLY the ramble, reinsert, then **assert the quote is byte-identical**;
   any mismatch → fall back to skip-all-copy-edit + flag. Title/summary generate normally.
9. **Placement**: Library behind a book toolbar icon on the memos list. **Conditional mini-player** —
   exists ONLY while a book session is active (Bound-style glass capsule: cover, ⟲15, play, 15⟳,
   **Capture ❝**, expand ˄); the record FAB nudges up above it; mini-player YIELDS on memo detail (book
   keeps playing in background); record-FAB-while-playing auto-pauses the book and resumes after save.
   Captures appear in the memos list with a book glyph. App identity stays notes-first.
10. Mobile-first; capture memos sync to the Mac as normal memos (book files never sync). Open/minor (mock
   decides): significance circles on the capture sheet vs detail-only; mini-player on the Library screen.

### (original direction, 2026-06-10 — superseded above)
Capture a passage from an audiobook as a quoted, attributed note + your own thoughts under it.
- **Flow (preferred shape, in-app):** audiobook section in Skrift → loads the transcription model in the
  background → fine scrubber for precise positioning (a ~15s micro-scrubber alongside the normal one — a
  15h book makes one scrubber useless) → set marker-in, listen, marker-out → that span is transcribed,
  **snapped to natural sentence boundaries** (don't cut mid-sentence; markers are imprecise by nature) →
  inserted as a QUOTE block (italics) with book/chapter/author metadata asked-or-inferred → free rambling
  space below the quote (the user's own thinking — the actual point).
- **Alt shape (lock-screen markers):** marker-in/out from the lock-screen player controls — iOS gives 3rd-
  party apps limited lock-screen control, so realistically this degrades to the in-app flow; park it.
- **Player inspiration:** "Bound" audiobooks app (one-time payment; loads audio straight from Files/iCloud —
  that ingestion model is the one to copy). User has it; could inspect on the jailbroken iPhone for UX.
- **Maybe-later:** linking the quote-note to existing notes at capture time (or leave linking to Obsidian).

### P2 — feature requests from testing
- **Instant record**: tapping record (or + append) should START RECORDING IMMEDIATELY — no record-ready
  screen stop; model loads in background (it already catches up).
- **Feedback rework**: not email — user wants Claude to read feedback directly off the phone (PROVEN possible
  today via devicectl pull) or append to backlog.md. Plus: floating/shake-to-feedback affordance w/ screenshot
  (Henry's idea), not while recording.
- **Copy-transcript button on each memo row** (today: open → ⋯ → copy). Multiple paths to the same action.
- **Auto-copy transcript to clipboard after transcription** (cheap backup against data loss).
- **Custom vocabulary / word boosting** ("Skrift" mis-recognized; FluidAudio CTC boosting exists per memory).
- **Trash with ~2-week retention** instead of permanent delete (like Apple Voice Memos).
- **Front camera option** for in-recording photo capture (selfie).
- **Click a `[[name]]` to revert to alias** (desktop review): popup like the disambiguator with "unlink".
- **Audiobook quote capture** (BIG idea, design doc needed): mark in/out while listening (in-app audiobook
  player or lock-screen scrubber), transcribe the marked span snapped to sentence boundaries, insert as a
  quote block (chapter/book/author metadata) + space for own rambling below. Inspiration: Bound audiobooks
  app (loads files from iCloud/Files). Possibly later: link to existing notes.
- **Significance-gated "wall" pipeline**: notes above a significance threshold require a manual refine pass
  (desktop gate: can't export to Obsidian until refined) → then export + send to printer for the physical wall.

## Device-testing feedback — 2026-06-11 (4 memos pulled; verifier-passed; screenshot of two-Jacks on dev Mac)
**PASSED:** front-camera flip ✓ (photo mid-record, `[[img_001]]` inline) · circles on phone ✓ (0.4 set via
circles) · circles render on dev Mac ✓ (screenshot) · "the black screen is fixed" ✓ (ambiguous which —
ask) · feedback-via-memos + pull workflow accepted (no dedicated feedback feature wanted).

**Not a bug:** two-Jacks file on the dev Mac showed NO name linking — the dev container has NO `names.json`
(starts empty by design; prod has the Jacks). To test names on dev: add the people in dev Settings or sync
from the dev phone first.

### New items
- **P1 — instant-record flashes the old ready screen** before recording starts (model-loaded screen with
  the legacy record button). Remove the transient screen (or skip straight to the live caption) — it no
  longer serves a purpose on the auto-start path.
- **P1 — AirPods RE-insertion doesn't resume**: pull-out mid-record survives (route-change fix works), but
  putting them back in didn't move input back to AirPods ("I think it was a fail"). Confound: they may have
  re-paired to the Mac. Repro with Mac BT off; likely the `newDeviceAvailable` branch needs the same
  restart treatment as removal.
- **WATCH — Live Activity "still going on the last thing"** on the lock screen right after the new install.
  Possibly a stale activity from the PRE-fix build (new build reaps on foreground). Observe once more on
  the new build; if it recurs, the reaper has a gap.
- **Confirms backlog priority:** Settings → Models/Storage list ("we have three models — transcription,
  diarization and something else") — already specced under "Show downloaded models in phone Settings".
- Next focus per user: the BIGGER design items (capture-items build, audiobook, significance-wall pipeline,
  vocab build).
- **Reassign in the unlink popover** (from the two-Jacks discussion): clicking a linked `[[Name]]` should
  offer not just Unlink but **"Change to → <other person>"** (one-tap fix when the deterministic alias
  match picked the wrong person — e.g. a spoken "Jack" auto-linked to Timmons but meant Hutton). Reuses
  the people-picker; per-mention scope.

## Audit findings (2026-06-09 post-batch error sweep — triaged, verified against code)
Two read-only agents swept both apps after the batch; orchestrator verified each claim before listing.
None are release blockers; fix in a follow-up pass.

**Mobile:**
- **`[photo N]` markers anchor by WORD COUNT at capture** (`RecordView.swift:83`) but the live caption
  re-transcribes wholesale, so the token can drift later than the real capture point (clamped, no crash).
  Fix: anchor by TIME offset (stable across re-transcription) — `LiveCaptionLayout` maps time→word at render.
- **Recorder teardown hygiene** (`LiveRecordingService.swift`): route observer + timers rely on `stop()`
  running before `deinit`; an abnormal teardown can leak them (`[weak self]` prevents a crash). Fix: explicit
  `stopTimers()` + `teardownRouteObserver()` in `deinit`.
- UX nits: silent video (no audio track) imports as a silently-`failed` memo (no user feedback); a failed
  video import shows import-time instead of the video's date; rapid photo taps are silently debounced (0.6s).
- *Dismissed as false positives (so future sweeps don't re-flag): "SwiftData off-main in append" (`MemoSaver`
  is `@MainActor`); "append audio format corruption" (export re-encodes via `AppleM4A`; merge-failure falls
  back to base-audio+text by design; temp-export→swap order is safe).*

**Desktop:**
- **Re-transcribe leaves STALE diarization segments** (`ProcessingCoordinator.retranscribe` resets transcript
  but not `diarizationSegmentsJSON`/sidecar) → re-transcribed conversation memos can carry old speaker
  segments → wrong enrollment slices. Fix FIRST: clear segments + delete the sidecar in `retranscribe()`.
- **Sidecar write is `try?`** (`DiarizationSidecar.swift:47`) — a failed write is silent. SwiftData copy
  still survives (so no data loss), but log + surface it; the sidecar is the portability/enroll copy.
- Pre-existing, already-tracked (now slightly more pressing with video uploads): full multipart body
  buffered in RAM (256 MB cap; `SyncServer.swift:90`); `DispatchQueue.main.sync` SwiftData bridge in the
  Bonjour handlers (`SkriftDesktopApp.swift:46,59` — deadlock-free only while handlers never run on main);
  health endpoint vs the model idle-unload interplay (phone may see `available=false` after 60s idle).
- Minor: HEIC→JPG conversion failure falls back silently w/ a possibly-broken md ref (`IngestService.swift:282`);
  snapshot PNG write is `try?`; `SpeakerFusion.foldShortIslands` indexing deserves explicit bounds asserts.

#### DevLog verdict 2026-06-12 09:14 (log in /tmp/devlog.txt — DevLog works perfectly)
NO crash ✓, echo-filter ✓, re-insert recovery ✓. REMAINING BUG: `canInstallTap` requires hw format ==
old tap/file format → REFUSES legitimate cross-rate rebuilds (AirPods 24k ↔ built-in 48k), gives up after
4×250ms permanently → recording goes DEAF on the new route (both the first-record race and the pull-out).
FIX: tap must install in the CURRENT hw format whenever valid (rate>0,ch>0) — the AVAudioConverter in the
write path bridges tap→file; only refuse transient invalid/disagreeing formats; retry with backoff ~3s;
NEVER permanent give-up — re-arm on every later route/config notification + observe
AVAudioEngineConfigurationChange (the canonical format-changed signal).

#### DevLog round 3 (2026-06-12 09:40, /tmp/devlog2.txt): DEADLOCK ON STALE VENDED FORMAT
ACCEPT path + echo-filter + start-retry all work. BUG: after a route flip the inputNode keeps VENDING the
old format (vended=48k vs sessionHw=24k, frozen across every retry) — AVAudioEngine caches node formats
until `engine.reset()`. The rebuild never calls reset → vended never converges → refuse-loop until user
cancels. FIX: on vended≠sessionHw in rebuild: removeTap → engine.stop() → **engine.reset()** → re-query
vended → install (+ reconnect/restart as the start path does). DevLog the reset.

#### DevLog round 4 (09:56, /tmp/devlog3.txt): DIAGNOSIS COMPLETE — WRONG PROPERTY
Even after engine.reset(), vended (inputNode.outputFormat) stays 48k forever — it's the ENGINE RENDER
format, not hardware. nodeIn (inputNode.inputFormat) = 24k AGREES with sessionHw on every line. The
validator demands the un-convergeable property. FIX (orchestrator doing it DIRECTLY, no agent): validate
nodeIn vs sessionHw; install the tap with format = inputFormat(forBus:0) (or nil); converter bridges to
file. Drop the vended check entirely.

#### ✅ AirPods P0 CLOSED — 2026-06-12, round 4 DEVICE-VERIFIED ("it works!")
Four layers, each peeled by a device trace: crash (NSException on install) → policy (refused legit
cross-rate) → cache (no engine.reset) → WRONG PROPERTY (validated outputFormat — engine-render-pinned,
can never converge — instead of inputFormat, which tracked hardware on every logged line). Final fix
applied by the orchestrator directly. Recording now survives pull-out AND re-insert.

#### Capture redesign — HYBRID SIGNED OFF 2026-06-12 ("everything works quite nicely")
Spec = `mocks/capture-redesign.html` mode 4 ⭐. One screen, one playhead, play/paused is the only state:
- ENTRY: auto-replays from −45s at 1.5× immediately (model preload stays). Full transport beneath
  (⟲5 · ▶/⏸ · 5⟳); rate pill (1×/1.5×/2×) pinned RIGHT of the row, transport stays centered.
- MARK: two buttons (「 Mark In / Mark Out 」) drop flags AT the playhead — −0.7s reaction bias while
  playing, exact while paused. Re-tap moves the flag. NO draggable handles, NO window/pan mode, NO gain
  graph, NO grains (playback IS the audio feedback).
- FINE-TUNE: ±1s chips per edge; in-chip nudges AND INSTANTLY REPLAYS from the new in-mark (the
  spam-to-find-start mechanism — MUST work while the span is playing, no pause needed; mock couldn't,
  code must); out-chips replay only the last ~5s up to the new out.
- ⟲ past the strip's left edge extends the window arbitrarily far back (clamped to the chapter file).
- Sentence-snap OUTWARD stays on confirm. ▶ Play span before Continue.
Replaces CaptureMomentView's interaction wholesale; capture SHEET (quote+ramble) unchanged.

#### Hybrid capture — first device test 2026-06-12 13:11
Screen matches the mock ✓ (sweep, transport, rate pill, marks, hints). Findings:
- **Make the capture screen FULLSCREEN + swipe-down to close** (currently floats with dead space below).
- **UX: start landed wrong — "I think it just added an extra sentence"** (user deleted the capture).
  Diagnosis: the −0.7s reaction bias can push the in-mark back ACROSS a sentence boundary into the
  previous sentence's tail; snap-OUTWARD then swallows that ENTIRE previous sentence. Bias + always-
  outward compose badly at the IN edge. Proposed (awaiting sign-off):
  (1) NEAREST-boundary snap at IN: if the mark sits in the last ~1s of the previous sentence (bias
      overshoot) snap FORWARD to the next sentence start; only snap back when the mark is genuinely
      inside the sentence. Outward stays for OUT.
  (2) Sentence-level trim on the capture SHEET: render the quote with first/last sentence droppable
      (one tap removes the leading/trailing sentence) — fix-by-reading after the fact, no re-scrub.

#### Capture round 2 — SIGNED OFF 2026-06-12 ("this works great, let's go"); one Sonnet lane
1. NEAREST-boundary snap at IN: mark in last ~1.0s of the PREVIOUS sentence (bias overshoot) → snap
   FORWARD to next sentence start; genuinely mid-sentence → snap back as today. OUT stays outward.
2. SENTENCE-TRIM on the capture sheet (spec = mocks/capture-sheet-trim.html): one grey context sentence
   each side; tap grey → include (context window slides); tap bright EDGE → drop (middles refuse w/ hint);
   audio span FOLLOWS included sentences via word timings; transcript = the existing span±buffer (already
   transcribed — zero wait). Sentence granularity only, no sub-sentence scrubber.
3. Capture adjust screen FULLSCREEN. 4. Swipe-down closes it.

#### Capture round 2 — DEVICE-VERIFIED working ("it works, very well done"). Two bugs:
1. KARAOKE broken on captured notes (word highlight/tap-to-seek no longer works during playback).
   Suspect: round-2 trim re-derives quote text+audio but the word-timings sidecar isn't re-derived/rebased
   to the final trimmed audio — or the styled-quote rendering path skips karaoke.
2. MEMO PLAYBACK and the AUDIOBOOK can play SIMULTANEOUSLY (play in a note while the book plays).
   Fix: AudioPlayerModel.play() pauses AudiobookSession (and book play should pause the memo player).
DIAGNOSIS (orchestrator): the sheet's trim is DISPLAY-ONLY — `included` changes never write back
(onFinish just closes; no re-derive of memo transcript/audio/timings). Karaoke on captures likely
collateral (sidecar/rebase or the styled-quote render path skipping karaoke). Fix design: apply trim
at the two moments that matter — when "Record your thoughts" is tapped (await apply, THEN open the
recorder so the ramble lands on trimmed audio) and on finish/close; re-derive from included sentences:
audio = exportSpan(bufferAudioURL, firstWord.start→lastWord.end), transcript = C1 blockquote of joined
sentences, timings = rebased included words → memo + WordTimings sidecar + duration. Plus: memo player
and AudiobookSession must be mutually exclusive (each pauses the other on play).

#### Session log 2026-06-12 morning (superseded — the ⭐ CONTINUE HERE entry is at the BOTTOM of this file)
STATE: `native` is green + fully landed (audiobook player + Hybrid capture + sentence-trim persistence +
playback exclusion all device-installed on Skrift Dev). NOT pushed to main; prod untouched.

1. ✅ **BUILT 2026-06-12 (refactor, inline/sole-editor) — KARAOKE on capture memos. AWAITING DEVICE VERIFY.**
   Done per the 1b mandate: the whole capture render path unified into ONE component —
   `Features/MemoDetail/TranscriptBodyView.swift`, three explicit modes derived in one place
   (playing wins → reading while transcribing → editing default). PLAYING = classic full-text karaoke
   over the WHOLE memo via new `Memo.karaokeText` (quote with "> " markers STRIPPED + ramble, one
   continuous text, word indices 1:1 with the sidecar from 0); EDITING = styled quote + attribution
   above the quote-protected ramble editor (raw "> " write-back untouched, tests still green);
   READING (transcribing) = styled quote + pill, no editor (append-clobber protection kept).
   DELETED: TranscriptContentView + overrideText/baseWordOffset plumbing + CaptureQuote.spokenWordCount
   (~215 lines out of MemoDetailView). BONUS FIX: the old "working" karaoke counted the ">" markers as
   words → captures were silently off-by-N vs the timings; karaokeText fixes the alignment by design.
   3 dup imageURL(markerIndex:) helpers consolidated onto Memo. Gate: full sim suite green (33 UI +
   unit bundles, 0 failures); new tests pin karaokeText + mode precedence. Dev build installed on the
   iPhone. **USER: verify karaoke on a capture WITH a ramble present (and quote-only).**
1c. ✅ **KARAOKE DEVICE-VERIFIED 2026-06-12 ("it pretty much works")** — full-text quote+ramble highlight
   confirmed on device. Follow-up finding: "tap a word → jump" did nothing — NOT a bug: tap-to-seek was an
   opt-in Settings toggle (`karaokeTapToSeek`, default OFF) and the device prefs (pulled over USB) had it
   unset. USER CALL: **default flipped to ON** (commit 0808543; toggle kept for opting back to the crisp
   single-Text rendering).
1d. ✅ **Round 2 (same day) — tap-to-seek verified working; two presentation findings, BOTH FIXED:**
   (a) quote+ramble "all mixed together, no division" — root cause: the tap-to-seek FlowLayout flattens
   ALL whitespace, so the \n\n division the AttributedString path kept (their first, toggle-off test)
   collapsed once tap-to-seek became default. (b) layout jumped on play (styled quote swapped out).
   FIX (design-level, playing mode evolved): the capture KEEPS its styled quote frame during playback —
   `CaptureQuoteFrame` (accent bar + attribution, shared by all 3 modes) now wraps the LIVE karaoke quote
   text (italic, offset 0) with the ramble karaoke below (offset `spokenWordCount`, re-added) → no jump,
   unmistakable book-vs-own-words division, highlight still continuous. Plus `KaraokeWordLayout.lines`
   (pure + tested): the word grid stacks per-line FlowLayout blocks so paragraph breaks survive in ALL
   memos (multi-append rambles included). `Memo.karaokeText` deleted again (regions replaced it).
   ✅ DEVICE-VERIFIED same day ("very close, looks way better"). One P2 polish nit logged, NOT blocking
   (user: "pretty good", moved on): on play the text spreads slightly vertically — the tap-to-seek word
   grid's FlowLayout lineSpacing 6 + per-line VStack spacing 8 vs the static text's lineSpacing 4; tune
   the grid constants to match. USER MOVED ON TO THE BOARD → capture items build started 2026-06-12.
5. **CAPTURE ITEMS BUILT 2026-06-12 (board item 1) — two Sonnet lanes + orchestrator integration; AWAITING
   DEVICE VERIFY.** Contract-first: `Skrift_Native/CAPTURE_CONTRACT.md` (C3) pinned the wire seam (no audio
   part + sharedContent = capture; literal fixture both lanes test against). Lane M = SkriftShare extension
   target + App Group inbox + share sheet (mock state 1) + capture upload + list/detail (state 2). Lane D =
   UploadService capture branch + skip/enhance-lite pipeline + compile/export pinned block + review surface
   (state 3). Integration fixes (orchestrator): 3 one-line compile slips; QueueDerivations read snake_case
   only (phone sends camelCase); ADDED the mock's shared-content card to the review column (lane built it
   export-only); **launch crash fixed** — `SkriftAppGroup` Info.plist key was extension-only + CaptureInbox
   assertionFailure trapped Debug at launch (every UI test "app not running") → key added to the APP plist,
   fallback derives dev/prod group from the bundle ID instead of trapping. Gates: desktop UnitTests 223/0 +
   full build + `-snapshot-capture` mock-faithful; mobile full suite green (see commit). V1 flags: no mic in
   the sheet (memory ceiling), no location/weather on captures, tags/title Mac-suggested only. **USER:
   share a URL → annotate → rate → Save; check the row/detail; then sync to the dev Mac and check the
   review surface + export.** Known-untested: real share-sheet payloads from third-party apps (sim tests
   cover the inbox/upload logic, not the OS share UI).
2. Then user re-tests: trim persistence end-to-end (tap sentence → ramble → saved audio/text/karaoke match).
3. Owed smalls — **BUILT 2026-06-12 (this session, pending device verify):**
   - ✅ Reverse playback exclusion BUILT — `AudioPlayerModel.nowPlaying` (static weak) +
     one guarded `pause()` at the top of `AudiobookSession.play()`; cleared on pause/stop/finish.
   - ✅ Ready-screen flash BUILT — instant record now shows a quiet "Starting…" placeholder instead of
     the legacy ready screen (RecordView `showManualReady`); the mic-button screen survives ONLY as the
     empty-stop retry surface + a ~7 s fallback when the auto-start retry loop gives up.
   - Mini-player idle auto-hide (2 h `idleEndDelay`) + Siri "Resume my book" (`ResumeAudiobookIntent`):
     CONFIRMED SHIPPED in code — user test still owed.
   - ✅ Watch item (stale Live Activity on lock screen): user considers it fixed — CLOSED.
4. THE BOARD — **ORDER LOCKED BY USER 2026-06-12:**
   1) **Capture-items build** (mock signed off — share URL/text/image + annotate; mobile share-extension
      target + App Group + `attachments` multipart; desktop non-audio capture content type; folds in the
      unified source taxonomy + "share video from Photos doesn't list Skrift").
   2) **Custom vocabulary build** (spike done — CTC keyword-spot + rescore in both transcribers +
      Settings "Custom words" list; ~97.5 MB extra model).
   3) **Models tab in phone Settings** (user re-confirmed: "a tab that says models" — list the on-device
      models w/ downloaded state/size; spec already under "Show downloaded models in phone Settings";
      Mac mirror later).
   4) **Prod promotion LAST** — push native→main + Release builds both apps when prod idle.
   **Significance-wall design session: DEFERRED** (user call).
   Status audit done same session: swipe-to-delete ALREADY DONE (native `.swipeActions` in MemosListView
   — item 3.5 partially closed; nicer drag-multi-select still open); confirmed-bugs list all still open
   (names auto-sync after enroll, Mac name-a-speaker UI, photo marker drift, confidence colours). QoL
   user picks: record-a-sample voice enroll = yes (later); desktop unlink-popover "Change to →" = yes.
PROCESS (now in skill rules): single bugs = orchestrator edits directly; lanes ONLY for batches; Sonnet for
specced lanes / Opus for taste; verify lane CLAIMS against write-paths. Feedback loop: "pull my feedback"
(skill) + devlog.txt for anything hardware-ish.
1b. ✅ **DONE 2026-06-12 — the refactor mandate was executed as specified** (whole path read first, then
   unified into the 3-mode `TranscriptBodyView`; quote-protection intact; inline as sole editor; sim
   gate green; installed to device). See item 1 for the full shape. Device verification owed by user.

#### (superseded by the ⭐ block at the bottom) — session wrap 2026-06-12 evening
STATE: `native` green through `df4850b`. Everything below is committed, sim-gated green (mobile 336 unit +
33 UI; desktop 223 unit + full build), and the DEV builds are installed: phone = Skrift Dev with capture
items; Mac dev build in DerivedData (launch on request for the round-trip test). NOT pushed to main; prod
untouched. The C3 contract doc is `Skrift_Native/CAPTURE_CONTRACT.md`; capability map in FEATURES.md.

SHIPPED THIS SESSION:
- ✅ DEVICE-VERIFIED: karaoke refactor (3-mode `TranscriptBodyView`, full-text capture karaoke), tap-to-seek
  default ON, round-2 presentation (styled quote frame stays live during playback; paragraph-true word grid).
- 📲 INSTALLED, AWAITING USER TEST: reverse playback exclusion; instant-record "Starting…" placeholder
  (ready-flash gone); CAPTURE ITEMS both apps (share extension + App Group inbox + share sheet + capture
  upload + list/detail; desktop ingest/pipeline/compile/export + review surface, snapshot-verified).
- Process: lanes rules.md gained "prove your base" (user-approved); CLAUDE.md records the App-Group CLI
  signing limitation (Xcode one-time visit done for dev IDs; Release IDs owe one at prod promotion).

USER FEEDBACK 2026-06-12 evening: "coming in from Safari was a bit shit" → ✅ REPRODUCED IN SIM + FIXED
(commits 7f76a77 + 6b95070; full gate green). A Safari-driving XCUITest probe
(`ShareFlowProbeUITests`, opt-in via TEST_RUNNER_RUN_SHARE_PROBE=1, screenshots to
/tmp/skrift-share-shots) reproduced the whole flow and caught FOUR stacked share-sheet bugs:
(1) keyboard buried significance+Save with no dismiss (ignoresSafeArea(.bottom) ate the keyboard
safe area → .container + keyboard-Done + scrim-tap unfocuses first — Save was literally
unreachable while typing, captures got lost); (2) light-mode innards on the dark shell
(preferredColorScheme is a no-op in extension UIHostingControllers → overrideUserInterfaceStyle);
(3) annotation TextEditor greedily filled the sheet (cap maxHeight 110); (4) the host content-hugs
the remote view leaving an unpaintable gray sheet backdrop (preferredContentSize 10k + opaque
#0e0f16 canvas). Sim E2E now verified: share → annotate → rate (works with keyboard up) → Save →
app inbox drain → capture row → detail (Open ↗ / annotation / Will-sync). SIM GOTCHA learned:
the share-sheet host caches extension processes per boot — reboot the sim after reinstalling
or you'll screenshot the stale extension. The fixed dev build is INSTALLED on the iPhone
(build 2026-06-12 evening, incl. share-sheet fixes); prod untouched.

USER FEEDBACK round 2 ("no way to record a voice message from sharing in safari — only type")
→ ✅ BUILT same evening + INSTALLED on the phone. The mock's mic, deferred-transcription design
(the v1 "no mic" flag is CLOSED): extension only RECORDS (Parakeet can't fit its ~120 MB memory
ceiling) → audio rides the App Group inbox → the APP transcribes on drain with the same Parakeet
engine → appends to the annotation, audio discarded (kept + Error pill on failure, re-kicked every
drain). Sync holds captures until transcription lands; detail editor swapped out meanwhile (clobber
window). Sim-verified (recording state + voice-note chip screenshots; 7 new unit tests incl. sync
gate + crash recovery; full gate green). DEVICE TEST OWED: share → tap mic (first time: mic
permission prompt INSIDE the share sheet) → talk → Save → open Skrift Dev → watch the annotation
fill in; then rate + sync → Mac gets the full text. C3 contract untouched (uploads stay text-only).

NEXT-SESSION DEVICE TEST LIST (in rough order):
1. CAPTURE phone half: Safari → Share → "Skrift Dev" (first time: enable via the share sheet's More/Edit
   row) → annotate + rate → Save → OPEN Skrift Dev (inbox drains on launch/foreground) → capture row +
   detail (Open ↗, editable annotation, no player bar). Also try a TEXT selection share + a PHOTO share.
   ↳ 2026-06-12 evening: sim-verified incl. the UX fixes above; device re-test still owed (esp. the
   share-from-Photos / text-selection variants + the first-time enable row).
2. CAPTURE Mac half: launch the dev desktop app → phone syncs the rated capture → review surface (source
   strip + banner + SHARED CONTENT card + url prop row) → Export to the test vault → check the .md
   (frontmatter url:/source:, pinned block above the annotation).
   ↳ 2026-06-12 evening: the WHOLE Mac half verified headlessly (commit 7799848) — real POST of the C3
   fixture → dev server → store row contract-perfect → REAL Gemma enhance-lite (title+summary on the
   annotation, no copy-edit) → compile → export to the test vault. New DEBUG flag `-processfile <id>
   [-exportafter]` (RunFile) runs Process+Export headlessly on any stored file — reuse it for future
   round-trips. CAUGHT + FIXED two export bugs affecting ALL notes: (1) filenames kept Obsidian-forbidden
   chars (Gemma's "Title: Subtitle" colons); (2) frontmatter title:/summary: unquoted → ': ' in a Gemma
   title makes Obsidian reject the whole frontmatter — both now sanitised/quoted + tests. What's left for
   the user here = just the visual review-surface check on a phone-synced capture. NOTE: a probe capture
   (Stoicism - Wikipedia, from the sim run) lives in the DEV store + an exported probe .md in the test
   vault — delete on sight if they get in the way. The dev desktop GUI app is currently QUIT.
3. Trim persistence end-to-end (OWED since the morning): capture sheet → tap a sentence in/out → ramble →
   saved audio/text/karaoke all match the trimmed span.
4. Reverse exclusion: play a memo in detail → start the audiobook → the memo must pause.
5. Instant record: no legacy ready-screen flash — brief "Starting…" then the live caption.
6. Mini-player 2 h idle auto-hide + Siri "Resume my book in Skrift" (shipped 2026-06-11, never tested).
7. Karaoke playback spacing nit (P2): confirm the slight vertical spread during playback is acceptable,
   or ask for the word-grid constant tune (FlowLayout lineSpacing 6 / VStack 8 vs static lineSpacing 4).

THE BOARD (user-locked order):
1. ✅ Capture items — BUILT, verify above.
2. CUSTOM VOCABULARY build (spike done 2026-06-11): CTC keyword-spot + rescore in BOTH transcribers +
   Settings "Custom words" list; one extra ~97.5 MB HF model. Integration pattern documented in the
   "Feature decisions — LOCKED 2026-06-10" §3 entry above.
3. MODELS TAB in phone Settings (list on-device models w/ state/size; spec under "Show downloaded models
   in phone Settings"; Mac mirror later).
4. PROD PROMOTION LAST: push native→main + Release builds both apps while prod idle. NOTE: Release bundle
   IDs need the one-time Xcode App-Group signing visit (same two clicks as dev, recorded in CLAUDE.md).
Significance-wall design session: DEFERRED (user call 2026-06-12).

OUTSTANDING (later, off the board):
- Confirmed bugs: names DON'T auto-sync after voice enroll (manual sync only); Mac "name a speaker" review
  UI (backend done, mock `name-a-speaker.html` awaits sign-off) + live enroll→auto-label round-trip;
  photo `[[img_NNN]]` marker drift (anchor by TIME not word count); confidence colours wrong in practice.
- Capture-items v1 flags (deliberate, flip on demand): no mic dictation in the sheet (extension memory
  ceiling); no location/weather on captures; "file" share type has no pinned block; UI-test capture
  seeding skipped (unit tests cover the logic); real third-party share payloads untested.
- QoL: drag-multi-select on the memos list (swipe-delete done); record-a-sample voice enroll in Names &
  voices; desktop unlink popover "Change to → <person>"; karaoke playback-grid spacing tune (P2).
- ✅ Audit nits — RECONCILED 2026-06-13 (verified each against CURRENT code + live on the fixture; the
  "open" citations were stale, written mid-desktop-track and never reconciled after the fixes landed):
  desktop sidecar try? writes (logged), 256 MB cap + early 413 (done), main.sync bridge (marshaled to
  main + NOW guarded by `dispatchPrecondition(.notOnQueue(.main))`), model idle-unload (real `unload()`
  fires 60 s idle — proven: idle `/health` returns available:false), real word_timings→karaoke (done,
  `BatchRunner:40`; runfile logs `word_timings: 90` on the two-Jacks fixture), `/health` truthful
  (`isModelReadySync`, not hardcoded), parity golden tests (`UnlinkTests`/`CompilerTests` cover it),
  HEIC→JPG (ImageIO now, fallback recomputes the md ref — old `sips` nit gone), snapshot try? (now
  logs write FAILED). Mobile — recorder deinit (belt-and-braces inline), silent-video import (titles
  "Video had no audio track"), photo-marker drift + confidence colours (fixed this wave). Commit dd…
  (`harden(desktop)`). NOTHING in this list is still open.
- With-user sessions: re-ingest ~30 old notes (`~/Desktop/Skrift old notes/`, prod quit, real vault);
  "transcription a bit weird" cold-start (parked unless seen again).

#### Session 2026-06-13 — desktop architecture A-list verified-done + Trash mirror built
- Verified the desktop "A-list" against CURRENT code + live (the backlog/CLAUDE citations were stale):
  model-unload, real word_timings→karaoke, 256MB cap+413, main-actor SwiftData marshal, truthful /health
  — ALL already done. Hardened the two genuine remainders: SwiftData-bridge invariant now enforced
  (`dispatchPrecondition(.notOnQueue(.main))`), snapshot write no longer claims success on failure
  (commit `2ac3d32`). Audit-nits section reconciled (`4a6a982`).
- ✅ **Desktop Trash / Recently Deleted** built (commit after `4a6a982`) — see board item 4 above.
- STILL genuinely open (features needing a pick/mock/user, NOT bugs): Mac "name a speaker" UI (mock
  awaits sign-off), drag-multi-select (mock first), watched-folder ingest, Backlink Weaver, unified
  source taxonomy, record-a-sample voice enroll (device voice), re-ingest 30 notes (with user), prod
  promotion (device tests + Release App-Group Xcode visit). Significance-wall = user-deferred.
- Deferred ideas: watched-folder ingest; summary prompt quality pass; tag lemma expansion; north-star
  semantic timeline ("how my thinking evolved").

#### CONTINUE HERE (SUPERSEDED — see the ⭐ block at the BOTTOM of this file, 2026-06-13 night) — session wrap 2026-06-12 night (the "do all outstanding" batch)
STATE: `native` green; every gate passed per commit (mobile 352 unit + 38 UI; desktop 231 unit + full
build). NOT pushed to main; prod untouched. PHONE: has capture items + share-sheet UX fixes + DICTATION
(installed earlier tonight); the LAST build (vocab + models tab + bug fixes + QoL) is STAGED in
`build-device/` — phone went unavailable before install. Install when plugged in + unlocked:
`xcrun devicectl device install app --device 00008110-001208C902EA201E Skrift_Native/SkriftMobile/build-device/Build/Products/Debug-iphoneos/SkriftMobile.app`

SHIPPED THIS SESSION (all sim/headless-verified, commits in order):
- Share-sheet UX pass (7f76a77+6b95070): keyboard buried Save (captures losable!) / light-on-dark mix /
  giant TextEditor / gray host backdrop — all fixed; Safari+Photos probes (opt-in) screenshot the flow E2E.
- Mac capture half verified LIVE (7799848): C3 fixture POST → store → real Gemma enhance-lite → export.
  New DEBUG flag `-processfile <id> [-exportafter]`. CAUGHT: Obsidian-forbidden filename chars + unquoted
  YAML title/summary (Gemma colons break Obsidian frontmatter) — both fixed, all exports affected.
- VOICE DICTATION in the share sheet (user ask): extension records (no model in-process), app transcribes
  on drain → annotation; sync holds till done; crash/failure recovery; ON THE PHONE already.
- CUSTOM VOCABULARY (board 2): CTC spot+rescore in BOTH transcribers + Settings editors both apps +
  word-timings re-alignment; `-runfile -vocab "A,B"`; LIVE-verified (planted "Jacques" replaced, real
  Jacks untouched). Dev Mac settings carry ["Skrift"]. Lists are per-device v1 (no sync — possible later).
- MODELS TAB (board 3): Settings → Library → Models (3 models, downloaded state + sizes). Mac mirror later.
- CONFIRMED BUGS fixed: names AUTO-SYNC after voice enroll (debounced push, no-op unpaired); photo-marker
  drift (marks anchored to the words they followed); caption colours now TRUTHFUL (solid = rotated
  committed chunks — a real finalized signal; volatile = live chunk; expect a LARGER lighter tail
  on device, up to ~25s — that's honest, not a regression).
- QoL: desktop unlink popover "CHANGE THIS MENTION TO →" (two-Jacks one-tap fix, Sanitiser.relinkOccurrence);
  karaoke grid spacing matches static text; silent-video failures self-titled. Git housekeeping done
  (haslett worktree + robustness-cleanup local branch removed — both targeted archived apps only).

DEVICE-TEST LIST (新, on top of the morning list):
1. Share from Safari with the NEW sheet: type + tap circles + Save WITH the keyboard up; dictate a
   voice note (first time = mic permission inside the sheet) → open Skrift Dev → annotation fills in.
2. Custom words: Settings → Capture → Custom words → add "Skrift" → record a memo saying it.
3. Models tab shows real sizes once models are on the phone.
4. Voice-enroll someone → names should reach the Mac WITHOUT a manual sync tap (~3s).
5. Live caption: solid text never changes now; lighter tail is longer than before (honest).
6. Desktop: click a [[Name]] → "Change this mention to →" the other Jack.

NOT DONE, with reasons:
- Significance wall / printer pipeline — user said skip.
- PROD PROMOTION — blocked on the device tests above + the one-time Xcode App-Group signing visit for
  the Release bundle IDs (CLAUDE.md records the steps).
- Mac "name a speaker" review UI — mock `name-a-speaker.html` still awaits sign-off (locked process).
- Drag-to-multi-select on the memos list — interaction design wants a mock first (locked UI process).
- Record-a-sample voice enroll in Names & voices — conversation-track; needs real-voice device
  validation; do with the next conversation-mode session.
- Desktop trash mirror, source-taxonomy unification pass, desktop A-list perf nits (multipart RAM cap,
  main.sync bridge, desktop real-timings karaoke, parity golden tests) — pre-existing backlog, untouched.
- Re-ingest ~30 old notes + "transcription a bit weird" — with-user sessions.

#### Text-first audiobook capture — DESIGNED + WAVE 1 BUILT 2026-06-13 (installed on the phone)
Trigger: real (non-builder) testers couldn't use the shipped Hybrid audio-marking capture
(didn't get in/out marks, too many buttons, didn't know sentences were tappable). Designed a
**text-first** alternative WITH the user + 2 verification agents (code-reality + locked-decisions)
+ 2 UX critics (caught the warming-screen purple-button misfire — "brightest element must be the
one intended action"). Full design + all decisions/nuances: `SkriftDesktop/mocks/text-capture-DESIGN.md`;
signed-off interactive mock: `mocks/text-capture.html`.

**LOCKED design points:** ships ALONGSIDE audio mode (A/B, Settings → Audiobooks Audio·Text toggle,
default Audio), surgically removable; the isolation seam is the `QuoteCaptureOutput` (Text mode emits
a GLOBAL span → SAME processor/sheet/save/sync/export). Tap-+-to-add / ✕-to-drop sentence select;
last line pre-picked; scroll (no button); "Hear selection" plays the span at 1.5×; warming screen is
just a wait (whole-book offer is a bottom link, NOT a button); no-speech = tiny "back to book"; no
false "place saved" reassurance. 35 s = one-time engine WARM-UP (not inference; ~1 s warm/screen).
Chunking = the path; **resumability locked** (chunk sidecar IS the resume state; discard the in-flight
half-chunk; pause-on-unplug/auto-resume). Whole-book transcribe = best overnight/plugged; ≈X-min/hr
estimate is a PLACEHOLDER pending real phone measurement.

**WAVE 1 BUILT (commit + installed):** the toggle, `TextCaptureView` (sentence-select),
`QuoteCaptureProcessor.transcribeWindowForDisplay`, the router in `QuoteCaptureFlowView` (both modes →
`confirmCapture(_:span:)`). 343 unit (+7 TextCaptureTests) + 38 UI green. Real transcription is
device-owed (no audiobook UI harness in the sim).
**OWED — DEVICE TEST (put it in front of the same testers):** flip Settings → Audiobooks → Text;
in a book, hit Capture → sentence-select; the two things to watch — (1) does +/✕ read as tappable
WITHOUT being told? (2) does the pre-pick + sandwich make EXTENDING feel natural, or do they just
confirm one line? If +/✕ still isn't instant, next lever = a one-time coachmark.
**WAVE 2 — BUILDING 2026-06-13 (user greenlit):** `BookTranscript` sidecar + chunker + resumable
overnight transcribe job + the transcribe-book button + instant-capture-from-sidecar + pre-warm-on-
book-open. Measure the real per-hour transcribe speed on the phone to replace the placeholder.
Multi-file/chapter-boundary confinement is already code-enforced (`QuoteCaptureProcessor:69-76`) — kept.
- ✅ Sidecar (`BookTranscript`/`FileTranscript` + `BookTranscriptStore`, per-file JSON, atomic write,
  `size:mtime` staleness, file-local word-timings; sentences derived on read via `buildSentences`).
- ✅ Chunk-seam fusion (`ChunkFusion`): cut at the last complete sentence, re-transcribe the tail next
  chunk — no split/dup words, uses `SentenceSnap`; run-on/silence fallbacks. Unit-tested.
- ✅ Resumable job (`BookTranscriptionJob`): sequential per-file chunk loop, save-after-complete =
  resume state (in-flight chunk discarded on interruption), pause-on-unplug + auto-resume on charge,
  foreground Pause/Resume, yields to live capture between chunks. Engine path device-owed.
- ✅ ⋯ "Transcribe book" button + sheet (`TranscribeBookView`, Text mode only): progress + %, Start/
  Pause/Resume, design §12/§13 copy. Instant-capture-from-sidecar (`TextCaptureView` Source +
  `buildOutputFromSidecar`; un-chunked → wave-1 fallback). Pre-warm on book-open in Text mode when the
  spot is un-chunked; live capture pauses the bg job.
- ✅ Real per-device speed: the job measures its own RTF (persisted) → the sheet shows a measured
  "≈ N min" estimate (placeholder removed). Mac `-asrbench` = ~100–134× realtime (inference tiny vs
  audio); the phone's absolute number is device-measured (job DevLogs per-chunk timing).
- **DEVICE-OWED:** real ASR on the phone (sim has no ANE) — run "Transcribe book" on a real book,
  watch the progress + the measured min/hr in the devlog, then capture at a done spot (instant, no
  warming screen) and at an un-done spot (wave-1 fallback); verify pause-on-unplug/auto-resume + that
  an interrupted job resumes from the last saved chunk.

#### Player redesign DEVICE TEST 2026-06-13 (night) — 2 fixes
- ✅ **Transcribe sheet showed "Resume transcribing" at 100% done** (device screenshot). Cause: the
  job clears `activeBookID` on finish → `isThisBook` flips false → the `.finished` control case was
  skipped → fell to the "Resume" default. Fixed: TranscribeBookView gates the done-state on
  **progress ≥ 0.999** (lede "Done…", a "Fully transcribed" indicator instead of a button, estimate
  hidden) — robust for both just-finished and a re-opened already-done book.
- ✅ **Read-along "text smaller & jumps fast" → Spotify lyrics** (device feedback). Reworked
  `ReadAlongView` from one re-coloring/reloading paragraph to discrete **lyric LINES**: current line
  large + bright (21 pt), neighbours dim by distance, **smooth auto-scroll** (centered, animated),
  soft edge fade, tap-a-line-to-seek. Loads the WHOLE covered prefix once (reloads only on coverage-
  frontier cross / file change) so scrolling is smooth, not jumpy. Device-owed re-look.
- ✅✅ **ROOT CAUSE of read-along trailing — chunker time-DRIFT (2026-06-13, proven on Mac).** Built a
  headless harness (`-readalongcheck`, `-chunksim` + `anchorDrift`, desktop `RunFile`): pulled the
  real book audio + sidecars off the phone, transcribed each chapter WHOLE on the Mac as ground truth,
  aligned on words unique-in-both. f0 (2 chunks) was clean (±0.08 s); **f2 "Beginning" (14 chunks)
  drifted monotonically late: thirds +0.40/+0.81/+1.99 s** — so no fixed lead could fix it. `-chunksim`
  reproduced + isolated the cause: **per-chunk `AVAssetExportSession` extraction from the compressed
  MP3 isn't time-accurate (error grows with seek position): thirds −0.24/+0.38/+0.96; sample-accurate
  `AVAudioFile` PCM frame reads = −0.02/−0.02/−0.01 (flat).** FIX (mobile): `BookTranscriptionJob`
  now extracts chunks via `extractPCM` (AVAudioFile → temp WAV), NOT exportSpan. `FileTranscript`
  schema 1→2 so the already-drifted sidecars re-transcribe. Quote-audio carving keeps exportSpan (a
  few-ms shift there is inaudible). Device re-test: re-transcribe "Do the Work", read-along should now
  ride the voice the whole chapter.
- ✅ **Read-along "text lags behind voice"** (device feedback) — also addressed the latency layer. The
  AVPlayer playhead (`session.currentTime`) only ticks every 0.5 s, so the lit line was quantized to
  half-second steps and always trailed. Fixed: `ReadAlongView` now INTERPOLATES the playhead between
  ticks (anchor + wall-elapsed × `session.rate`) on a 0.1 s timer, plus a small `lead` (0.2 s) for
  Parakeet-TDT's slightly-late word timings, and a snappier highlight (0.18 s). Lit line now tracks
  the narrator. `lead` is tunable if it reads early/late on device.

#### Wave-2 DEVICE TEST 2026-06-13 (evening) — vocab + transcribe-book
- ✅ **Custom vocab WORKS on device now** (user: "customs words are working"). Pre-warm-at-launch was
  the fix, confirmed.
- ✅ Transcribe-book runs: progress moves, measured estimate shows ("~11-12 min left"), pause-on-
  unplug → "plug in to continue" → auto-resume on charge all confirmed ("very cool"). Resume after
  force-quit PRESERVES progress (11% survived) — the sidecar resume state works.
- ✅ FIXED two device-found bugs (commit): (1) the transcribe sheet showed **0% on reopen** until
  Start (saved % wasn't displayed — data was fine); now `reflectSavedProgress` seeds the bar/label/
  estimate from the sidecar on open. (2) **Start while already charging showed "paused, plug in"** —
  `isPluggedIn` was read before battery monitoring was enabled (→ `.unknown` → false unplugged);
  monitoring now enabled in `init` + before the read in `start`.
- ✅ **UX — library long-press to transcribe (BUILT 2026-06-13):** `AudiobookLibraryView` rows got a
  `.contextMenu` — "Transcribe book" (Text mode) presents `TranscribeBookView` for that book without
  opening it; + Delete. No need to open book → ⋯.
- ✅ **UX — Control Center / record-widget icon (BUILT 2026-06-13):** the literal app icon CAN'T be a
  Control Center glyph (it's a detailed 3-D render; Control Center renders simple MONOCHROME templates
  → its silhouette is an indistinct blob). Control Center control kept as `mic.fill` (clear record
  glyph, already labelled "Skrift"). Real fix applied: the Home/Lock **record widget** was a generic
  RED mic-dot while the in-app record button is `skAccent` purple — rebranded the widget to the Skrift
  accent (`RecordWidget.accent` = 0x7c6bf5) so it reads as Skrift. A custom monochrome Skrift logomark
  for Control Center is a later option (needs simple mark artwork, not the 3-D icon).
- ✅ **Audiobook player UI redesign — DESIGN SIGNED OFF 2026-06-13** (grill-me). Spec mock:
  `Skrift_Native/SkriftDesktop/mocks/audiobook-player-redesign.html`. Direction = **text-forward
  A+D hybrid**: warm cover-derived tint header; cover demoted to a 56px chip; **live read-along text
  is the hero**, current line lit (reuse `Karaoke.activeWordIndex` on the sidecar word-timings); `Ch
  N/M` pill; speed◁ transport ▷sleep; slim **Chapters + Bookmark** icon row above a hero **Capture
  this** pill. Un-transcribed spot → **"Transcribe this book to read along →" nudge** (routes to
  `TranscribeBookView` — the player sells the transcribe feature). No read-along on/off toggle (v1).
  Resolved via grill: feature set = bookmarks + surfaced chapters (NOT AirPlay — Control Center
  covers it; NOT skip-silence/EQ). **Bookmark = NET-NEW, lightweight:** tap drops a marker (global
  position + chapter + timestamp), haptic + toast; list in the Chapters sheet under a Bookmarks tab
  (jump / swipe-delete); Capture stays the rich save. Mock-first step done.
  - ✅ **BUILT 2026-06-13** (autonomous): `Bookmark.swift` (model + `BookmarkStore`, per-book JSON,
    near-dupe guard, 6 unit tests); `ChaptersBookmarksSheet.swift` (Chapters | Bookmarks tabs);
    `ReadAlongView.swift` (sidecar-fed read-along, current line lit via cached window + per-tick
    recompute; nudge when un-chunked → TranscribeBookView); `AudiobookPlayerView` rewritten to the
    text-forward layout (cover-tint header from `UIImage.averageColor`, 56px cover chip, Ch N/M pill,
    speed◁/sleep▷ flanking transport, slim Chapters+Bookmark row, hero "Capture this"). Chapters
    removed from the ⋯ menu (now the sheet + slim row). App builds, bookmark unit tests green.
  - **DEVICE-OWED:** visual check (no headless iOS screenshot) + the read-along is only real on a
    transcribed book (sim has no ANE → shows the nudge). Verify: cover-tint band, read-along lit line
    tracking playback on a transcribed book, nudge on an un-transcribed one, bookmark drop+toast,
    Chapters/Bookmarks sheet jump + swipe-delete.
  - **GATES:** app builds (sim + device) ✓; **396 unit tests green** (incl. 6 bookmark); device build
    ✓ + INSTALLED. UI suite (re-run at low load): 36/38 ran-and-passed; the 2 failures
    (`testEnrolledPersonAutoLabeledOnSplit`, `testSplitSpeakersButtonSplitsIntoTurns` — both
    speaker-diarization, UNRELATED to the player/library/widget changes) fail on the fresh-erased-sim
    permission-dialog + onboarding wall (`allow-media`/`allow-location`/`get-started-button`), not an
    assertion — they passed earlier this session on a stateful sim (412-green). No UI tests exercise
    the changed audiobook player/library/widget surfaces. (Earlier mass UI failures were the host at
    load ~80 SIGTERM-ing the runner; resolved once load dropped.)
- Note: charging-state can lag a second after plugging in mid-run (iOS `batteryStateDidChange`
  latency); self-corrects. Acceptable.

#### Text-capture round 2 device feedback 2026-06-13 (evening)
PASSED: text-capture double-select GONE ("I can record my thoughts. Nice."); +/✕ & extend confirmed.
SHIPPED + installed: share-sheet PROMINENT record button (was a missed tiny mic — "why doesn't it
just have a button to record like the rest of the app"); ShareSheetView reworked (record primary,
type secondary). Vocab booster INSTRUMENTED with DevLog (spot/rescore outcome + replacements).
CONFIRMED BUG — custom vocab does NOT correct "Script"→"Skrift" with the model loaded. Next:
user records one more Skrift memo → pull devlog.txt → the `vocab:` line says whether the SPOTTER
missed it (phonetic limit) or the RESCORER declined (loosen minSimilarity/cbw). Don't blind-tune.
OPEN: (a) old stuck-"Transcribing" memos from the pre-fix build — delete, or add a launch
reconciler that re-transcribes stuck .transcribing memos (offered). (b) "sentence breaks up
strangely" in text capture — awaiting the capture-screen screenshot; likely Parakeet punctuation
(abbreviations like "Dr.") splitting sentences in SentenceSnap.isSentenceEnd.

#### ✅ CUSTOM VOCAB — VERDICT + FIX (2026-06-13, both apps)
**Devlog verdict = NEITHER spotter nor rescorer; the booster was never READY.** The fresh
`vocab:` lines (14:26:58) read `not ready (loaded=[], rescorer=false) → bg prepare, unboosted` —
no `wasModified` line ever appeared, so the boost never reached spot/rescore. Root cause: the
booster's spotter/rescorer are per-PROCESS in-memory state that resets every launch, and the
non-blocking design (the queue-jam fix) makes the FIRST transcribe skip while the ~97 MB ctc110m
loads in the background. The user records ~one memo per launch → it always raced the load → always
unboosted. "Model downloaded" (Models tab = on-disk) ≠ "booster warm" (in-memory, per-session).
**Mac ground truth** (`-runfile -vocab` with a synchronous prewarm + booster stderr diagnostic;
no phone audio needed): once warm, the spotter detects + the rescorer replaces — proven
(`Jacques: jack` alias surfaced `Jacques` at sim 0.43, below the 0.50 floor, and replaced).
script→Skrift is an EASIER case (sim 0.667, candidate already surfaces; the audio genuinely says
"skrift" so the acoustic gate favours it).
**FIX (committed, both apps):** (1) **pre-warm** the booster at launch when custom words exist →
the confirmed bug; (2) **aliases** via `"Canonical: alias1, alias2"` → user-controllable widening
for stubborn mis-hearings; (3) **trust guard** → FluidAudio's spotter-anchored rescue mangles
ordinary speech once warm (negative-control clip turned `room→Rox`, `its alias.→Tiuri`); the
booster now drops a boost when EVERY replacement is a distant acoustic-only guess (sim < 0.55 AND
no alias) → negative control verified CLEAN. cbw tuning was a DEAD END (even cbw=2.0 kept the FPs —
the original words' constrained-CTC scores are too low). cbw stays at FluidAudio's 4.5.
**DEVICE RE-TEST (owed — phone was unavailable this session):** with the new build, in Skrift Dev
say "Skrift" once → it should now correct (booster warm at launch). If a SHORT/uncommon word
(≤3-4 char, e.g. "Rox") still mis-fires on unrelated speech, drop it or add it with an explicit
alias; report and we tighten further. Note: very short words are inherently spotter-FP-prone.

#### ⭐ CONTINUE HERE — session wrap 2026-06-13 night
STATE: branch `native`, all committed, **`main` untouched / not pushed, prod untouched**. Mobile dev
build ("Skrift Dev", `com.skrift.mobile.dev`) **installed on the iPhone 13** (devicectl UUID
`A9195A77-601A-54C1-B3BD-659FBFE1DC54`). Desktop dev build in `build/` (vocab fix + read-along sync
harness). Gates per chunk: mobile 396 unit green (the 2 UI fails are the documented permission/
testmanagerd sim flake on unrelated speaker tests — pass on a stateful sim); desktop 248 unit + full
`-skipMacroValidation` build.

✅ SHIPPED + DEVICE-CONFIRMED:
- **Custom vocab fix** (both apps) — pre-warm booster at launch + aliases (`"Canonical: alias"`) +
  trust guard (drop distant spotter-rescue FPs, sim<0.55). **User confirmed working** ("customs words
  are working"). Root cause was readiness (per-process booster never warm), not spotter/rescorer.
  See the `✅ CUSTOM VOCAB` block above + [[project_vocab_booster]].

✅ SHIPPED (mobile, on the phone; real-ASR / read-along behaviour is device-owed to eyeball):
- **Text-capture WAVE 2** — `BookTranscript` sidecar (per-file JSON, file-local times) + `ChunkFusion`
  (cut-at-sentence, redo-tail) + `BookTranscriptionJob` (resumable charger job: save-after-complete,
  pause-on-unplug/auto-resume, yields to capture) + ⋯/long-press "Transcribe book" sheet + instant
  capture from the sidecar (else wave-1 fallback) + measured per-device speed (no placeholder).
- **Audiobook player redesign — text-forward A+D hybrid** (signed-off mock
  `Skrift_Native/SkriftDesktop/mocks/audiobook-player-redesign.html`): warm cover-tint header, 56px
  cover chip, `Ch N/M` pill, **Spotify-style read-along** (current line lit, smooth auto-scroll, edge
  fade, tap-line-to-seek), speed/sleep flanking transport, slim **Chapters + Bookmark** row, hero
  "Capture this". **Bookmarks** (light position markers) + **Chapters/Bookmarks TOC sheet**.
- **Library long-press → Transcribe book**; **record widget** rebranded red→Skrift purple.
- **Read-along sync — fully chased down + fixed (Mac harness, real data):**
  1. timings drift — per-chunk `AVAssetExportSession` on compressed MP3 drifts late, growing to
     ~+2s deep in a chapter (proven via `-chunksim`); fixed with sample-accurate `AVAudioFile`
     extraction (`extractPCM`), sidecar schema 1→2 to force re-transcribe of drifted transcripts.
  2. latency — interpolate the playhead between the 0.5s AVPlayer ticks + advance at line-END.
  3. stuck-nudge — the player now re-checks coverage every ~1.5s even paused, so a finishing
     transcribe flips nudge→read-along live (devlog proved the data was fine; it was stale UI state).
  4. smoothness + lead (device feedback "too early" + "words hustle"): lead 0.3→0.1; lines are now a
     UNIFORM 18 pt (font-size change can't animate → reflowed/shoved neighbours = the hustle), the
     current line emphasised by a smooth `scaleEffect(1.08, anchor:.leading)` (transform, no reflow) +
     brightness. Device re-eyeball owed.
  Desktop harness (`-readalongcheck`, `-chunksim`, `anchorDrift`) committed for reuse.

⏳ STILL OPEN / DEVICE-OWED (next session):
1. **Read-along final eyeball** — drift/latency/stuck-nudge/smoothness/lead all fixed + installed;
   confirm on a re-transcribed book it tracks the whole chapter, smoothly (no hustle), in-sync (not
   early). `ReadAlongView.lead` is the dial (now 0.1s) if still slightly off.
2. **Vocab — RESOLVED on device:** user confirms **both "Rox" and "Skrift" work** as custom words.
   The short-word-FP worry didn't materialise; keep as a watch-only note, no action.
3. **Control Center glyph — ✅ RESOLVED 2026-06-13: user chose A (`quote.opening` ❝).** Swapped
   `mic.fill`→`quote.opening` in BOTH `SkriftWidget/RecordControlWidget.swift` (the CC tile) and
   `SkriftWidget/RecordWidget.swift` (the Lock/Home widget — all four families: circular / inline /
   rectangular / systemSmall) for one consistent Skrift-forward mark. Sim build+test gate green
   (38 UI tests, 0 failures) + device build+install kicked off. The ONE thing no gate can prove for a glyph (SF Symbol names are plain
   strings — a typo renders blank, never a compile error) is that it draws ❝ → quick device eyeball
   owed. Options B (`pencil.line`) and C (custom carved-strokes template asset) not taken.
4. **Wave-2 deferred** (design doc §9): cross-chapter quotes; auto-transcribe-ahead while playing;
   **A/B test integrity** for text vs audio capture (assign the arm, pre-transcribe the test book,
   define the success metric); desktop mirror of wave-2 (mobile-only today).
5. **Bookmarks**: viewing the list is via Chapters sheet → Bookmarks tab (the Bookmark button only
   drops). Consider a more direct path if it feels hidden.
6. Pre-existing untouched: **prod promotion** (one-time Xcode App-Group signing for the Release bundle
   IDs, then Release build + `native`→`main`); Mac "name a speaker" mock sign-off; drag-multi-select
   mock; record-a-sample voice enroll (conversation track); desktop A-list perf nits (multipart RAM
   cap, off-main SwiftData on the Bonjour queue, real word_timings→karaoke, parity golden tests);
   re-ingest ~30 old notes; "transcription a bit weird" investigation.

#### ⭐ CONTINUE HERE — capture redesign + full-screen player (2026-06-13, DONE — installed, eyeball owed)
User signed off the **merged note-style capture screen + full-screen player** (mock
`mocks/audiobook-capture-merged.html`). **Text capture is now the only flow — the audio mark-in/out arm is
retired.** Built in 3 gated chunks on `native` (all committed + sim-green + on the dev phone):
1. ✅ **Player fills** — `ReadAlongView` flexible-height (geo-relative head/tail spacers, was a fixed 234 pt
   panel) + `AudiobookPlayerView` controls pinned at the bottom (dropped the dead `Spacer`). Sim green
   (38 UI + units, TEST SUCCEEDED). Committed.
2. ✅ **Merged capture** — `MergedCaptureView.swift` (NEW): one note-style screen = header (❝ + book·ch) →
   the real `SignificanceCircles` card → build-your-quote sentence rows (reuses `TextCaptureSelection`) →
   Record-your-thoughts pinned. On record: build quote from the selection → `saveQuoteCapture` → apply
   significance → `RecordView(appendTo:)` → recorder dismiss auto-resumes the book + lands as the normal
   note (NO preview; the ramble append is fire-and-forget so it's safe). Routed via a rewritten
   `QuoteCaptureFlowView` (all capture → merged). A bail before recording discards the quote-only memo
   (always-records). Sim green (TEST SUCCEEDED), committed. Old views still present-but-dead (deleted in 3).
3. ✅ **Retire audio arm** — deleted `CaptureMomentView` / old `CaptureSheetView` / `TextCaptureView`
   (pure `TextCaptureSelection`+`TextCaptureMath` relocated to `Models/TextCaptureSelection.swift`) /
   `AudiobookCaptureStyle` + its Settings toggle / `CapturePausedRow` / the now-orphaned `GrainPlayer` +
   `SpanWaveform`. Kept `CaptureMath` (`QuoteCaptureProcessor` still uses it). Ungated the `.text` checks
   (Transcribe-book always in player ⋯ + library long-press; `prewarmIfUseful` always). Dropped
   `testCaptureStyleDefaultsToAudio`. Sim gate green (TEST SUCCEEDED), committed.

ALL 3 CHUNKS DONE + sim-green + **DEVICE-INSTALLED** on the iPhone 13 (`com.skrift.mobile.dev`, devicectl
UUID `A9195A77-601A-54C1-B3BD-659FBFE1DC54`). `main` untouched / un-pushed. Commits: glyph `806645b`,
player-fills `605efec`, merged-capture `24d6e85`, retire-audio `6a08df7`.
DECISIONS (locked w/ user): always records voice (no quote-only save, may revisit); auto-resume + no
preview; significance on top mirrors the note (verified: note order is title→chips→significance→body).
⏳ OWED (device-only — sim has no ASR): eyeball the **❝ glyph** (CC + Lock/Home widget), the **full-screen
player**, **read-along sync** (`ReadAlongView.lead` 0.1 s is the dial), and the **merged capture E2E**
(Capture → significance + build-quote → Record your thoughts → auto-resume into note). Re-transcribe a
book first (schema-2 sidecar). If read-along reads early/late, say which → tune `lead` (+ desktop
`-readalongcheck` to separate data-drift from offset).

✅ BUILT 2026-06-14 — **bidirectional + bounded build-your-quote** (`MergedCaptureView`). Took two
corrections to land the shape: (1) first attempt went BACKWARD-only (an "Earlier ↑" control) — the user
meant scroll DOWN / select AFTER the tap ("i cannot scroll down. only allows selection from before capture
point"); (2) the fix then over-shot to load the whole file = INFINITE scroll — user: "8 is plenty". FINAL:
the tapped line is the pre-picked anchor in the MIDDLE; the displayed slice = the ~90 s heard BEFORE it +
up to **8** lines AFTER (transcribed) / **4** (un-chunked) — scroll up earlier, down a little later, NO
infinite. Transcribed → sidecar (`fileTranscript().words`, file-local); un-chunked → transcribe ≈90 s back
… ≈45 s forward. `sel` indexes the full array; only the bounded slice (`displayLo…displayHi`) renders;
auto-scrolls to the tapped line. Compile + unit gate green; device-eyeball owed.

#### Audit 2026-06-14 — P1 bugs + build-ready features verified against code (read-only agent)
Most of the old P1 list is ALREADY FIXED (code + a doc comment naming the original bug); device re-verify only:
- ✅ Desktop summary editable (`NoteDisplayView.swift:394`); ✅ name-link first-mention-only
  (`Sanitiser.swift:81-111`, handles per-turn `**[[Person]]:**`); ✅ desktop Photos-drag ingest
  (`SidebarView.swift:495-615` FilePromiseDropCatcher); ✅ confidence colours use the real committed-word
  boundary (`RecordView.swift:227` + `TranscriptionService.liveCommittedWordCount`); ✅ video thumbnail BOTH
  apps (mobile `MemoSaver.swift:162`, desktop `IngestService.writeVideoThumbnail` — the "desktop has none"
  note was stale); ✅ Spotify-stops-on-open + paste-scroll-to-top both fixed.
- ✅ **FIXED 2026-06-14 — share-a-video from Photos.** Added `NSExtensionActivationSupportsMovieWithMaxCount`
  (`project.yml` → regenerated `SkriftShare/Info.plist`) so Skrift appears in the Photos share sheet for
  videos; `SharePayloadLoader.loadVideo` copies the movie to the App Group inbox as a `"video"` entry
  (raw-string type — NO `ShareContentType`/contract change; extension copies the file, never loads it into
  its memory ceiling) and bypasses the capture sheet (`ShareViewController.completeVideo`); `CaptureInboxDrainer`
  imports it via `MemoSaver.importVideo` → a normal voice memo (audio + frame thumbnail + transcribe; delete-
  before-import so a re-drain can't double-import). Compiles (both targets), installed on the dev phone.
  ✅ **DIAGNOSED + FIXED 2026-06-14 (DevLog device trace).** It was NOT a delete or a crash — the memo
  **relocates**. `importVideo` inserts it at `recordedAt = now` (top of the list, where you see it), then
  `processVideo` rewrites `recordedAt` to the video's EMBEDDED filming date (trace: `recordedAt=2026-06-11`
  vs `now=2026-06-14`) — intended ("sort by when it happened") — so it jumps from the top down to its real
  date and "vanishes" from where you're watching. The trace proved the relay + extract + thumbnail +
  transcribe all COMPLETE (`done; final status=done`); none of the three delete-vectors fired. FIX (user
  picked "keep the date, open it on import"): `MemoOpenBridge` (mirrors `RecordingIntentBridge`) — the drain
  calls `open(memoID)` after a shared-video import; `MemosListView` consumes it (`.onChange` + `.onAppear`
  for cold-launch-from-share) and sets `path = [id]`, landing the user ON the memo regardless of where it
  sorts. The `DevLog` markers along drain→importVideo→processVideo + the delete vectors are kept (DEBUG-only).
  Original symptom below.
  ⓘ Earlier repro note: share a video → it preps → share UI closes (no confirm = expected) → open Skrift →
  memo appears, flashes `transcribing`, then **VANISHES** (= relocates, per above). STATIC READ rules out the obvious causes: (1) nothing
  auto-deletes a non-trashed memo (`purgeExpiredTrash` only touches `deletedAt`-set / ≥14-day memos; there's
  NO purge of empty/transcribing memos); (2) the extract-failure path does NOT delete — `MemoSaver.processVideo`
  marks the memo `.failed` + title "Video had no audio track" and keeps it. So a true vanish is runtime/
  device-specific (AVFoundation reading the App-Group→temp copy, a drain timing thing, or security-scope on
  the shared file — note the leaked app-temp `shared_import_<id>` too). PLAN: add `DevLog` to the
  drain→importVideo→processVideo path (entry found · temp path · importVideo memoID · extractAudio result ·
  final transcriptStatus · any delete), repro on device, pull `Documents/devlog.txt` — share-ext + AVFoundation
  + device-only, the sim can't repro (CLAUDE.md: instrument + diagnose from the trace FIRST). The bidirectional+
  bounded capture (8/4) is the OTHER thing on the phone from tonight; eyeball both.
- (g) disk-writes `.ips` = profiling, not a clear fix (model downloads + whole-book transcribe = suspects).

Build-ready feature TRUE status (corrects the stale lists above):
- Models/Storage: ✅ MOBILE (`Features/Settings/ModelsView.swift` + `ModelInventory.swift`); ❌ DESKTOP (none).
- Record-a-voice enroll: ⏳ PLACEHOLDER both apps (`PersonDetailView`/`VoiceEnrollView` doesn't record; enroll only via conversation-naming).
- Mac "name a speaker" review UI: ⏳ OPEN (backend `DiarizationService.embedSpeaker` ready, called only from the `-voiceloop` harness; no turn-renderer / click-to-name in `Features/Review/`).
- Drag-multi-select (Photos-style lasso): ⏳ OPEN (native edit-mode drag works only AFTER the Select button; the lasso-replacing-Select wants a mock).
- In-app feedback → inbox/backlog: ⏳ OPEN (only the email zip; routing today is the external pull-phone-feedback skill).
- Source taxonomy: ⏳ PARTIAL — glyph/label maps DUPLICATED (`QueueDerivations.swift:61` desktop vs `MemoDisplay.swift:184` mobile), coincidentally in sync, no shared module; no PDF/video first-class type.

#### ✅ Memo sort/filter by date (recorded / added / edited) — built 2026-06-14
From the share-video discussion (user: "the date of recording just stays true"). `Memo` gains `createdAt`
(when it entered Skrift) + `editedAt` (bumped on title/transcript/tags/append edits via `markEdited()`) —
both nil-default, so legacy memos fall back to `recordedAt` (NO migration/backfill). Sort sheet:
**Recently added (NEW DEFAULT)** / Recently edited / Recently recorded / Oldest / Longest; the day-headers
follow the active sort (`groupDate`). Filter gains a **date range** on Recorded OR Added (from/to,
inclusive). `recordedAt` stays the content's TRUE date — so a shared video keeps its filming date but
sorts to the TOP under "added": this (not the open-on-import patch) is the real resolution of the "video
vanishes" report — both shipped, belt-and-suspenders. Compile + unit gate green; device-eyeball owed (the
date-range pickers + the edited-sort over real edits). Not added to the Mac upload contract (local-only).
Deferred edit-sites: conversation-turn text edits + C3 annotation don't bump `editedAt` yet (fall back to
`createdAt` — fine; add if it matters).
