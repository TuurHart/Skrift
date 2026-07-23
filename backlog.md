# Skrift — Backlog

Deferred ideas and features, captured during the 2026-06 overhaul planning so they're not lost. Not scheduled — pull from here when ready.

## 📖 Phone feedback 2026-07-23 (1 memo, 08:03 — pulled + second-agent verified same day)

All items are the ePub/audiobook-text flow. ⚠️ **The concurrent audiobook session
(`claude/audiobook-ui-harry-collab-e065c7`) is working this area live with Tuur** — the memo
even ADDRESSES its replace-vs-augment fix, and Tuur's screenshots live in that chat. Coordinate
before building any of these here; tick items off when either session lands them.

- **P1 · Partial-ePub ingest is the real bug (corrects that session's diagnosis):** ePub text ==
  spoken text in this case, so replace-vs-augment wasn't the failure — **not all parts of the ePub
  were displayed/ingested**; whole-ePub ingest would have worked. The "weird error" in Tuur's last
  two screenshots (in the other chat) is likely this same bug's visible symptom — check them first.
- **P2 · Big-ePub import UX (13-hour book):** long load, no progress bar, and unclear whether
  listening can continue during the load — show progress + keep playback available (or say so).
- **P2 · Block ePub upload while the book is still transcribing** — currently undefined; Tuur:
  "it should not" be allowed.
- **P2 · Unify the transcribe-book menu with the ePub-upload menu:** one "add text" flow, two
  levels — level 1 get text (transcribe), level 2 upgrade quality (attach the ePub).

## ⏱ One-clock lifecycle: BUILT 2026-07-22 (suites green both apps) — Dev-deploy eyeball owed

**Spec = `Skrift_Native/SkriftDesktop/mocks/lifecycle-triage-peek.html`** (committed d27a047; m6 = the
build panel, m5 = the model; Q-block records the verdicts: m2+m5 adopted, **Lock demoted to a
background verb** — Tuur, 2026-07-22). **DOCTRINE:** supersedes 2026-07-17 "touched never fades" →
*touch restarts the 30-day clock*; only rated/locked/reminder/backlinked sit off the clock. Memory =
`project_lifecycle_one_clock`; roadmap node = `LifeClock` (done).

### ⏱ v3 amendment — "NO NOTE DIES UNSEEN" (Tuur voice note 2026-07-23; BUILT same day, branch `claude/note-deletion-app-open-5r5z56`)

**DOCTRINE (Tuur):** the fade clock keeps running while the apps sit closed (fading stays honest
about time), but **the final doors only move at an app-open** — a note can only be *sent to Recently
Deleted*, and Recently Deleted can only *burn purge days*, while the user has actually opened the
app. Phone in a drawer for three months → the note is still there at the next open (in Recently
Deleted at worst, with its FULL 14-day window to bring back). The bug this kills: the Mac's
unattended 24h sweep stamped `deletedAt` with nobody looking, and the phone's `init` purge (which
also fires on BGTask/silent-push background launches) counted wall-clock from that synced-in stamp —
so a forgotten note could be purged BEFORE the first post-absence render.

**Built:**
- **Purge clock = new synced `Memo.trashSeenAt`** — first open with the note in the trash; a stamp
  older than `deletedAt` is stale by construction (restore → re-trash restarts unseen). Rulebook =
  `MemoLifecycle.trashClockStart/purgeDue/goneAt/stampTrashSightings`; `MemoSpine` + phone
  `trashDaysRemaining` + WayOut labels all derive from it, so an unseen synced-in deletion honestly
  shows the full window from *now* ("shown dates must be true" holds).
- **Phone:** `purgeExpiredTrash` filters on `purgeDue` (the `SkriftApp.init` purge is now SAFE on
  background wakes — it can only remove notes that had 14 SEEN days); `FadingSweep.run` stamps
  sightings then sweeps, and now also runs on every foreground (`scenePhase .active`, behind the
  once-per-device migration guard so ordering stays load-bearing); `softDelete` stamps its own
  clock; `restore`/Bring-back clear it; deduper clones stamp at trash (no unseen grace for clones).
- **Mac:** `LifecycleSweepScheduler` **day-change + 24h heartbeat RETIRED** → sweeps at launch +
  every app activation only; `MacFadingSweep` stamps sightings and stamps what it sweeps; every Mac
  delete gesture + the delete-sync mirror (`MacCloudDeleteSync`) stamps `trashSeenAt` (user
  present). Desktop's LOCAL `PipelineFile` trash purge unchanged (mirror-only — the cloud copy is
  the phone's to purge). Dev hooks: `-poke-daychange`/`-sweepHeartbeatSeconds` → **`-poke-sweep <sec>`**.
- **Tests (NOT RUN — Linux session, no xcodebuild):** TrashTests +3 (synced-in never purges unseen;
  stale-stamp re-trash; softDelete/restore stamp hygiene), MemoLifecycleTests +2 both suites,
  MemoSpineTests unseen-counts-from-now both suites, WayOutView/Trash label fixtures sighted.
- **Prod note:** `trashSeenAt` is additive → lightweight migration + CloudKit schema deploy rides
  the standing promotion checklist. Pre-v3 trash (stamp nil) gets its clock started at the first
  post-update open — a one-time ≤14-day purge deferral, never an early purge.

**VERIFIED 2026-07-23 (Mac session) + merged to `main` (93c5a8a):**
- Suites green: mobile 868 unit / 0 fail (863 + the 5 new v3 tests), desktop 490 / 0 + full MLX
  build. The 18 mobile UI-bundle failures are the known deferred iOS-26 set — re-ran the 4
  not-yet-catalogued ones on the pre-v3 base commit: identical failures, so v3 added ZERO.
- Mac Dev deployed + eyeballed live: exactly one "lifecycle sweep ran over N memos" at launch and
  one per cmd-tab activation, none while idle (log stream, 3 cycles).
- Phone: build 106 (v3) installed + **launch eyeball DONE on device** (11:55, phone reconnected).
  First open under the new build fired `FadingSweep: purge clock started for 53 synced-in trashed
  note(s)` — the pre-v3 migration case. Re-pulled the store: all 53 trashed tombstones now carry
  a valid `trashSeenAt` (== the open moment, 11:55), and their purge countdown reads the **full 14
  days from today** (a note deleted 2026-07-15 that used to read ~6d, and 2026-07-12's ~3d
  "Deleting soon", both now show 14). Purge gate confirmed running off `trashSeenAt` (0 of the 53
  eligible to purge). NOTE the brief's expected cross-device devlog line was a misread of the final
  code: a Mac DELETE GESTURE syncs in WITH its stamp (by design — the user was at the Mac), so it
  shows the countdown from the Mac deletion, NOT a fresh open-window; the `purge clock started`
  line fires only for PRE-v3/unstamped trash (exactly the 53 above). Optional-only remaining: a
  live visual look at the Recently Deleted screen (label code is unit-green, so cosmetic).
- ⚠️ **Concurrent-session hazard found live:** another worktree session (`gracious-easley`,
  audiobook branch at pre-v3 3d3b71e) ran ITS Dev desktop build against the shared Dev store —
  SwiftData migrated the schema DOWN (dropped `trashSeenAt`), my running v3 app's fetches then
  failed silently ("0 memos") until relaunch (relaunch re-migrates up; 103 rows intact, verified
  via sqlite; erased stamps are doctrine-safe = unseen again). Until every desktop-running session
  is on ≥ 93c5a8a, pre-v3 Dev launches will keep flip-flopping the schema — rebase that branch.

**Built (commits cbf87ff → a3fb3ae → c14daf5, desktop 487 + mobile 863 green, full MLX build green):**
- **Shared:** `clockStart = max(recordedAt, keptAt)`; `markEdited()` bumps `keptAt` (all 19 call
  sites audited = genuine investments; 3 speaker-turn paths that skipped it now call it);
  `MemoSpine` lost Parked → `held(locked/reminder/linked)`, gained `chipText` + `peekSentence`;
  once-per-device migration (`oneClockMigrated.v1`) gives old parked notes a fresh clock — phone
  runs it BEFORE FadingSweep in the same launch task (ordering is load-bearing).
