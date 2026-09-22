# Bugs — one list, worst first

Every bug we have collected, pulled out of `archive/state-2026-09/backlog.md` (8k lines, chronological), `archive/state-2026-09/AUDIT_PLAN.md`
and the device-feedback rounds, so there is one place to work through instead of a scroll.

**How to read the status.** Section 1–3 were each re-opened against today's source and the line
numbers are current — they are real, now. Section 4 is from the ledger and has NOT been re-checked;
treat those as leads and verify before acting. Section 5 is the opposite: ledger entries that turned
out to be **already fixed**, listed so nobody re-opens them.

Built 2026-09-14 off `main` at `858ec1b`. Fixing something? Tick it here and in its home section of
`archive/state-2026-09/backlog.md`, which keeps the full story.

---

## 1. Data loss — fix regardless of anything else

- [ ] **D4 · A whole recording is lost if the app dies mid-recording.** A phone call is enough.
      Nothing persists an in-flight recording until `stop()`, and `rec_tmp` appears exactly once in
      the repo — `SkriftMobile/Services/Recording/LiveRecordingService.swift:433`, the line that
      creates it. No sweep recovers the orphan, and the user is never told.
      Tuur, 2026-08-22, prod. Happened before: the 2026-06-10 crash-mid-recording P0 ("3× today,
      one recording LOST") fixed the crash and left the durability gap.
      → [issue #14](https://github.com/TuurHart/Skrift/issues/14) · full triage + 4-step fix in
      `archive/state-2026-09/backlog.md` `## 🚨 OPEN P0` · `tools/rescue-lost-recordings.py` pulls the existing orphans.

- [ ] **D1 · `names.json` can be lost across every device.**
      `Shared/Naming/NamesStore.swift:50` is `try? encoded.write(to: fileURL)` — not `.atomic`.
      `load()` returns an empty roster on decode failure, and `addVoiceEmbedding` is an unguarded
      read-modify-write called off-main by `VoiceEnroller`. CloudKit LWW then propagates whichever
      side lost. One-line partial fix: `options: .atomic`. Full fix: actor + cache (folds in P7).
      Re-confirmed 2026-09-22 in the native port: `NamesStore.swift:28-53` still non-atomic, `load()`
      still empty on decode failure (names probe shape 1, Shared sweep).

- [ ] **D2 · Re-transcribe destroys the transcript when the audio has moved.**
      `SkriftDesktop/Features/Shell/ProcessingCoordinator.swift:368-370` sets `pf.transcript = nil`
      (plus wordTimings, diarization, sanitised, enhanced, compiled) **before** `process()` learns
      the audio is gone. `BatchRunner.swift:66` then marks the note done anyway and `:103-107` marks
      it enhanced-and-empty, with no error. Permanent for Mac-local rows; phone-sourced rows heal on
      the next sweep.

- [ ] **D3 · Vault export deletes a file it doesn't own.**
      `SkriftDesktop/Pipeline/Export/VaultExporter.swift:269-270` and `:293-294` both `removeItem`
      then copy, under the **original filename**. An attachment called `IMG_0001.jpg` clobbers
      whatever is already at that path in the Obsidian vault. The markdown lane is protected by
      `VaultWriter`; these two attachment lanes bypass it entirely.

---

## 2. Wrong behaviour — verified open today

- [ ] **Two people with the same full name fuse into one.** `Shared/Naming/NamesStore.swift:157-179`
      and `NamesData.swift:154-184` union the aliases and voiceprints of a second "John Smith" into the
      first; the Mac's `RosterAudit` guard only runs on one of three add paths (`SettingsView.swift:47,
      50-53`, `NamesCloudSync.swift:54`). SPEC R61, R62 / C254 / D96.
- [ ] **A deleted person's voiceprints come back.** The sync merge unions embeddings onto the
      tombstone (`NamesStore.swift:88-97`, `NamesData.swift:180`). SPEC R63 / C259.
- [ ] **A mid-body quote links names.** `Sanitiser.swift:713-716` protects only a note-opening `>`
      block; D21 says any quote block. SPEC R64 / C82.
- [ ] **`#Jack` becomes `#[[Jack]]`.** No tag-span guard in the linker (`Sanitiser.swift:751-756`).
      SPEC R65 / C260.
- [ ] **The assign-speaker sheet mints alias-less people.** `MemoDetailView.swift:1671-1690` →
      `NamesStore.swift:113-128`, no editor shown; R12's shape at a second call site. SPEC R66 / C257.
- [ ] **A synced rename leaves stale name spans on the open note.** The phone loads `people` once per
      open (`MemoDetailView.swift:821,893-896`) and `NamesCloudSync.run` posts nothing. SPEC R67 / C258.
- [ ] **Ines never matches Inés.** No diacritic folding in `Sanitiser.swift:748-756`; same site for the
      Dutch bare possessive (`Wims`). SPEC R68, R69 / C256, C255.
- [ ] **The Mac never sends timings or speaker turns back to the phone.** `MacCloudWriteBack` has no
      asset writer, so a Mac re-transcription of an untrusted phone note, or a conversation split on
      the Mac, loses karaoke and turns on the phone/iPad. Widens the Mac-take bug above. SPEC R35.
- [ ] **A Mac import is authored without metadata** (`MacMemoAuthor.author`): a video imported on the
      Mac shows the mic glyph on the phone; Mac recordings carry no weather/daypart. SPEC R36, D92.
- [ ] **Name picks go nowhere:** the Mac ignores the phone's per-note picks (`MemoCloudUpdate.swift:156`),
      the Mac's own picks live on its row and never sync, and the phone's export ignores its own picks
      (`MemoLinking.swift:26,28`). One note exports different links per device. SPEC R37 / D20.
- [ ] **OCR text and shared documents never export**; `sharedContent` type `file` falls through
      `Compiler.swift:254`; `createdAt`/`duration` never written. SPEC R38 / D12.
- [ ] **The Settings "Model repo" field floats to revision `main`** for any non-default repo
      (`PolishPrompts.swift:44-45`, `SettingsView.swift:160`) — the August two-models drift can recur. SPEC R39.
- [ ] **A failed cloud fetch in the reconcile sweep is swallowed** (`MemoCloudReconciler.swift:59`): the
      Mac silently stops pulling phone notes and it looks like "nothing new". SPEC R40.
- [ ] **`voice:` can lie**: the phone labels a raw body `cleaned` when the Mac's polish set only
      title/summary (`MemoExporter.swift:90` vs `CompilerBridge.swift:73-75`). SPEC R41.
- [ ] **A corrupt bookmark sync blob wipes the device's bookmarks** for that book (decode → `[]` →
      adopted, stamp advanced, never heals) (`AudiobookBookmarkSyncCore.swift:41`). SPEC R42.
- [ ] **Apple Notes import can create a blank note** when the copied file fails to read back
      (`IngestService.swift:180`). SPEC R43.
      Sources: `plan/parity.md`, `plan/bug-shapes.md` (2026-09-22, verified against code by the sweep).
- [ ] **Second hunt, 2026-09-22 (plan/scenarios-adverse.md, plan/scenarios-review-archive.md,
      plan/bug-shapes-outer.md, plan/test-coverage.md) — SPEC R44–R60, each with its file:line there:**
      clock-skew LWW refusal (R44) · future `recordedAt` = immortal note (R45) · disk-full silent
      `try?` in the recorder (R46) · iCloud account switch unhandled (R47) · reminder set before
      permission (R48) · hand-typed `[[word]]` leaks to the vault (R49) · tag with `: ` breaks YAML
      (R50) · archive: `people:` garbled by its parser, `![[…]]` for picture-only, `date:` not `added:`
      (R51) · Redo clobbers hand edits (R52) · stale folder bookmark never read (R53) · iPad polish
      battery claim false (R54) · Mac live-caption finalize drops sentences (R55) · sweep trashes the
      open Mac note (R56) · diarization parity (R57) · Connections failure invisible on mobile, iPad
      cap 4 (R58) · corrupt bookmarks.json wipes bookmarks, `receiveTranscripts` unverified (R59) ·
      turn edit lands on the wrong turn (R60). Verified SAFE, don't re-spend: DST vs duration,
      duplicate keeper at scale, 400-person roster, recording-start reentrancy, cold-launch double
      fire (idempotent), fading-conveyor coverage.
- [ ] **A Mac recording never gets karaoke on the phone or iPad.** `MacMemoAuthor.swift:92` authors
      the synced memo with the audio asset only; the word timings stay on the Mac's `PipelineFile`
      (`ZWORDTIMINGSJSON`, present for every Mac take). The phone's timings DO reach the Mac. Fix:
      author the `wordTimings` (and diarization) assets too. Found 2026-09-22 on the five Dutch
      rambles; SPEC R34 / C245.

- [ ] **A person added on the phone can never be linked.**
      `SkriftMobile/Features/Names/NamesListView.swift:202` saves `aliases: []`, while
      `PersonEditorView.swift:222` already seeds `[name]`. Nothing matches a person with no aliases.
      Fix: same seed in AddPersonView, plus a one-time backfill `aliases = [canonical]` for
      alias-less people (safe — only AddPersonView ever produced them). The backfill also fixes
      IJsbrand. Ledger: Stz020 #3.

- [ ] **"Edit book details" never syncs.**
      `SkriftMobile/Services/Audiobooks/Audiobook.swift:562-566` — `update(_ book:)` replaces the
      row and persists but never sets `modifiedAt`, so the reconcile send-guard never fires. The
      contrast is four lines below it: `updateProgress` at `:570-574` sets it with the comment
      "sync LWW key". A replaced cover never re-uploads either, because of the `audioUploadedAt`
      upload-once gate.

- [ ] **Seek while paused is never persisted.**
      `SkriftMobile/Services/Audiobooks/AudiobookSession.swift:258-272` — `seek(to:)` updates the
      player and Now Playing but never calls `persistProgress`, so force-quitting after a paused
      scrub loses the position.

- [ ] **Book cover placeholders change colour every launch.**
      `SkriftMobile/Features/Audiobooks/BookCoverView.swift:56` picks the palette with
      `abs(book.id.uuidString.hashValue)`, and `hashValue` is seeded per process — despite the
      comment claiming otherwise. Use the UUID bytes.

- [ ] **Same-titled notes overwrite each other's images on export.** `convertImageMarkers` names
      images `<safe-title>_NNN.ext`, so two notes with the exact same title collide in the vault
      attachments folder. Uniquify by the note stem, which the `.md` already uniquifies.

---

## 3. Reported on device, not yet diagnosed

These need a device round or a log pull before they can be fixed.

- [ ] **Semantic search intermittently finds nothing.** "I'm trying" stopped surfacing the testing
      notes; worked on earlier builds. Instrumentation is already in: `SemanticSearch …` devlog
      lines log count / top-score / floor per query, and FAILED on throw. Suspects: a swallowed
      engine-load error, or short queries genuinely scoring under `searchFloor` 0.25. Repro, then
      pull the devlog. (Dev build only — Release has no devlog.)

- [ ] **Skrift Dev crashed a few times at random spots** (build 53, mixed usage). Never diagnosed.
      Pull crash logs with `idevicecrashreport` per the pull-phone-feedback skill. Builds 45–53 span
      the recording, books and P8 work, so the lane is unknown.

- [ ] **The app feels slow next to other apps** (Tuur, 2026-08-18) at under 200 notes, so not data
      volume. Step 0 is a Time Profiler run on the **prod** build — busy main thread or blocked? The
      cheap suspects are already located: `archive/state-2026-09/AUDIT_PLAN.md` P1–P7. Two of the audit's findings are
      DEBUG-only and never ran on his phone.

- [ ] **Transient "lost the link" on the Mac**, once, not reproducible (second try kept it). Watch
      for it rather than hunt it.

---

## 4. From the ledger, NOT re-verified

Leads. Check them against source before you act — section 5 is why.

- [ ] Append can silently add no text (3× repro on build ~30, broader than the cold-model theory) —
      `MemoSaver.appendRecordingAsync`. `archive/state-2026-09/backlog.md` "Original P0 list".
- [ ] Tail of a recording cut off after Stop, both dev and prod, intermittent. A finalize/transcribe
      race was fixed for one path (`audioFile.close()` before the one-shot read); unclear if this
      report is the same one.
- [ ] Mac search-jump parity gap — Mac search filters the sidebar but doesn't jump to the hit.
- [ ] Post-0.2.0 prod findings (2026-06-26, build 22) — a triage block nobody closed out.
- [ ] Device-testing feedback 2026-06-17 — one data-integrity finding in that batch.
- [ ] ANE-compile hang has no timeout or retry affordance (speculative, needs UX).
- [ ] `NamesMerge` millisecond-tie always favours remote (`Shared/Naming/NamesData.swift:172-178`);
      `MacCloudWriteBack` wall-clock LWW has no skew tolerance (fine on a single Mac).
- [ ] Starting a transcribe on book B while book A's job runs may still cancel A's job silently.
      The *display* half of this one is fixed (below); this half was never checked.

---

## 5. Already fixed — do not re-open

- ✅ **WhatsApp voice messages import as a link.** The ledger says `SharePayloadLoader` has no
      `UTType.audio` branch, so the url branch wins. It does now:
      `SkriftShare/SharePayloadLoader.swift:85-94` filters audio providers first, with the comment
      "conforming to public.audio is an audio import, full stop". Fixed after that entry was written.
- ✅ **The transcribe-book sheet shows another book's progress.**
      `Features/Audiobooks/TranscribeBookView.swift:16` now derives
      `isThisBook { job.activeBookID == book.id }` and gates the running / paused-by-user /
      paused-unplugged cases on it (`:161-165`). The silent-cancel half of that report is untested —
      it's in section 4.
- ✅ **The iPad's note button says "Process" for a note already processed** — closed 2026-08-18.
- ✅ **List thumbnail stale after deleting photos** — fixed 2026-07-18.
- ✅ **Audiobook import rejects MP3** — fixed twice, second time with a different root cause
      (2026-06-24, then 2026-07-05, device-verified).
