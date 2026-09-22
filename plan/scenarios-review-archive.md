# Gap hunt — the archive as consumer + the reviewer's day (2026-09-22)

Read from the worktree `code-audit-report-4816f4`. Two fresh angles the spec hasn't used:
(1) does the archive repo's OWN parser/rules actually accept what Skrift writes, and
(2) 20 review-side scenarios (not capture) traced through the current code, cold, against SPEC.md.
Verdicts: COVERED Cn / PARTLY / UNCOVERED / CONTRADICTED. Paths: `M/` = `SkriftMobile`,
`D/` = `SkriftDesktop`, `S/` = `Shared`.

---

## Viewpoint 1 — the archive as consumer

Read: `portfolio/README.md`, `.claude/rules/portfolio.md`, `portfolio/_ideas/README.md`,
`portfolio/_inbox/README.md`, `capture/tools/vault_index.py` (all in
`~/Hackerman/Tiurihartog.com`, read-only) against `S/Export/Compiler.swift`,
`ExportProfile.swift`, `VaultWrite.swift`, `VaultLayout.swift`, `D/Pipeline/Export/VaultExporter.swift`,
`M/Services/Export/ObsidianPublisher.swift`.

**Ground truth check first:** `vault_index.py`'s `scan()` explicitly skips any path segment
starting with `_` (line 73) — it parses `item.md` under category folders only. **Nothing in the
archive repo currently parses `_inbox/`, `_ideas/` or `_inspiration/` at all**, and none of the
three folders holds a single Skrift-shaped export today (checked: `_ideas/` has 2020-era loose
files, no `.md` matching `YYYY-MM-DD-HHMMSS.md`). So every claim below about "the archive's
parser" is checked against `vault_index.py`'s `parse_front()` — the only flat-YAML parser that
exists in that repo — run directly against sample Skrift output, not against a real round trip
(none has happened yet).

### Key-by-key table

