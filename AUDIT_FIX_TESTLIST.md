# Audit-fix branch — review + manual test list (2026-07-19)

Branch `audit-fixes` (worktree `.claude/worktrees/audit-fixes`). Review the diff with
`git diff main..audit-fixes`. Wave 1 (the `try?` hardening pass) is already ON MAIN
(`509c4fb` desktop, `349270a` mobile) — it landed before you asked for isolation; both
suites were green. Everything below is on the branch.

**Verified by me:** mobile unit suite 718/718 green (twice), desktop unit suite green
(see final summary for the run on this branch). The UI-test bundle still carries the
KNOWN pre-existing iOS-26 failures (deferred 2026-06-18) — unrelated to this branch.

## Phone checks (Dev build)

- [ ] **Record → stop → immediately background the app** (pocket it). Reopen after ~1
      min: the memo should say transcribed, NOT be stuck "Transcribing…" until relaunch.
      (BackgroundTask wrap on the record path — wave 1, on main.)
- [ ] **Scroll the memos list** with a few hundred notes + photos: should feel snappier;
      photo tiles sharp (downsampled now). Search-as-you-type smoother. (Wave 2.)
- [ ] **Read-along while transcribe catches up**: play a book past the transcribed
      frontier ("Keep listening — the page catches up"). Playback + UI should stay
      smooth (was a 2Hz full-JSON decode on main); the page still flips to read-along
      when the frontier passes you. (Wave 3.)
- [ ] **Whole-book transcribe**: progress % still advances per chunk; a finished book
      still detects chapters. (publishValue now reads a cached frontier.)
- [ ] **Merged capture view** (tap a line in a transcribed book): opens instantly even
      on a fully-transcribed long book. Sentences at the window edges look whole.
- [ ] **Audiobook sync — permanent failure surface**: hard to fake without filling
      iCloud; if you ever see "iCloud storage is full — sync paused for this book." in
      the book's sync sheet, that's the new terminal state. Toggle sync off/on = retry.
- [ ] **Initial-sync burst**: on a fresh device sync, the app should stay responsive
      (sweeps now coalesce ~1s after the burst instead of running per event).

## Mac checks (Dev build)

- [ ] **Drop a long video** onto the sidebar: UI stays responsive during the audio
      extraction (was a full beachball). Note still appears + transcribes as before.
- [ ] **Edit a note WHILE it's processing** (start Process, open the note, type in the
      body during the enhance step): your edit survives; the note's status returns to
      pending with a log line ("stale run discarded") instead of your text being
      overwritten. Reprocess re-derives from the edited body.
- [ ] **Launch the app twice** (Dock/Spotlight while it's already running): second
      launch just brings the running window forward — no second process on the store.
- [ ] **Reconcile sweep memory**: with Mac sync on and a big library, Activity Monitor
      during launch/foreground should no longer spike by the size of your audio/photo
      blobs (steady-state sweep no longer realizes them).
- [ ] **Reconcile summary log** (Console, subsystem com.skrift.desktop): now reads
      "ingested X, reflected Y, ingest-failures Z" — Z > 0 means a memo is failing
      every sweep and the log names it (was invisible).
- [ ] **Connections gate**: if a model download/sweep fails, the gate now shows the
      reason in red under the footnote (was: silently re-shows "Turn on Connections").
- [ ] **Vault export**: a failed attachment copy now logs (subsystem com.skrift.desktop,
      category export) — vault embeds can no longer dangle silently.

## Cross-app / retrieval

- [ ] **Connections still work** on both apps (index intact): related notes show as
      before. The new empty-snapshot guard means a transient fetch failure can no longer
      silently wipe the index (would have re-paid the 2-min ANE cold start invisibly).
- [ ] After any future embedder model bump: not-yet-reindexed memos DROP OUT of
      related/search until re-embedded (no-bad-info) instead of scoring as garbage.

## Deliberately NOT changed (verified + documented)

- Trash purge stays synchronous in App.init — its "before any UI shows them" ordering
  is deliberate; the fetch is trash-only and usually empty (falsifier downgraded to P3).
- BookCoverCache stays sync-on-main — cached after first miss, pixel decode deferred to
  draw (falsifier P3); an async refactor would churn 4 views for negligible gain.
- Per-buffer `Task { feedStream }` ordering (recording captions): NEEDS-DEVICE evidence
  first — architectural hazard confirmed, but display-only and self-healing; instrument
  before restructuring.
- Quote-capture `AVAssetExportSession` drift: production passes the precise-timing flag
  the measured-bad harness lane lacked; STEP 0 is a chunksim third lane (export WITH the
  flag) — an experiment, not a code change. Backlog carries it.
- `ExportStateStore` O(k·n) persist: `publishAll()` has no production caller (unwired
  standalone publish phase) — fix lands when that phase is wired.

## Discovered during final verification

- **`mlx-swift-lm` is pinned to `branch: main` (floating)** — a fresh checkout/worktree
  resolves today's upstream, which currently does NOT compile against the resolved
  mlx-swift (`DType.greatestFiniteMagnitudeArray`). Your main checkout only builds
  because its resolution is cached. The worktree build was fixed by copying main's
  `Package.resolved`. Durable fix (your call on revision): pin mlx-swift-lm to an exact
  revision in `project.yml`, like FluidAudio already is. Backlogged.

## Known-issue notes for this branch

- The 6 failing UI tests (Smoke launch, Settings inventory, Share probes, VoiceEnroll)
  predate this branch — most trace to the lifecycle chat's Settings/list restructure +
  the deferred iOS-26 cluster. Not touched here.
