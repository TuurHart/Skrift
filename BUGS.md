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