| Key / construct | Skrift writes (`Compiler.swift`) | Archive expects | Verdict |
|---|---|---|---|
| `title` | Always `yamlQuoted()` — `"…"`, `\"`-escaped | One line, only when he gave one; "reword, don't quote" is human guidance, not a parser rule | **MISMATCH** (minor) — a title with an embedded `"` round-trips through `parse_front()` as literal `\"` (the naive `.strip("\"'")` doesn't unescape); verified by running the parser (see below) |
| `date` | `date: 2026-09-22` unconditionally | **`added:`** — confirmed by `portfolio/README.md` (`added: 2026-08-19`), `_inbox/README.md`'s item.md example, and `.claude/rules/portfolio.md` ("it writes ids, `type:`, `added:`, `source:`"). `date` is not in C130's own allowed-key list | **MISMATCH** — wrong key name, not a format issue. `ArchiveExportTests.swift:105` (`SkriftMobileTests`) actively asserts `text.contains("date:")` as a *required* key, so this is baked into the test oracle, not just an oversight |
| `capture` | `capture: Voice-memo` / `Video` / `Audiobook-quote` / `capture-url` etc. | Skrift-owned key, no archive-side meaning collision | OK |
| `book` / `bookAuthor` / `chapter` | Written unconditionally when present (any destination) | Not in C130's allowed list; archive's own doc: "add keys freely… the tools ignore what they don't know" | OK (tolerated, uncatalogued) |
| `url` | Written for capture types with a URL | Same — not catalogued, tolerated | OK |
| `voice` | `raw` \| `cleaned` \| `written`, matches the archive's vocabulary | Same 3 values, same meaning | Format **OK**; correctness **MISMATCH** — `M/Services/Export/MemoExporter.swift:91` sets `.cleaned` whenever `enh != nil`, with no check that `enh.copyedit` is non-empty, so a Mac pass that only set title/summary (leaving the body raw) still exports `voice: cleaned` on the phone. `D/Pipeline/Export/CompilerBridge.swift:71-73` gets this right (checks `enhancedCopyedit` emptiness). = **R41**, confirmed still present |
| `needs` | `needs:\n  - credit` only for Inspiration / an Idea tagged `inspiration` | Archive's own key, block-list shape | OK — `Compiler.swift:127-133` matches C134 exactly |
| `summary` | Written **unconditionally**, every profile — `Compiler.swift:137` has no `profile == .obsidian` guard | Explicitly **DROPPED**: `.claude/rules/portfolio.md` — *"`confidence:` and `summary:` are DROPPED — his call 2026-08-26: 'is from a template… no need for this'"* | **MISMATCH** — already named in SPEC C130 as a known required difference, **still unfixed**, and `ArchiveExportTests.swift:105` requires `summary:` be present — the test would need to change alongside the fix |
| `tags` | Block list, `#` stripped once | Block list, never `[a, b]` | OK |
| `people` | **One line**, comma-joined: `people: [[Alice]], [[Bob Jones]]` | Person wiki-links, "credit his friends by name" (C137) | **MISMATCH — verified by execution.** Ran `vault_index.py`'s real `parse_front()` against this exact line: the value starts with `[` and ends with `]`, so the parser's inline-list branch fires and does `v[1:-1].split(",")`, producing `['[Alice]]', '[[Bob Jones]']` — garbled brackets, not clean names. **Breaks even for a single person**: `people: [[Alice]]` → `['[Alice]']`. This is the single highest-value finding: it defeats the one thing C137 exists for (crediting his friends by name) |
| `location` | `location: "<place>"`, no escaping of embedded `"` (unlike `title`, which does escape) | Quoted plain scalar; a comma inside is fine (quoted) | Comma case: OK. Embedded-quote case: **MISMATCH** (minor, latent — breaks the YAML fence itself, not just mis-parses, if a place name ever contains a literal `"`) |
| `lastTouched` / `skriftID` / `skriftHash` | Always appended last | Explicitly allowed by C130 ("the stamp trio"); unknown-but-tolerated by `parse_front()` | OK |
| Pinned image for a **marker-less capture** (`Compiler.captureSharedBlock`, `Compiler.swift:234-258`) | Hardcoded `![[filename]]` — **no `profile` parameter on this function at all**, only call site is `compile()` line 186, which passes no profile | C129: *"`![](file)` relative embeds only, never `![[…]]`"* | **MISMATCH — high severity.** A picture-only Idea/Made/Inspiration with no `[[img_NNN]]` markers (i.e. a bare shared photo, no annotation — per the archive's own docs *"the minimum is a bare picture… often it's just a picture"*, its single most common entry shape) exports an Obsidian-only wiki-embed that will not render outside Obsidian, breaking the archive's core "walk out whole" contract. `ArchiveExportTests.swift` never exercises this path — its one fixture memo is a plain voice memo (`sourceType` never `.capture`), so the bug has zero test coverage in either direction |
| Made destination folder | `NoteDestination.archiveFolder` = `"_inbox"` (`S/Model/NoteDestination.swift:57`); `VaultLayout.home(forPicked:profile:)` returns the archive pick **unchanged** (no `Skrift/` subfolder — `ownsHomeFolder` is `false` for `.archive`, `VaultLayout.swift:46`) | `_inbox/Skrift/` — both `_inbox/README.md` ("memos then arrive in `_inbox/Skrift/`") and SPEC C62 (dated the SAME DAY, 2026-09-22: *"Made lands in `_inbox/Skrift/`… v1 writes flat `_inbox/` — required difference"*) | **MISMATCH — CONTRADICTED against a same-day spec decision.** Current code still writes flat into `_inbox/`, exactly the v1 behavior C62 calls out as wrong |
| Multi-image basename | `<stem>_NNN.ext` (e.g. `a-bench_001.jpg`) vs the archive doc's one-picture example `<timestamp>.jpg` | No explicit rule for >1 photo; "media beside it sharing its basename" | Not a parse-breaker (files sit beside the note either way) — flagged as a **watch item**, not counted |
| `author:` / `type:` / `source:` | Never written on archive profile | Archive-owned keys, collision forbidden by C130 | OK — correctly avoided |
| `credit:` | Never written by Skrift (by design — filled by a later archive pass) | Matches C134's "a later archive pass reads it and fills `credit:`" | OK |

**MISMATCH count in the table: 8** (title-quote-escaping, `date`/`added`, `voice` R41,
`summary`, `people` bracket-collision, `location`-quote-escaping, the wiki-embed leak,
`_inbox/Skrift`). Of those, **3 are cosmetic/edge-case** (title-quote, location-quote, and the
multi-image basename watch item, which isn't counted) and **5 are load-bearing**: `date`/`added`
(the archive can't find when an entry was captured), `people` (breaks even one name), the
wiki-embed leak (breaks the bare-picture case, the most common one), `summary` (already known,
unfixed), and `_inbox/Skrift` (contradicts a decision made the same day as this audit).

### Verification method for the `people:` finding

```
$ python3 -c "
import sys; sys.path.insert(0,'.../capture/tools'); import vault_index as vi
print(vi.parse_front('---\npeople: [[Alice]]\n---\n'))
"
{'people': ['[Alice]']}
```
Run against the real `vault_index.py` in the portfolio repo, not simulated by hand.

---

## Viewpoint 2 — the reviewer's day (iPad + Mac)

**1. Opening Review with 200 rated notes.**
Both apps `@Query` the FULL non-deleted set into memory (`M/Features/MemosList/MemosListView.swift:62-67`;
`D/Features/Shell/RootView.swift:30-31`) and filter client-side over the whole array every
recompute (`AppModel.visible`, `AppModel.swift:104-105`). SwiftUI's `List` lazily renders rows,
but the fetch+filter itself is O(all memos), no page size, no clause governs it.
Verdict: **UNCOVERED**. Clause: *"Review lists load without a hard cap; a filter/sort recompute
is O(all live memos), not O(displayed)."* Fixture: a 500-memo synthetic corpus + a frame-time
budget check.

**2. Process pile, 30 waiting, Mac asleep.**
`ProcessPile.isWaiting` (`S/Pipeline/ProcessPile.swift:24-28`) is a pure per-memo predicate —
rated, live, unlocked, real transcript, not yet enhanced. Nothing tracks "has a Mac claimed
this" or a queue-age/heartbeat. The iPad's own "Process N" button offers to run the SAME pile
locally regardless of whether a Mac is mid-run elsewhere; LWW-by-`enhancedAt` (C179) prevents a
double-write from corrupting anything, but nothing tells the user "the Mac is asleep, nothing
is moving."
Verdict: **UNCOVERED** (no clause on staleness/liveness). Clause: *"A device showing 'N waiting'
carries no claim on WHICH device is working the pile; a note only leaves the pile once
`isProcessed`."* Fixture: none needed (behavior is safe, just silent) — a UX note, not a
correctness bug.

**3. Redo copy-edit on a note already hand-edited.**
`PolishCenter.runRedo` (`M/Services/Polish/PolishCenter.swift:182-222`) guards only
`isAvailable, !locked, !isWorking`, and that a `MemoEnhancement` row still exists — never
whether the CURRENT `copyedit`/`title`/`summary` was a hand edit. On success it unconditionally
does `e.copyedit = out` (etc.), `enhancedAt = Date()`, `save()`. C181 says an edit to the polish
"lands in the enhancement, stamped" — Redo then silently regenerates and overwrites that same
field with fresh AI output, no diff, no confirm.
Verdict: **CONTRADICTED** (against C181's premise that a hand edit is a real edit, and C248's
bug-shape sweep — "a fallback that returns the wrong input" / silent-clobber shape, the same
shape as the 2026-07-10 P0 enhancement-clobber incident in a different code path). Clause:
*"Redo never overwrites a field the user hand-edited since the last polish; offer regenerate-vs-keep
instead."* Fixture: `voice-en-hand-edited-then-redo` — edit `copyedit`, then invoke Redo, assert
the edit survives or is explicitly surfaced as a choice.

**4. Title changed on the Mac after the phone set one.**
Title itself syncs as a plain `Memo.title` field via CloudKit (`MacCloudMetaSync.setTitle`,
event-driven, no `lastEditedAt` bump) — ordinary last-write-wins, not the tracked-conflict path
C98 describes for body edits. Separately, and more concretely broken: a Mac title Redo calls
`MacCloudWriteBack.upsert` (`D/Pipeline/Ingest/MacCloudWriteBack.swift:97-114`), which is
**whole-record** LWW over `title`+`copyedit`+`summary` together, guarded only by
`existing.enhancedAt > now` for a DIFFERENT device. A Mac-local title Redo pushes ALL THREE of
its local `pf` fields, so if the Mac's local `copyedit`/`summary` are stale relative to a more
recent phone-side edit, a title-only Redo can silently regress the copyedit/summary the phone
set. The file's own comments (`:11-13, 99-104`) already flag this as whole-record, not per-field.
Verdict: **CONTRADICTED** (against C98's "never a silent overwrite" for the copyedit/summary
regression case specifically; title-only LWW is fine on its own). Clause: *"Enhancement write-back
merges per field (title/copyedit/summary independently LWW'd), never as one bundled record."*
Fixture: phone sets copyedit+summary, syncs; Mac (stale local `pf`) does a title-only Redo;
assert the phone's copyedit/summary survive.

**5. Unlinking a name on the iPad, then opening the note on the Mac.**
`Memo.nameResolutionsData` (`S/Model/Memo.swift:154-163`) is syncable (a plain field) but its own
doc comment says it plainly: *"Phone-side display/export only… the Mac's CloudKit ingest ignores
this field."* Confirmed — no reference to `nameResolutionsData` anywhere under
`D/Pipeline/Ingest/`. The Mac keeps its OWN separate `unlinkedNames`/`namePicks` on `PipelineFile`.
Verdict: **CONTRADICTED = R37** (already pre-registered: *"name picks are one-way and unapplied…
one note exports the same links from every device (D20)"*, C81). Confirms R37 is still exactly
as described, with a fresh citation. No new clause needed — it's already required, just unbuilt.

**6. Rating a conversation.**
`NoteConsent`/`ProcessPile` read only `memo.significance`/`deletedAt`/`locked` — no branch on
conversation vs monologue anywhere in either file; the rating UI (`SignificanceCircles`) renders
identically. The only conversation-specific gate found is unrelated (Redo copy-edit is hidden for
conversations per C36 — turns are the diarization, not the rating).
Verdict: **COVERED C87** (uniform, as the clause implies).

**7. Exporting a note whose picture hasn't synced from CloudKit yet.**
`ObsidianPublisher.convertPhotoMarkers` (`M/Services/Export/ObsidianPublisher.swift:231-260`)
resolves `[[img_NNN]]` purely against the MANIFEST (which entries exist), not against blob
availability — it rewrites to `![[<stem>_NNN.ext]]` regardless. The actual blob fetch happens
later (`photosProvider`, line ~205); if the blob isn't there, `compactMap` silently drops that
ONE attachment from what gets written — but the markdown body, already committed, still contains
the embed reference. Net effect: a broken embed pointing at a file that was never copied, no
wait/retry, no partial-export warning.
Verdict: **UNCOVERED** (no clause addresses an unsynced asset at export time). Clause: *"Export
either waits for an unsynced image blob or drops its embed reference from the body too — never a
dangling `![[…]]`/`![]()`."* Fixture: `voice-en-photo-blob-missing` — a manifest entry with no
matching `MemoAsset.blob` at export time; golden = no dangling reference in the written markdown.

**8. Connections on a note with no rated neighbours.**
`ConnectionsPanel.aiZone` (`M/Features/MemoDetail/ConnectionsPanel.swift:169-179`) has a clean
three-way branch: gate (not rated) → finding (spinner) → empty ("No connections yet" / "As more
notes touch this idea, its arc shows up here", `RetrievalGate.swift:71-72`) → results. Backlinks
render independently even when the AI zone is empty.
Verdict: **COVERED** (reasonable, matches the calm-empty-state doctrine elsewhere in the spec,
e.g. C135's "no invented sentence").

**9. The wall printer with no printer.**
`WallPrinter.swift` (full read): no printer saved → `ratingCommitted` silently no-ops
(`guard autoPrint, hasPrinter else { return }`, line 55). Printer saved but unreachable →
`tryDrain` keeps the card queued (`notifyQueued`, line 101) and fires a local notification +
Settings retry row; nothing is dropped. Matches "offline-queued" verbatim.
Verdict: **COVERED C233**.

**10. Fading conveyor, 40 notes same day.**
`FadingSweep.run` (`M/Services/FadingSweep.swift:24-42`) does one `softDelete` + one `save()`
PER memo, no batching — 40 fades same day = 40 separate SwiftData saves in the sweep loop.
Each is independently safe (no dedup needed, `deletedAt` prevents re-sweep) but there's no
chunked/batched save, and no test exercises a 30-40-note simultaneous fade
(`MemoLifecycleTests.swift`, `WayOutViewTests.swift` are all single-note).
Verdict: **UNCOVERED** (perf risk, not correctness — no clause on batch scale). Clause: *"A
sweep of N due memos performs O(1) context saves, not O(N)."* Fixture: 40-memo corpus all
crossing the fade threshold on the same sweep tick; assert save-call count.

**11. "Mark all as Passing."**
`SidebarView.processAll` (`D/Features/Sidebar/SidebarView.swift:780-786`) sets
`significance = 0.1` on each memo from `WayOutRules.unpipelined`, which BY CONSTRUCTION excludes
locked (`:40`), already-rated, and fading notes — one loop, one save. No progress UI for 100+
notes but nothing unsafe.
Verdict: **COVERED** (safe by construction; no named clause, but nothing contradicted).

**12. Locking a note mid-polish.**
C91 is explicit and decided: *"Processing continues on a locked note… lock is about eyes, not
the pipeline."* The Mac's `WayOutRules.needsProcessing` (`:102-104`) never checks `locked` at
all — consistent. The iPad's `PolishCenter.run()` never re-checks `locked` once an async pass is
in flight either — also consistent (a lock applied mid-run doesn't abort the write-back). BUT:
`PolishCenter.canPolish`/`redo` (`:156, 183`) DO refuse to *start* on an already-locked note
(`!memo.locked` guard), while the Mac's batch will happily START a fresh pass on a locked
`PipelineFile` — a genuine iPad/Mac inconsistency against C91's "processing continues on a locked
note," which reads as lock-agnostic, not "lock-agnostic mid-run only."
Verdict: **PARTLY C91** (mid-run behavior matches; the START-gate differs by device, and C91
doesn't distinguish "don't start" from "don't stop"). Clause: clarify C91 — *"Lock never gates a
polish pass, start or resume, on either app"* (or the reverse, if that's the actual intent) —
needs Tuur's call, this is a genuine ambiguity, not a one-sided bug.

**13. A note edited on the Mac while the iPad shows it live.**
`MemoDetailView.swift:826-833`: the enhancement is read via a live `@Query`, explicitly
documented as replacing an older stale-fetch/onChange hack — "live-updates when a polish arrives
over CloudKit." The top-level memo list is also a live `@Query`.
Verdict: **COVERED** (SwiftData + CloudKit push updates the open note view without navigation).

**14. Searching a word that only appears in OCR.**
Both apps DO index OCR: phone `MemoDisplay.matches` (`M/Models/MemoDisplay.swift:83-99`, line 95)
checks `imageManifest[].text`; Mac `AppModel.matchesSearch` (`:85-94`, line 92) checks
`imageOCRText`. The literal scenario (word only in OCR) is found on both. But C111/C236 require
MORE fields than either app actually checks: the phone's `matches()` has no `summary` and no
PDF/article-text check at all; the Mac has `summary`+OCR but no separate PDF/article field
either.
Verdict: **PARTLY C111/C236** (OCR itself works; summary/PDF/article coverage is short of the
clause). Clause: none needed, C111/C236 already state the requirement — this is an
implementation gap, not a spec gap. Fixture: `pic-ocr-text` extended with a `summary`-only hit
and a PDF-text-only hit, run against BOTH apps' search.

**15. Opening a Mac-recorded note on the iPad (no word timings).**
`MacMemoAuthor.swift:90-93` inserts only a `.audio` `MemoAsset` — confirmed, no timings/turns
asset anywhere in `MacMemoAuthor` or `MacCloudWriteBack.upsert`. Playback degrades gracefully:
karaoke highlight is gated on `!timings.isEmpty` (`MemoDetailView.swift:1349, 2337`), so the note
plays fine, just without word-level highlight.
Verdict: **CONTRADICTED = R34/R35**, confirmed still present at the exact lines SPEC already
cites. Graceful degradation on the iPad side is a genuine positive not covered by the R-row
(worth adding to the fix's acceptance criteria so a future fix doesn't regress it).

**16. Re-export after the vault folder was renamed.**
`ObsidianVault.resolveVault()` / `ArchiveVault.resolveRoot()` (`M/Services/Export/…`) both
resolve the security-scoped bookmark and set `stale`, **then never read `stale`** — despite
their own doc comments claiming *"nil if unset or unresolvable (stale → re-prompt in the UI)"*.
A rename the OS can still resolve via the bookmark's inode tracking returns silently with the
stale bit ignored. Downstream, `VaultLayout.home(forPicked:)` decides the write target by NAME
match (`homeFolderName`) or by stamp-sniffing (`holdsSkriftNotes`) — a renamed folder that no
longer matches either creates a NEW nested `<picked>/Skrift`, silently, rather than surfacing
"your vault moved."
Verdict: **CONTRADICTED against the code's own documented contract** (not yet a numbered
clause). Clause: *"A resolved bookmark that reports `stale` triggers a re-prompt before the next
write; export never silently mints a second home folder."* Fixture: rename the picked folder,
re-export, assert either a re-prompt or the SAME folder is reused (not a new `Skrift/` nested
inside the rename).

**17. A note whose polish exists but `processedAt` is nil.**
`MemoEnhancement.isProcessed` (`S/Model/MemoEnhancement.swift:76-82`) falls back to "all three of
copyedit/title/summary filled" exactly as C37 describes, with the reasoning documented inline
(why "any part" was rejected).
Verdict: **COVERED C37**.

**18. The Mac's Queue with an unrated Mac-local take vs an unrated SYNCED note.**
The literal scenario (Mac-LOCAL unrated take) IS handled: `WayOutRules.isUnratedLocalRecording`
(`:80-82`) excludes it from `needsProcessing`. But the broader and more common case is NOT:
`needsProcessing` (`:102-104`) is `deletedAt == nil && enhanceStatus != .done &&
!isUnratedLocalRecording(pf)` — `isUnratedLocalRecording` requires `pf.isLocalRecording`, so an
UNRATED note **synced in from the phone** sails through this gate untouched and gets
auto-polished by the Mac's batch runner.
Verdict: **CONTRADICTED = R17**, confirmed still present at the exact lines SPEC.md:384-388
already names (`WayOutRules.swift:102`) — this pre-registered required difference is unresolved,
and it's the more common case (synced notes vastly outnumber Mac-local takes), so its real-world
impact is understated by the R-row's Mac-local framing.

**19. The iPad polishing while on battery at 5%.**
`PolishGate.isSupported` (`PolishCenter.swift:62-77`) checks device idiom, simulator, and RAM
(≥6 GB per C180) — no battery read anywhere in `PolishCenter`/`PolishGate`
(`UIDevice.current.batteryLevel`/`batteryState` never appears). Yet
`PolishSettingsView.swift:17`'s footnote text tells the user *"the iPad never polishes in the
background or on battery-critical"* — a claim the code does not implement. (Contrast:
`BookTranscriptionJob.swift` DOES have a real 20% pause threshold for audiobook transcription,
C244's "battery measured, not guessed" — that discipline exists in the codebase, just not here.)
Verdict: **CONTRADICTED** (UI copy promises behavior the code doesn't have). Clause: *"PolishCenter
pauses/refuses below the same battery floor as audiobook transcription (20%), matching its own
Settings copy."* Fixture: a battery-level test double at 5%, assert `canPolish` returns false or
`run()` refuses.

**20. A future-dated note in the Journal.**
`MemoDate.group` (`M/Models/MemoDisplay.swift:373-385`): `days = daysBetween(startOfDay(date),
startOfDay(now)); if days <= 0 { return "Today" }` — a negative `days` (future date) folds
silently into "Today." Sort order (`.recent`, `MemosListView.swift:1251-1259`) uses raw
`recordedAt >`, so the future note sorts ABOVE every real today note while still labeled "Today"
— a phantom entry, mislabeled, not crashing but not honest either. No clamp found in either
`JournalHomeView.swift` or `JournalCalendarView.swift`.
Verdict: **UNCOVERED** (no clause addresses a future `recordedAt`; C64 is about timezone
consistency of `date:` at export, a different problem). Clause: *"A memo whose `recordedAt` is
in the future groups/labels as 'Upcoming' (or is clamped to today), never silently as 'Today.'"*
Fixture: `edge-future-dated` — `recordedAt` = now + 3 days; golden = distinct group, not "Today."

---

## Summary

| Verdict | Count | Scenarios |
|---|---|---|
| COVERED | 6 | 6, 8, 9, 11, 13, 17 |
| PARTLY | 2 | 12 (C91), 14 (C111/C236) |
| UNCOVERED | 5 | 1, 2, 7, 10, 20 |
| CONTRADICTED | 7 | 3, 4, 5 (=R37), 15 (=R34/R35), 16, 18 (=R17), 19 |

Archive table: **17 rows, 8 MISMATCH** (5 load-bearing: `date`/`added`, `people`
bracket-collision, the wiki-embed leak, `summary`, `_inbox/Skrift`; 3 cosmetic/edge-case:
title-quote, location-quote, and a noted-but-uncounted multi-image basename watch item).

## Uncovered / contradicted — proposed clauses

- **C252** [new] Redo never overwrites a field the user hand-edited since the last polish pass
  (scenario 3). Fixture: `voice-en-hand-edited-then-redo`.
- **C253** [new] Enhancement write-back (`MacCloudWriteBack.upsert`) merges per field, never as
  one bundled title+copyedit+summary record (scenario 4). Fixture: stale-Mac-title-redo test.
- **C254** [new] Export never leaves a dangling image reference for a blob that hasn't synced —
  wait or drop the reference too, never one without the other (scenario 7). Fixture:
  `voice-en-photo-blob-missing`.
- **C255** [new] A resolved-but-stale security-scoped bookmark triggers a re-prompt before the
  next write; export never silently mints a second home folder (scenario 16). Fixture: rename
  the picked folder mid-session, re-export.
- **C256** [new] PolishCenter pauses/refuses below the same battery floor as audiobook
  transcription (20%), matching its own Settings copy (scenario 19). Fixture: battery-double at
  5%.
- **C257** [new] A memo whose `recordedAt` is in the future groups distinctly ("Upcoming" or
  clamped), never silently as "Today" (scenario 20). Fixture: `edge-future-dated`.
- **C91 clarification needed** — does "processing continues on a locked note" also mean a NEW
  pass may *start* on an already-locked note? iPad refuses to start; Mac doesn't check at all.
  Needs Tuur's call (scenario 12), not a drafter default.
- **Archive `people:`/`date`/wiki-embed fixes** — not new clauses; C130/C129/C62 already state
  the rule, the code doesn't meet it yet. Tracked as MISMATCH rows above, not duplicated here.

## Fixtures to add

- `dest-idea-picture-only` / `dest-made-picture-only` — a marker-less image capture, destination
  Idea/Made; golden = `![](file.jpg)`, never `![[file.jpg]]`.
- `dest-made-folder` — assert the Made write lands at `_inbox/Skrift/<name>.md`, not
  `_inbox/<name>.md`.
- `dest-idea-two-people` — a body linking two known people; golden = a `people:` line that
  round-trips through `vault_index.py`'s `parse_front()` to exactly `["Alice", "Bob Jones"]`.
- `dest-idea-added-key` — assert the date key is `added:`, not `date:` (requires updating
  `ArchiveExportTests.swift:105` in the same change, since it currently asserts the wrong key).
- `voice-en-processed-no-content` (already named in R41) — re-run specifically checking `voice:`
  agreement between phone and Mac exports of the same note.
- `voice-en-hand-edited-then-redo`, `voice-en-photo-blob-missing`, `edge-future-dated` — see
  proposed clauses above.