- **Mac:** `UnpipelinedMemoSheet` = m6 (clock chip · sentence · photos at `[[img_NNN]]` via
  manifest→`MemoAsset` blob · circles AS the flag — silent-0.1 button GONE · soft Delete + "14 days
  to undo"); quiet rows right-click **Flag for processing / Lock / Open / Delete**; band excludes
  locked; conveyor renamed **Fading** + fading rows get a trash button; **the Mac can delete a
  synced note for the first time**.
- **Phone:** Fading renames (nav title, Journal shelf, empty state, clock copy); WayOut peek renders
  photos + Delete (soft for fading / confirm-purge for deleted); detail hint = "rate it to keep it".

**Eyeball waves (2026-07-22, live round with Tuur):**
- Wave 1 (b103→104): Mac list confirmed working — migration proven on sight (old "kept — edited"
  memos read "starts fading 21 Aug" = fresh clock; untouched one kept 15 Aug). Phone list rows
  briefly got an always-on clock line (68dbcc2) — overshoot, trimmed by wave 2.
- Wave 2 (b105, 6a096bb) — **ASYMMETRY DOCTRINE LOCKED (Tuur):** the Mac list = the deciding room
  (always-on per-row state: chips, hollow circles, clock lines); the phone list = the NOTEBOOK —
  unrated is the default state there, not an alarm, so rows stay clean. Phone clock line =
  urgency-only (amber, fading ≤7d away or already fading); couch-triage = the new **"Not rated"
  toggle** in Sort & Filter (unrated + unlocked, the Mac band's membership). The two lists are
  deliberately NOT twins — surface role, not drift.

**OWED (next session, rides the 🧬 walkthrough tail):**
1. Deploy Dev both apps + eyeball: peek (chip/sentence/photo/circles/Delete) on the bed-photo memo
   B122966B-era case · quiet-row menu verbs · Fading renames everywhere · phone peek photos+Delete ·
   migration actually bumped the old parked notes (check a "kept — edited"-era memo now reads
   "starts fading <date>").
2. 🧬 walkthrough items phrased in the old vocabulary are OBSOLETE: "kept — edited" chips no longer
   exist — expect "starts fading <date>" / held lines instead.
3. Prod promotion: one-clock rides along with the 🧬+📖 promotion (nothing extra beyond the
   standing checklist).

## ⭐ CONTINUE HERE (session end 2026-07-22 ~15:00 — the 📖 marathon session)

**THE 📖 LANE IS DONE** (roadmap EPubAlign = done 2026-07-22): spikes 1–6 + batch D + FOUR live
device rounds in one session — attach ePub, true-text read-along (device: "way more fucking
aligned"), real-TOC chapters w/ honest partial-merge, multi-text sheet w/ time-true bar, all
on phone b102; Mac Dev current (v0.15.5 + all harnesses). Sections below = the full record.

**NEXT CHAT'S WORK (in order):**
0. ✅ **📖 ROUNDS 5–8 VERIFIED + MERGED 2026-07-23** (the verify session; full record = 📖
   ROUND 8 block below): sim suite 894/0 + Mac 492/0 + MLX build green; R5 device-proven
   live (re-adopt devlog line, real ePub TOC in library.json, 29 chapters); the repro spots
   turned out to be ROUND 8's same-text merge eater — fixed, schema 5, and the healed
   device sidecar machine-verified (7,506 sentences, both repro sentences present as book
   text at conf 1.00, "Book 1: The Boy and the Goddess" chapters). ✅ TUUR EYEBALL SAME
   SESSION: "the parts that were gone before are now there. The chapters look good." ✅
   Attach-UX also live-confirmed (Tuur re-attached the Odyssey text himself, saw "Matching
   the text against the transcript…"). ✅ **MOCK SIGNED OFF same session** (Tuur walked all
   4 phones: liked the flow + time estimate + step ②, A0-vs-A1 explained, "Perfect, yeah.
   I like it." → yes): **`mocks/book-text-unified.html` = the next build board** — ONE
   "Text…" verb/sheet (Level 1 Transcript / Level 2 Book text) replaces the two menu
   entries, + the A0 once-only post-import do-both prompt. Roadmap idea i12. Lane CLOSED.
   → **BUILT same session (b110):** `BookTextSheet` grew the Level-1 inline transcribe card
   (fresh/partial/live-progress+pause/complete; estimate only from measured throughput),
   Level-2 empty card + tan waiting rows; `BookTextPromptSheet` = A0 (once per book,
   UserDefaults seen-set, sheet-swap-race-safe presentation via onDismiss parking);
   ONE "Text…" verb in both menus (TranscribeBookView survives as the read-along nudge's
   sheet); `-showTextSheet`/`-showTextPrompt` render hooks. Suite green (new
   TranscriptCardState/waiting/subtitle/footer/A0 tests); sim A0+A1 vision-checked against
   the mock. **OWED: Tuur's b110 device eyeball** (A3 on the Odyssey, A0 on the next real
   import, the one-verb menus).
   NEW P2 filed same session: silent re-align freezes the library UI.
0b. ✅ **⏱ v3 verify FULLY DONE 2026-07-23** (record in the v3 block above): suites + MLX green,
   merged to `main`, Mac Dev sweep-per-activation eyeballed, AND the phone-open eyeball landed —
   first open under build 106 stamped 53 pre-v3 trashed notes at the open moment, all now showing
   the full 14-day window. Nothing owed. (Optional only: a visual glance at Recently Deleted.)
1. **Pull phone feedback if Tuur recorded any** (/pull-phone-feedback) — 4 live rounds today
   means fresh findings likely.
2. **🧬 walkthrough tail (eyes, guided — b92-era items still unconfirmed):** untouched-note
   detail fade line · WayOut row peek + Bring back · b90 map trio · "0.1 · Passing" on the
   flagged B122966B memo · Mac unified Notes list (quiet rows / Flag verbs / Unrated chip).
   Fading-search WAS confirmed 2026-07-21. Then LifeIA (roadmap now) = done.
3. **Prod promotion decision** (still Dev-only: 🧬 overhaul + everything 📖): deliberate step —
   Release builds both apps while prod idle, CloudKit prod schema deploy (Reminders note in
   NFeat), the Release bundle-ID App-Groups one-time Xcode visit (capture-items lesson).
   Profile the phone list/search paths first (Tuur: Dev "not very well optimized"; Debug build
   caveat noted).
4. **iPad: update its old Skrift Dev build** (it erased additive sync fields once — the
   local-only doctrine now protects those, but old writers + new fields stay a standing risk).
   iPad UDID via `xcrun devicectl list devices` when it's reachable.
5. **Next build lane candidates** (Tuur picks): reading-mode redesign (signed mock 2026-06-19,
   never built; now also the home for ePub images-in-reader + coverage visibility) · Journal
   desktop build board · Connections owed items.
**Standing:** ~~another session owns `mocks/lifecycle-triage-peek.html`~~ → RESOLVED: that
session committed the mock (d27a047) AND built the whole ⏱ one-clock lifecycle same day —
see the ⏱ section at the top of this file. LANE_PLAYBOOK.md = the standing lane contract
(3 batches ran under it today; pinned-contract seams compiled first-try twice).

## 🧬 (previous CONTINUE HERE) lifecycle IA overhaul: BUILT + MACHINE-VERIFIED LIVE (2026-07-21 eve); Tuur walkthroughs = the only gate left

**✅ Owed verifications CLOSED 2026-07-21 pm (machine-verified over USB — phone store pulled +
diffed against the Mac's; new DEBUG dev hooks below):**
1. **MacMemoAuthor live round-trip ✅** — fresh `Mac roundtrip 21 Jul.m4a` ingested headlessly
   (real IngestService) → launch reconcile authored the Memo (sig 0.1 floor, transcript
   `pending`, 300,654-byte audio asset) → arrived on the iPhone byte-identical → Mac
   `-processfile` transcribed it → next sweep logged `reflected-transcripts 1` → phone got the
   474-char transcript (`done`, confidence 1.0). Blob re-extracted from the PHONE store =
   valid m4af (afinfo). **Backfill ✅**: 12 old Mac-only rows (incl. Hotel Du Vin, New
   Recording, an .mp4, a pathless capture → correctly text-only) all authored + on the phone;
   real ratings preserved (0.5/0.6/0.2), unrated floored to exactly 0.1.
2. **Q2 write-back ✅ (data leg)** — `-flagmemo` ran the real sheet verb on unrated
   `memo_B122966B…` (0.0→0.1) → phone store shows 0.1. The "0.1 · Passing" RENDER = Tuur's eyes.
3. **Timer sweep ✅** — `lifecycle sweep ran` on launch, on an in-process NSCalendarDayChanged
   poke, and on a 25s-shrunk heartbeat tick (loop machinery sound; real midnight/24h = OS
   contract, unpokeable without moving the system clock).
4a. **✅ Tuur 2026-07-21 pm: b92 fading-search CONFIRMED on device** ("I can look up the
   notes that are about to fade away by searching for them"). ⚠️ Same round: **phone Dev
   feels SLOW** ("not very well optimized… better than the non-dev version") — NOTE the Dev
   build is Debug (-Onone), so part of this is build config, but don't hide behind that:
   profile the list/search paths on device before prod promotion; ⚡ audit follow-up candidate.
4. **REMAINING — Tuur walkthroughs (eyes only):** phone b92 (amber 'fading' search hits ·
   untouched note's detail "starts fading <date>" line · WayOut row peek + Bring back · b90 map
   trio: card scrolls all in-view notes, pin tap never zooms out, gestures clear selection ·
   NEW: play "Mac roundtrip 21 Jul" + see "0.1 · Passing" on the flagged B122966B memo) + Mac
   (unified Notes list quiet rows / Flag verbs / Unrated chip / peeks). Then LifeIA = done.
**New DEBUG dev hooks (desktop, RunFile family):** `-ingestfile <path>` (real import verb,
headless), `-flagmemo <uuid>` (real Q2 flag verb + export hold), `-poke-sweep <sec>`
(LifecycleSweepScheduler verification; replaced `-poke-daychange`/`-sweepHeartbeatSeconds` when v3
retired the unattended triggers, 2026-07-23). Quit the GUI first, as ever.
**Branch note:** `claude/skrift-roundtrip-verify-wvnpbn` merged to main 2026-07-21 (fast-forward,
contains q3kv2n). The 5 📖 open decisions remain with Tuur — 📖 section bottom.
Everything below = the build record of how we got here.

## 🧬 (build record) lifecycle IA overhaul (locked 2026-07-21; spine BUILT)

**THE SPEC = `mocks/lifecycle-ia-explorations.html`** (Fable-agent exploration, Tuur-approved):
Direction 2 (Two Rooms, One Spine) + Direction 3's exit conveyor. Root diagnosis: significance was
BOTH the process gate (MemoCloudIngest:39) and one of nine touch signals (MemoLifecycle:23) → the
zombie quadrant (touched-unrated: never processed, never fades, RootView:34 dead-end) + two
same-named trashes over different stores. Superseded on arrival: `mocks/unrated-shelf.html` (same
problem, worse room — keep as the artifact that exposed it).

**Tuur's Q-picks (all locked 2026-07-21):**
- Q1 band YES — the Queue grows a collapsed "○ Not in the pipeline · N" band (gate drawn as a boundary).
- Q2 band "Process" writes significance **0.1** — NEW Mac→cloud write direction for that field (same
  lane as Keep/Restore); phone will show Mac-set "0.1 · Passing". Accepted.
- Q3 zombie = **"Parked"**, per-row copy only ("kept — tagged"), NO counting surface.
- Q4 merge Fading + Recently Deleted into ONE "On its way out" conveyor, verb **"Bring back"**;
  sweep moves off Review-refresh onto a DAILY TIMER (shown dates must be true). Phone ⋯ = one item.
- Q5 answered by DISSOLVING the premise: Mac-only files exist only because the Bonjour-era upload
  path predates CloudKit and nobody taught it to author a Memo (verified: zero `Memo(` constructions
  in the desktop app). Direction: **Mac captures author a Memo (+ audio MemoAsset) and sync like any
  note** — both devices are collectors; new build step ⑤ + one-time backfill for existing UUID-id
  local rows. Until ⑤ lands, deleted Mac-local files ride the Review trash as a tiny transitional tail.
- Q6 retire the `processAllSyncedMemos` Settings toggle once the band's "Process all N" exists.
- Q7 copy trio SIGNED: "starts fading <date>" (30d) · "moves to Recently Deleted in Nd" (60d) ·
  "gone for good in ~Nd" (74d) — every surface both apps, verbatim from the spine.

**Build order — ✅ ALL BUILT 2026-07-21 via a 3-lane Sonnet batch (SURF ②③④ / AUTHOR ⑤ /
PHONE parity; briefs = `LANES-2026-07-21/`), Fable conducting. Integrated gate green: desktop
full unit suite + MLX build, phone full unit suite; conveyor snapshot vision-checked.**
- [x] ① the spine — `Shared/Pipeline/MemoSpine.swift` + twin `MemoSpineTests` (11 green each app).
- [x] ② Queue band "○ Not in the pipeline · N" (collapsed, hidden at 0) + per-row/all Process
      (=0.1 + `reconcileSoon()`) + `UnpipelinedMemoSheet` replaces the RootView:34 dead-end flash;
      Q6 toggle UI removed. Testable logic in `Pipeline/WayOutRules.swift` (27 tests).
- [x] ③ ONE trash: queue sheet + footer retired (footer row now jumps to the Review shelf via
      `AppModel.reviewShelf`); `RecentlyDeletedView` (Mac) deleted; MacCloudDeleteSync kept.
- [x] ④ conveyor: `WayOutColumn` = "On its way out" (fading + deleted + Mac-only tail, soonest
      first, ONE verb Bring back = keptAt+undelete); `LifecycleSweepScheduler` daily-timer sweep
      (launch + day-change + 24h) replaces sweep-on-Review-refresh; spine one-liners throughout.
- [x] ⑤ Mac authors Memos: `MacMemoAuthor` (author/backfill/reflectTranscripts, 0.1 floor,
      idempotent, demo-row guard) hooked into the reconcile sweep + instant on upload; 13 tests.
      NOTE: the in-UploadService instant hook was REVERTED by the lane (Pipeline/→App/ breaks the
      host-less test compile) — instant authoring is via reconcileSoon() post-ingest instead.
- [x] Phone parity: ⋯ menu → ONE "On its way out (N)" (`WayOutView` absorbs FadingShelfView +
      phone RecentlyDeletedView; unread-dot semantics untouched; hard-delete kept phone-side).
- **Conductor catches at the gate:** #Predicate can't capture a model property (hoist first);
  `-snapshot-trash` had to move writePNG→hostPNG (ImageRenderer blanks ScrollView rows — the
  header said 5 over an empty body until vision caught it).
- **✅ Tuur's live eyeball round (2026-07-21, same day) — 7 findings, all fixed:** (1) band
  double-homed FADING notes (one-home violation — now New+Parked only, fading-exclusion test
  added); (2) band expanded list unbounded/unscrollable → bounded ScrollView; (3) rows now
  open a read-only PEEK (band → Process, conveyor → Bring back; same UnpipelinedMemoSheet,
  action-parameterized); (4) "✕ Back" text → clear "‹ Back" accent capsule (conveyor + map);
  (5) Review-card importance dots uneven → whole-pixel pitch (5+3); (6) Mac "Queue" renamed
  **"Notes"** to match the phone (SharedCopy.notesTitle, single-sourced both apps); (7) the
  Queue-side "Recently Deleted · in Review" footer row CUT (one home = the conveyor row) +
  dead plumbing removed (wayOutFooterCount, trashedFiles pass-through).
- **✅ Round 3 (2026-07-21): the band is DEAD — one list, like the phone.** Tuur: "flag = it just
  moves into the notes, right?" = correct, and proof the two-container model failed. Unrated memos
  now render as QUIET ROWS interleaved by date in the Notes list itself (dimmed, hollow ○, no
  badge; tap → peek with "Flag for processing"); chips gain **Not rated** (sort control moved up
  to the count line for width); count line reads "N ready · M to process · K not rated"; "Flag
  all K" appears only in Not-rated mode. Conveyor centered like the river. Verbs locked: **Flag
  adds to the pile, Process runs the pile.**
- **LOCKED (Tuur, 2026-07-21): search does NOT include Recently Deleted.** Considered after a
  live "searched a deleted note, no matches" moment and rejected — the trash-excluded idiom
  stands (fading ≠ trash: fading IS searchable per b92). Don't reintroduce.
- **✅ b92 (same eve) — discoverability without a tour:** search finds FADING notes again
  (no-bad-info: "no results" about a recoverable note was the worst answer to "where did my
  note go" — phone hits wear an amber 'fading' capsule, Mac quiet rows self-mark via the
  one-liner; browse mode untouched, conveyor stays the one home) + an untouched note's
  DETAIL narrates its own lifecycle ("starts fading 19 Aug — rating or editing keeps it",
  live-hidden on any touch). PARKED → standalone onboarding phase: first-launch framing +
  a once-ever first-fade explainer card (STANDALONE_PLAN / standalone-onboarding.html).
- **✅ Q-PLACEMENT locked 2026-07-21 (b91): pick B** (mock `wayout-phone-placement.html`,
  Tuur: "B for sure — mac and phone are similar; fading is 3 days old, no habit to protect").
  The phone conveyor's one home = a quiet row at the BOTTOM of the Review feed (Mac-rail
  idiom, non-empty only, amber unread dot moved onto the row — a custom tab-icon dot isn't
  drawable in SwiftUI tabItems); the Notes ⋯ shelf entry + its dot RETIRED. Same session:
  b89 map port (owned camera, dive, in-frame card) + b90 fixes (card scrolls all notes,
  dive never zooms out, gestures clear selection, WayOut rows peek w/ Bring back — Mac parity).
- **✅ Build 88 ON DEVICE 2026-07-21** (iPhone 13, install verified via dylib string-grep):
  merged "On its way out" shelf, flag-to-process microcopy, shared taxonomy glyphs, spine
  one-liners. Device eyeball = Tuur's next phone session. Round 4/5 same-day extras: shared
  SourceTaxonomy (4 hardcoded copies → 1 Shared file + twin tests incl. SF-Symbol-validity),
  count-line tooltip fixed (whole-line hover) + 3-state explainer, quiet-row icons taxonomy-true,
  count line unwrappable. **OWED:** Tuur's live eyeball of the unified Notes list (Mac) + the
  phone b88 walkthrough; prod promotion later as usual.

## ⭐ CONTINUE HERE (2026-07-18 remote session; merged + sim-verified LOCALLY 2026-07-19)

Branch `claude/note-thumbnail-update-bug-tuhrp3` ✅ MERGED to main 2026-07-19 (conflict in this file
resolved: 07-18 sections stacked above the ⚡ perf audit). Thumbnail fix ✅ SIM-VERIFIED: all 8 new
MemoModelTests green, unit suite 742 green (19 UI-suite fails = the known iOS-26 cluster + a
testmanagerd runner crash mass-kill — unrelated areas incl. Safari-ext/vocab; not this change).
1. **Device eyeball owed — build 87 INSTALLED on the phone 2026-07-20** (supersedes 86; includes the
   audit fix waves — one build serves BOTH rounds: this repro + AUDIT_FIX_TESTLIST's top-4 smoke).
   Thumbnail repro: 3-photo memo → delete photos 1–2 in the editor → row thumb becomes photo 3; delete
   all → tile disappears; share-capture + still-transcribing rows keep thumbs. (Audit waves verified
   composed with this fix 2026-07-20: wave 2 rebuilt the row thumb ON `thumbnailPhotoFilename`;
   718/718 unit green re-run independently at audit HEAD, all thumbnail tests in.)
2. Then pick a lane from the two 2026-07-18 sections below: 📤 exportability (attachments = phone-parity
   chunk, brainstorm owed on phone mechanics; lat/lon frontmatter = small buildable chunk), 📍 place notes
   (design session).
3. NEW LANE (2026-07-19 remote session): 📖 ePub↔audiobook alignment — researched + spike-boarded
   (section below). Spikes 1–2 first: Tuur supplies 2–3 real book+ePub pairs; `-asrsweep` ground
   truth on the Mac (punctuation? glued words?). 5 open decisions at the section bottom.

## 📍 Place notes with feeling — "the pin you actually act on" (Tuur direction 2026-07-18; NEEDS DESIGN SESSION before code)

The thesis (verbatim intent): a Maps pin ("to eat") is a dead TODO — it never gets acted on. A voice note
recorded AT the moment ("we walked past a restaurant, Brooks said we should eat there") carries the feeling,
so browsing your notes re-evokes why you cared and you actually engage. Skrift already half-does this;
make it explicit and close the loop.

What EXISTS today (so the design session starts from truth, not memory):
- Recording auto-attaches location + placeName (`MetadataService`); rows carry place chips; place filter + search.
- Share an Apple/Google Maps pin INTO Skrift (D6, `PlaceLink.swift`) → capture item with the same location
  metadata + chip; voice-annotatable. Gap: short `maps.app.goo.gl` links stay plain link cards (opaque
  without a fetch, E4) — and the Google Maps iOS app shares exactly those short links.
- Places map on the phone (`JournalMapView`, Journal tab v1 2026-07-07): pins clustered by place → that
  place's notes. Mac/iPad map-behind-Places is in the signed-off journal-desktop v2 mock (not yet built).
- Reminders are TIME-only (`remindAt` + ReminderScheduler, synced). NOTHING resurfaces a note by PLACE.

Candidate directions for the design session (none decided):
1. **Place-triggered resurfacing** — the literal fix for "and then it doesn't really happen": near the
   restaurant → the note (with your voice from the moment) knocks. iOS geofencing / UNLocationNotificationTrigger;
   fits the existing reminder model as a WHERE alongside remindAt's WHEN. Region limits (~20 monitored) need
   a nearest-N strategy. Privacy: all on-device.
2. **Explicit intent facet** — "I was here" (journal) vs "I want to go back" (to eat / to visit / to try).
   Makes "places I still owe a visit" browsable on the map + filterable; folds into the unified source
   taxonomy work. Could be as small as a tag idiom the UI understands.
3. **Capture friction** — resolve short goo.gl links (needs one fetch — revisits E4); surface the
   share-a-pin flow in onboarding/empty states so the D6 path is discoverable at all.
Related ledger: journal-desktop board (backlog "CONTINUE HERE — desktop-parity"), unified source taxonomy
(CLAUDE.md open cross-app work). Mock-first applies — no code before a signed-off design.

## 📤 Full exportability — markdown as the durable home (Tuur principle 2026-07-18)

The principle (verbatim intent): as features get more complicated, ALL data stays fully exportable — as
much as possible lives in markdown, the app is a smart VIEWER over it. Honest boundary: CloudKit stays the
sync spine (locked 2026-06-15, STANDALONE_PLAN — file-based sync explicitly rejected), so the realistic
form is **the vault is a complete, continuously-published MIRROR**: if Skrift vanished tomorrow, the
markdown + files beside it carry everything human-meaningful. App-internal by nature (document, don't
pretend): word-timing JSON (karaoke), voice embeddings, sync/provenance state; locked notes stay out of
the plaintext vault BY DESIGN.

Already true today: one-way create-only publish into `<vault>/Skrift/` (`ObsidianPublisher`, sticky paths +
hash idempotency + user-edit backoff); body syntax is portable markdown (tasks `- [ ]`, `[[Name]]` links,
photo embeds); Mac polish auto-upgrades the export; speaker turns survive as `**Name:**` text.

Export-completeness GAPS (2026-07-18 code check — the audit's starting list):
1. **Attachments never reach the vault FROM THE PHONE** — phone publish writes ONLY the `.md`. The MAC
   already does this right (`VaultExporter`): `.md` at vault root, audio → audio subfolder, images →
   attachments subfolder (Settings: vault + "Audio subfolder"/"Voice Memos" + "Attachments subfolder"/
   "Attachments"), `[[img_NNN]]` → `![[<title>_NNN.ext]]` embeds. So this is a PHONE-PARITY chunk, and the
   Mac's settings model + embed-naming scheme is the prior art — phone must converge on the SAME filenames
   so both devices publishing one memo don't fork. Tuur 2026-07-18: ✅ wanted; **brainstorm session owed on
   the phone mechanics** (subfolder scheme, audio-by-default or not, security-scoped copy costs, idempotency
   for binaries).
2. **Location coordinates dropped** — frontmatter carries placeName only (`MemoExporter.compilerMetadata`
   AND desktop path); a place note loses its pin outside the app. Direct dependency of the 📍 place-notes
   direction above.
3. **YAML carries ALL metadata — Tuur decision 2026-07-18** ("even steps if we want to" — steps ALREADY
   exports, Compiler.swift:104 😄). In today: title/date/author/source/people/book·bookAuthor·chapter/url/
   location(name)/weather/pressure+trend/dayPeriod/daylight/steps/tags/significance/summary. To ADD:
   lat/lon, duration, createdAt/editedAt, remindAt. Stays internal: sync/provenance state, confidence,
   OCR text (derived; revisit if search-outside-app matters).
4. **Audiobooks — export the USER'S layer, not the book** (answer to "what of the book do we need?"):
   quote captures already export as memos with book frontmatter ✓; **bookmarks don't** (per-book
   `bookmarks.json` — position markers by design, `Bookmark.swift`) — export them into a **per-book index
   note** ("Book — Author.md": book frontmatter, bookmark list ch·timestamp, links to that book's capture
   notes) = the vault face of the roadmap **Commonplace Book** node. NOT exported by default: the audio
   (user's imported property, huge), the whole-book transcript (derived, bulk — on-demand at most),
   positions/detected chapters (ephemeral/app data).
5. No completeness surface — nothing answers "is my vault a full mirror?" (published/skipped/backed-off counts).

First chunk when picked up: field-by-field audit table (→ lands in frontmatter / body / file beside /
app-internal-documented), then phone attachments-parity + lat/lon frontmatter. New frontmatter keys =
contract change → mirror phone `MemoExporter` + Mac `Compiler` in the same pass (no drift).

## 📖 ePub ↔ audiobook alignment — the book text becomes the source of truth (Tuur idea 2026-07-19; RESEARCHED same session, 4-agent fan-out; spike board ready, NOT built)

The idea (verbatim intent): attach the book's ePub alongside the audio; after transcribing, match
transcript ↔ ePub and use the ePub as the source of truth. Read-along/reading mode then shows the
REAL book text (names, punctuation, paragraphs), quote captures export the VERBATIM published
sentence, chapters come from the real TOC; the transcript degrades to a timing layer. Cheap because
the hard half exists: `BookTranscript` sidecars already carry word timings — this is pure
text-to-text alignment, no ML. Prior art ships exactly this pipeline (Storyteller = Whisper + fuzzy
match, sentence-level; we'd be word-level). Amazon/Apple dodge mismatch entirely (matching editions
required / self-generated audio only) — graceful partial alignment would EXCEED the commercial products.

DESIGN (locked by the research):
1. **Aligner**: unique n-gram anchors → LIS monotonicity filter (patience-diff trick) → banded DP in
   the gaps → timestamps onto ePub words, interpolate small holes. Phonetic second signal
   (Metaphone-ish) beside edit distance — ASR mishearings are REAL words ("shore"/"sure",
   Storyteller's lesson). Optional timestamps BOTH directions: transcript-only spans (narrator
   credits) keep ASR text; ePub-only spans (front matter, footnotes) render unhighlighted.
   Per-sentence confidence → per-sentence fallback. Coverage verdicts aligned/partial/rejected; a
   wrong ePub self-detects at attach (near-zero unique anchors). Chapters located INDEPENDENTLY
   (narrators reorder/skip front matter); short generic text (ToC pages) = false-positive bait.
   ePub = ONE continuous text across audio-file cuts (file splits are arbitrary vs book structure)
   even though storage stays per-file.
2. **In-repo ancestor + consolidation**: `Karaoke.wordTimes` (Shared/Pipeline/Karaoke.swift:34)
   already solves the miniature; word-list matching exists in TRIPLICATE (+ `RunFile.anchorDrift`:20,
   inline block RunFile.swift:140) — AlignmentCore is the consolidation point, NOT a 4th copy.
   Adaptations: indexed next-occurrence lookup (kill the linear scan), per-file windowing.
3. **Integration surface is TINY**: `BufferSentence` (QuoteCaptureProcessor.swift:6) is the
   boundary — read-along (ReadAlongView.swift:42) + capture (MergedCaptureView.swift:362) both
   consume `[BufferSentence]` and don't care where `.text` came from. Alignment-backed sentence
   builder at those TWO call sites; seek/bookmark/capture audio-export math untouched
   (`.start/.end/.words` stay from `FileTranscript`). Chapters: ePub TOC just populates
   `detectedChapters` → every consumer follows (`Audiobook.effectiveChapters`:236). DECIDE
   precedence: ePub TOC > transcript-detected > embedded (ChapterDetector doc currently claims
   "THE standard", ChapterDetector.swift:5).
4. **Storage/sync** (mirrors transcripts exactly): `alignment_f<n>.json` beside `transcript_f<n>.json`;
   `FileAlignment{schema, fileIndex, transcriptSignature, epubSignature, alignedUpTo, sentences:
   [AlignedSentence{text, start, end, wordStart, wordEnd, confidence, epubAnchor}]}`. Sync =
   `AudiobookAudioTransport` verbatim: `ab_<bookID>_a<n>` records + additive
   `AudiobookSyncRecord.alignmentSignature`; send/receive/RESTAMP mirroring
   AudiobookCloudSync.swift:356-409. Triggers: BookTranscriptionJob.swift:250 (beside
   `detectChaptersIfNeeded`) + the `AudiobookSession.open` retro-hook (:120) + on ePub attach.
   ePub file: new additive `Audiobook` field; attach UX reuses the `PendingAudiobookImport`
   confirm-sheet pattern.
5. **ePub parsing (HARD PREREQUISITE — zero zip capability exists in the project today)**:
   ZIPFoundation (MIT, zero transitive deps — SPM dep #2 after FluidAudio) + strict `XMLParser`
   for container/OPF/NCX/nav; LENIENT fallback for spine XHTML bodies (real files: `&nbsp;`-style
   entities + malformed markup hard-fail XMLParser) — libxml2's own HTMLparser is on-device
   (bridging header, no new dep) or SwiftSoup. Readium REJECTED (iOS-only, 8-package graph,
   rendering-shaped); EPUBKit doesn't solve the hard part. Footnote exclusion: `epub:type="noteref"`
   + class/id heuristics (semantic markup inconsistently used in the wild). Also accept .txt/plain
   HTML as book text (Gutenberg; dodges DRM). DRM: `encryption.xml` alone ≠ DRM (allowlist the two
   font-obfuscation algorithm URIs); ADEPT = `rights.xml` present; unknown algorithm → treat as
   protected, honest message, never bypass. FairPlay ePubs don't exist as loose files — no detector.
6. **ASR reality check (the load-bearing surprises)**:
   - PUNCTUATION CONTRADICTION: FluidAudio's own Benchmarks.md says Parakeet TDT v3 = "no
     punctuation"; NVIDIA's card + OUR device history say otherwise (lost-period truncation bug
     ChunkFusion.swift:66, the "Dr."-split report backlog:3768 — both only make sense if periods
     are normally present). Settle empirically via `-asrsweep` BEFORE designing sentence segmentation.
   - WORD-GLUING upstream bug (FluidAudio #683), confirmed on our pinned v0.15.2: long-form chunk
     merge splices ignoring SentencePiece `▁` word starts → "wordonewordtwo" possible at every ~15s
     INTERNAL seam. FIXED upstream v0.15.3 + v0.15.5 — our 2026-07-11 pin (7f963cdc) predates both.
     Aligner must tolerate glued tokens regardless; consider a pin-bump chunk (device-verify,
     TrEngine precedent).
   - NUMBERS are confidence-dependent, not guaranteed digits: "ITN usually emits digits"
     (ChapterDetector.swift:590) BUT the spelled-out EN+NL parser exists because both occur; the
     Dutch `-asrsweep` A/B showed the SAME years as correct digits when decoding well, Dutch
     number-words when drifting. Canonicalizer = port/reuse `ChapterDetector.parseNumber`
     (EN+NL cardinals/ordinals + glued Dutch compounds).
   - FluidAudio ships an UNWIRED `TextNormalizer`/ITN (deferred, backlog:2244) — decide: wire it
     pre-aligner vs normalize inside the aligner.
   - Timings run slightly LATE (the ReadAlongView 0.1–0.2s `lead`, :8) — display tuning only,
     alignment math unaffected.
   Normalization ruleset: case-fold; strip punctuation to MATCH KEYS (display keeps original);
   number canonicalization EN+NL; tolerate glued/duplicated/mis-substituted seam words. NOT needed:
   filler stripping, contraction expansion, hyphen-specific rules.

SPIKE BOARD (in order; 1–5 are the research, 6 is the feature):
1. 🟡 Pair #1 DELIVERED (Tuur, 2026-07-21): Steal Like an Artist ePub (in ~/Downloads,
   libgen filename with a LEADING SPACE; keep OUT of git — copyrighted). DRM-free (bare
   container.xml), EPUB2 (OPF+NCX), 10 real chapter titles in the NCX, 9,767 words + 108
   images. 1–2 more pairs still wanted — ideally one matching-edition pair and one messy one.
   **⭐ PYTHON PROBE (2026-07-21, scratchpad — pre-spike-5 de-risk, vs the REAL phone
   sidecars):** the audiobook is the TRILOGY (4 files, ~39,400 words); the ePub is book 1 only —
   and per-file verdicts resolve it perfectly: f0 matched 6,515 unique 4-gram anchors, 96%
   monotonic, spanning words 121–9102 of 9106 (≈98% coverage; ~1 anchor per 1.4 words); f1–f3
   matched ~40 non-monotonic anchors each = noise floor. RIGHT-vs-WRONG book separation ≈
   150:1 — the attach-time self-detect is empirical fact, thresholding is trivial. Only TWO
   >30-word unmatched spans in the whole hour: the 121-word narrator/publisher intro (the
   predicted transcript-only span) + one 35-word epigraph quirk at 3.6min. Kleon's
   hand-lettered image pages = NON-issue here (narrator doesn't read them / text also in
   body). Image alt texts are all FILENAMES → alt is never book text. Spike 5 (Swift
   AlignmentCore + -aligncheck + thresholds) proceeds on a de-risked bet.
2. ✅ ASR ground truth (2026-07-21, real device sidecars + Mac `-asrsweep` on a real audiobook
   chunk — findings):
   - **PUNCTUATION: PRESENT, both apps.** Phone sidecars (Steal Like an Artist ×4, on the
     7f963cdc pin): ~650 periods/hour + commas + question marks + capitalization. Mac
     `-asrsweep` on Man's-Search preface mp3: same. Benchmarks.md's "no punctuation" claim is
     REFUTED for our path — sentence segmentation MAY use ASR punctuation as a signal.
   - **#683 gluing on our pin: REAL but RARE.** 4.5 h of current-pin transcripts → ONE true
     seam artifact: `works.eep` ("works. Keep" with the K eaten). Old-pin June transcript adds
     `Co.oper` ("Cooper" split by an inserted period). So the damage class = glue + eaten
     leading letter + seam-local punctuation corruption, ~1 per 4.5 h — the aligner's
     tolerate-glued-tokens requirement stands, and per-sentence confidence absorbs the rest.
     Pin-bump (spike 3) is thus justified-but-not-urgent, data in hand.
   - Sweep variants: mel-off (B/C) diverges 14% of words from the old default; dual-decode
     alone (D) = 0% — knob effects confirmed on audiobook audio. (Sweep's one-shot API covered
     the opening ~2 min of the chunk; enough for the punctuation verdict.)
3. ✅ Pin BUMPED v0.15.2 → v0.15.5 (2026-07-21, Tuur-approved "fix the bug"): both project.ymls
   → 19600a48 (the v0.15.5 tag). Gate: desktop full build + suite green, mobile 743 unit tests
   green (the 2 UI fails = the known iOS-26 cluster), `-asrsweep` C-variant output
   WORD-IDENTICAL old-vs-new on the preface chunk (seam fixes only touch long-form merges),
   phone b93 built + installed (device lists 93), Mac Dev redeployed on v0.15.5. OWED: next
   real whole-book transcribe should show works.eep-class artifacts gone (falsifiable on the
   next book Tuur transcribes; don't re-transcribe 4.5h just for this).
4. ✅ **EPubParse SHIPPED 2026-07-21 eve** (LANE_EPUB, first LANE_PLAYBOOK batch =
   `LANES-2026-07-21B/`): `Shared/Pipeline/EPubParse.swift` — PURE Foundation (unzip stays
   app-side; ZIPFoundation 0.9.20 revision-pinned, desktop target only for now), spine-ordered
   blocks, NCX+EPUB3-nav TOC, lenient entity/malformed-markup fallback, DRM verdict w/
   font-obfuscation allowlist, footnote/img exclusion. 12 twin tests green both apps.
   REAL-BOOK smoke (Steal ePub): DRM none, 314 blocks / 9,670 words, all 18 TOC titles clean.
5. ✅ **AlignmentCore + `-aligncheck` SHIPPED same eve** (LANE_ALIGN + conductor harness):
   `Shared/Pipeline/AlignmentCore.swift` — unique-n-gram anchors → LIS → banded per-gap DP
   (match/sub/ins/del + glue ops incl. eaten-letter), EN+NL number keys, interpolation,
   Config-tunable thresholds, 10-largest-spans reporting. 12 twin tests green both apps
   (1 gate catch: an LIS test must MOVE a block, not COPY it — duplicated shingles lose
   uniqueness before LIS ever runs). **REAL-PAIR VERDICT (the board's GO/NO-GO): GO.**
   `-aligncheck` on the Steal ePub × all 4 trilogy sidecars: f0 ALIGNED (coverageBook 86.9%,
   7,639 anchors, 95.5% monotonic, 123 ms for 9k×9.7k words); f1/f2/f3 REJECTED (2–7%
   coverage, ~25% monotonic). DEFAULT THRESHOLDS HELD — note: wrong-book coverage can reach
   ~7% (trilogy-sibling phrase bleed), the MONOTONIC gate is the real discriminator. The
   narrated-but-image-only pages (logbook / What Now? lists) surface exactly as honest
   unmatched transcript spans.
6. ✅ **PRODUCTIZED 2026-07-21 night (batch C = `LANES-2026-07-21C/`, 2 Sonnet lanes +
   conductor pre-ship; THE SEAM COMPILED FIRST TRY — 805/0 mobile unit tests):**
   - Pre-ship: `Audiobook.epubFilename`/`epubChapters` + `effectiveChapters` precedence
     (ePub TOC > detected > embedded, Q1), ChapterDetector doc amended, ZIPFoundation into
     the iOS app target.
   - CORE: `BookAlignment.swift` — `FileAlignment`/`AlignedSentence` (published text +
     per-word times + transcript word-range + confidence + chapter marks) + store +
     `BookAlignmentRunner` (attach / alignIfNeeded, security-scoped, .txt freebie) +
     triggers (transcribe-finish + book-open retro) + CK sync `ab_<id>_al<n>` mirroring
     transcripts (receiver holds application until its transcript matches, then derives
     epubChapters). Lane call worth keeping: adjacent same-file EPubBlocks MERGED before
     aligning (AlignmentCore resets word indices per block — unmerged would corrupt
     sentence ranges; `-aligncheck`'s 1:1 bridge is fine for its coverage-only use).
   - UI: `AlignedSentenceSource` (nil unless fresh + verdict aligned; sentence < 0.5
     confidence splices its ASR words via the existing builder) + ReadAlongView/
     MergedCaptureView swaps (trim/audio-export math untouched) + library context-menu
     "Attach book text…" (fileImporter .epub/.txt, verdict toast, wrong-book alert
     Keep-anyway/Remove, "Replace book text…" when attached).
   **✅ DEVICE ROUND 1 (Tuur, 2026-07-22 am) → fix wave SHIPPED same hour (b95 INSTALLED):**
   three findings, all fixed + verified: (1) **highlight trailed the narrator** — the
   sentence assembly linearly re-distributed each matched range's time span across its
   words, drifting seconds over natural pauses (measured on the phone's own f0 sidecar:
   85.4% of words >0.3s off, sentence-END lag median +1s / p90 +5.6s). AlignmentCore now
   surfaces the DP's per-word times verbatim (`MatchedRange.wordTimes` + `direct` flag),
   assembly consumes them, confidence = direct fraction; re-measured offline on the same
   real pair: **median drift 0.0000s, 2.07% >0.3s**. `FileAlignment` schema 1→2 →
   attached books silently re-align on next open. (2) **phantom chapters** — REJECTED
   trilogy-sibling files claimed the 6 front-matter TOC entries f0 couldn't
   (`assignChapterMarks`/`epubChapters` had no verdict gate; f1 carried 6 junk-timed
   marks). Both derivation points now aligned-only + a cheap self-heal re-derives
   `epubChapters` on book open. (3) **"no indication anything changed"** — the outcome
   was a 1.6s toast fired after seconds of silent processing; now a persistent
   "Checking the text…" busy toast + explicit user-dismissed ALERTS, incl. honest
   multi-book copy ("matches N of M — likely one book of a multi-book audiobook").
   Mobile 808/0 + desktop suite green. Sync note (accepted, iPad-scale): a receiver
   holding v1 sidecars whose source signature didn't change won't re-pull until the
   next signature change — irrelevant while the phone is the only aligner.
   **✅ b95 DEVICE-CONFIRMED (Tuur, same hour): "way more fucking aligned… chapters are
   better" — sync fix + phantom-chapter fix both pass ears/eyes.** Follow-up caught by his
   trilogy question: "ePub TOC wins" was WHOLE-BOOK, silently deleting books 2–3's
   transcript-detected chapters (no-bad-info violation) → partial-match MERGE shipped
   (ePub chapters inside aligned files' spans + detected chapters/separators outside;
   boundary entries belong to the next file). 809/0. **b96 BUILT + signed — phone went
   offline again mid-install; one `devicectl install` when it's back**, then the chapters
   sheet shows book 1's real TOC AND books 2–3's detected chapters with their Book-N
   separators. REMAINING (eyes, b96):** AirDrop the Steal ePub to the phone (Files) →
   Books → long-press Steal Like an Artist → Attach book text… → expect "Aligned 1 of 4
   files" (the trilogy: file 1 = book 1, rest honestly rejected) → read-along shows
   Kleon's REAL sentences in file 1 (ASR elsewhere) → capture a quote there = verbatim
   published text → Chapters sheet shows the ePub's real 18-entry TOC.

**📖 ROUND 8 (2026-07-23, the VERIFY session's real-data catch — the actual root cause of
round 6's sighting): `mergeSentences` ate same-text sentences.** Verifying rounds 5–7 on
device surfaced it: the schema-4 re-align healed chapters (R5 ✅ live: devlog "re-adopted
orphaned attached texts" + "toc [40] → 29 marks → 29 epub chapters"; library.json now
persists all three attach fields; real TOC titles) — but BOTH repro spots stayed empty and
`bridged=0`. Offline reproduction (new env-gated `OdysseyRealDataDiagnostics` harness: the
pulled phone ePub + transcript through parse → align → assemble → merge) showed the aligner
had matched both sentences at conf 1.00 ALL ALONG — the align result is bit-deterministic
(coverage identical to 16 digits, device vs sim) and produces 7,506 sentences; the device
sidecar held a strict 7,310-subset. The eater: `mergeSentences` contested collisions WITHIN
one text's own fresh batch — adjacent sentences legitimately overlap by seam fuzz (exact
per-word times straddle sentence boundaries: "(andra)." ends 165.8, "He is not 'the' man…"
starts 165.6), same text = same rank, and the strict-win tie rule silently dropped the later
one — 196 of 7,506 (~2.6%), including both user-reported holes. Rounds 6+7's fills were
built to paper over what was actually this merge bug downstream (the bridge/gap-fill layers
stay — they cover TRUE aligner misses). Fix: collisions contest BETWEEN texts only
(`result[$0].textFile != ns.textFile`); schema 4→5 so every persisted subset sidecar
re-aligns once on next open. Suite: 894/0 incl. the real-data harness asserting
merged=7506 of 7506 + the Trojan-War sentence surviving the merge, and two new
`MultiTextMergeTests` regressions (seam-overlap survives / between-text contest intact).
Device: b109 installed, re-heal launch owed (phone re-locked). DURABLE LESSONS: (1) verify
derived DATA end-to-end on real inputs, not just the layer you changed — assemble alone
looked perfect, the sidecar was wrong; (2) a "collision rule" needs an explicit answer for
SELF-collisions. Also for the record: -resumeBook DEBUG launch hook added (headless device
verify via devicectl); untriaged b105-era crash 09:49 pulled (SIGKILL during a CoreData
fetch — watchdog-flavored, pre-branch; feeds the pre-promotion profiling item).
**NEW P2 from the live re-heal (Tuur, 2026-07-23 ~14:15, b109 on device): the silent
book-open re-align FREEZES the library UI** — tap a book, then no book responds ("frozen…
maybe stuff's happening in the background — annoying"). The schema-heal path has NO visible
surface (R7's live stages exist only on the attach sheet) and the align's CPU starves the
UI on the iPhone 13 (cpu_resource .ips reports confirm). Fix pair: (a) reuse the attach
stage line as a small in-player/library pill for any running re-align ("Matching up your
book text…"), (b) drop the align below .utility / add yields so the main thread breathes.
Also: an app-killed-mid-align restart currently restarts the whole file from scratch —
fine at 1 file, worth per-file resume if multi-file books grow. And the align dies with
the app on lock when nothing is playing — the "keep listening" advice is real; consider
a BGProcessingTask ride-along for the heal case (parked, standalone-phase candidate).

**📖 ROUND 7 (Tuur 2026-07-23, going over rounds 5+6): four items, all handled (same
branch `claude/epub-chapter-discrepancy-wlgvhd`).**
(1) **"If it had actually put in the whole ePub that was working"** — right: round 6's ASR
gap fill is the fallback, not the fix, when narration == book text. NEW (schema 4): a hole
run SANDWICHED between two timed sentences re-emits the BOOK sentences with times
interpolated across the gap (`AlignedSentence.bridged`), gated on corroboration — the
window's spoken-word count must be 0.5–2.0× the book words (a silent window = narrator
truly skipped it → still dropped, ASR fill owns leftovers). Confidence stays 0 (honest);
the flag drives book-text rendering; collision rule unaffected (bridge loses to any real
match). Schema 3→4 forces every attached book to re-align on next open, so the Trojan-War
sentence should come back as REAL book text, not ASR. Layering now: exact book text >
bridged book text > ASR splice > ASR gap fill.
(2) **13 h attach: no progress, "can I keep listening?"** — the busy line now follows the
runner's live stages ("Copying the file in…" / "Reading the text…" / "Matching the text…
(file k of n)" / "Placing chapters…") + a standing sub-line "You can keep listening while
this runs." (true — playback never contends). Real % inside ONE file's matching would need
an AlignmentCore progress callback (single DP pass) — parked as a candidate.
(3) **ePub while still transcribing** — now DELIBERATE: attach mid-transcribe copies +
records the text but defers alignment (alert: "still transcribing — it will match up on
its own the moment transcription finishes"); `alignIfNeeded` no-ops while the job runs
(the job's own finish call does the real pass) — no more bogus verdicts off a partial
transcript, no churn from player opens.
(4) **Unify transcribe + book-text menus** ("both are about adding text — two levels") —
DESIGN, so mock-first: `mocks/book-text-unified.html` proposes ONE "Text…" verb/sheet:
Level 1 Transcript (status/progress/Transcribe), Level 2 Book text (today's signed-off
sheet unchanged), incl. the mid-transcribe deferred state. Follow-up (Tuur 2026-07-23,
from the phone): + an **A0 import-moment state** — a once-only post-import prompt offering
BOTH actions together ("start both and walk away; the ePub matches up on its own when
transcription finishes") — the import→transcribe→auto-match chain already works in code
(rounds 5–7); A0 makes it visible. **✅ SIGNED OFF 2026-07-23 (verify session, all 4
phones walked) — build board = the ⭐ item-0 note above; roadmap idea i12. Not built.**

**📖 ROUND 6 (Tuur 2026-07-22 ~23:11–23:16, Odyssey): read-along DROPS spoken text —
FIXED (same branch `claude/epub-chapter-discrepancy-wlgvhd`).** Two sightings, one bug:
(a) red-line at ~3:00 — narration between "(andra)." and "The poem tells us…" never
displayed; (b) Apple-Books-vs-Skrift at ~5:35 — "It is not the start of the Trojan War,
which began with the Judgment of Paris…" is in the ePub AND the audio, absent in Skrift.
Cause: the aligned view REPLACED the transcript wholesale — `assembleSentences` drops
zero-timed sentences (aligner holes), and `AlignedSentenceSource` had per-sentence ASR
fallback only for LOW-CONFIDENCE sentences, never for spans with no sentence at all →
silent jumps while the audio plays (Tuur's exact insight: "the transcript is better in
some ways… it has replaced the transcript"). Fix: the display is now a UNION —
`uncoveredWordRanges` finds transcript-word runs no aligned sentence's splice range
covers; runs ≥ 3 words render as ASR sentences via the same builder (1–2-word runs =
boundary fuzz, stay silent). Also fills leading/trailing narration (Audible credits, end
matter) and a partially-matched sentence's untimed tail; capture (`MergedCaptureView`)
inherits it via the shared source. Tests: hole-between-sentences, fuzz threshold,
leading/trailing, no-duplication-with-low-confidence-splices, union/clamp math. Eyes owed
(Tuur, tomorrow): Odyssey ~3:00 and ~5:35 — the missing lines should read along in ASR
text. NOTE the shown ASR fills are the transcript's words (no book punctuation/casing) —
if a fill looks garbled there, that's the aligner MISSING a matchable sentence: next lever
is aligner recall, not display.

**📖 ROUND 5 (Tuur 2026-07-22 ~23:00, Odyssey screenshots): chapters ≠ ePub TOC after
relaunch — ROOT CAUSE FOUND + FIXED (branch `claude/epub-chapter-discrepancy-wlgvhd`).**
Symptom: Odyssey ePub attached + read-along shows the REAL book text (intro), but the
chapters sheet still shows the detected list ("Opening / Part 6 / Part 11 / Part 19 /
Part 20 / Part 24", Ch 1/6 — the detector's structural vote caught only 5 of the 24 spoken
"Book N" announcements; "book" keyword maps to the Part kind, hence "Part N" labels). Root
cause: **`Audiobook`'s hand-written Codable never carried
`epubFilename`/`epubFilenames`/`epubChapters`** — every library.json persist dropped them, so
ANY relaunch forgot the attachment while the sidecars (and read-along) kept working. This is
the SECOND cause of round 2's "fields VANISHED" (the iPad-LWW theory was real but partial —
"re-attach once and it sticks" could never stick; a lone device reproduces it). Fix (5
chunks): (1) the three keys now encode/decode (sync blob still stripped via
`sanitizedForSync` — regression-tested); (2) `alignIfNeeded` RE-ADOPTS orphaned attached
texts from the book folder (disk = durable truth: attach copies in, removeText deletes), so
every already-bitten book self-heals on open — no manual re-attach; (3) title accessors keyed
off `usesDetected` alone → now `titlesAreDisplayReady` (ePub OR detected): with ePub chapters
+ nil detection the sheet rendered EMBEDDED titles against ePub rows (mismatch + index-crash
when the ePub list is longer); (4) `mergeAndFinish` DevLogs toc-counts → marks → derived
chapters (round 5 was undiagnosable from the devlog); (5) TOC parse got the lenient retry the
spine bodies always had — a nav/NCX doc with `&nbsp;`-class entities hard-failed strict XML
and silently yielded an EMPTY TOC (zero marks, broken "real table of contents" promise) — the
OTHER way this same symptom arises with no relaunch at all (both EPubParseTests copies
extended). Tests added (Codable round-trip, store reload, sanitize-strip, ePub-title
accessors, orphan scan, entity-laden nav/NCX). ⚠️ Fixed from a Linux session —
**xcodebuild suite NOT run; next chat verifies** + device-checks the Odyssey book heals.

**📖 ROUND 4 (b101+b102): sheet DEVICE-CONFIRMED end-to-end.** b100 bar verified (one block +
sliver, 22%); "partial"→"full match" tolerance 0.97→0.95 (real f1 = 96.7%, credits absorb);
the 44s calendar-art gap (narrator reads Kleon's hand-lettered calendar page — image-only in
the ePub: "…Don't break the chain." → gap → "Just as you need a chart of past…") was rendering
~5× too wide — the mock-copied 2pt inter-segment spacing is GONE, bar = grey background +
colored overlays at exact fractions, strictly time-true (Tuur: "I do like the truth in this
player"). Interleaved-trilogy theory REFUTED with data (95.5% monotonic = sequential).
Reaffirmed parked: ePub images in the reader (the calendar gap = the demo case).

**📖 ROUND 3 (same session, b100 INSTALLED):** re-attach WORKED on b99 (alert + sheet live on
device) but the bar sprinkled confetti + "37% / 1 h 41" — `textSummary` counted the text's
sentences from files whose per-text verdict was REJECTED; now aligned-files-only (regression
test in). Also dc:title read `.text` on the element but element text lives in `#text` child
nodes → `flattenText`; NOTE the Steal libgen ePub's own metadata has title/creator SWAPPED
("Austin Kleon" as dc:title) — garbage in, honestly displayed, filename fallback covers absent
titles. EXPECTED LOOK on b100: reopen the sheet → ONE contiguous span over the first ~hour,
"~21%", row "~58 min · full match" (row title stays the filename-ish string — the file's own
bad metadata).

**📖 DEVICE ROUND 2 (Tuur live, 2026-07-22 ~14:00) → b98+b99 same hour:** (1) "Book text…"
was library-long-press only; the player ⋯ (where you actually are) now has it — flow extracted
to ONE shared `BookTextFlow` modifier (shared-code-first, both surfaces). (2) **Add button
dead + "No book text attached" LIE** — root causes: a fileImporter attached to the covered
presenting view silently refuses to present on iOS 26 (picker + the 3 outcome alerts now hang
off the SHEET's own content), and the record's attach fields had been ERASED by whole-blob
LWW sync (a device on an older build — iPad suspected — re-encodes the record without
additive fields; on-device sidecar still schema-1 + `epubFilename: None` proved it).
**Doctrine fix: epubFilename/epubFilenames/epubChapters/detectedChapters are LOCAL-ONLY** —
`sanitizedForSync` strips them from every sent blob, `keepingLocalTextFields` preserves them
at all four adopt sites (reconcile receive, session open, adoptSyncedPosition, first-add
strips legacy blobs). Tuur must RE-ATTACH the Steal ePub once on b99 (the erased record can't
self-heal); after that it sticks. ⚠️ If the iPad has an old Skrift Dev, UPDATE it eventually —
it can no longer erase these fields, but other additive fields ride the same risk.

**📖 ✅ MULTI-TEXT + "Book text" SHEET SHIPPED 2026-07-22 pm (batch D = `LANES-2026-07-22D/`;
mock B signed "yess. ur reccomendation"; the pinned-contract seam compiled FIRST TRY again —
858/0):** schema-3 sidecars (per-text sources w/ verdict+coverage, sentences tagged by text,
collision = higher confidence wins/tie = attach order), additive attach (append, re-attach
same file replaces itself), per-text TOC marks unioned, `textSummary` (real global spans,
30s gap-bridge) + `removeText` (surgical detach), 4-field cloud signature. UI: long-press →
"Book text…" opens the timeline-first sheet (bar = real aligned spans colored per text, grey
= transcript; rows w/ dc:title + Remove/Re-check; ＋ Add; busy toast threads into the sheet).
Gate catches: reject-alert Remove now detaches exactly the failed text (lane-flagged), doc
drift fixed. Conductor pre-ship: EPubBook.title (dc:title) + Audiobook.epubFilenames+accessor.
**b97 INSTALLED (device lists 97; includes the b96 chapter merge Tuur never got).
EYES OWED (b97):** open Steal → the schema-3 gate re-aligns silently → long-press → Book
text… → the bar shows book 1's span colored + 3-hour grey tail; chapters sheet = real TOC
then detected Book-2/3 chapters; then someday attach Show Your Work! and watch the bar fill.
CORE2 tabled (fine to leave): 30s gap-bridge untuned; epubChapters' detected-merge span
suppression stays whole-file (revisit only if a partially-covered file miscounts chapters).
(design record, superseded:) mock = `mocks/book-text-sheet.html` — Tuur keeps listening to the
trilogy and will want book 2's/3's ePubs → one-text-per-book graduates to a LIST. Semantics
settled in the chat: alignment is already per-file/per-span, so each new text aligns the spans
it matches and leaves the rest; if two texts claim the same span, the higher-confidence match
wins; NOTHING is ever deleted (un-narrated intros simply get no time; narrated-but-unmatched
spans keep ASR — same as today). Coverage visibility gets a HOME instead of a fleeting alert:
variant A = list-first sheet (rows per text + dimmed "not attached" remainder), B =
timeline-first (one bar = whole audiobook, colored per source, grey = transcript), C = a
"Book text · 2 texts · covers 45% ›" row inside a per-book options screen (placement, opens
A/B as detail). Persist per-file coverage % in the sidecar at the next schema touch (free,
feeds the sheet). Build after the mock pick — likely one lane batch (schema 3: sources array
per sidecar + sheet UI).

Open decisions — **ALL 5 LOCKED (Tuur, 2026-07-21 pm)**:
1. ✅ **Chapter precedence: ePub TOC wins when attached** ("if an EPUB is attached, we're
   gonna use its chapters"); transcript-detected > embedded remains the fallback order;
   ChapterDetector.swift:5's "THE standard" doc gets amended in spike 6.
2. ✅ **Aligner-internal normalization** (raw transcript stays untouched; the matcher treats
   "2026"≡"twenty twenty-six"). FluidAudio's TextNormalizer stays unwired.
3. ✅ **Pin bump: DONE** ("fix the bug, we will do it again" = re-verify round accepted) —
   executed same day, see spike 3 above.
4. ✅ **ZIPFoundation approved as SPM dep #2.**
5. ✅ **Formats: .epub primary** (Tuur: books come as epub, maybe mobi). .mobi = dead format,
   skip in v1 (Calibre converts in one step); keep .txt as a freebie (trivial, Gutenberg).
   Images inside ePubs: invisible to ALIGNMENT; **showing pictures in the reader = PARKED
   for later (Tuur: "we may consider putting pictures in the reader, but we'll push that
   for later")** — a display question for after spike 6, never an alignment risk (probe
   confirmed; alt-texts are filenames, never book text).

## 🐛 List thumbnail stale after deleting photos (reported 2026-07-18, ✅ FIXED same day — branch `claude/note-thumbnail-update-bug-tuhrp3`)

Repro: record with several photos → row thumb = first photo; delete the first photo(s) in the editor →
thumb stays the DELETED photo. Cause: deleting a photo removes its `[[img_NNN]]` marker from the body but
never its manifest entry (markers are 1-based indexes into the manifest — pruning would renumber every later
marker on both apps), and the row blindly showed `imageManifest.first`. Fix: new `Memo.thumbnailPhotoFilename`
(MemoDisplay.swift) = first marker in BODY order that resolves; all markers deleted → no thumb; marker-less
bodies keep manifest-first (share captures render off-manifest, pending/failed transcriptions have no body
yet). Row tile + `hasPhoto` + the "Has photos" filter all ride it (MemosListView). 8 unit tests added
(MemoModelTests). ✅ SIM-VERIFIED 2026-07-19 (all 8 green, unit suite 742 green). **OWED: device eyeball
(build 86)** — delete photos 1–2 of 3, row should show photo 3; delete all → no tile.

## ⚡ Perf + reliability audit — 2026-07-16, VERIFIED 2026-07-19 (5 Sonnet lanes → 5 Opus falsifiers → Fable adjudication; UNBUILT unless ticked)

Wide-net audit of both apps by area; every item confirmed at the cited line. Verification tally: 33/41 confirmed as filed (several understated), 6 downgraded, 1 dropped, 2 corrected, 1 widened — all folded in below. Line numbers drift with ongoing work; items are mechanism-anchored. NEW unaudited surface since the sweep: Connections/retrieval stack (`Shared/Retrieval/` 6 files + `ConnectionsIndexService`) — auditor dispatched 2026-07-19 — findings in the subsection at the end. **FIX WAVE MERGED TO MAIN 2026-07-19** (built on branch `audit-fixes`; Tuur-approved merge; phone/Mac smoke of the testlist top-4 owed). Ticked = fixed on that branch; review artifact = `AUDIT_FIX_TESTLIST.md` on the branch.

**Cross-cutting theme — failures are invisible (`try?` everywhere on the write surface):**
- [x] **P0 `NotesRepository.save()` = `try? context.save()`** (`SkriftMobile/Services/NotesRepository.swift:244`) — the ONE save path for every mobile write incl. the editor's debounced text commit; a throw = user edit silently lost. Log + surface on the editor path. S
- [x] **P1 `MemoSaver.persist()` swallows the temp→dest audio move** (`Features/Recording/MemoSaver.swift:741-742`) — on failure it still inserts a Memo pointing at a file that was never written (phantom memo, orphaned audio). `saveQuoteCapture` ~:511 already does it right (do/catch + abort). S
- [x] **P1 Mac reconciler `try?`-swallows ingest + all saves** (`SkriftDesktop/Pipeline/Ingest/MemoCloudReconciler.swift:70-73`, `+Wiring.swift:77,99`, desktop `NamesCloudSync.swift:46`, `VocabularyCloudSync.swift:58`) — a memo that always fails ingest = silent black hole retried forever, zero trace. Count+log failures. S
- [x] **P2 `VaultExporter` `try?`-swallows image copies (`:152,176,202`) and the phone-edit re-export swallows entirely** (`+Wiring.swift:94`) — vault silently stale/incomplete, `![[embed]]` refs written with no file behind them. Verify bonus: the `:84-85` comment claiming "an export failure is logged by the caller path" is FALSE — nothing logs it; fix the comment with the code. S
- [x] **P2 audiobook raw-CK transport has no CKError-code handling** (`Services/Audiobooks/CloudKitAudiobookTransport.swift`, `AudiobookCloudSync.swift:236-252`) — permanent failures (quota, auth) retry forever, no retryAfterSeconds honored, no terminal UI state. M
- [x] **P3 `runTranscription` catch has no DevLog** (`MemoSaver.swift:817-822`) — `.failed` memos undiagnosable from a device pull. S

**Recording (lane verdict: unusually hardened — session-recovery ladder, ANE time-share, @Observable isolation all excellent):**
- [x] **P1 `save()`'s transcription lacks `BackgroundTask.run` wrap** (`MemoSaver.swift:39-55`) — every import path has it (`:101,141,297`); ordinary record→stop→background-the-app = stuck "Transcribing…" until next launch. S
- [ ] P2 per-buffer `Task { feedStream(out) }` has no ordering guarantee into the caption accumulator (`LiveRecordingService.swift:479-499`) — display-only garble risk; verify on device before hardening. M
- [ ] P2 live-caption rebuilds full AttributedString per poll (`RecordView.swift:644-676`) — only bites when auto-off is disabled (long lectures). M
- [x] P3 `SpeakerVoiceStore.swift` dead code — DONE for free: deleted by SharedKit wave 2e (28efb35).

**Notes UI (mobile):**
- [x] **P1 `MemosListView.filtered`/`flatIndex` recompute the full filter+sort PER ROW** via `.accessibilityIdentifier` (`MemosListView.swift:253,633-639`) — O(N²) per list render; verify found it WORSE: `matches(query:)` JSON-decodes metadata inside the filter, and `groups`/`relatedDisplay` re-access `filtered` in the same body pass. Compute once per body eval. S
- [x] **P1 list photo thumbs decode full-res on main, uncached** (`MemosListView.swift` photoThumb — now keyed off `thumbnailPhotoFilename` since the 2026-07-18 stale-thumb fix) — `MemoImageLoader.thumbnail` exists for exactly this (the "600× with a picture" fix); one-line swap. S
- [x] P2 (was P1 — `[[img_` fast-path covers image-less notes) `NoteBodyView.load()` runs `snappedImageBody` BEFORE the `t == loaded` no-op check (`NoteBodyView.swift:301-314`) — reorder two lines. S
- [x] P2 `Memo.metadata` re-decodes JSON per access (`Shared/Model/Memo.swift:248-251`) — 4-5 decodes per list row per render; cache keyed on data identity. S/M
- [x] P2 `applyTierStyling` re-runs `BodyTransform.pieces(of:)` once PER name span (`NoteBodyView.swift:483-492`) — compute once per pass. M
- [x] P3 (was P2 — early-break scan, tiny constant; repaint already minimal-diff) `Karaoke.activeWordIndex` scans from 0 at 20Hz (`Shared/Pipeline/Karaoke.swift:17-24`) — resume from last index. S
- [ ] P3 (was P2 — fetch is trash-only, usually empty) `purgeExpiredTrash()` runs sync in `SkriftApp.init()` before first frame (`App/SkriftApp.swift:45`) — move to `.task` like every other sweep. S
- [x] P3 Release builds compute `photoHits` corpus scan per search keystroke to feed a DEBUG-only log (`MemosListView.swift:158-167`) — wrap in `#if DEBUG`. S
- [ ] P3 detail pager `@Query` = whole non-trashed corpus (`MemoDetailView.swift:20-21`) — fine now, window it when corpus grows. M/L

**Audiobooks (mobile) — root cause shared by top two: `BookTranscriptStore` has no lightweight read, every consumer decodes the full word array:**
- [x] **P1 `ReadAlongModel.reloadIfNeeded` full-sidecar decode at ~2Hz on main whenever playhead is ahead of the transcribe frontier** (`ReadAlongView.swift:31-49,142-146`) — a designed-for common state. Store-layer fix (cheap `coveredUpTo` read or frontier-advanced signal). M
- [x] **P1 `BookTranscriptionJob.publishValue` re-decodes EVERY file's full sidecar after EVERY chunk, on main** (`BookTranscriptionJob.swift:381-399`) — track covered-seconds in memory. S
- [ ] P2 `QuoteCaptureProcessor.exportSpan` drift — CORRECTED by verify: production passes `PreferPreciseDurationAndTiming` (`:373`), which the measured-bad `-chunksim` export lane did NOT, and live capture paths are self-consistent (audio + word-times shift together). Only `buildOutputFromSidecar` (sidecar times paired with exported audio) is exposed. STEP 0 before any code change: add a chunksim third lane — export WITH the flag — and measure. M
- [x] **P2 failed chunk = permanent silent gap marked covered-with-zero-words, no retry** (`BookTranscriptionJob.swift:226-233`) — retry once or flag for next `start()`. M
- [ ] P3 (was P2 — NSCache hit after first miss; pixel decode deferred to draw) `BookCoverCache.image(for:)` on-main file read in body (`BookCoverView.swift:66-73`) — decode off-main into the existing NSCache. S
- [x] P2 `MergedCaptureView.load()` sentence-parses the ENTIRE covered transcript for a ~90s window (`MergedCaptureView.swift:360-370`) — `ft.words(inWindow:)` exists, unused here. S
- [ ] P3 read-along `setCurrent` linear-scans sentences from 0 at 10Hz (`ReadAlongView.swift:56-60`); P3 `AudiobookCloudSync.localTranscriptSignature` full decode for two scalars (`:325-336`, and it runs on the MAIN actor). Both S. (Dropped by verify: AVAudioFile-reopen-per-chunk — negligible vs the transcribe itself.)

**Sync spine (cross-app):**
- [x] **P1 sync sweeps fault FULL audio/photo blobs into memory — BOTH apps** (WIDENED by verify): Mac `MemoCloudReconciler.swift:42-49` fetches every memo's assets even for already-ingested rows, BEFORE the ingest check, plus N+1 (2-3 fetches per memo); mobile `AssetMaterializer.swift:42` touches `.filename` before its exists-guard and faulting is ROW-level, so its protective doc comment is WRONG (fix the comment too). `MemoAsset.blob` can't be externalStorage (CloudKit). Fix: metadata-only reads (`propertiesToFetch`) + skip unchanged rows. M
- [x] **P1 CloudKit import bursts re-run full-library sweeps un-debounced on BOTH apps** (`SkriftMobile/Services/CloudSyncMonitor.swift:101-136`, `SkriftDesktop/App/MemoCloudReconciler+Wiring.swift:30-81`) — the `isSyncing` UI flag is debounced 1s, the actual work isn't; initial device sync = dozens of back-to-back O(n) main-actor passes. Coalesce the sweep dispatch. S/M
- [ ] P3 (was P2) `ExportStateStore.persist()` whole-ledger rewrite per record (`Services/Export/ExportStateStore.swift:56-69`) — verify found `publishAll()` has NO production caller (unwired standalone publish path; and it's O(k·n), skip-unchanged short-circuits). Dirty-batch it WHEN wiring the publish phase. S
- [ ] P3 `NamesMerge` millisecond-tie always favors remote (`Shared/Naming/NamesData.swift:172-178`); P3 `MacCloudWriteBack` wall-clock LWW has no skew tolerance (single-Mac fine, `:60-65`); P3 `MemoCloudIngest.swift:83-89` Bonjour double-ingest comment likely dead — verify + prune.
- Clean bills: SharePayloadLoader (extension memory ceiling handled textbook), CaptureInbox/Drainer (crash-safe ordering + poison pill), MemoDeduper, VaultExporter locked-note gate, MemoCloudUpdate content-based echo guard.

**Desktop:**
- [x] **P1 drag-drop/open-panel ingest runs on main incl. a semaphore-blocked video export** (`Features/Sidebar/SidebarView.swift:76-101` → `Pipeline/Ingest/IngestService.swift:205-207`) — comment at `:186` only proves no-deadlock, not no-freeze; multi-minute beachball on video drop. `UploadService`'s prepare/commit split is the right pattern next door. M
- [x] **P1 no guard against editing a note the pipeline is actively processing** (`ProcessingCoordinator.swift:158-180`, `BatchRunner.swift:150-156` unconditional overwrite vs `NoteBody.swift:183-194` live editor) — user edits during the multi-second LLM window get clobbered; none of the sync paths' LWW care applies here. Disable editor for the in-flight file or skip final write if hand-edited mid-run. M
- [x] P2 (was P1 — dev/prod stores isolated, needs two SAME-config instances) no second-instance store guard (only the `RunFile.swift:514` comment + discipline) — `NSRunningApplication` check at launch. S
- [x] P3 (was P2 — bounded by library size, active-typing only; and it's 2 full fetches per keystroke via `matches`+`exactExists`) tag typeahead re-tallies the whole library per keystroke (`Features/Review/NoteProperties.swift:252-325`) — compute once when the field opens. S
- [ ] P2 LINKED-FROM backlinks full-corpus body scan per note switch (`NoteDisplayView.swift:501-511`) — maintain a backlink index on save. M
- [ ] P3 `BodyTextView.restyle` full-doc regex per keystroke (`BodyTextView.swift:417-496`) — fine now (fast paths), scope-limit for long pasted transcripts. M
- [x] P3 `Sanitiser.wordRegex` recompiles per alias per call, uncached (`Shared/Naming/Sanitiser.swift:759-763`) — not hot-path; memoize. S
- Clean bills: engine lifecycle (load-once + 60s idle unload of the ~9GB weights), all Mac↔phone write-back LWW/echo guards, serial batch model, `RunReconciler` crash recovery.

**⚡ Found during final verification (2026-07-19):**
- [x] **P1 `mlx-swift-lm` pinned to floating `branch: main`** — PINNED a47894a1 on main 2026-07-19; (desktop `project.yml`) — a fresh checkout/worktree resolves today's upstream, which currently fails to compile against the resolved mlx-swift; the working Mac only builds off its cached resolution. Pin an exact revision (like FluidAudio's `7f963cdc`) — needs Tuur's pick of revision. S

**⚡ Connections/retrieval surface (Sonnet audit 2026-07-19, built same day unless noted):**
- [x] P1 empty-snapshot sweep wipes the whole embedding index on a failed fetch (`EmbeddingIndex.sweep` guard added)
- [x] P1 query failure rendered identically to "no matches" — Mac: `lastError` observable + gate line + "Connections unavailable" empty-state; PHONE PARITY still owed (Related in search)
- [x] P1 `modelRev` never checked on the read path — filtered in scores/related/gistPairScores (mixed-generation vectors excluded, no-bad-info)
- [x] P2 every query re-fetched + re-decoded the whole store — actor-state vector cache, invalidated per sweep
- [x] P2 `EmbeddingStore` silent in-memory fallback — now logged (was: full cold-start tax every launch, invisibly)
- [ ] P2 actor-reentrancy window: a query during a sweep's await can see a mid-swap memo (self-corrects; snapshot-swap deferred — structural M)
- [ ] P3 `ConnectionsModel` backlink full-corpus scan per note switch (needs a backlink index design; on-main rule blocks a trivial hop)
- [ ] P3 ANE-compile hang has no timeout/retry affordance (speculative; needs UX)

**Suggested attack order:** (1) the `try?` hardening pass — P0 + all silent-failure items, one small sweep, mostly S; (2) the three mobile one-liners (list O(N²), list thumbs, `load()` reorder); (3) `BookTranscriptStore` lightweight-read fix (kills both audiobook P1s); (4) Mac sweep blob/N+1 + burst debounce; (5) desktop ingest off main + pipeline-vs-editor guard + instance guard; (6) the P2 tail.

## 🎛 Transcription-engine wave — ✅ BUILT 2026-07-11 (worktree `transcription-engine-wave`; roadmap `TrEngine`)

Research session → user picked the lot; all mobile unless said. **Device round owed on everything below.**
- ✅ **Transcript chapter detection = THE chapter standard** (user call: even multi-file splits aren't reliably
  chapters). `ChapterDetector` (pure, 15 tests): long pause (≥2s) or file start + heading grammar — "Chapter/Hoofdstuk
  N" (digits, spelled EN/NL, ordinals, glued Dutch "drieëntwintig"), "Part/Book/Deel N", standalone Prologue/Epilogue/…;
  the number must TERMINATE (punct or ≥0.35s beat) so prose starting "Chapter seven ended…" can't match; spoken-title
  pickup only when the next short sentence HANGS (≥0.4s); same-heading echo drop (<45s); needs ≥2 detections, ≤30%
  number inversions (reset-to-1 after a part is fine) else nil; "Opening" prepended when the first heading starts >30s.
  Stored as `Audiobook.detectedChapters` (LOCAL-only, not in any sync carrier; `[]` = ran-found-nothing → never
  re-scans; nil = not yet run). `effectiveChapters` routes the WHOLE chapter UI (sheet, pill, sleep end-of-chapter,
  chapter line, capture attribution): detected > embedded/file-synth. Triggers: `BookTranscriptionJob` finish + player
  `open()` retro path (`detectChaptersIfNeeded`, detached, coverage-gated); session `refreshFromStore()` after store.
  Attribution `chapterNumberString` uses the ANNOUNCED number for detected books; a prologue quote carries NO number.
- ✅ **Detection v2 — style vote (same day, after web research + real-library probe).** ACX has narrators read
  headings EXACTLY as the manuscript writes them (so style varies by book but is consistent WITHIN one); m4b-tool's
  silence-chaptering proves gaps need duration priors. v2 harvests every style after silences and the book votes:
  keyword ("Chapter N", now incl. LibriVox "Chapter N of <book>") › bare numbers ("Seven. Don't turn into human
  spam.") › title-only (short HANGING utterances, accepted only when the book's biggest silences are dominated by
  title-shaped sites — sting-heavy productions fail the vote). All winners pass duration priors (median ≥4min,
  spacing ≥2min — kills counting scenes). Probing the REAL phone sidecars found two data truths: pre-2026-06-27
  sidecars carry chunk-seam ECHOES ("ten Ten." → was mis-parsed as 20; now deduped) and multi-file imports can be
  several WORKS (trilogy) → ascending-sanity resets at file boundaries. Result on the real library: Steal-trilogy
  0 → 5 real chapters (+44min Opening; sparse because the old-seam sidecars ate headings — a RE-TRANSCRIBE with the
  fixed seams + 180s chunks should lift recall a lot); Digital Minimalism → Opening + Part 1 + Part 2 (its narrator
  never says "chapter"; its per-chapter titles are title-only style — sidecar only 41.7% covered, finish the
  transcribe and re-judge). 21 detector unit tests; suite 659/659.
- ✅ **Round-2 device feedback (build 71, same evening): "Book N" separators** — the trilogy's restarting numbers
  read as shuffled ("??") → a separator entry lands at every numbered reset (suppressed when a real Part heading
  marks it), and a finished transcribe now FORCE-re-derives chapters (fresh sidecar supersedes old detection — no
  more USB cache-clears). Device-proven same night: trilogy redo = 4.5h in 6.5min (~33× cumulative, ~1.8 min/hr vs
  the June engine's ~3.2; per-chunk ~50× vs 21×), detection auto-fired → 8 real chapters (recall capped by this
  narrator running numbers into titles without a beat — the number+title-as-one-unit loosening is the parked tuning
  experiment, fresh sidecar pulled for offline iteration).
- ✅ **Round-3 (same night): separator restyled as a real SECTION HEADER** (user: the peer-row "Book 2" read as a
  ninth chapter). `AudiobookChapter.isSeparator` (display-only), sheet renders small-caps headers (no bullet/time/tap),
  and ALL index semantics (Ch N/M pill, sleep, attribution, current-highlight, prev/next) run on `playableChapters`
  (separators excluded). Sim-verified WITH VISION via the new `-seedDetectedChapters`/`-showTOCSheet` launch flags
  (self-serve sheet screenshots — no more shipping chapter UI unseen).
- ✅ **Round-4 (same night): SENTENCE-anchored bare numbers — the recall breakthrough.** Fresh-sidecar probing showed
  the missing headings have ZERO silence before them (this production never pauses; silence marks decorative stings
  instead). The discriminator is the SENTENCE BOUNDARY: every true heading follows a finished sentence ("…their
  example. | Two. Think process not product."), every prose number flows mid-sentence ("a nine to five job", "when he
  saw one", "Ecclesiastes chapter one") — all die on the prev-word-ends-sentence test. New anchor: prev-punct + number
  terminates + MANDATORY title sentence (hang waived at zero-gap); vote gates carry the rest. Trilogy probe: 8 → **21
  chapters with real spoken titles** + Book 2/Book 3 separators at the RIGHT places, zero FPs. Suite 677/677.
- ✅ **Round-5 (same night): completeness gate — "better no information than bad information" (user principle, now
  law in the detector).** Ordinals with holes make listeners feel chapters went missing. Numbered headings split into
  per-work SEGMENTS at resets; a segment shows its chapters ONLY when numbers run 1..k hole-free; any hole → the
  segment collapses to one tappable "Book N" jump point; a lone hole-y segment (normal novel with gaps) suppresses
  entirely (book keeps existing chapters). Real Part headings suppress synthesized markers. Trilogy now renders
  Opening · Book 1 · Book 2 · Book 3 (probe-verified) — complete jump points, zero false implications; the full
  21-chapter data stays in the sidecar for the day recall reaches 100% per book. Suite 677/677.
  **Follow-ups parked:** manual "Re-transcribe book" affordance for pre-fix sidecars (no created-at in the sidecar to
  auto-detect age); consider a review-sheet UI for gap-only books that fail the vote (the reading-mode chat owns
  player IA).
- ✅ **Book-transcribe efficiency trio:** (1) chunks feed the engine as in-memory PCM buffers — the temp-WAV round-trip
  is GONE (was ~15–30GB flash I/O per long book) and book chunks skip the custom-vocab CTC second pass (FP-prone on
  prose, pure cost); (2) `chunkSeconds` 60→180 (per-seam 3s lead + redo-tail overhead ~13%→~4%); (3) captures, user
  pause, AND battery-conserve now CANCEL the in-flight chunk (FluidAudio aborts between its ~15s windows) — cancel ≠
  failure: failure skips past the chunk, cancellation redoes the SAME frontier (never a gap).
- ✅ **Lazy RMS (both apps)** — the phantom-guard RMS decoded the ENTIRE file before every transcription; now computed
  after, only when the transcript came back ≤3 words. Free win on every memo/import/chunk.
- ✅ **Filler filter, opt-in (default OFF)** — Settings→Capture "Remove filler words": standalone um/uh/hmm/ehm… (tiny
  EN/NL list; "er"/"so"/"like" deliberately excluded — real words) stripped from text + karaoke timings in lockstep at
  memo save (`FillerFilter`, 6 tests); a dropped filler's sentence terminator transfers to the previous word; `[[img]]`
  markers pass through; an all-filler memo stays unchanged. NEVER audiobook quotes; live caption untouched. Capture
  DICTATION path deliberately not wired (separate path — add on demand).
- ✅ **FluidAudio pinned** to `7f963cdc` in BOTH project.yml (was floating `branch: main` — the drift risk flagged at
  the 2026-06-16 asrsweep entry). Upgrade = deliberate, both apps together, with a device round.
- ✅ **Trunk fix (drive-by, other lane's file):** `NoteBody.imageURL` had a shadowed `let url` from 7b597ad — full
  desktop scheme was RED on main (the UnitTests gate doesn't compile that file). One-line unshadow; ShareW2 chat heads-up.
- **Device-owed:** chapter detection on the real library (titles esp.), capture-cancel latency feel, 180s-chunk memory
  on the iPhone 13, RTF re-measure (buffer path + no-booster should raise the ~min/hr number), filler toggle on a real
  ramble.
- **Parked (from the same research):** per-book language override for the book job (a Dutch book under the global
  English toggle garbles — needs a small Transcribe-sheet picker); Paragrapher grouping for reading-mode when that
  builds; FluidAudio streaming managers for the live caption at the NEXT engine upgrade.

## 🎙 Recording robustness + heat diet (2026-07-07, worktree nice-shtern — roadmap `RecHard`)

User report (iPhone 13, warm): tap record → UI froze, stop unresponsive, memo captured only HALF the
message. Full-code audit found two separate causes, both fixed same day (5 commits, 588 unit tests
green; **device round owed** — the sim can't fire interruptions or measure ANE duty):
- **Data loss:** NO `interruptionNotification` handling — a call/Siri/alarm stops the engine with no
  route/config event, so the recovery lattice never fired and the wall-clock timer kept counting over
  dead capture. Fixed: interruption observer + foreground re-arm (iOS can skip `.ended`) + a
  display-timer capture WATCHDOG (engine dead >2 s, no rebuild in flight → rebuild) + resume()
  rebuilds when a plain start fails. The route-rebuild ladder itself is untouched (device-proven).
- **Heat/freeze:** live captions re-ran FULL ASR over the whole ≤25 s live window every 0.6 s (ANE
  ~100% duty, cost grows with the window) + the camera session ran the entire recording + the screen
  re-rendered ~30×/s (20 Hz timer on a whole-object ObservableObject) + Live Activity got the whole
  transcript every poll. Fixed: self-pacing polls (≥1.5× last snapshot cost, thermal floors
  2.5 s/.serious 6 s/.critical) + early rotation (>10 s window once snapshots >1.2 s) + camera runs
  only while the sheet is open + @Observable per-property observation with child-view splits (4 Hz
  timer) + Live Activity pushes a word-aligned ~220-char tail at ≥1.5 s. DevLog now traces
  window-size/snapshot-ms/rotations — pull `devlog.txt` on the next device round for the real numbers.

**Owed / follow-ups:**
- ⬜ Device round (13 + AirPods): freeze gone? snapshot-ms trace, mid-record call/alarm survives,
  camera-sheet first-open latency (~½ s expected), auto-off still fires, Live Activity tail reads OK.
- ⬜ Phase 3 (own session, riskiest): move session activate/deactivate + engine start/stop OFF the
  main thread — `setActive` blocks 100–300 ms in `start()`/`stop()`; touches the hardened lattice.
- ⬜ Spike: FluidAudio ships true streaming ASR we hand-rolled around — `SlidingWindowAsrManager`
  **accepts the already-loaded `AsrModels`** (`loadModels(_:)`, same weights in RAM) with push
  `streamAudio`/`finish`; would replace the snapshot loop with bounded incremental windows. Also
  `StreamingEouAsrManager` (separate EOU weights). Quality/latency device eval needed.
- ⬜ Extraction pass once device rounds lock behavior: TapWriter / RouteRecovery / CaptionFeed out of
  the 1000-line `LiveRecordingService`; protocol-seam the `if mock` branches.
- Deferred judgment calls: captions keep running while backgrounded (Lock-Screen Live Activity shows
  them — thermal floors now bound the cost); memory-warning `unload()` still no-ops mid-recording.

## ⭐ CONTINUE HERE (2026-07-07 night, audiobook-UX chat wrap) — worktree `sweet-goldstine`

Branch `claude/sweet-goldstine-13dfca` (pushed, NOT yet PR'd) holds **builds 46→51** on top of merged PR #6:
bottom-chrome saga (Option A split row → V2a pill → card-at-rest/pill-when-live → compact header + unified
30pt titles → card as scrolling list row → List-row tap-hijack fix w/ 2 green ContinueCardUITests). Contains
PR #8's content (sprint branch merged in) — **when this branch's PR merges, close PR #8 as contained.**
NEXT: (1) user+Hendri eyeball of build 51 (× must not autoplay; card/pill lifecycle; title sizes), then
(2) OPEN THE PR → merge → close #8. Ghost dismissal-write in the sim container never got attributed —
both write-sites DevLog themselves now; if the card vanishes without ×, pull the devlog.

## 🔬 Audiobook deep-review findings (2026-07-07 chat; UNBUILT unless ticked) — the perf/correctness list

**Perf (one root cause: monolithic sidecar JSON + main-actor I/O):**
- ⬜ P1 read-along uncovered-spot hot loop: `ReadAlongModel.reloadIfNeeded`'s `|| !covered` guard re-decodes the
  ENTIRE partial sidecar ~2×/s on main while playing past the frontier (worst exactly during "keep listening
  while it transcribes"). Cache by (sig, coveredUpTo) or check mtime/tiny header before decoding words.
- ⬜ P1 `BookTranscriptionJob` is @MainActor incl. statics: per 60s chunk — `extractPCM` (~20MB decode+WAV write)
  synchronous on main; `store.save` re-encodes the WHOLE accumulated sidecar (O(n²) bytes over a long file);
  `publishValue` re-DECODES every sidecar per chunk though the loop already holds `coveredUpTo` (trivial fix).
- ⬜ P2 `AudiobookCloudSync.localTranscriptSignature` full-decodes every sidecar per reconcile (launch/foreground/
  pull) just for coveredUpTo+wordCount.
- ⬜ P2 over-observation: 2Hz `currentTime` re-renders Books list (+ per-row SwiftData `isSynced` fetch + N×
  fileExists) via whole-session @ObservedObject; split a PlaybackClock sub-observable; make sync state a real
  observable (kills the `syncToggleTick`/`tick` hacks in AudiobookLibraryView + SyncedAudiobooksView).
- ⬜ P3 `setCurrent` linear-scans sentences 10×/s; per-body `Timer.publish` churn in ReadAlongView; CIContext
  per loadCoverTint.
**Correctness:**
- ⬜ P1 "Edit book details" never syncs: `store.update()` doesn't bump `modifiedAt` → reconcile's send guard
  never fires; replaced cover also never re-uploads (audioUploadedAt upload-once gate).
- ⬜ P2 TranscribeBookView shows the ACTIVE book's progress/ETA on any book's sheet while a job runs, and Start
  silently cancels the other book's job.
- ⬜ P2 seek-while-paused never persists (`seek()` lacks persistProgress; force-quit loses a paused scrub).
- ⬜ P3 BookCoverView placeholder gradient uses `uuidString.hashValue` (per-process seed) — not stable across
  launches despite the comment; use UUID bytes.
- ⬜ VERIFY quote audio extraction: `exportSpan` (AVAssetExportSession + precise-timing key) vs the durable
  PCM-extraction gotcha — if deep-chapter captures drift vs sidecar karaoke, switch to `extractPCM`+m4a.
**Dead code (~800 lines + tests):** wave-1 capture arm — `CaptureMath` (all of it), `CaptureScrub` shim,
`QuoteCaptureProcessor.process()`, `applyTrim`/`TrimResult`, `SentenceSnap.snap`/`inIndex`,
`CaptureSpan.proposal`/`replayWindow`; `AudiobookSession.sleepLabel`; `QuoteCaptureOutput`'s vestigial
buffer fields (shrink the struct). Zero non-test callers verified by grep 2026-07-07.
**UX (decided elsewhere or open):** per-book "N notes" surface + note→book jump-back (metadata `bookID`/
`bookPosition` now accrues since PR #6); multi-select import of N DISTINCT books silently merges into one
(warn when album tags disagree); Books empty-state deserves a real CTA button.

## 🎧 Books tab + one-tap resume — ✅ BUILT 2026-07-07 (mock-first, signed off; worktree `sweet-goldstine`)

From the 2026-07-06/07 audiobook deep-review chat (roadmap detour node **D4**). Mock = `mocks/books-tab-and-resume.html`
(v2, rebuilt 1:1 against Theme.swift + real components after v1 "looks different from the app" feedback). Decisions:
- **Highlights tab CUT** (user: "well kill it") — captures live in Notes; P6 becomes a book-context surface later.
- **Library → Books** (tab + header). **Screen title Memos → Notes**; "memo"→"note" across all user-facing copy
  (list/detail/trash/settings/onboarding/widgets/intents/Live Activity — Siri phrases had no "memo", unchanged).
- **One verb: "Add note"** (capsule pill + capture-screen header renamed from "Capture"; player already said it).
- **Cold-launch resume:** last PLAYED book restores as a **paused** capsule (`restoreOnLaunch`) → resume = 1 tap,
  record = 1 tap, same screen (the "two first things" tension dissolved). Never auto-plays; skips w/o local audio.
- **Global capsule:** mounted per-tab via `safeAreaInset` in AppTabView; persists over pushed screens; covers hide it.
  Memos list stopped observing the session (kills the 2 Hz whole-list re-render during playback).
- **Tap a book row → autoplays** (+ full player opens running); PLAYING/PAUSED row badge dropped (tint stays).
- **Books sort/filter chip** (was a dead-looking static label): Recently played (default, persisted) / Title / Author /
  Recently added + In progress / Not started / Finished. Unit-tested.
- **Capture memos now carry `bookID` + `bookPosition`** (stable join key for the future per-book-notes surface;
  additive metadata, Mac ignores).
Also fixed in passing: stale "Tap Mark" bookmarks empty-state copy; stale "last 30 seconds" capsule a11y label.
**Gate:** build green; unit suite 327 run — only the 8 PRE-EXISTING CloudKit-epic failures (verified identical at
branch HEAD baseline); new sort/filter tests green; 4 UI-test files' "Memos" assertions updated to "Notes".
**Device round 1 (build 40, 2026-07-07): FAIL — record button buried under the capsule.** The tab-level
`safeAreaInset` mount never propagated into the tabs' NavigationStacks on iOS 26; uncatchable in sim (no book
seedable). **FIXED build 46 — Option A** (signed `mocks/notes-bottom-chrome.html`): Notes = ONE 60pt row, compact
`AudiobookMiniPill` (cover · play/pause · ❝ Add note) left + record right (no session → record alone, right corner);
Books keeps the full bar (mounted INSIDE the view); Journal/Settings carry nothing (user call); ˄ chevron cut
everywhere (duplicate of cover-tap); list gets bottom content margin. New hooks `-seedAudiobook` + `-openTab` make
the capsule sim-visible per tab — vision-verified all four before install. **Round 2 (build 46): pill interior "weird — empty space / I'd tap it to open the book" + Henry "crowded".** Iterated V1/V2/V3 then V2a/b/c (mocks notes-pill-variants + notes-pill-v2-iterations); discovered the 390pt truth (title + labeled chip + play don't fit). **PICKED V2a → build 47:** cover · time-left · ❝ Add note · filled accent play; pill BODY opens the player; 16pt pill↔record gap. **Round 3 (build 47) + the Hendri debate:** designer pushback — media chrome on a notes list is weird; dashboard floated. Resolved via mocks (notes-book-presence-debate + notes-compact-header, both signed): **cards for starting, chrome for controlling** — build 48: at rest = ZERO chrome, "Continue listening" CARD above search (▶ 1-tap resume · body → player · × dismiss-for-today); live = V2a pill; launch-restore REMOVED (no phantom paused session — card reads the library). Plus **compact header**: Select/scan/filter inline with the "Notes" title (~44pt back; dodges the iOS-26 trailing-toolbar-item bug). New sim hook `-seedAudiobookIdle`. Both states sim-verified with vision; 582/582 unit green; MemoDetailUITests 5/7 fails PRE-EXISTING (identical at baseline — the known iOS-26 cluster). **Round 4 (build 48) → build 49:** (a) ×-dismissing the card then starting a book left the card gone — playing now VOIDS the dismissal (re-engagement rule; card returns when the session ends). (b) Title parade fixed: all four tabs share ONE 30pt `ScreenTitle` (was 30/26/34/34); Books folded its + into the title line; Journal + Settings got custom headers w/ root-only nav-bar hide (pushes keep bars). Four-tab sim vision check + 582/582 green. **Round 5 (build 49) → build 50:** the pinned card read as "stuck to the top" while scrolling — moved UNDER the search bar as the FIRST LIST ROW (scrolls away with the notes, honoring the original "content, not chrome" pitch). Player cover + the plays-again-voids-dismissal rule hoisted out of the card (a cover on a List row dies when the row unmounts). **Round 6 (build 50) → build 51:** × on the card AUTO-PLAYED the book — the SwiftUI List-row tap hijack (buttons in a List row need `.buttonStyle(.borderless)` or the row fires siblings; broke exactly when the card became a List row). Fixed + **2 new ContinueCardUITests** (tap × → no session; tap ▶ → pill) — green. Seeded launches now reset card-dismissal state (hermetic); ×/void writes DevLog-instrumented (a ghost dismissal write was found in the sim container — logs will name any recurrence). **OWED:** user eyeball of build 51.
Build numbering: 43–45 were consumed by the sprint branch in parallel → renumbered 46; rule = bump to
max(installed-on-phone, main) + 1 before any device build.

## 🔭 Next unclaimed lane + code-verified quick hits (2026-07-06 Fable survey, worktree youthful-wozniak)

Surveyed while three lanes were claimed elsewhere: note-editing (`claude/gracious-easley-e3fc96`),
audiobooks, and the Bonjour-removal/live-sync handoff (`claude/xenodochial-mclaren-9361b9`).
**Recommended next big lane = P8 Journal & retrieval** — full Opus-ready plan in
**`JOURNAL_RETRIEVAL_PLAN.md`** (repo root): locked decisions, chunk list with gates, collision map.

**⭐ P8 ENGINE BUILT 2026-07-07 (this branch — user green-lit parallel build, PR merge flow):**
mock signed off · engine bake-off RUN on the Mac (EmbeddingGemma-300M d512 wins 10/10 vs Apple NL
5/10, `Skrift_Native/spikes/EmbeddingBakeoff/`) · chunks 1–3 built + tested (Shared/Retrieval
gist/chunker/protocol; MemoEmbedding in its OWN local container; hash-diff sweep + orphan cleanup;
search/related max-cosine queries; 14 new unit tests green; full suite's 8 failures PROVEN
pre-existing on base — they're the Bonjour-era SyncCoordinator/MemoModel pill tests the removal
lane owns). Wiring is INERT (`journalIndexEnabled` default-false + model-on-disk guard — no
surprise 295 MB download). **Still owed:** UI chunks 4–8 after the other lanes merge (tab bar /
memos list / detail), floors calibration histogram, device perf run, Settings consent toggle.

**Quick hits (unclaimed; each verified against today's code, not memory):**
1. ⬜ **Stz020 #3 STILL LIVE — phone-added person is unlinkable.** `NamesListView.swift:202` still
   saves `aliases: []`; `PersonEditorView.swift:222` already seeds `[name]`. Fix: same seed in
   AddPersonView + a one-time backfill `aliases = [canonical]` for alias-less people (safe: only
   AddPersonView ever produced them — the editor auto-seeds on save). Backfill also fixes IJsbrand.
2. ⬜ **i4 ROOT-CAUSED — WhatsApp voice message imports as a LINK.** `SkriftShare/SharePayloadLoader.swift:48-70`
   classifies url → movie → image → text → file and has **no `UTType.audio` branch**; WhatsApp audio
   also exposes a URL representation, so the url branch wins. Fix: an audio branch BEFORE url,
   mirroring the movie fast-path (copy into the App-Group inbox, `type: "audio"`, host imports as a
   voice memo + transcribes). Feature half (multi-select messages → append-as-one vs split): the
   loader only reads `attachments.first` per type — iterate all providers + a small share-sheet
   choice. Verify on device with a real WhatsApp share.
   → **2026-07-07 share-ingest deep review:** i4 is row A7 of **`SHARE_INGEST_SURVEY.md`** — the
   full row-by-row table (existing share bugs A1–A16 + multi-item B + link-enrichment C + new
   input types D + cross-cutting UX/IngestKit E). User reviews it row-by-row (memo per row, say
   the ID); triage verdicts back into this ledger, then build.
   → **2026-07-10 VERDICTS RECORDED** (voice pass, in the survey's last column). Headlines:
   big GO wave (all of A incl. A7/A15, B1–B3 w/ B2 = photos ALWAYS one note, C3 podcasts ⭐,
   C5 pdf-urls, D1 quote-detect [NO Highlights tab — quotes are plain notes], D4, D7, D8,
   E1–E5 w/ E2 threshold = 1 h); **SKIP** D2 vCards; **D3 already live** (drainer manifests +
   PhotoTextIndexer — verified); **pending Tuur's call** after plain-words re-explain: C1
   (captions rejected outright), C2, C4, D5, D6, B4. Scribbel reference checked for A7:
   no extension there (doc-types + onOpenURL + ImportTranscriber w/ bg-task claim + toast).
   **r2 same day:** C4 GO · D5 SKIP · D6 GO-w2 · D1 PARKED (Books/Journal chat) — still
   pending only C1/C2/B4.
   → **2026-07-10 WAVE-1 MOCK SIGNED OFF:** `mocks/share-ingest-wave1.html` — 4 states
   (single audio · 8-memos 1-or-N chooser [default = one note, Save relabels live] ·
   photos-always-combine · Saved✓/Error/Unsupported), vision-verified, all questions
   resolved. LOCKED: every share jumps to its note on next app-open; audio shares have
   NO ramble UI (append in-app later — user rule); combine = audiobook-capture model
   (append in timestamp order, one karaoke transcript); "N photos → one note" title.
   → **2026-07-10 WAVE 1 BUILT — chunks 1–3 same day** (`827965f` A7 audio fast-path +
   jump-on-open-for-every-share; `394a916` A11 multi-select 10×, B1 1-or-N chooser
   [combine = clips MERGED in order via `MemoSaver.importAudioClips` → ONE transcription
   pass, no import/append race], B2 photos→one-manifest-note, ImageIO downsample ≤2048px;
   `3371fb1` A12/E3 Saved✓/error/unsupported states + A16 husk guard + A15 "Skrift Dev"
   label). Unit suite 610/610 green; roadmap node `ShareW1` inprogress. i4 = FIXED IN CODE.
   **✅ DEVICE ROUNDS 1–4 RUN 2026-07-10 (builds 60→63).** PASSED: singles+dates (Sunday ✓),
   multi order (chat order ✓), m4a transcribe, video, PDF (after the round-2 file-url fix
   — `public.file-url` CONFORMS to public.url and ate every Files share since June), photos
   inline-in-text (round-3 rebuild: markers in annotation + editorPage routing — user: "the
   only way we should have"), Saved✓, dev label, multi-select visibility. FIXED ALONG THE
   WAY: phantom silent tail on the 4-clip merge (composition+export fabricated duration
   287.5s — rewritten as sample-accurate AVAudioFile frame reads, EOF guard); clip-list
   scrolls all rows. **RETIRED: sheet dictation** — iOS blocks extension recording at the
   entitlement level (mediaserverd refusal; perm 'grnt' yet record()=false, both session
   categories; Apple forums 742601/108435). Old test image-captures stay broken by user
   decree (no migration — "they can go"). **REMAINING/PARKED:** slow first transcribe =
   cold engine + app-suspension (existing launch-sweep recovers; Scribbel-style bg-task
   claim = Wave-2 candidate); voice-annotate captures IN-APP (Wave-2); drag inline photos
   like Apple Notes (note-editor lane); PDF "text, PDF, text" inline (Wave-2 design).
   → **⭐ CONTINUE HERE — SHARE WAVE 2 (kickoff 2026-07-10, Wave 1 MERGED via PR #11).**
   Start from MAIN, fresh worktree. Read `SHARE_INGEST_SURVEY.md` (top status block +
   Verdict column) first. Two tracks: (A) **code-first, no mock needed** — A9 open-in video
   nav + prune avi/mpg, A14 off-main drain copies + pending indicator, C5 pdf-url →
   download→file-capture, D4 .md/.txt → note body, D6 Maps place-note, D8 in-app Files
   importer (audio+video), E2 1-hour Books routing, A4 EXIF date on image captures,
   A6 PDF text-extract (unpin — searchable PDFs), bg-task claim on share imports
   (Scribbel `ImportTranscriber` pattern, ~/Hackerman/ShhcribbleiOS). (B) **mock-first**
   (locked process): E1 unified sheet (video+PDF get the slim sheet — significance at
   share time), PDF text-inline in the body, in-app voice-annotate a capture. C3 podcasts ⭐
   = own lane when user says go. Still awaiting user calls: C1 YouTube rich-card-only?,
   C2 Insta/TikTok, B4 chat-export. Device builds number from **64** (63 = on-phone).
   → **2026-07-11 WAVE-2 TRACK A BUILT — all 10 items, one session, suite 632/632**
   (commits `7b597ad`..`f9386cf`): Mac capture-marker fix FIRST (the Wave-1 unproven
   edge was REAL — literal `[[img_NNN]]` in the Mac Review UI AND the vault export,
   plus a stale-name pinned embed; fixed in VaultExporter/Compiler/NoteBody, desktop
   345/345) · A9 open-in nav + honest "format not supported" for avi/mpg (extensions
   KEPT — public.movie delivers them anyway; pruning would silently eat the share) ·
   A14 drain copies off-main + reentrancy guard + "Importing N shares…" pill · C5
   pdf-url → download (magic-byte sniff, link-card fallback) · D4 .md/.txt → note body
   (loader also FIXED: a text FILE decoded to nil → empty sheet) · D6 Maps → place
   chip (PlaceLink parser; goo.gl short links stay cards — opaque without a fetch) ·
   D8 header import menu (Files audio+video via AppURLHandler; wires the ORPHANED
   VideoImportPicker — it had zero call sites) · E2 ≥1h → Books chooser in the sheet
   (default Books, fallback-to-memo when unreadable) · A4 EXIF dates (read in the
   extension BEFORE the downsample strips them; earliest across a multi-share) · A6
   PDFKit text-extract → sharedContent.text (searchable; 120k cap) · bg-task claims
   on drain + all three import transcriptions (Scribbel pattern). **Track B mock
   `mocks/share-ingest-wave2.html` AWAITS SIGN-OFF** (4 states: E1 video · E1 PDF ·
   PDF text-in-note collapsed/expanded · voice-annotate idle/recording/after; open
   questions printed on the panels). **BUILD 64 INSTALLED on the phone 2026-07-11**
   (freshness strings-verified: Wave-2 symbols in the dylib, app+extension plists = 64).
   → **✅ DRAIN HALF DEVICE-VERIFIED 2026-07-11 (USB, no hands needed):** staged 6
   crafted inbox entries into the app-group container over devicectl, launched the
   app, verified via devlog + pulled SwiftData store + library.json — C5 ✅ REAL
   network download ON the phone (w3.org dummy.pdf → file capture) · A6 ✅ its text
   extracted on-device (sc.text='Dummy PDF file') · D6 ✅ place parsed
   (location{38.7223,-9.1393,'Hotel Du Vin'} + urlTitle fallback) · D4 ✅ .md → body
   (ramble + file text in order, sc.type=text, provenance fileName kept) · A4 ✅
   recordedAt=2026-07-02 = EARLIEST photo date, not share time (2-photo manifest +
   markers) · A9 ✅ garbage .avi → title 'Video format not supported' · E2 ✅ audio
   routed to the Books library (book in library.json) · A14 ✅ drain visibly
   interleaves off-main (pdf download logged mid-video-import). Test junk on the
   phone: 6 notes + 1 'shared import 402AD…' book — delete at will.
   **REMAINS FOR TUUR (extension/UI half, ~3 min):** share-sheet entries from real
   apps (Safari pdf-link · Maps · Files .md · Photos w/ EXIF · 1h+ audio → Books
   CHOOSER visible) · header import menu eyeball · import pill on a big movie ·
   open-in jump lands on the note. KNOWN GAP (pre-existing, logged): the phone's
   OWN Obsidian publish never copies images for ANY photo memo — Mac stays the
   attachment exporter.
   → **ROUND 2 (Tuur's hands, 2026-07-11 evening) — 2 bugs found, both FIXED, build
   66 installed:** (1) **Safari-PDF: Skrift absent from the share sheet** — the
   DICTIONARY activation rule only matches homogeneous items; Safari shares a PDF
   page as ONE item [web-URL + PDF]. Swapped to an explicit predicate string
   (per-attachment OR over url/text/image/movie/audio/pdf/file-url/data, ≤10);
   **sim-verified both ways** via the new `ShareSheetActivationProbe` UITest that
   drives sim-Safari's share sheet (iOS-26 'Share under ···' path): arxiv PDF now
   offers Skrift, plain pages still do. Run it explicitly after any rule change —
   a bad predicate silently removes Skrift from EVERY sheet. (2) **'Video format
   not supported' memo spam** — an inbox entry whose dir survives delete re-imports
   on EVERY open (video/audio mint fresh memo UUIDs; hit via devicectl-staged test
   entries whose dirs the app can't remove — NB devicectl-planted files are
   app-undeletable; the wipe antidote is `devicectl ... copy to --remove-existing-
   content true`). Fix: failed deletes TOMBSTONE the entry id (persisted, cap 200),
   pendingEntries skips them; poisoned inbox wiped; Tuur already purged the junk
   memos. (3) Bonus find: **arxiv links are extensionless** (`/pdf/2406.19741`) —
   C5's .pdf check missed them → now a 10s HEAD content-type sniff catches any
   `application/pdf` link (magic-byte gate unchanged; suite 661/661). Google-Maps
   APP shares = opaque goo.gl short links → stay link cards BY DESIGN (needs a
   fetch; parked with A1/C4 enrichment). Tuur's arxiv paper staged for drain on
   next app-open (build-66 sniff e2e = watch for `drain: pdf-url ... downloaded`).
   E2's Books CHOOSER UI still unverified (no ≥1h file handy) — routing itself is
   device-proven.
   → **⭐ WAVE 3 BUILT 2026-07-12 early-AM ("do everything that's left" — Tuur
   green-lit Track B as drawn via the option pick).** Commits `51a483f`..`c0e8e99`:
   **A3** selected-text beats url, link rides along (loader) · **D7** odd-UTI voice
   notes (Signal/Telegram) reroute off the file branch by audio extension ·
   **A1+C4** link enrichment ON DRAIN — one GET: og/title/description + og:image
   downloaded LOCAL (`linkthumb_<id>.jpg`, offline rule) → url card grows thumb +
   description; Readability-lite article text → `sharedContent.text` (searchable,
   never rendered; 3-para/400-char floor, 60k cap; Maps + pdf-routed links skip);
   pure parser = `HTMLMeta` (6 tests) · **B3** mixed bundles → ONE note: loader
   collects photos+text alongside clips, sheet stacks the signed idioms + forces
   combine, drainer manifests photos under the memo id (markers via the
   transcription pass) + chat text → annotation · **E1 (Track B m1/m2)** video +
   documents get the SLIM SHEET (preview cards w/ duration/filmed-at · pages/size,
   honesty lines, typed thought + significance; silent imports + completeVideo/
   completeFile RETIRED; thought lands as an annotation-lead above the transcript
   — new non-capture annotation display) · **PDF text-in-note (m3)**
   `PDFTextDisclosure` collapsed row under the inline PDF → expanded dimmed
   preview w/ fade → full selectable reader sheet · **voice-annotate (m4)**
   `CaptureVoiceAnnotate`: mic pill on audio-less captures → inline strip with
   LIVE CAPTION (LiveRecordingService reused) → on-device transcribe → appends
   below the ramble → 'Add another'. **v1 = dictation model (audio consumed):
   attaching playable audio flips the Mac capture-ingest discriminator (capture =
   memo WITHOUT audio) — Mac-counterpart chunk owed before that half.**
   **VERIFICATION STATE (resolved 2026-07-12 morning):** the overnight "build-stack
   wedge" was a PENDING macOS DEVELOPER-TOOLS AUTHORIZATION DIALOG — xcodebuild
   sat silently alive at clang-stat-cache/codesign waiting for a GUI prompt no
   terminal can see (Tuur accepted it → suite ran green in 6s). Durable lesson:
   silent multi-minute stalls at stat-cache/codesign ⇒ check the Mac's screen for
   an auth dialog BEFORE diagnosing a wedge. Voice-annotate's UNVERIFIED flag
   LIFTED: suite 669/669 compiles + passes with it; **BUILD 67 INSTALLED**
   (freshness: version 67 + Wave-3 strings in the dylib) and the 61-min chooser
   test file is ON THE PHONE (Files → On My iPhone → Skrift Dev →
   long_test_recording.m4a). **REMAINS: Tuur's Wave-3 retest** — Safari
   selected-text → quote note w/ url · article link → rich card + searchable text ·
   WhatsApp voice+photo multi-select → one note · video/PDF share → sheet w/
   thought+circles · PDF note → text disclosure + reader · capture → mic-pill
   voice ramble · share the 61-min file from Files → Books CHOOSER (E2 eyeball).
   → **⭐ NEXT SESSION KICKOFF — B3 round 2: multi-ITEM WhatsApp bundles (found by
   Tuur 2026-07-12 19:12, devlog-proven).** He multi-selected voice notes + a photo
   + a link + a VIDEO in WhatsApp → only a video note appeared. Root cause: WhatsApp
   ships a multi-select as MULTIPLE NSExtensionItems and `SharePayloadLoader.load`
   reads `inputItems.FIRST` only — his first item was the video, so the voice
   notes/photo/link never entered the loader. B3 merges multi-ATTACHMENT items only.
   Build: (1) flatten attachments across ALL extensionItems before the type
   dispatch; (2) decide video+link roles inside a mixed bundle (suggestion: video →
   its own memo alongside the bundle note, link → rides the note like B3 text; OR
   everything-in-one via markers — design call, mock if UI changes); (3) the sheet
   must SAY what it's keeping (honesty line), never silently drop; (4) device round
   with the same WhatsApp selection. Suite baseline 672/672; builds from 71.
   → **✅ CHAPTER CLOSED 2026-07-12 evening (last Fable-5 day; roadmap ShareW2 →
   done, now → NFeat).** Builds 64→70 shipped; crash loop fixed (dup CloudKit ids
   → tolerant dicts + MemoDeduper trash-sweep); no-bubble rule LOCKED + applied
   (audiobook-quote idiom for shared text, borderless annotation); voice-annotate
   cold-start now says "Warming up the transcriber…" (build 70). **PARKED, ZERO
   URGENCY — user retest of the wave-3 share paths** (list stands below; every
   path fails honestly now — error states + extLog + tombstones — so regressions
   surface in normal use, no test session required). Parallel-board note: Lane P
   builds ON these MemoDetail changes; Lane B (podcasts) reuses C5/enrichment
   plumbing.
   → **2026-07-12 17:00 — Tuur's first retest hit 'Couldn't save this' on EVERY
   share: MY wipe's collateral.** A devicectl-created CaptureInbox dir is
   IMMUTABLE to the app+extension → every extension write died at
   createDirectory (and only print()'d — invisible). **FIXED in build 68
   (installed):** write failures now extLog into the devlog; inboxURL SELF-HEALS
   a file squatting on the inbox name (recovery = devicectl turns the poisoned
   dir into a file; app OR extension unlinks + recreates it app-owned on next
   use). The heal completes on Tuur's next app-open or share attempt. HARD RULE
   FOR SESSIONS: never devicectl-write into app-group paths the extension must
   own (staging test entries planted this twice); pull-only is safe.
3. ⬜ **Stz020 #5 remainder — "every note is a conversation".** `dda494d` (C2) only fixed tag
   over-suggestion on turn bodies. Still open: WHY stored transcripts carry stale `**Name:**` turn
   markers, + a bulk un-diarize/re-transcribe path. (Workaround: sidebar right-click →
   Re-transcribe, `SidebarView.swift:527`.)
4. ⬜ **Prod gate runbook (no code — dashboard + user GUI), before ANY Release promote:**
   (a) CloudKit Dashboard `iCloud.com.skrift.mobile` → deploy Development→Production schema, must
   now include `MemoEnhancement` + `NamesRecord` + `VocabularyRecord`; (b) prod Mac Settings →
   cloudKitMacSync ON; (c) Release bundle-IDs' App Groups capability — one-time Xcode Signing &
   Capabilities visit (CLAUDE.md signing lesson); (d) one real prod round-trip test.
5. ⬜ **Sequencing:** Mac in-place name-linking parity (§ CloudKit epic above) touches
   `Features/Review/NoteBody.swift` — the same file live-sync Part B will edit. Do it AFTER
   live-sync lands, then run `/code-review` over the whole CloudKit sync spine (newest,
   least-battle-tested code in the repo).

Also noted: `AppTabView`'s dimmed "Highlights (soon)" tab — the P8 mock
(`Skrift_Native/SkriftDesktop/mocks/journal-retrieval.html`, drafted 2026-07-06) proposes **Journal
takes that slot** (Notes · Library · Journal · Settings); P6's Highlights feed + Daily Review later
land as sections *inside* Journal, and P6's quote cards remain a user-led design session.

## ⭐ CONTINUE HERE — stabilization DONE, next board (handoff 2026-07-10)

**Stabilization round CLOSED 2026-07-10** (all four triage items below ✅, device-verified;
builds 58/59/60 shipped same-day; phone runs **60**; sim suite 601/601; main pushed through
`30edbc6`). One session-spanning lesson is in memory `project_p0_enhancement_clobber`: the
"truncated transcript", the empty single-word searches, AND the build-53 crashes were ONE
system — the embedder cold path (OOM → relaunch → lazy-pager opens rendering raw).

**The board now (pick by Tuur's call):**
1. ⬜ **Soak-watch builds ≥59** (passive): after a day of normal use, pull devlog + crashes —
   confirm zero tokenizer-OOMs (single-flight fix) and no 0xDEAD10CC recurrence; cold-load
   lines now report duration. If OOM returns: tokenizer-load memory diet (CoreML-LLM side).
2. ⬜ **Design question (1 mock)**: "warming up…" row in the Related section — first search of
   a session shows nothing for ~40s (measured 42.5s cold load). Mock-first if picked up.
3. ⬜ **Prod CloudKit schema deploy** (§ Stz020) — deliberate prod action, Tuur-gated: deploy
   the dev schema to prod + Release app-ID registration, then one real phone↔Mac round-trip.
4. ⬜ **Desktop Review mock sign-off** (user design session) + desktop-parity device
   round-trips owed (lock-gate, OCR search, link export, vocab LWW — see DParityA/SharedKit).
5. ⬜ **Vault lens** — waits on Tuur's iCloud vault move (JOURNAL_RETRIEVAL_PLAN.md Phase 2,
   incl. title-linking design).
6. ⬜ **Parked kickoff: capture-as-note + note-editing follow-ups** — verbatim brief in memory
   `project_capture_as_note_kickoff` (user deferred 2026-07-07).
Wall printer reminder stands: after the office test print, RE-PICK the home printer.

## ✅ Post-convergence stabilization (handoff 2026-07-08 → closed 2026-07-10)

Five chats merged into main in ~24h (P8/Review+Wall · note-editing · Books/recording · SharedKit ·
desktop parity). Feature velocity was huge; convergence bugs surfaced. **NEXT CHAT = a
STABILIZATION round, not a feature lane.** Phone = iPhone 13, Dev build **57** installed (wifi
installs work: devicectl + CoreDevice, no cable). Sim suite 599/599 green.

**Triage, in order:**
1. ✅ **P0 CLOSED 2026-07-10 — NO DATA WAS EVER LOST; two real bugs found + fixed (build 58).**
   Forensics: the memo is a 6.3s recording — its RAW transcript was ALWAYS 108 chars; the "lost"
   body is Tuur's 369-char edited note, which the PHONE STORE STILL HELD INTACT (pulled over
   devicectl — NB the live SwiftData store is in the APP-GROUP container
   `group.com.skrift.mobile.dev`, not the app container, since the 06-12 App-Groups work). All
   memos scan clean. **Restore ABORTED** — the phone's copy was newer than the Mac's frozen
   mirror; running it would have rolled the note back. Mac Skrift Dev safe to launch again.
   - **Real bug A (what Tuur saw), FIXED `6724a41`:** memos opened FROM SEARCH RESULTS rendered
     the raw body and never healed — the pager's LazyHStack realizes pages during the programmatic
     scroll WITHOUT delivering appear events, so the `.task` that fetched the enhancement never ran
     (devlog-proven: zero task side-effects on sick opens; list-flow opens healed in ~200ms).
     Fix: the polish is a live per-memo `@Query` — correct on the first body eval, no appear-event
     dependency, live CloudKit updates (retired the onChange(sync.isSyncing) refetch).
     PolishedDisplayUITests + 601/601 green. ✅ DEVICE-VERIFIED build 59 (2026-07-10 13:58): Tuur
     opened the memo from active search MID-cold-load — first render `len=369`, zero raw frames.
   - **Real bug B (found en route), FIXED `56f360e`:** commitDraft wrote the dirty draft to
     whatever `polishedBinding` held at COMMIT time; the binding arrives async / drops on churn, so
     a raw-born draft COULD flush into the arriving binding (copyedit ← raw). Never fired for this
     memo but the mechanism was real — commit target now PINNED at first dirty edit
     (`markDraftDirty`), both directions regression-tested. The DEBUG `-restoreEnhancementMemo/-Body`
     launch hook stays available (unused).
2. ✅ **Semantic search CLOSED 2026-07-10 (`0778575`, build 58) — it was a COLD-LOAD STALL, not
   weak scores.** Devlog (build 57): first query of the session took 122s — cold `prepare()` (ANE
   load of the 294MB encoder + parsing the 31.8MB tokenizer.json) serialized SIX queries behind
   the index actor; they drained ~15ms each once warm and ALL scored above floor (1-word 'Try'
   0.43, 'Trying' 0.45, 'Attempt' 0.41 vs floor 0.25 — results arrived minutes late into a dead
   view). The 60s idle unload then re-paid the load on nearly every search. Fix: model held 10 min
   (unload immediately on backgrounding), warmup fires at the FIRST keystroke, cold-load duration
   now DevLogged. searchFloor untouched — the bake-off calibration stands. ✅ DEVICE-MEASURED
   builds 58/59: cold load = 42.5–43.9s from the ANE cache (the 122s on 07-08 was the uncached
   worst case). The instrumented run ALSO caught prepare() double-loading on actor reentrancy
   (warmup racing the query path → two concurrent 295MB loads) — fixed with a shared in-flight
   load task, single-load verified on 59 (`70c3714`). DESIGN QUESTION for Tuur: 42s is long
   enough that the first search of a session shows an empty Related section for ~a minute — a
   quiet "warming up…" row would make it honest (mock-first when picked up).
3. ✅ **Crashes CLOSED 2026-07-10 — logs pulled over USB (153 reports, kept on device). Four
   classes, all explained:**
   - **3× Jul-8 10:12–10:15 (build 53) — the ones Tuur reported**: `swift_abortAllocationFailure`
     OOM aborts inside the embedder's tokenizer parse (`BPETokenizer.init` / YYJSONParser over the
     31.8MB tokenizer.json), on the cooperative pool while typing searches. Same root system as
     triage item 2 — crash pid 26017 IS the devlog's sick session (crash → relaunch → lazy-pager
     opens = how the "truncation" kept being seen). The 58/59 fixes attack it directly:
     single-flight load (the reentrancy DOUBLE-load meant two concurrent parses), 10-min hold
     (fewer cold parses), first-keystroke warmup. If OOM recurs on ≥59: next step is a
     tokenizer-load memory diet (serialize parse, release intermediates) — CoreML-LLM side.
   - **1× Jul-7 18:00 (build 39) — reminder-tap assert, FIXED build 60 (`2593da3`)**: async
     UNUserNotificationCenter delegate on a nonisolated class resumed UIKit's completion on the
     cooperative pool → state-restoration snapshot ran off-main → main-thread assert. Delegate now
     @MainActor. Fix by construction; repro (lock-screen reminder tap while snapshotting) is
     impractical — watch.
   - **2× Jul-7 22:07/22:08 (build 48) — RUNNINGBOARD 0xDEAD10CC** (held DB/file lock across
     suspension), books/recording-lane era PRE-hardening; zero recurrence in builds 52–57 (Jul 8)
     after PR #10's recording hardening. WATCH: if it returns, suspect the app-group SwiftData
     store being written at suspension.
   - **1× Jul-7 14:26 (build 35)** — iOS-26 CoreAutoLayout exception inside the system
     keyboard-cursor-accessory (`_UICursorAccessoryHostView`), during the accessory-bar round;
     accessory work landed builds 36+; no recurrence. Watch-only.
   - Jetsam Jul-9: Skrift appears only as `idle-exit` (benign). Older `.diskwrites_resource`
     (Jun 14/26) + `.cpu_resource` (Jun 21) reports predate the current architecture — noted, not
     chased.
4. ⬜ Wall: Tuur's office print test → REMIND: re-pick the HOME printer after (saved printer IS
   the wall). First physical card = design round on paper.
5. ⬜ Then: vault lens (after Tuur's iCloud vault move; incl. title-linking design above),
   desktop Review mock sign-off, prod CloudKit schema deploy (still pending, § Stz020).

**KICKOFF PROMPT for the next chat:**
> Stabilization round on main (all lanes merged). Read backlog.md "⭐ CONTINUE HERE —
> post-convergence stabilization" and work the numbered triage top-down, instrument-first
> (DevLog + devicectl pulls; wifi installs OK, crash logs need USB). Start with the P0
> transcript-truncation data bug. Build numbers continue from 57; bump per device install.
> Commit per finding with explicit paths; update this backlog section as items close.

Noticed in passing (P0 forensics, 2026-07-10; NOT acted on): list-row previews render raw
`memo.transcript` (`MemosListView` transcriptSnippet) while the note detail shows the polish —
after the restore the row's first line ("Yo yo, my name is tiuri…") won't match the note body.
Pre-existing choice, cosmetic; fold into a display-consistency pass if it bothers in use.

**Bug reports (Tuur, on build 53; INSTRUMENT-FIRST — phone off-cable, diagnose from devlog next USB session):**
1. ⬜ **Semantic search intermittently finds nothing** ("I'm trying" no longer surfaces the
   testing notes; worked on earlier builds). Suspects: swallowed engine-load error (was `try?` —
   NOW LOUD: `SemanticSearch …` devlog lines log count/top-score/floor per query, FAILED on
   throw); or scores genuinely below `searchFloor` 0.25 for short queries. Repro then pull devlog.
2. ⬜ **Skrift Dev crashed a few times at random spots** (build 53, mixed usage). Pull crash logs
   next cable session (`idevicecrashreport` per pull-phone-feedback skill); suspects unknown —
   could be any lane's (builds 45–53 span recording + books + P8 work).

**Design adds (locked in conversation):**
- **Vault lens gains title-linking** (the old Backlink-Weaver idea): reading the vault yields a
  title index → transcripts can suggest/insert `[[wikilinks]]` to VAULT notes (not just
  memo↔memo). Belongs to the vault-lens chunk (JOURNAL_RETRIEVAL_PLAN.md Phase 2).
- **Then-vs-Now pair-picking (mechanics)**: for each memo of the last ~2 weeks, `related()` →
  keep hits ≥6 months older → highest-scoring pair above `relatedFloor` renders as the card
  (old + new juxtaposed). No pair clears floor+gap → no card. Cosine picks the topic, the
  time-gap guarantees the "then."
- **Office-printer guard (behavioral rule for now)**: the saved printer IS the wall — test prints
  at the office are fine, but re-pick the home printer after (or toggle auto-print off). Later
  nicety: bind auto-print to the HOME printer identity only.

## 🖨️ Print-to-wall + significance in the Journal (Tuur design session 2026-07-07 evening)

**✅ BOTH BUILT same evening (build 43 on device; 581/581 tests; sim-screenshot verified).**
`Features/Journal/WallPrinter.swift` (service + WallCardView + settings section), Important-lately
in `LookbackProvider`/`JournalHomeView`, queue row on Journal home (the in-app surface — Tuur:
notifications get dismissed), SignificanceCircles commit hook, ⋯ "Print Card". OWED on device:
pick the real printer (Settings → Wall printer), rate a note orange, watch it print; test-card
polish round on the physical print. Original design (still the spec):
1. **"Important lately" card on Journal home** — the orange-tier (≥0.8) notes of the last ~30 days,
   above the Looking-back cards. This is P6's Highlights feed taking its first slot inside Journal.
   Resurfaced UNRATED notes stay in Looking back by design: they're prune-candidates (idea i2)
   making their case — the journal is where a note earns its life (rate it → it survives).
2. **Auto-print Important notes ("the Wall")** — when a note crosses INTO the orange tier, silently
   print a designed card to the home printer. Mechanics: one-time `UIPrinterPickerController` pick
   in Settings ("Wall printer" section: printer + auto-print toggle + threshold, default 0.8) →
   `UIPrintInteractionController.printToPrinter` (NO dialog). Card = the P6 quote-card renderer on
   paper (title + polished text + date/place footer + thread first-mention line; mono-first
   typography; ImageRenderer → PDF). `printedAt` stamp = idempotent (re-rating never reprints);
   manual "Print card" in the note ⋯ menu; offline → queue + retry on foreground + "🖨 sent to the
   wall" toast. Printed notes get a 🖨 mark; later a Journal "Wall" section mirrors the physical
   wall in print order. (Mac-as-print-daemon = robustness fallback later; phone-first is
   standalone-true.) Quote-card renderer is shared with P6's shareable image cards.

## ⭐ CONTINUE HERE — desktop-parity board (written 2026-07-11 for the NEXT chat; Fable→Opus handoff)

**Read this first.** The A-list shipped 2026-07-07 (section below). What remains is three boards, all
**GATE (1) CLEARED — mock v2 ✅ SIGNED OFF 2026-07-11 (Tuur): `mocks/journal-desktop.html` IS the
spec for Boards A+B.** Gate (2) ALSO CLEARED 2026-07-13 — Tuur confirmed all lanes done; verified: no
live lane branches, board-cited files all present on main, desktop trunk build fixed (744cc0f),
FluidAudio pinned 7f963cdc. BUILD FROM CURRENT origin/main (base-proof: MemoDeduper.swift exists).
Stale-gate check for any future session: (2) check no other chat is mid-flight
before touching app code (`git worktree list` + `git branch -a --sort=-committerdate`, merge
origin/main first, work in YOUR OWN worktree branch, `git add` explicit paths only).

**Board A — B-list body parity (desktop), mock panels 3/4 are the spec:**
1. ✅ **DONE 2026-07-13 — memo-link chips + LINKED FROM.** Atomic `MemoLinkChipAttachment`
   (rides the img-marker attachment machinery — `modelString` reconstructs the literal, offset
   math generalized to variable-length attachments); click → `onOpenMemo` → AppModel selection;
   `MemoBacklinks` strip under the body (contains-scan, newest first). Demo seed grew a fixed-UUID
   link pair; NEW verification tool: `-snapshot-memolinks` renders the LIVE NSTextView editor via
   an offscreen NSHostingView + in-memory store (ImageRenderer can't) — chip + strip both
   eyeballed. GOTCHA fixed en route: `.task` on empty conditional content never fires (the strip
   kept itself empty) — keep a zero-height clear view rendered. `[[` creation picker still owed.
2. ✅ **DONE 2026-07-13 — live checklists on the Mac.** `BodyTransform` (the ONE raw⇄display token
   scan: tasks + img markers + memo-links) MOVED to `Shared/Pipeline/` first (phone re-green, 677);
   desktop `TaskBoxAttachment` renders `- [ ]`/`- [x]` as toggleable checkboxes (checked = strike +
   muted line), a click flips the box and writes the flipped syntax back through `modelString` →
   `bodyBinding` → persists + `MacCloudEditSync` push (the phone sees the toggle). Hosted-snapshot
   verified. Return-continuation stays phone-only for now.
3. ✅ **DONE 2026-07-13 — PDF/file capture card (honest variant).** The document BLOB never syncs
   (no `MemoAsset.Kind.document`), so no fake first-page render: the card shows 📄 filename +
   "PDF · on your iPhone — its text is captured in the note" (the phone's A6 extraction already put
   the text in the body the Mac shows/searches/exports). Hosted-snapshot verified. NEW follow-up
   below. BONUS: `-snapshot-capture` switched to the hosted renderer — the sidebar's yellow-🚫
   ImageRenderer placeholder is GONE (sidebar snapshots work now); `pdf:<path>` arg renders the
   file-capture fixture.
3b. ✅ **DONE 2026-07-15 (sync + Open) — `.file` capture documents sync as `MemoAsset.Kind.document`**
   (additive kind, no migration). Phone `AssetMaterializer` captures the `.file` document; Mac
   `MemoCloudIngest.buildParts` adds a `document` part; `UploadService.prepareCapture` writes it into
   `capture_<id>/files/`; the Mac capture card (`CaptureSharedContentBlock`) gains an **Open** button
   (`NSWorkspace`) when the file is present. Golden test `testFileCaptureDocumentMaterializes`; desktop
   365 + mobile 678 green. **STILL OWED (follow-ups):** (a) the mock's true first-page inline render on
   the Mac; (b) C3's Mac-wire — run `PDFTextExtract.text(of:)` on the materialized PDF as a fallback when
   `sharedContent.text` is empty; (c) vault copy of the document on export. LIVE device round-trip owed.
4. Verify: UnitTests scheme + full `-skipMacroValidation` build + `-snapshot` PNGs (see
   [[native-ui-verification]] memory: sidebar can't snapshot; live-drive via UITests if needed).

**Board B — ✅ BUILT 2026-07-13 (chunks 1–5 in one pass; device/live eyeball owed):** shared
`LookbackProvider` + `PlaceCluster` moved to `Shared/Pipeline/` FIRST (phone re-tested green — 677),
then `JournalView.swift` to the mock: switch/rail/column/map-mode, cloud-store read-only w/
`MemoDuplicates.canonicalRows`, in-flight slim row, locked = 🔒 title-only, `-snapshot-journal`
hosted verification (lookback + map states eyeballed; annotation count-bubbles want a live-deploy
look). Original spec follows:
- Chunk order: (1) `Queue | Journal` mode switch (AppModel surface enum; RootView swaps the
  content pane; sidebar per mock). (2) SHARE FIRST, then build: move the phone's pure logic to
  `Shared/Pipeline/` — `LookbackProvider` (pure date math over [Memo]; Memo is shared) and the
  `PlaceCluster` grouping inside `SkriftMobile/Features/Journal/JournalMapView.swift` — so the Mac
  compiles the SAME rules (that's the whole point; don't re-implement). (3) Rail = mini month grid
  (dot density via `LookbackProvider.dayCounts`) + Places list. (4) Column = Looking-back cards +
  selected-day list; in-flight notes = slim row, NEVER a card (review-1). (5) Map mode = SwiftUI
  `Map` (fine on macOS 14) with PlaceCluster pins; a place click swaps the COLUMN (the rail never
  changes); ⨯ returns to Looking back.
- **Data source: the Mac's journal reads the CLOUD Memo store** (`MemoCloudStore.container`), NOT
  PipelineFile — the cloud DB has the full corpus (ingest is significance-gated; sync is not).
  Locked memos: list row shows title + 🔒 only; content stays behind the existing `LockGate`.
- Respect the flag: journal is read-only — never mutate Memos from the Mac journal (the Mac's
  write path stays MemoEnhancement/edit-sync only).

**Board C — SharedKit round 2 (UNBLOCKED 2026-07-13: all lanes done, no live branches; ONE chunk
per commit, both suites green each time — the round-1 recipe):**
0. ✅ **DONE 2026-07-13 — Mac sweep duplicate-tolerant.** Shared `MemoDuplicates` keeper rule
   (alive > most content > latest edit > first; `Shared/Pipeline/MemoDuplicates.swift`);
   `MemoDeduper` refactored onto it (677 mobile tests green); the Mac sweep iterates
   `canonicalRows` (351 desktop tests green incl. the churn regression + trashed-clone-never-
   shadows-keeper). CORRECTION to the original claim: there IS no Mac delete path keyed on
   `memo.deletedAt` (MemoCloudUpdate's comment is aspirational) — so no delete-flap existed; the
   real defect was divergent same-id rows flip-flopping ONE PipelineFile every sweep. Observed
   gap left on record: a memo trashed on the phone is never trashed on the Mac (no delete sync —
   pre-existing, deliberate for now). BONUS: full-scheme desktop build was red on ANY fresh
   regenerate — swift-transformers floated to 1.3.3 (breaks vs Swift 5.9) and transitive Jinja
   floated to 2.4.0 (ObjectKey API) → BOTH exact-pinned in project.yml (1.3.0 / 2.3.6).
0b. ✅ **DONE 2026-07-15 — shared lazy-RMS helper.** `averageRMS` (+ the buffer-path `rms(of:)`)
   extracted to `Shared/Pipeline/AudioRMS.swift`; the lazy `trimmed`/`wordCount` gate folded into a
   pure `BPEMerge.shouldDropAsPhantom(text:rms:)` overload (a lazy closure keeps BPEMerge
   Foundation-only). All 3 call sites (desktop file, phone file, phone buffer) now hit the ONE copy;
   both local copies deleted. New host-less test proves the RMS provider stays lazy for real
   transcripts + fires once for tiny ones. Desktop 352 + full MLX build + mobile 677 green.
1. ✅ **DONE 2026-07-13 — SpeakerTranscript → Shared** (`Shared/Pipeline/SpeakerTranscript.swift`,
   both twins deleted): the shared Sanitiser now parses conversations through ONE type. Turn =
   Identifiable + content-only `==` (id ignored — desktop's equality tests pass, mobile's ForEach
   works). Helper union, and the drift got FIXED in the merge rule: empty-safe join (Mac's rule) +
   preamble preservation (phone's rule — the Mac's twin used to DROP a leading [[img]] preamble on
   mergeAdjacentTurns). Both suites green (351/677) + full MLX build.
2. ✅ **DONE 2026-07-15 — LockGate → Shared.** The two byte-identical twins collapsed to
   `Shared/Session/LockGate.swift` (new `Shared/Session` folder, added to both app targets);
   one `#if canImport(UIKit)` picks `UIApplication`/`NSApplication.willResignActiveNotification`;
   the id key is unified on the memo-UUID **String** (`unlockedIDs: Set<String>`, was `Set<UUID>`
   on the phone). Model-typed `isLocked` + the phone's `unlock(UUID)` live as thin per-app adapters
   (`LockGate+PipelineFile.swift` / `LockGate+Memo.swift`). Desktop 352 + MLX build + mobile 677 green.
3. ✅ **DONE 2026-07-15 (share + rewire) — PDF text-extract → Shared.** The phone's inline
   PDFKit extraction is now `Shared/Pipeline/PDFTextExtract.swift` — a pure `normalize` core
   (trim/drop-empty/120k-cap, host-tested ×3) + `text(of:)` that runs `PDFDocument`; the phone
   drainer calls it (its now-unused `import PDFKit` dropped). Desktop 355 + MLX build + mobile 677 green.
   **Mac-wire FOLDED INTO 3b (below):** the Mac has NO PDF blob today (no `MemoAsset.Kind.document`),
   so there is nothing to extract at ingest — it already receives the phone-extracted `sharedContent.text`
   via sync (A3). Once 3b materializes the document blob on the Mac, wire `PDFTextExtract.text(of:)` at
   ingest as the fallback for memos missing the phone text.
4. ✅ **DONE 2026-07-15 — VocabularyBooster trust→apply core → Shared.** The identical tail of
   both `boost()` bodies (filter shouldReplace → resolve each canonical's aliases → keep the boost
   ONLY when ≥1 applied and EVERY replacement trusted) is now `Shared/Pipeline/VocabularyBoostCore.swift`
   (neutral `VocabularyReplacement` struct; an `aliasesFor` closure keeps FluidAudio's `vocab.terms`
   app-side). The phone's `allReplacementsTrusted` deleted; both boosters map their rescore output →
   the shared core. CTC spot + rescore ENGINES and the DEBUG tuning knobs stay app-side (per the board).
   Trust test repointed to the shared core + a new `appliedReplacements` test. Desktop 355 + MLX build
   + mobile 678 green.
5. ✅ **DONE 2026-07-15 — NamesCloudSync reconcile core → Shared.** The byte-identical phone + Mac
   `run` bodies now delegate to `Shared/Naming/NamesSyncCore.reconcile` (fold carriers → `NamesMerge`
   per-canonical LWW + voiceEmbeddings union → sorted-keys byte-compare → collapse to ONE carrier row
   via injected insert/delete; returns merged + localChanged). One shared encoder so the two can't
   churn-loop. Each adapter keeps its own differences: the phone's DevLog, the Mac's
   `cloudKitMacSyncEnabled` gate + `.namesDidChangeFromSync` post. The 5 `NamesCloudSyncTests` (through
   the phone adapter) cover the shared flow — first-sync, remote merge, embedding union, idempotent,
   collapse-dupes. Desktop 355 + MLX build + mobile 678 green.
6. ⚠️ **ANALYZED 2026-07-15 — do NOT collapse yet; the leniency is load-bearing.** Concrete finding
   from comparing `PhoneMetadata`/`SharedContent` (CompilerBridge) to the shared `MemoMetadata`:
   PhoneMetadata is DELIBERATELY looser — `Weather.temperature`/`Pressure.hPa` are `Double?` (shared:
   non-optional **`Int`**), `dayPeriod`/`pressure.trend` are `String?` (shared: non-optional **enums**
   `DayPeriod`/`PressureTrend`), and `Location` reads only `placeName` (shared requires lat/long). A
   naive collapse would make the STRICT shared decoder THROW on legacy RN/Python working-folder
   payloads (float temps, unknown enum values, lat/long-less locations) → silently drop ALL export
   frontmatter for old notes. `SharedContent` likewise keeps a snake_case (`shared_content`) fallback
   for demo seeds and stays desktop-side (mobile has its own; there is no shared `SharedContent`).
   **To actually do C6:** first give the shared `MemoMetadata` a lenient `init(from:)` (float→Int
   coercion, unknown-enum→nil, optional lat/long) — a CROSS-APP contract change the phone also decodes
   through — backed by GOLDEN ingest tests over real old working-folder payloads on BOTH sides; only
   then retire PhoneMetadata. That's its own deliberate chunk, not a mechanical dedup. Left as-is for now.
7. Cheap/optional — **DONE 2026-07-15 (Tuur asked for both merged):**
   - ✅ **FlowLayout → `Shared/UI/FlowLayout.swift`** — new `Shared/UI` folder added to both app
     targets; the `SkriftShare` extension's `DesignSystem/FlowLayout.swift` path repointed to it (the
     extension listed but never used it). Both app-local copies deleted. Desktop + mobile app + Share
     extension all build; desktop 355 + mobile 678 green; chip-wrap vision-checked on the fresh desktop
     `-snapshot` (tags row `#work ×`/`#ideas ×`/`+ #rewrite`/… flows cleanly, no clip/overlap).
   - ✅ **Karaoke → ONE `Shared/Pipeline/Karaoke.swift`** — the two apps use DIFFERENT functions
     (phone `activeWordIndex` lookup; desktop `wordTimes`/`activeCount`/`normalize` alignment), so this
     is single-home consolidation, NOT a behavior change: both functions now live in one shared `Karaoke`
     enum, each app keeps calling the one it used. (see the Karaoke commit for the details.)

**🐛→✅ DEVICE-FOUND FIX 2026-07-15 — Mac photos added-on-edit now materialize.** Tuur deployed the Dev
Mac and saw a note's `[[img_001/002/003]]` rendered as LITERAL text (photos never showed, would've
missed the vault). Root cause: the Mac writes a memo's photo files only on FIRST ingest
(`MemoCloudIngest`); the phone→Mac update path (`MemoCloudUpdate`) reflected the markers/manifest but
never wrote the image files, so any photo inserted while EDITING an already-synced note was orphaned.
Fix: `Pipeline/Ingest/MemoPhotoMaterializer.swift` writes any missing photo blobs + refreshes
`image_manifest.json` each sweep for already-ingested memos (idempotent; heals already-broken notes on
next launch), wired into `MemoCloudReconciler.sweep`'s update branch (nudges `lastActivityAt` when it
heals a row `apply` didn't touch). Also extracted `PipelineFile.workingFolder` — ONE derivation now
used by the resolver (`NoteBody.imageURL`), the exporter (`VaultExporter`), and the materializer. 3 new
host tests; desktop 358 + full MLX build green. **VERIFIED on real synced data:** the launch sweep
materialized all 3 photos of the reported note (manifest + `images/photo_..._00{1,2,3}.jpg` written
12:49:49, post-launch).
- ⬜ **Minor follow-up (noted, not fixed):** export image collision when two notes share the EXACT same
  title — `convertImageMarkers` names images `<safe-title>_NNN.ext`, so same-titled notes' images
  overwrite in the vault attachments folder. Uniquify by the note stem (which the .md already uniquifies)
  rather than the raw title. Low priority.

## ⭐ Phone↔Mac intertwining — "a thing done in one happens in the other" (2026-07-15, Tuur direction)

Audit of the two sync channels (2026-07-15): **phone→Mac is rich** (transcript, metadata blob, lock,
reminder, photos, OCR); **Mac→phone is narrow** — `MemoEnhancement` carries only body/title/summary.
That asymmetry is the root of the gaps. Order chosen by Tuur: **delete sync FIRST, then widen the
Mac→phone metadata channel.**

- ✅ **DONE 2026-07-15 — Delete sync (trash + restore mirror BOTH ways).** `Memo.deletedAt` is the
  synced carrier. Phone→Mac: `MemoCloudUpdate` mirrors trash/restore onto the row, watermarked by
  `PipelineFile.syncedSourceDeletedAt` (reflects only a real change → never un-trashes a pre-existing
  Mac-local trash; heals a note the phone binned that the Mac still showed). Mac→phone:
  `MacCloudDeleteSync` writes `memo.deletedAt` on a Mac trash/restore (wired at `SidebarView` softDelete
  + `RecentlyDeletedView` restore). Re-export skips trashed rows. Permanent delete stays device-local
  (both purge from the same 14-day stamp). Also folded the 4th working-folder derivation (`DesktopTrash`)
  onto `pf.workingFolder`. Desktop 362 + MLX build + mobile 678 green; core logic unit-tested (5 tests).
  **LIVE round-trip owed** (needs both Dev apps): trash on Mac → gone on phone; trash on phone → gone on
  Mac; restore either way mirrors.
- ✅ **DONE 2026-07-15 — widen the Mac→phone channel: tags + importance.** Both are plain `Memo`
  fields that already sync, so — like delete-sync — the Mac just writes them onto the `Memo`. (a)
  phone→Mac: `MemoCloudUpdate` now reflects `memo.tags`/`memo.significance` onto `pf.tags`/
  `pf.significance` (content-based, like the rest); `MemoCloudIngest` also backfills `pf.tags = memo.tags`
  at first ingest (the Mac's derivation only fills `tagSuggestions`, so the phone's applied tags never
  appeared before). (b) Mac→phone: `App/MacCloudMetaSync.mirror` writes `memo.tags`/`memo.significance`
  from the row, wired via `.onChange(of: file.tags/significance)` on `NoteProperties` (echo-guarded —
  no-op when the memo already matches). Desktop 364 + MLX build green (2 new reflect tests). **LIVE
  round-trip owed** (needs both Dev apps): tag/importance edit on Mac → phone, and phone → Mac.
- ✅ **DONE 2026-07-15 — Mac `[[` link picker** (create memo-links on the Mac, phone parity). Typing
  `[[` in the review body (`BodyTextView` coordinator detects the two-char trigger at the caret) opens
  `MemoLinkPopover` — a search field over every other live memo (title + date subtitle, most-recent
  first; `NoteDisplayView.linkCandidates` lazily fetches, memo-UUID rows only, trashed excluded).
  Picking inserts `[[memo:UUID|Title]]` → `spliceMemoLinkChips` renders the chip → `parent.text` write
  rides the Part-B edit sync to the phone. Popover snapshot-verified (`-snapshot-linkpicker`); desktop
  364 + MLX build green. **LIVE eyeball owed**: does `[[` open it + does pick insert the chip (NSTextView
  typing isn't headless-drivable). Follow-up idea: also link to EXISTING vault notes (the Backlink-Weaver
  title index — backlog line ~539), not just Skrift memos.
- ⬜ Later gaps from the audit:
  reminder alarm on the Mac; (by-design, NOT gaps: Mac shows `[[links]]`+polish, phone shows raw; Mac
  has the LLM; Mac writes Obsidian). Open Q for a future chat: should trashing also DELETE the note's
  Obsidian `.md`? (destructive to the vault — needs Tuur's call before building.)

### 🔴 CONTINUE HERE — device-test findings 2026-07-15 (Tuur, iPhone build 76 + latest Mac Dev)

**✅ FIXED + DEVICE-CONFIRMED 2026-07-16 — the sweep read STALE memos.** Tuur re-tested: a phone edit
(importance 0.1 + tags #testy/#more tags + text + photo + a link) synced to the Mac — *"took a while to
sync but it worked."* phone→Mac is live now. Root cause found:
`reconcile()` read the cloud store via `cloud.mainContext`, and a CloudKit import writes the STORE but
does NOT refresh `mainContext`'s already-registered `Memo` objects — so the sweep saw a stale memo and
never noticed the phone's later delete/tag/edit (a first-seen memo is fresh → ingest worked; Mac writes
mutate the same context → Mac→phone worked). Fix: the sweep now reads through a fresh `ModelContext(cloud)`
(empty row cache → every fetch hits the store). Same fix applied to `NamesCloudSync`/`VocabularyCloudSync`
(same trap). Added an os.Logger line (`reconcile: ingested N, reflected M`) to confirm on the next device
pull. Desktop 365 + MLX build green. **RE-TEST on device:** phone delete/tag/importance edit → the Mac
reflects on the next sweep (refocus the Mac app to force one).

**THE HEADLINE BUG — phone→Mac sync is one-directional right now.** Tuur's words: *"whatever I do on
the Mac syncs to the phone, but what I do on the phone does NOT sync to the Mac."* Mac→phone works
(the Mac writes the shared `Memo`/`MemoEnhancement` → phone auto-mirrors via NSPersistentCloudKitContainer).
Phone→Mac does NOT reflect. The phone's changes DO reach the Mac's `memo_cloud.store` (78 memos confirmed
via sqlite), so the data arrives — but the Mac's PipelineFile never updates. **Leading hypotheses for
next session (diagnose FIRST, everything below hangs off it):** (1) the reconciler SWEEP isn't triggered
on a CloudKit import while the Mac app is already foregrounded (triggers = launch / active / CK-import —
check the CK-import trigger actually fires + `cloudKitMacSync` gate is on); (2) CloudKit Mac↔iCloud
propagation latency (the change hadn't landed in `memo_cloud.store` when checked — but Tuur tested over
several minutes); (3) a bug in `MemoCloudUpdate.apply` reflect despite green unit tests. Instrument the
sweep (does it run? does it find the memo with the new deletedAt/tags? does apply return true?).

Per-feature verdicts:
1. **Delete sync — phone→Mac ✗ / Mac→phone ✓.** Restore on Mac → back on phone ✓. Delete on phone →
   still on the Mac (not reflected) ✗.
2. **Tags — phone→Mac ✗ / Mac→phone ✓.** Mac tag add → phone gets ALL the Mac's tags ✓. Phone tag add
   AND phone tag delete → NOT reflected on the Mac ✗. Worse: a Mac tag write pushes the Mac's whole set
   down and OVERWRITES a tag the user had just deleted on the phone (the phone's deletion is lost).
3. ✅ **FIXED 2026-07-15 — Importance now editable on the Mac.** Cause confirmed:
   `SignificanceCircles(value:, enabled: file.steps.enhance == .done)` in `NoteProperties` disabled the
   control (0.5 opacity + hit-testing off) until the note was enhanced. Dropped the gate → always
   editable (phone parity + it now syncs back via MacCloudMetaSync). Device re-verify owed.
4. **Memo links `[[ ]]`:** Mac→phone ✓ (link appears on phone; clicking on either opens the SAME target).
   - (a) ✅ **FIXED — chip "Untitled" on the phone.** My live-title fix over-reached: `liveLinkTitle`
     returned `title ?? firstTranscriptLine ?? "Untitled"`, so a title-less capture/Maps note resolved
     to "Untitled" and CLOBBERED the good snapshot. Now returns nil when there's no REAL title → the chip
     keeps the snapshot (the name the link was made with). Mac `liveTitle` made symmetric.
   - (b) ✅ **FIXED — backlinks missing on the phone.** `recomputeBacklinks` scanned only `memo.transcript`,
     but a Mac-made link lives in the enhancement COPYEDIT (not the transcript). Now scans transcript +
     copyedit (new `NotesRepository.allEnhancements()`). Device re-verify owed.
   - (c) ⬜ transient "lost the link" on the Mac once (couldn't repro; 2nd try kept it). Watch for
     link-persistence flakiness — NOT fixed (unreproduced).
   - (d) ✅ **FIXED 2026-07-16 — Mac chip showed `memo_<UUID>`.** A phone-made link to a title-less
     note rendered the raw filename on the Mac: `liveTitle` used `queueTitle`, which falls back to
     `cleanFilename(filename)` (= `memo_<UUID>`). Switched to `enhancedTitle` only (the real title) →
     no enhanced title → nil → the chip keeps the snapshot (the phone's title). Device re-verify owed.

**🐛→✅ TRANSCRIPTION SLOWNESS 2026-07-16 — NOT the engine; the embedder starved the ANE.** Tuur saw
a 13s clip take ~1 min. Device log showed `embedder: cold load DONE in 117.7s` — the P8 "Related notes"
embedder (EmbeddingGemma-300M) cold-loading on the SAME Neural Engine as ASR, blocking the transcription
until it finished (transcription completed right after the embedder). Fix: `TranscriptionActivity` flag
(the transcriber raises it; `GemmaEmbedder.prepare` YIELDS its cold load while active, capped 30s so a
long book transcribe can't defer Related notes forever). The transcription engine itself is fine.
Desktop 365 + mobile 678 green. Device re-verify owed (record a clip while the embedder is cold).
5. **Photos — ✅ WORKS on device.** Materialization fix confirmed: photos render on the Mac.
6. **PDFs (3b) — ✗ not synced to the Mac.** A shared PDF shows on the phone (first-page render + text);
   the Mac doesn't get it. LIKELY because the tested PDF is an OLD capture (pre-build-76) — 3b only
   materializes a `.document` asset for captures made on the updated phone. RE-TEST with a FRESH PDF share
   before treating it as a bug.
7. **Filter/sort — parity gap (SCOPED 2026-07-15; mock-first before building).** They're different
   models: Mac (`QueueFilter` All/NeedsWork/Done + sort Newest/Oldest/Title) is review-workflow;
   phone (`MemoFilter`: place · has-photos · unsynced · date-range; `MemoSort`: added/edited/recorded/
   oldest/longest, via `SortFilterSheet`) is content-browsing. The gap on the Mac = the phone's CONTENT
   filters (place, has-photos, date-range) + the extra sorts (edited/recorded/longest). "Unsynced only"
   doesn't map to the Mac (everything there is synced). NOT a blind port — the Mac sidebar is compact, so
   where a richer filter set lives is a layout call → do a mock-first pass (which phone filters belong on
   the Mac's review context) before building.

Next-session order: A/B/C all ✅ FIXED + DEPLOYED (see above). (D) re-test 3b with a fresh PDF capture
[device — Tuur]; (E) Mac filter/sort parity [mock-first]. Then re-run the whole checklist.

### 🖼️ image-at-sentence-end reflow — ✅ BUILT + hostPNG-verified 2026-07-16 (DEVICE ROUND OWED)

**Status:** BUILT + tested + Mac-hostPNG-eyeballed. Device round on both apps is the only thing owed.
- **Shared rule:** `Shared/Pipeline/BodyTransform.swift` `snapImages(_:) -> SnapResult` (snapped display/export
  string + a raw→snapped offset map). Moves each MID-SENTENCE `[[img_NNN]]` to its sentence end as a `\n\n`
  block; boundary photos normalize in place; **idempotent**. Handles: `\n\n`-wrapped (injector) AND inline
  (Gemma-reflowed) markers, two-in-a-sentence (both blocks in order), photo-before-any-sentence (block at top),
  newline-as-terminator, and a word-merge seam guard. 10 host-less tests in `BodyTransformTests`.
- **Both renderers:** mobile `NoteBodyView.load` builds from `snappedImageBody(...)` + `applyTierStyling` maps
  name spans raw→snapped→display; desktop `BodyTextView.render` builds storage from the snapped model, the
  `updateNSView` no-op check compares `modelString` vs `snappedImageBody(text)` (idempotent, no re-render loop),
  and `suggestedRanges` maps `ambiguousNames` offsets raw→snapped. Killed the giant inline caret on the Mac.
- **Export:** `VaultExporter` snaps the compiled markdown before `convertImageMarkers`, so the `![[…]]` embed
  drops beneath the whole sentence, matching the screen. (Phone `ObsidianPublisher` doesn't embed inline photos
  yet — separate pre-existing gap, no snap needed there until it does.)
- **Design decision (honored):** display + export snap; the stored RAW keeps the marker at its recorded
  moment — UNTIL a user EDIT, when `reconstruct`/`modelString` writes the snapped form. That's safe: edited
  notes are `userEdited`-trusted and never re-injected/re-snapped, and the true moment lives in
  `imageManifest.offsetSeconds`. So "raw keeps the marker" holds for the display path (the common case).
- **Verify done:** 366 desktop UnitTests + 687 mobile SkriftMobileTests green; full MLX desktop build green;
  Mac hostPNG `-snapshot-photoblock` eyeballed (sentence whole, photo block beneath, rounded corners) — see
  `Features/Shell/Snapshot.swift` `renderPhotoBlock`. **DEVICE ROUND OWED** (both apps, build-number bump per push).

_(original brief kept below for reference)_

Tuur's #1 next build. He approved the layout via an inline before/after mock. **Ship the shared rule +
render a REAL hostPNG of the red-cup note before it goes to device.**

- **The problem:** a photo's `[[img_NNN]]` marker is pinned to the exact moment it was taken, which
  lands MID-SENTENCE. Both apps render it there — the Mac INLINE (text wraps around it + a giant
  image-height caret), the phone as a block-at-marker (still splits the sentence). Both weird.
- **APPROVED layout:** when a marker falls inside a sentence, render the sentence WHOLE, then drop the
  photo to its own **full-width block** right after it (snap to the next `.`/`!`/`?`/newline). Rounded
  corners already ship. This also kills the giant caret (photo no longer shares a line with text).
- **Contract:** ONE shared rule (extend `Shared/Pipeline/BodyTransform.swift` — it already has
  `imageBreaks`/`Piece` parsing), used by BOTH renderers AND the Obsidian export, so nothing drifts.
  The RAW text keeps the marker at its exact spot (moment fidelity); only the DISPLAY + EXPORT snap.
- **Edge cases (handle the obvious way):** photo before any sentence → block at top; two photos in one
  sentence → both blocks in order after it; always snap to the sentence end, never mid-word.
- **The hard part (why it's a real reflow, not a tweak):** the current architecture ties an image's
  DISPLAY position to its raw marker position (the Mac's `splice` inserts the attachment AT the marker;
  `modelString`/`reconstruct` maps it back by scanning). Snapping to the sentence end DECOUPLES display
  position from raw position — the reconstruct + caret/edit handling must survive that. Mac render =
  `BodyTextView` (`splice`, `spliceMemoLinkChips`, `modelString`); phone = `NoteBodyView`
  (`attributed(from:)`, `reconstruct`, `BodyTransform.pieces`).
- **Verify:** hostPNG the real note on the Mac (`-snapshot-memolinks` is the NSTextView-hosted mode; add
  an image to its seed or a new `-snapshot-photoblock` mode), eyeball, THEN device round on both apps.
  Mock-first is satisfied (design approved) — build to it.

**Device-verify checklist owed (fold into the next device session):** Mac-added vocab word →
phone (and deletion → Mac) [LWW fix 6f78ac1]; lock on phone → Mac refuses export + gates body,
unlock → auto re-export; search a photo's OCR text ON THE MAC; Mac-exported memo-link opens the
target note in Obsidian; 🔔 reminder row shows.

**Cautions for the next agent:** commit per chunk with explicit paths; regenerate xcodegen after
every pull; mobile tests = `-only-testing:SkriftMobileTests` (UI suite has known iOS-26 failures);
sim "preflight/Busy" flake → `xcrun simctl shutdown all && xcrun simctl erase "iPhone 17"`;
desktop full build REQUIRES `-skipMacroValidation`; never run two Skrift Dev instances; promote
prod deliberately (idle) only; roadmap.yaml updated in the SAME change as shipped work (exactly
one `now`); mock-first for any NEW UI beyond these signed specs.

- 🅿️ **Review note-detail mock PARKED** (Tuur, 2026-07-18): `mocks/review-note-detail.html` — the
  read-only detail + "Process on this Mac" fix for the purple "Not in the queue" dead-end. Parked
  because the Fading lifecycle ATE most of its audience (untouched old notes — the alert's main
  source — now drain themselves out of Review). REVIVE TRIGGER: the alert annoys again in practice
  (clicking a <30d untouched note, or a touched-but-unflagged note — those still dead-end). Mock is
  sign-off-shaped; build as drawn when revived. Its 2 open Qs ride the revival.

### ⭐ CONTINUE HERE — session end 2026-07-18 ~2am (the wave-2 + lifecycle marathon chat)
**Everything committed + PUSHED; both Dev apps at HEAD (Mac redeployed · phone b85).**
- ✅ THIS CHAT: SharedKit wave 2 complete (6 extractions, 3 drift bugs fixed, 2 dead-code deletes) ·
  Review label single-sourced · phone note-swipe off · map camera/dive/in-frame round · rail
  mini-map (mock→picked→shipped) · **FADING LIFECYCLE end-to-end** (design→mock v3→shipped
  cross-app→3 device fix rounds: auto timers, un-squared ⋯ dot, unread-dot semantics).
- 🅿️ PARKED: review-note-detail mock (below, revive trigger inside) · vault-read direction (🔭
  below, Huginn-shaped) · 6 Palette DriftedPair reconciles (one eyeball round → one-liners).
- ⬜ TUUR'S EYES (casual, no chat needed): fading round (dot→shelf→dark, Keep, sweep-all, phone↔Mac
  convergence) · the b81-era carried items (Journal gate arc %/PREPARING/N-of-M, ~2s search
  highlight, ⌥⌘C/badge/hover-✕/tooltip, light-mode fills) · map dive re-wiggle.

### 🍂 NOTE LIFECYCLE — "Fading" auto-cleanup · DESIGN LOCKED 2026-07-17 (Tuur + chat session), mock round next
**The rule: a note you never invested in fades out by itself; anything you touched stays until you say otherwise.**
- **Touch-list (LOCKED — any of these = never fades):** significance > 0 · transcriptUserEdited ·
  title set · manual tags · locked · remindAt · typed capture annotation · linked-to by another note
  ([[memo:]] backlink, scanned at sweep time) · keptAt (rescued). Explicitly NOT touches (Tuur):
  photos attached, bare share-captures. Guards: in-flight + already-trashed excluded.
- **Timers (LOCKED "for now"): 30 → 30 → 14.** Untouched 30d → Fading shelf (leaves river/day/map/
  search defaults); 30d more → auto-move to Recently Deleted (existing deletedAt); existing 14d purge
  ends it. Every stage visible + one-tap rescue; rescue sets keptAt (permanent).
- **Sync shape:** fading is DERIVED (no stored state, no migration, retroactive for free); ONE new
  additive synced field `keptAt: Date?`; the 60d sweep just sets `deletedAt` (already syncs/restores/
  purges; idempotent per device). Shared rule module (`MemoLifecycle.isFading(...)` in Shared/) —
  phone + Mac filter through ONE copy, tests both suites.
- **First-run guard (P0-trauma rule):** the inaugural sweep NEVER auto-trashes — everything eligible
  lands visible on the shelf with an explicit "sweep now?" prompt; timers only run after that.
- **Placement input (Tuur):** phone Recently Deleted's scroll-to-bottom spot is BAD ("stupid
  position"); Mac's bottom placement is fine. The Fading shelf must not inherit the bad spot — fix
  Recently Deleted's phone placement in the same mock round.
- 🎨 MOCK ROUND OPEN: `mocks/fading-shelf.html` — Mac shelf (column swap; rail row paired with
  Recently Deleted at the rail bottom, count-badged, hidden when empty), first-run sweep prompt,
  Keep-only actions, countdown colors; phone v3 PICKED (v1 chips + v2
  Review-stack row both rejected — vertical space): behind a ⋯ in the Notes header actions
  cluster, amber dot when something's fading, both shelves as menu items; Notes loses its old
  bottom Recently Deleted row. Remaining open Q: search "include fading" toggle (recommend SKIP).
  ✅ SIGNED OFF ("good!") + BUILT SAME SESSION 2026-07-18 — see FEATURES.md "Fading lifecycle" row:
  Shared MemoLifecycle (+keptAt) · phone ⋯/shelf/sweep (b83) · Mac shelves + sweep. Search toggle
  SKIPPED per recommendation. 📱 b83 round findings, FIXED same hour (b84 + Mac redeployed):
  (1) the ⋯ amber dot rendered SQUARE sometimes — an out-of-bounds overlay offset gets mangled by
  the menu-source preview snapshot; dot now lives INSIDE the label frame (+compositingGroup). Menu
  open latency = system Menu behavior, not tunable — revisit as Button+sheet only if it keeps
  annoying. (2) "Start the timers" arming gate CUT on Tuur's call ("why is it not automatic?") —
  sweeps are fully automatic from install; the 14d reversible trash + shelf counts + the dot are
  the safety; "Sweep all now" stays as a plain shelf action both apps. Mock's first-run section is
  now historical. (b84 round) Tuur: "is the dot always there?" — it was (steady 30-60d trickle = permanently lit =
  no signal). b85: UNREAD semantics — the ⋯ dot lights only for notes that ENTERED fading since the
  shelf was last opened (shared `fadeEntersAt` + per-device lastSeen stamp; opening the shelf clears
  it). ⬜ re-eyeball: dot lights fresh → opens shelf → goes dark; Keep; sweep-all; cross-device
  convergence.

### 🔭 PARKED DIRECTION — read the Obsidian vault INTO the app (Tuur, 2026-07-17)
Use vault content (hand-written notes) for linking/Connections/Related, maybe Review. Constraints +
sketch from the chat think-pass: app's-own-code scans only, on-device models only (the privacy rule
allows exactly this — no cloud AI ever); NEW separate consent ("index my vault" ≠ journal consent);
Mac-first (the phone has no vault; embeddings never sync by design); the indexer MUST dedupe/exclude
Skrift's own published exports or every note matches its own export (frontmatter/stem identifies
them); vault-note identity across renames + FSEvents change-watching are the hard bits; start with
Connections/Related + search rows (surface exists), Review-resurfacing of vault notes = later/maybe.
Aligns with the standing "push / pull-for-search" model. Roadmap node = a Huginn conversation.

### 📱 Live round findings — 2026-07-16 night (Tuur, Mac Dev @ HEAD + phone build 82) — ALL FIXED SAME SESSION
- ✅ **Mac still said "Journal"** (sidebar pill + column header) while the phone says "Review" —
  the label had forked AGAIN (the 2026-07-07 rename only landed on the phone). Fixed by
  single-sourcing: `Shared/UI/SharedCopy.reviewTitle` now feeds the phone tab + screen title AND
  the Mac pill + header (5 sites, zero literals left). Snapshot-verified on the Mac fixture.
- ✅ **Swipe-between-notes OFF** (phone) — horizontal page-swipes fought text editing (Tuur).
  `.scrollDisabled(true)` on the detail pager; structure kept — memo-link hops + initial jump
  still work programmatically. Deployed in build 82.
- ✅ **Map glitchiness (Tuur report) — 3 bugs found by code-read, all fixed**: (1) `Map` had NO
  camera binding → automatic framing re-fit ALL pins on every span-driven re-cluster, snapping the
  view back mid-gesture (THE glitch; mechanism-certain, feel-verify on next wiggle); (2) clicking a
  place row while in map mode never moved the camera → now `focus()` flies to the place (0.3°
  span); (3) selection highlight vanished when zoom-out merged pins (compound "a+b" ids vs exact
  match) → id-component matching. Suites + MLX green, Dev redeployed.
- ✅ **Rail mini-map SHIPPED** (mock `review-minimap.html` #m1 — Tuur picked A 2026-07-17): ambient
  `MKMapSnapshotter` shot in the rail under PLACES (static — no live Map idling), fitted to ALL pins
  via new shared `PlaceCluster.fitRegion` (3 tests), same merged clusters drawn on top (+N badges),
  POIs excluded, "click → full map" → map mode fitted to every pin, no place pre-selected; hidden
  when nothing located; river untouched. Fixture vision-checked (real Lisbon tiles + pins); Dev
  redeployed. ✅ click-through eyeballed by Tuur 2026-07-17 → 2 findings, FIXED same hour:
  (1) fit-all entry showed NOTHING below the map (selectedPlace nil) → now lists ALL located notes
  newest-first, narrowing on pin/place pick; (2) rapid zoom in/out stuttered → clusters cached per
  refresh (build() was in every body eval) + span commits only on >20% zoom change (each commit
  tears down every annotation). Round 3 (same night): "All places" → **IN-FRAME list** (map = the filter, Tuur's intuited model:
  pan/zoom refines the notes below; fit-all entry starts with everything); **pin tap = DIVE** (flies
  down to split a merged pin — the fast path for deep zoom, scroll speed isn't tunable; tap the
  selected pin again = back to frame mode); rail place click dives city-level too (was regional 0.3°).
  ⬜ re-wiggle owed.
- ℹ️ **Map on the Mac: already BUILT** (journal-desktop mock v2 shipped with the Journal lane) —
  click a place row under PLACES to swap the reading column for the map; clicking a calendar day
  swaps back. Not a gap, just undiscovered.

### 🕸️ CONTINUE HERE — Connections SHIPPED (2026-07-16); 🧭 SharedKit wave 2 SHIPPED same evening (all 6 ranked items ✅ below + 2 clone-mode items; i10/MemoSaver items fold into their own lanes); STILL OWED: Tuur's Dev eyeball round (Dev at /Applications is ~10 commits behind — redeploy first: build → pkill → ditto → open), the phone device round (blocked on iPhone attached), and the 6 Palette DriftedPair reconciles (one eyeball round, then each collapse is a one-liner)

**2026-07-20 (panel polish chat):** Tuur's eyeball caught the panel's hot borders — root cause:
`Theme.hairline` (pure white) used at 0.25–0.6 where house/mock = 0.02–0.08; fixed (606dd35,
before/after snapshot-verified). Same session: **top-K cap** — Mac showed EVERY ≥0.45 match
(phone caps at 4; unbounded at corpus scale) → new `RetrievalTuning.cappedRelated` (shared,
unit-tested): closest `relatedKMac`=7 shown, the genuinely EARLIEST match always swapped in so
the Date rail's FIRST MENTION can't lie, "Show all N" expander (per-note reset), Closest
subtitle → "showing 7 of N" when capped. Dev at /Applications redeployed this session.

**SESSION-END STATE (2026-07-16 eve — all committed, main @ 522cae5, 31 local/unpushed):**
- ✅ VERIFIED this session: shared index+embedder+gate (both unit suites green per chunk: 372 desktop /
  687 phone); full MLX desktop builds green; panel hostPNG fixture vision-checked; Tuur's LIVE Dev round:
  download→PREPARING→indexing→panel all work on the real 19-note Dev corpus; amber warm-text eyeballed.
- 🌓 BUILT, NOT YET EYEBALLED: the ~2s lingering search-highlight (582cdfd — flash-too-fast fix,
  deployed, one look owed); ⌥⌘C/badge/hover-✕/tooltip on real corpus; light-mode amber fill on Mac.
- ⛔ BLOCKED on iPhone attached: the phone device round — upgraded Journal gate (real % + PREPARING +
  N-of-M, sim-compiled only), phone light-mode warm fill, panel↔phone cross-checks.
- Next chat's HEAVY work = **🧭 SharedKit wave 2** (list below, ranked; SharedContent first) — the
  scanning/triage is DONE, only the fixing remains; tree is clean, tool = `python3 tools/twin-scan.py`
  (+ `--clones`).

### (history) Mac Connections panel: ✅ MOCK SIGNED OFF 2026-07-16 ("oke im down!") → BUILT same day

**THE SPEC = `mocks/related-panel.html` v3** (3 review rounds, all picks in the mock's decisions block):
one panel + Date⇄Closest pill · P1 importance decimals (warm ≥0.8, unrated = nothing) · closeness =
hover tooltip "58% match · shares: …" (raw cosine ×100, %-format, NEVER ambient) · hover ✕ "not related"
per-note hide · in-panel consent gate (295 MB EmbeddingGemma, one consent also unlocks Mac Journal
search) · collapsible w/ count badge ⌥⌘C · REPLACES the bottom LINKED FROM strip · #m6 polish parked.
**Build phases:** (1) ✅ DONE 2026-07-16 (chunks A/B/C, suites green each): index core →
`Shared/Retrieval` (be75213); GemmaEmbedder + TranscriptionActivity shared, Mac binds the SAME
CoreML-LLM EmbeddingGemma — deployment 15.0, model cache `~/Library/Application Support/Skrift/
EmbeddingModels` shared dev+prod (5f5df0d); `ConnectionsIndexService` (consent key = phone's
`journalIndexEnabled`, REAL download progress via the package's onProgress, sweep N-of-M progress,
PipelineFile→MemoSnapshot with metadata `recordedAt` as the thread axis, sweeps ride reconcile+runs,
Mac raises the shared ANE-yield flag around engine work).
(2) ✅ BUILT 2026-07-16 — `ConnectionsPanel.swift` (pure `ConnectionsPanelBody` + live wrapper +
`ConnectionsModel`): Date⇄Closest pill, rail w/ this-note card + FIRST MENTION/CLOSEST MATCH flags,
flat closest rows w/ hover-✕ hide (per-note defaults list), P1 importance decimals (warm ≥0.8, unrated
= nothing), why-chips (people ∩ via [[wikilinks]], tags ∩, shared ≥5-char terms), closeness = `.help`
tooltip "N% match · shares: …", in-panel gate → REAL download % → indexing N-of-M → empty, LINKED FROM
moved in (bottom strip DELETED from NoteDisplayView), collapse ⌥⌘C + count badge (app-wide AppStorage).
hostPNG fixture mode `-snapshot-connections` (4 states) — vision-checked, 2 rounds (count-chip contrast,
CTA/progress offscreen-render fixes). DEVIATION from mock, deliberate: backlinks render below the gate
even pre-consent — consent must not cost the old LINKED FROM strip.
(3) 🌓 LIVE ROUND STARTED 2026-07-16 (Tuur, Dev app): download→index→panel flow WORKS end-to-end
(19-note Dev corpus). FIRST FINDING fixed same hour: after 295/295 MB the CoreML compile/ANE load ran
with the bar looking FROZEN → new `.preparing` state ("Compiling for the Neural Engine…"), plus
`.finding` ("Finding connections…") so a cold engine on a first query never shows a false "No
connections yet". Mock synced (#m4 preparing close-up). SECOND FINDING fixed: warm circle FILL in
LIGHT mode = dirty brown (the accent+amber mix on white) → light shows plain amber, dark keeps the
mix — BOTH apps. ⬜ rest of the eyeball: rows on real notes, pill, hover-✕, tooltip, ⌥⌘C/badge.
⬜ then the phone round. ⬜ FEATURES.md row + roadmap tick owed — BLOCKED on the other session's
uncommitted edits; fold in when they land.

**NEXT CHUNK (Tuur's live-round Qs, 2026-07-16):**
- ⬜ **Shared `RetrievalGate` core** (Shared/Retrieval): the state machine gate/downloading/preparing/
  indexing/finding/ready + the user-facing copy strings, ONE source; Mac panel re-renders from it and
  the **phone's Journal gate adopts it** — real download % (the `GemmaEmbedder.downloadProgress` hook
  exists, phone shows an indeterminate spinner today), PREPARING during the ~2-min A15 ANE compile
  (today the spinner sits frozen across download AND compile — worse than the Mac's bug), sweep N-of-M
  (shared `sweep(onProgress:)` exists).
- ⬜ **Mac search-jump parity (VERIFIED GAP)**: Mac search filters the sidebar (incl. photo-OCR text ✓)
  but opening a result lands at the TOP of the note — no scroll-to-match + flash like the phone. Needs
  an NSTextView ranged scroll + temporary highlight in BodyTextView; device-eyeball verify (hostPNG
  can't capture the flash).
- ✅ **DECIDED (2026-07-16, v1)**: the hover-✕ hide list stays **per-device** — consistent with the
  per-device index (the pairing it hides only exists in THIS device's ranking), and syncing it would
  grow the CloudKit contract (the spine) for marginal value. Revisit only if device use shows it
  annoying in practice.
- ⬜ (small, from Tuur's Q) **photo-OCR search edges on the Mac**: search MATCHES OCR text of synced
  memos (`imageOCRText` mirror ✓, phone runs the OCR), but (a) Mac-local ingests never get OCR'd (no
  Mac-side indexer), and (b) an OCR-only match can't flash in the body (the text isn't there) — could
  scroll to the matching `[[img_N]]` attachment instead.
Suites green per chunk, ledgers same commit.

## 🧭 SharedKit wave 2 — twin-scan triage (2026-07-16, tool: `python3 tools/twin-scan.py`)

First run: 13 file twins · 21 type twins · 40 string twins. Deliberate twins (no action): parity
test files both suites; NamesCloudSync/VocabularyCloudSync thin adapters (cores shared 2026-07);
RootView/SettingsView/RecentlyDeletedView/NoteBody = per-platform surfaces (rules already shared).
**Extraction candidates, ranked:**
- ✅ **SharedContent** — DONE 2026-07-16: ONE typed struct `Shared/Model/SharedContent.swift` (enum
  `ShareContentType` both sides; desktop consumers flipped string→enum; SkriftShare target repointed).
  Goldens FIRST (`SharedContentParityTests`, both suites) — which caught that the desktop's snake_case
  `shared_content` fallback was DEAD code (wrapper decode always succeeds → fallback unreachable, no
  producer since the RN era): deleted, camelCase pinned as the contract; unknown `type` → nil (no
  junk-typed records). Desktop 376 + mobile 691 + full MLX build green.
- ✅ **AppPaths** — DONE 2026-07-16: the name was declared per-app with DIFFERENT members (the
  worst twin class — a shared file referencing it would silently bind either). Now ONE
  `Shared/Model/AppPaths.swift` with `#if os(iOS)`/`#if os(macOS)` sections (LockGate pattern);
  `names.json` literal hoisted to one `namesFileName` constant. Suites + MLX build green.
- ✅ **Theme palette values** — DONE 2026-07-16: `Shared/UI/Palette.swift` = ONE hex table; both
  Themes keep their dyn wrappers but source cross-app tokens from it (agreed: surface/accent/green/
  amber/red/nameLinked). **FOUND 6 already-drifted tokens** (light columns tuned twice): bg,
  textPrimary/Secondary/Tertiary, nameSuggest, nameSuggestLine — kept per-app as explicit
  `DriftedPair`s so ZERO pixels changed (desktop PROVEN: 6 snapshot fixtures byte-identical
  pre/post; deterministic renderer control). ⬜ RECONCILE the 6 DriftedPairs after an eyeball
  round (each collapse = a one-line change now). Suites + MLX build green.
- ✅ **TranscriptionService/TranscriptionResult + DiarizationService/DiarizationOutput/Diarizing** —
  DONE 2026-07-16: contracts + pure passes → `Shared/Pipeline/{TranscribingContract,DiarizingContract}.swift`
  (TranscriptionResult, ONE `Transcribing` protocol — mobile's `Transcriber` renamed, buffer path a
  requirement w/ spill-to-WAV default; DiarizationOutput + unified `Diarizing` w/ `targetSpeakers`;
  SpeakerAudio clip+window constants; SpeakerIdentification identify/clusterToTarget behind an embed
  closure; SpeakerClustering moved to Shared). FluidAudio bindings stay per-app in the engine layer.
  BONUS: the Mac engine now honors `targetSpeakers` (force-to-N was phone-only) — substrate for the
  "per-note Split speakers on Mac" fast-follow (FEATURES row 29), UI still owed.
- ✅ **NamesStore** — DONE 2026-07-16: ONE `Shared/Naming/NamesStore.swift` (the twins' load/save/
  livePeople/addVoiceEmbedding were already line-identical; desktop's writeWithSmartBumps/
  upsert(replacing:)/seedRoster/prune are now the one superset + the phone's convenience upsert kept).
  Phone editor now saves through `upsert(_:replacing:)` — same path as the Mac (rename keeps
  enrollment via replace, no tombstone+re-attach dance). Semantics note: delete now tombstones
  WITHOUT voiceprints on both apps (was: phone kept them on the tombstone) — deleted people don't
  carry voices, matching what LWW sync already made effective. Phone additionally GAINS (inert,
  unwired): seedRoster + pruneOldTombstones (the phone never pruned tombstones).
- ⬜ VocabularyBooster.boost() cores + SpeakerTranscript — already tracked above (SharedKit wave 1
  follow-ups), confirmed by the scan.

**`--clones` mode (added same day — normalized-token shingles, catches RENAMED/adapted copies):**
- ✅ **PersonEditorView ↔ PersonEditor** — DONE 2026-07-16: editing SEMANTICS → one
  `Shared/Naming/PersonEditCore.swift` (materialise/displayShort/aliasDemo/isEnrolled; 9 tests both
  suites); chrome stays per-platform. THREE behavior drifts fixed by the unification: (1) phone
  RENAME dropped the voice enrollment (tombstone + fresh upsert) — now carries + re-attaches
  voiceprints (the Mac's rule); (2) Mac allowed saving a person with NO alias (who never links) —
  now defaults alias to the name (the phone's rule) + case-insensitive de-dupe; (3) the alias demo
  line bolded different things (Mac: full canonical, phone: short display) — unified on short
  display, which now agrees with the [[Full|Short]] help line under it (Mac fixture vision-checked).
- ⬜ **NoteBodyView ↔ BodyTextView** (14) — the body renderers' shared logic; = the i10 premise,
  fold into i10 rather than a separate job.
- ✅ **SpeakerVoiceStore ↔ DiarizationService** — RESOLVED 2026-07-16 by DELETION: SpeakerVoiceStore
  (per-person PCM samples for Sortformer enrollment) had ZERO callers — dead since the identity pivot
  to embedding-cosine (`Person.voiceEmbeddings` + VoiceMatcher). Removed; git history keeps it. Any
  old `recordings/voices/` dirs on devices are orphaned bytes, harmless. The clip-math overlap it was
  flagged for is now the one shared `SpeakerAudio.clip`.
- ⬜ **MemoSaver ↔ IngestService** (10) — the two ingest paths share adapted logic.
- (Scores ≤9 vs SidebarView etc. = generic SwiftUI patterns — noise, no action.)

**MOCK ROUND 2 history (Tuur's round-1 feedback folded in):**
- **A/B variants are DEAD → ONE panel + a Date ⇄ Closest sort pill** (Tuur's call: single click, exactly
  two orders, no click-then-select; same pill idiom as Queue|Review so it self-teaches). #m1 = Date mode
  (the arc: rail + line, first-mention sub-line); #m2 = Closest mode (flat best-first rows; hover swaps a
  row's date for **✕ "not related"** = per-note hide — the weird-embedder-match remedy, v1 hide-only,
  on top of the 0.45 floor).
- **⚠️ ROUND-3 CORRECTION — the O1 "3-circle" pick is VOID.** The mock had drawn importance as 3 circles
  (fiction cribbed from an old journal mock); Tuur flagged the mismatch repeatedly and finally
  screenshotted the app. REAL control = shared `SignificanceScale` (10 steps, 0–1 on a 0.1 grid, tiers
  Passing/Useful/Important, **0.8 refine wall** + flame tag, nil = Not rated; gates phone→Mac sync).
  Mock v3: reading column redrawn FROM SOURCE (NoteProperties + SignificanceCircles); row echo options
  rebuilt honestly — **P1 PICKED (Tuur, same session)**: the control's own decimal readout, warm past the
  0.8 wall; unrated rows show nothing (no fake 0.0). Lesson memorized: `feedback_mock_as_is_from_source`.
  SEMANTICS: rows echo USER-set importance; embedder closeness = Closest-mode ordering + CLOSEST MATCH
  flag + **hover tooltip "58% match · shares: …" (Tuur-approved: tooltip only, never ambient; % format
  vs importance's 0.x so the two numbers can't be confused).**
- **#m4** consent gate in-panel (phone Journal-gate copy, 295 MB EmbeddingGemma, same consent unlocks Mac
  Journal search) + downloading/indexing/no-connections; **#m5** collapsed w/ count badge (⌥⌘C) — both
  states Tuur-liked in round 1.
- Panel REPLACES the bottom LINKED FROM strip; local per-device index; sidebar label Journal→"Review"
  (phone-tab parity — memory `feedback_shared_code_first`).
AFTER sign-off → build phases below (embedder binding → shared index port → panel UI).

**Main-column polish proposal (2026-07-16 — NOT this feature's scope; now an explicit boxed proposal =
mock #m6, no longer drawn as if real):** ⬜ ① tags move UP under the context chips (today: bottom of the
properties card) — Tuur liked; ⬜ ② importance control one size down (10px circles, drop the tier caption
row; today's full-size row IS the signed-off significance-circles spec — this is a feel question, "might
be a little too big", not a bug); ⬜ ③ icons on the context chips (code already passes a symbol per chip —
`MacContextChip(systemImage:)` — but Tuur's chips render without; check why + turn on) — Tuur liked.

Tuur picked the direction (AskUserQuestion, this session): **connections side-panel + thread-as-timeline +
why-related chips** — unlinked mentions = later idea. MOCK-FIRST (locked process): no code until an HTML
mock in `Skrift_Native/SkriftDesktop/mocks/` is signed off; the approved mock IS the spec. Vision-check
mocks via the WKWebView snapshot script (no Chrome on this Mac — memory `reference_mock_vision_check`).

**Investigation facts (verified this session — reuse, don't re-derive):**
- Phone P8 (shipped): `JournalIndexService` sweeps memos → `EmbeddingIndex` (vectors from `GemmaEmbedder`,
  gated on Journal-index consent + model download). Related card = top-K neighbours over
  `RetrievalTuning.relatedFloor`/`relatedK`; thread = `threadOrder` (same scores, OLDEST-first, "the arc
  of this idea") + first-mention date. UI in `MemoDetailView.relatedSection` (~L917) + thread sheet.
- ALREADY SHARED: `Shared/Retrieval/` — `EmbeddingEngine` protocol, `RetrievalMath` (cosine), `MemoGist`
  (gist compose/chunk/textHash). NOT shared: the embedder binding + the index store (phone-local).
- Mac: NO embedder/index/UI today — but the Mac already runs MLX natively (Gemma enhancement), so the same
  embedding model runs there. Each device builds its OWN LOCAL index (embeddings never sync — private by
  construction, zero CloudKit contract change).

**Design brief for the mock (the three locked powers):**
1. **Connections side-panel** — persistent right-hand pane on the review surface: Related + backlinks
   (LINKED FROM) + thread entry in ONE place (Obsidian panel idiom; the phone stacks them under the body).
2. **Thread as a real timeline** — the arc rendered as a dated rail (importance dots, current note
   highlighted, click to hop) — not a sheet list.
3. **Why-related chips** — each related row shows WHAT connects it (shared people / tags / gist terms).
   Needs a cheap explanation heuristic (overlap of MemoGist terms + people + tags) — design the UI first,
   the heuristic can be dumb v1.
Design questions the mock must answer: does the panel collapse? does it replace the bottom LINKED FROM
strip (yes, presumably)? what does an EMPTY state look like (index not built / model not downloaded — the
Mac needs its own consent/download flow mirroring the phone's Journal gate)?

**Build phases AFTER sign-off:** (1) Mac embedder binding (mlx-swift, same model, download+consent) +
`EmbeddingIndex` port over `PipelineFile`s (much of the phone index should move to `Shared/Retrieval` —
same anti-drift move as BodyMarkdown); (2) panel UI + timeline + chips; (3) device/hostPNG verify rounds.
Rules: suites green per chunk, commit explicit paths, ledgers same commit, hostPNG any NSTextView surface.

## ⭐ Desktop parity A-list — the Mac catches up to the phone waves (2026-07-07, roadmap `DParityA`)

**2026-07-16 parity batch (from a phone/Mac screenshot compare — built + verified, device round owed):**
- ✅ **Context chips on the Mac**: place · weather · daypart chips now render under the title
  (`NoteProperties.contextChipRow` + `MacContextChip`; `PipelineFile.contextChips` decodes the synced TYPED
  metadata via `PhoneMetadata`). ROOT CAUSE fixed: the old properties row read demo-only `phone_location`
  keys, so REAL synced memos showed no location/weather and never showed daypart at all. `DayPeriod.symbol`/
  `.label` moved to the SHARED model. hostPNG-verified (Amsterdam · 14° · Morning).
- ✅ **Mac tag-adding — redesigned to a TYPEAHEAD (design #1, user-picked)**: first cut showed the library
  as a chip WALL (Tuur: doesn't scale past a handful; "tag, tag" placeholder weird) → now "+ add tag" opens
  an AUTO-FOCUSED field (device finding: it needed a 2nd click; Esc closes) and typing shows a dropdown of
  prefix-matching tags (most-used first, capped) + a "Create #x" row. Deterministic `tagSuggestions` rank
  first + show as ≤4 quick chips only while the field is open + empty. Return commits, comma-splits via the
  shared `Memo.parseTagInput`. hostPNG'd (`-snapshot-tags`).
- ✅ **Editing-next-to-a-snapped-photo re-render bug (device-found)**: typing after a photo re-rendered the
  whole body EVERY keystroke (photo flashed, typed text jumped before the image) — the reflow's snapped-only
  no-op check misfired because a mid-edit reconstruct isn't snap-stable. `BodyTextView.updateNSView` now
  re-renders only when `modelString` differs from BOTH the raw binding AND its snapped form. Device-confirmed
  fixed (flashing gone).
- ✅ **Inline `#tags` in the Mac body (Obsidian idiom — user-picked after the typeahead), ROUND 2**:
  typing `#word` opens a caret-anchored menu of matching tags. **Round 1 was buggy on device (Tuur: slow,
  typed text vanished, backspace dead, popup churn)** — root cause: it drove NSTextView's BUILT-IN
  completion session with its preview-inserts suppressed; the session's internal bookkeeping desynced and
  consumed keystrokes, plus a full-library fetch ran per keystroke. **Rebuilt the way Obsidian/Xcode do
  it**: a PASSIVE non-activating child panel (`TagSuggestPanel`) that never takes key and never touches the
  text path — typing/backspace/clicks stay fully native; only ↑ ↓ Return Esc are intercepted (`doCommandBy`)
  while it's up; candidates cached once per `#`-run. Accepting inserts the tag inline AND files it → tags
  row → frontmatter ("inline tags copy to the YAML"). Inline `#tag` runs render accent. Pure core =
  `Pipeline/Tags/TagComplete.swift` (Obsidian rules; `TagCompleteTests`), one `TagLibrary` source with the
  field. Device re-eyeball owed.
  **ROUND 3 (Obsidian-parity, Tuur's screenshot ask "just the way Obsidian works"):** a BARE `#` now opens
  the FULL library list immediately (browse; scrolls past 11 rows; keyboard selection stays in view; cap 50
  most-used); typing narrows; the space of a `# ` heading breaks the run so the menu steps aside. PLUS
  **markdown headings render as titles** in the Mac body: `# ` H1 / `## ` H2 / `### +` H3 tier, marks dim
  (turn-header treatment), characters verbatim → the export stays plain markdown. Device re-eyeball owed.
  **Shared-core extraction done same day (Tuur: "make sure the last edit is shared")**: the RULES now live
  in `Shared/Pipeline/BodyMarkdown.swift` (headings + inline-tag detection, host-tested) and
  `Shared/Pipeline/TagComplete.swift` (moved from desktop Pipeline/Tags) — the Mac consumes them; the phone
  compiles them (renderer wiring = i10).
  ⬜ **PINNED (roadmap idea i10, Tuur 2026-07-16 — "not critical to our path")**: Obsidian-grade markdown
  body — bold/italic/==highlight==/strike on BOTH apps by extending `BodyMarkdown` (font-trait merge for
  nesting), dim-visible marks (NEVER Obsidian's vanish-off-caret-line — offset-math trap, phone-hostile),
  phone heading/#tag rendering + inline-# popup, ⌘B/⌘I Mac + accessory B/i/🖍 phone. ~2-3 sessions.
  ⬜ follow-up: move `TagMatcher` → `Shared/` and run the deterministic tag step on the PHONE against its
  synced tag list (Tuur 2026-07-16).
- ⬜ **NEXT — Mac Related notes + thread (DEFERRED to a design pass):** the phone shows a RELATED section
  (✨ embedding-suggested notes) + "View thread"; the Mac shows only LINKED FROM. Tuur wants this on the Mac
  but it "can be MORE POWERFUL on the Mac" → needs a features + UI thinking/mock session FIRST (mock-first),
  not a straight port. Check whether the P8 related-notes embedder data is already available Mac-side.
- Note: phone→Obsidian publish still doesn't embed inline photos (comment left in `ObsidianPublisher.swift`);
  by design we export to Obsidian from the MAC only for now — revisit under the standalone push.

The contract-level "musts" from the parity analysis (memory `project_desktop_parity_plan`), built same-day:
- ✅ **Locked notes**: `PipelineFile.locked` mirror (ingest + update sweep), `VaultExporter` REFUSES export
  (typed error surfaces in the toast; auto re-export sweep skips locked and re-exports on unlock), note
  body + sidebar Copy gated behind Touch ID/password per session (desktop `LockGate`, deactivate
  re-locks), 🔒 properties row. The plaintext-vault promise now holds with the Mac on.
- ✅ **Memo-link precise resolver**: `Compiler.compile(file:)` supplies the whole queue's stems
  (`MemoLinkStems` over `VaultExporter.noteStem` — ONE derivation with the exported filename);
  zero-cost for notes without links. Body chip rendering + backlinks UI = mock round.
- ✅ **Photo-OCR search**: `imageOCRText` flat mirror (kept fresh when the phone's indexer lands late —
  the update sweep now refreshes the metadata blob + recompiles on change, fixing stale book fields too);
  `matchesSearch` matches it.
- 🌓 **remindAt**: mirrors + shows in properties (🔔); Mac-side alarm reconciler still owed.
- Device round-trip owed for the batch (lock on phone → Mac gate; OCR search on Mac; link export).

## ⭐ Shared-code dedup — anti-drift consolidation (2026-07-07, roadmap `SharedKit`)

Every phone↔Mac parity algorithm + wire struct that existed as annotated copies now compiles from
ONE file in `Shared/` (commits `0192947`…`6e4ab09`; both suites green; full MLX desktop build green).
Moved: SignificanceScale (fixed the Mac's residual "Significant" value label — 5207ec3 had only
caught 1 of the Mac's 2 copies), MemoMetadata(+nested), WordTiming, DiarizedSegment, ISO8601, the
0.7 trust rule (`Memo.isTrustedTranscript`), VocabularyTermParsing+Trust+Tuning, VoiceMatcher,
SpeakerFusion, BPEMerge (phone's inline mergeBPETokens/phantom-guard/alignWords deleted), ImageMarkers.

**Follow-ups found in the research (not built — each needs its own care):**
- ⬜ **SpeakerTranscript twins** — the SHARED `Sanitiser` (line ~351) parses conversations through
  `SpeakerTranscript`, which exists per-app (desktop `Diarizing.swift` / mobile `SpeakerTurnsView.swift`,
  same anchored regex today, different helper sets + `Turn` types). A change to one app's parser silently
  forks the shared Sanitiser's behavior. Unify into Shared (reconcile Turn Identifiable-vs-Equatable,
  desktop flattened/isAttributed + mobile setText/reassign helpers).
- ⬜ **MemoCloudIngest de-multipart** — the Mac's ONLY ingest path still re-encodes the typed shared
  `Memo` into fake multipart parts for the retired Bonjour parser (`UploadService` then string-parses
  `[String: Any]`); its comments cite the DELETED phone `UploadPayload`. Map Memo+assets → PipelineFile
  directly/typed (decode `MemoMetadata` where UploadService reads dict keys). Golden parity test first
  (same memo through old + new path, byte-equal PipelineFile).
- ✅ **DONE (2026-07-07, `6f78ac1`) — Mac custom vocab is consume-only** — fixed: shared
  `VocabularySyncCore` (whole-list LWW) + Mac `customVocabularyModifiedAt` + push-on-edit + one-time
  union migration; both adapters are thin wrappers now. 8 new host-less core tests. Live phone↔Mac
  round-trip unverified — fold into the next device session.
- ✅ **DONE 2026-07-15 (Board C5) — NamesCloudSync reconcile core** — one shared
  `Shared/Naming/NamesSyncCore.reconcile` (fold-carriers → NamesMerge → sorted-keys byte-compare →
  collapse-duplicates, injected insert/delete); one encoder so the halves can't churn-loop; thin
  app adapters keep the store/gate/notify differences.
- ⬜ **VocabularyBooster.boost() cores** — same spot→rescore→trust→apply flow both sides but drifted
  (VocabLog vs DevLog, tuning knobs, store injection). Unify around a small store/log seam.
- ⚠️ **Desktop legacy readers — ANALYZED 2026-07-15, kept by design** (see Board C6 above): `PhoneMetadata`'s
  `Double?`/`String?` leniency vs the shared `MemoMetadata`'s `Int`/enum strictness is LOAD-BEARING for
  legacy RN/Python payloads — a collapse needs a lenient shared `init(from:)` (cross-app contract change) +
  golden tests FIRST, or old notes lose their export frontmatter. Not a mechanical dedup.
- ⬜ (nice-to-have) shared `DevLog` for the desktop (it has only VocabLog; the devlog.txt discipline is
  mobile-only today).

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
**📱 DEVICE TEST ROUNDS 1–5 — builds 31→39, all 2026-07-07. ⭐ CONTINUE HERE next chat.**
**ROUND-5 VERDICTS (build 39, session close):** long-press list menu ✓ works · search-hit flash ✓
works · viewer zoom ✓ works · PDF inline ✓ "very nice" — BUT the capture PAGE still reads as a
special layout (pinned block + boxed "Add a note about this capture…"), not a note. NEW DESIGN
CHUNK (next session, MOCK-FIRST): **capture reads as a NOTE** — fold annotationText into the note
body, the file/PDF becomes a body BLOCK (the [[img]]-style machinery from today generalizes: marker
kind + attachment + rect hit + zoom viewer all exist). Touches the C3 contract + exporter + Mac —
design it, don't patch it. ⚠️ STILL OPEN: selection-handles repro NOT retested since build 35 —
build 39 carries the armed probes (`sel-during-scroll` FR-inclusive + frame-write guards); pull
devlog after the next repro. Also owed: Mac parity halves (below), prod CloudKit schema at
promotion, and the **merge decision — this branch is 41 commits ahead of main** (user's call).
**Session ledger 2026-07-07 (builds 31→39):** 6 P1 fixes · camera dialog · checklist
Return-continuation · markup save-back + erase-crash fix · bar v2→v2.1 · photo display-block ·
search-hit flash · viewer zoom · PDF inline · 2 signed-off mocks · 552/552 unit (was 523).
---
**Historical: rounds 1–3 detail below.**
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
- ✅✅ **P1#4 photo search — SOLVED round 5: never broken.** User had been using the in-note 🔍
  (find-in-note) the whole time; photo text matches in the LIST "Search transcripts" bar. Sim e2e
  test stays as the permanent regression gate. SPAWNED the round-5 ask → search-hit flash (below).
- ✅ **NEW (round 5, BUILT build 37): search-hit flash** — tapping a search RESULT opens the note,
  scrolls to the first match and flashes it (~1.4 s): text hit = accent-tinted range; OCR hit = an
  accent ring over the photo (a background hides behind an image). One-shot SearchHitBridge; cleanup
  via the idempotent tier restyle so name-tier colors (incl. ambiguous backgrounds) repaint exactly.
  3 unit tests; device eyeball owed.
- 🔬 **(superseded) P1#4 round-4 evidence trail:** device devlog shows
  Vision READ his photo (`chars=21 head='TENHO…'` at 14:55) yet ZERO `search '…'` probe lines — the
  query never reached the memos-list search field. Sim end-to-end repro (user-directed) is GREEN:
  `-seedPhotoTextMemo` (real rendered-text JPEG, un-OCR'd) → launch sweep → REAL Vision → typed in
  the REAL search field → memo surfaces (`testPhotoTextSearchEndToEnd`, `ccb7ce4`). ROUND 5 = type
  **"tenho"** in the Memos-list "Search transcripts" bar (not the in-note 🔍); the probe logs the
  query either way → distinguishes typed-elsewhere vs a dead device binding.
- ✅✅ **markup ERASE crash — FIXED, device-confirmed round 4** ("works perfect").
- ✅✅ **doc-scan — FOUND + WORKS round 4** (leading slot; "super cool", adjust works). Two spawns:
  (a) NEW ASK: scanned PDF should render INLINE in the note ("text, PDF, text — like Apple Notes"),
  not behind an Open button → design/mock next session (capture-card PDF preview block);
  (b) minor: VisionKit's adjust handles sit under the finger — system UI, note only.
- ✅ **long-press misunderstanding resolved round 4** — he'd been pressing in the NOTE BODY all
  along; the menu lives on the LIST cards. Proper verdict owed but unblocked.
- 💥→✅ **markup ERASE crash (round-3 finding, fixed build 36)** (draw → close → reopen → erase → app dies; crash
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
12. ✅ **Photo-viewer ZOOM — BUILT 2026-07-07 (build 38):** the viewer is UIKit-presented
    (`MarkupQuickLook`) so QuickLook's native zoom runs, anchored on the tapped photo's drawn rect
    (transient UIImageView over the attachment; file-card opens keep the standard animation). The
    markup + dismissal-deferred edit chain moved into the presenter unchanged (tested: edit reports
    on dismiss ONLY — the erase-crash contract). Old cover wrapper deleted. Device eyeball owed.
13. ✅ **PDF INLINE in the note — SIGNED OFF (A) + BUILT 2026-07-07 (build 39):** a readable PDF
    capture (doc scan / shared) renders its FIRST PAGE as a full-width block + "N pages" chip
    (CapturePDFInlineBlock + PDFThumbnailLoader, mtime-cached); tap → the viewer (all pages,
    markup). Non-PDF files + unreadable PDFs keep the card. Snapshot-checked against the mock;
    3 loader tests; device eyeball owed. Search unchanged (sharedContent.text).
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
real book + transcript). Owed: light/sepia themes; ~~a global cross-tab mini-player~~ ✅ BUILT 2026-07-07 (see "🎧 Books tab + one-tap resume"). NEXT → Phase 2 Export.**

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

## ⭐ PARALLEL BOARD 2026-07-12 (last Fable-5 day — three lanes launched as separate chats)

Base for ALL lanes: origin/main ≥ `8d65ea6` (base-proof file: `Skrift_Native/SkriftMobile/Services/MemoDeduper.swift` —
if missing in your worktree, your base is stale: reset before any work). Every lane: OWN worktree branch,
explicit-path staging, sim-green end state, **NO phone installs / NO CFBundleVersion bumps** (device rounds
queue centrally — one phone), ledger edits only as small appends in the lane's FINAL commit, PR to main.
LOCKED design rule for all lanes: shared inputs never get bubble/box chrome (memory feedback_no_bubbles_on_shared_input).
- **Lane D (desktop)** — Boards A+B at "CONTINUE HERE — desktop-parity board" above (mock v2 = spec).
  Board C is HELD until Lane P merges (SpeakerTranscript move touches MemoDetailView = Lane P territory).
- **Lane P (phone editor)** — capture-as-note + note-editing follow-ups (memory project_capture_as_note_kickoff),
  on TOP of tonight's Wave-3 MemoDetail changes (borderless annotation, voice-annotate, PDF disclosure, rich url card).
- **Lane B (podcasts, C3 ⭐ STRONG GO)** — episode share/URL → RSS enclosure download → lands in the Books tab
  (playable, whole-transcribed via BookTranscript infra, read-along + quote capture). Audiobooks area only.

**Roadmap sweep 2026-07-12 (Command Center chat, v17):** the three lanes got roadmap nodes —
**DParityB** (Lane D) · **CapNote** (Lane P) · **Podcasts** (Lane B), all `inprogress`; **flip YOUR node
to `done` in your final commit** (don't mint a new one). Same sweep: fixed roadmap.yaml being INVALID
YAML since the 2026-07-11 TrEngine entry (unquoted `probe:` colon — the hub couldn't parse the file);
NEdit → done 2026-07-10; ShareW2 note refreshed to the chapter close (+ multi-item WhatsApp follow-up
in its backlog); duplicate idea id i5 → print-to-wall is now **i8**; i4 removed (shipped as ShareW1);
new idea **i9** = Tuur voice-over easter egg (tap About ~3×, everything goes weird); SSOT §4 Mac + P8
flipped done; STANDALONE_PLAN Phase 8 header marked done; stale NFeat desktop items pruned
(lock gate / link resolver / OCR search shipped in DParityA; body parity → DParityB).
**v18 history fix (2026-07-13):** H_rn re-ordered AFTER the Electron desktop (Tuur: the phone
companion came later — both sat at order -1.92); new first node **H_whisper** = the undated
pre-repo whisper-fork tinkering (from memory, no dates). Hub-side: lane bands now absorb
fractional rows into their parent lane (Tiuri-Command-Center PRs #82/#83).
