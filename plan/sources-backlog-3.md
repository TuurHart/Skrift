# Source ledger — archive/state-2026-09/backlog.md lines 2577–4420

Date: 2026-09-23. Rule: SPEC.md C276, "a cited document is not a folded document." Every open
item in this slice gets a verdict against the live ledgers (SPEC.md clauses/R-rows/D-rows,
BUGS.md, roadmap/roadmap.yaml, plan/perf-sweep.md) and, where needed, the code.

Line numbers below are backlog.md line numbers (the file itself, not the slice).

---

## iPad wave 1 — CONTINUE HERE board (2577–2612)

| item | line | verdict | id / why |
|---|---|---|---|
| Review board step 2: cosmetic — detail ⋯/+ toolbar pill floats over the Connections panel corner | 2603–2604 | SUPERSEDED | The whole note toolbar + Connections layout this pill sat in was torn out and rebuilt twice more (note-view stacking rebuild b130, `1f81136`; "chrome that belongs" b132, `3c871ed`, Tuur-confirmed "this looks soo good" 2026-07-24). Node `IPadWave1`. |
| Review board step 3: Polish on iPad device test (Download 4.6 GB, Polish now, confirm LWW hand-off) | 2605–2607 | DONE-SINCE | commit `b8f8540` (pinned model revision) then fully closed same day — devlog line "wrote enhancement for E3E0CF97…" on b142. Node `IPadWave1`. |
| Owed by contract: wide-player live eyeball (tap-driven) | 2608 | OPEN | Not in SPEC/roadmap/BUGS. Audiobook player redesign is `P9b` (status `planned`), scoped as "after the reading-mode redesign" — no R-row or queue item for this specific tap round. |
| Owed by contract: landscape pass | 2608 | OPEN | Not tracked anywhere live. |
| Owed by contract: Stage Manager/Split View compact fallback | 2608 | OPEN | Not tracked anywhere live. |
| Owed by contract: ⌘-shortcut feel | 2608 | OPEN | Not tracked anywhere live. |
| Owed by contract: onboarding on pad | 2609 | OPEN | Not tracked anywhere live. |
| Promotion: Release App-Group one-time Xcode visit still pending (capture-items precedent) | 2610–2611 | OPEN | No SPEC clause or BUGS row for the manual Xcode Signing & Capabilities step on the prod bundle ID; needs a queue "[tuur]" item, not code. |

---

## Unrated note IS a normal note (2613–2697)

| item | line | verdict | id / why |
|---|---|---|---|
| OWED: Tuur's live eyeball (open an unrated note, rate it, watch hand-over) | 2654 | OPEN | Not confirmed in any live ledger; the round-5/round-6 rounds below fixed bugs found in a *later* eyeball, but no line records this specific hand-over check closing. |
| Bug found in passing, not fixed: `PipelineFile.durationSeconds` parses an HMS string while `MemoCloudIngest.metadataJSON` writes `duration` as a Double — no CloudKit-synced note shows a duration chip on the Mac | 2656–2659 | FOLDED | SPEC.md C219 / A106-108: "the Mac row's duration reads numeric seconds and legacy HMS, v2 writes one representation" — the rewrite folds this fix in. |

(Round-5 eyeball items 1 and 2 — title mid-word clip, un-rating going nowhere — are marked done in the doc itself with commits; item 3, the one-way rating door, is a closed Tuur decision, not an open item; neither is listed here.)

---

## The two SignificanceCircles views are ONE view (2700–2736)

| item | line | verdict | id / why |
|---|---|---|---|
| Six style fields drift-parked, not decided (flameSize, tag/tier tracking, syncDotSize, syncFontSize, flameOpacity, tierWeight) — "collapsing a pair is an eyeball round" | 2722 | SUPERSEDED | `i23` (SPEC.md:456, D30, D52): the SignificanceCircles control itself is being replaced by a 3-button importance control ("mock pass owed first (mocks/significance-circles.html); re-baseline the two render gates"). The pixel-drift question is moot once the control is rebuilt. |

---

## Export destinations — CONTINUE HERE (2739–2925)

Build board items 1–5 and the video decision (item 6) are all shipped per roadmap node
`ExportDestinations` (`status: inprogress`, shipped log matches this section nearly verbatim,
commits `37ae2c17`, `d7702652`/`2d8f87d1`, `020e7314`, `56e7df94`). Only the still-open tail:

| item | line | verdict | id / why |
|---|---|---|---|
| Owed: Tuur's device round (throwaway folder first, then the real portfolio repo) | 2913 | OPEN | Node `ExportDestinations` note itself says "OWED: a device round" — still unresolved in the live roadmap, i.e. genuinely open, not un-tracked. |
| Owed: the gate fix (`00e67299`) still device-unverified | 2914 | OPEN | Same as above — the node's own note carries this as unresolved. |
| Question to portfolio chat: is `_inspiration` still right now that it's the narrower bucket? | 2916, 2922 (duplicate) | OPEN | Not answered anywhere in SPEC.md's archive-contract section (SPEC.md:590–650) or `Decisions`. |
| Question to portfolio chat: does the site render person pages (or do `[[Jack]]` links dangle)? | 2917, 2923 | OPEN | Same — no answer found. |
| Question to portfolio chat: does the site have a "type" concept matching the four? | 2918, 2924 | OPEN | Same. |
| Question to portfolio chat: does the archive accept video files? | 2918, 2924 | OPEN | Same; also relevant to D-decisions on video (video export was separately DECIDED cut for a different reason — Tuur: "don't store them, skip them" — but that doesn't answer whether the archive site *accepts* video, a distinct question). |

---

## ONE export engine, both apps (2928–2972)

| item | line | verdict | id / why |
|---|---|---|---|
| Owed: Tuur's real-device round (throwaway folder, then `0 Inbox/Skrift`) | 2967 | OPEN | Node `SharedExport` note: "INPROGRESS not done: Tuur's first real-device run owed." Still unresolved live. |
| Parked: `includeAudioInExport` sync (own contract chunk) | 2971 | OPEN | Confirmed still Mac-only in code (`SkriftDesktop/Pipeline/Export/VaultExporter.swift`, `PipelineFile.swift`, `NoteProperties.swift` — no `Memo`/Shared property). Node `SharedExport` note repeats "parked" as of the current roadmap. |
| Parked: the Mac-side return path (kept small on purpose, plugin owns following moves) | 2971 | FOLDED | `i14` / node `ObsidianPlugin` — the plugin's "real inbox" feature is explicitly the thing that retires the return-path problem. |

---

## THE OBSIDIAN PLUGIN MENU (2975–3011)

Whole section (10-wireframe proposal menu, not signed off) is **FOLDED** → `i14` / roadmap node
`ObsidianPlugin` (`status: planned`, `lane: 5`, deps `SharedExport`). The node's `note:` field
reproduces the v1 bundle recommendation (2 inbox + 4 sync doctor + 1 listen), the Connections
verdict (Mac-live only, static tier rejected), and "don't start until Tuur picks his features off
the menu" verbatim. No sub-item here is open beyond that node.

---

## RESUME HERE — 2026-07-26 (3013–3327)

| item | line | verdict | id / why |
|---|---|---|---|
| OPEN BUG: the iPad cannot process a note; it errors (blocks the then-`now` node) | 3056–3075 | DONE-SINCE | Diagnosed to an unpinned model revision, then fixed: commit `b8f8540` (pin `defaultModelRevision` + raise mlx-swift-lm floor), then fully closed same day ("THE iPAD POLISHES", three walls each hiding the next, all fixed) — devlog-confirmed enhancement write on b142. |
| "Add 'Remove model' to Settings card" (option A, recommended) + completeness check pairing | 3257–3259 | PARTIALLY DONE-SINCE | `PolishSettingsView.swift:48` has a destructive "Remove" button → `PolishCenter.removeModelForSettings()` → `MLXPolishEngine.removeModel()`, added in commit `fad9a7af` ("an MLX fault throws instead of killing the app, and a bad model can be removed"). The paired **completeness check is still unbuilt**: `MLXPolishEngine.isModelOnDisk()` (current source) still uses only the 500 MB floor with the comment "Advisory only … exact detection is device-owed to confirm" — the false-positive risk the backlog flagged is still live. OPEN for the completeness half; no SPEC/BUGS row covers it. |
| ⚠️ Worth fixing regardless: an MLX error should not kill the app (`MLX.withErrorHandler`) | 3260–3263 | DONE-SINCE | Same commit `fad9a7af` — title says "an MLX fault throws instead of killing the app." |
| Model bake-off verdict: don't switch models (12B-4bit is a trade not a win; QAT mobile build cannot load) | 3155–3178 | FOLDED | Decision stands unchallenged; no later SPEC/roadmap entry revisits the model choice. Recorded here so it isn't re-litigated — no action needed. |
| Alternative considered: bump mlx-swift-lm past `a47894a1` instead of re-downloading | 3180–3184 | SUPERSEDED | Overtaken by the actual fix — pin `defaultModelRevision` + raise the floor to `e6e3de75` (commit `b8f8540`), which is the mac-verified route that shipped. |
| PARKED behind fleet-ledger: "fleet ledger takes priority" (blocking a Mac `-runfile` test) | 3187–3191 | DONE-SINCE | The deciding test ran and is recorded a few lines earlier in the same doc (Mac succeeded, iPad failed identically) — moot once the root cause was found via that very test. |
| OWED: Mac sync only runs at launch + didBecomeActive (not a bug, a design note to remember) | 3193 | FOLDED | SPEC.md C220/C221 area (recording/sync contract, "out of the rewrite") and the general reconcile-sweep behavior in `SPEC.md`'s rewrite-target-3 section describe launch/foreground-gated sync as current design, not an open item. |
| OWED: first real export round, throwaway folder first | 3197 | OPEN | Duplicate of the `SharedExport` node's own "Tuur's first real-device run owed" — same open item, already counted above; not double-counted in the OPEN total. |
| OWED: unrated-note eyeball — export + language rounds are what's left | 3199 | DONE-SINCE | Language sync round-trip: "✅ CLOSED 2026-08-11 (device session, phone builds 133→134) … CONFIRMED WORKING BOTH WAYS on device" (same document, later section, line 3184-area / backlog ~2261 outside this slice but referenced at 3199's own neighboring text). Export half remains open (see `SharedExport` row above). |
| NEXT-in-order item: monthly-digest spike | 3204 | FOLDED | `i15` (idea, not yet noded) — plan carried verbatim into SPEC.md's "Parked ideas that are NOT decisions today" list (SPEC.md:1544-1552, "monthly digest"). |
| NEXT-in-order item: Plugin v1 bundle (inbox + doctor + listen) | 3206–3207 | FOLDED | `i14` / node `ObsidianPlugin`, same v1 bundle recommendation. |
| NEXT-in-order item: book pages in-app (roadmap i16) | 3208 | FOLDED | `i16` (idea, not yet noded — text explicitly says "mock-first design chat before building"). |
| NEXT-in-order item: timeline-in-Review (open design question) | 3208–3209 | OPEN | Not folded anywhere; no SPEC/roadmap mention of a "timeline" or "how did my thinking evolve" view outside the digest idea. Needs a roadmap idea entry. |

---

## THE UNRATED-NOTE MODEL (3331–3376)

| item | line | verdict | id / why |
|---|---|---|---|
| Phone chunk: exclude unrated memos from `JournalIndexService` embedding at index time (they currently DO appear in Related on phone/iPad) | 3369–3372 | OPEN | No SPEC clause, R-row, or BUGS entry matches this specific exclusion-at-index-time fix for the phone's embedding index. Closest is SPEC R58 ("Connections failure invisible on mobile, iPad cap 4") which is a different defect. Needs its own R-row or a BUGS §2 entry. |
| Digest ripple: "top-K by Connections degree" formally dead for unrated notes; digest mentions render as plain text never `[[links]]` | 3374–3376 | FOLDED | Folds into `i15`'s own selection rule, which already states unrated notes enter only via backlinks and render as plain text — consistent, not contradicted. |

---

## Tuur's menu verdicts (3379–3448)

| item | line | verdict | id / why |
|---|---|---|---|
| 9 "Daily, spoken": not mentioned/unreviewed | 3382–3383 | OPEN | No verdict recorded anywhere; not folded into `i14`'s bundle picks or any decision. |
| 10 Timeline: re-pitch, design unclear — needs its own idea/design chat | 3392–3394, 3442–3443 | OPEN | Same as the RESUME-HERE timeline row above — one open item, not double-counted. |
| Book pages idea (#7 spun bigger) — per-book page in Review/Books + vault export | 3394–3397 | FOLDED | `i16`. |
| 3 Connections: static tier REJECTED, live-Mac-only decided | 3384–3387 | FOLDED | `i14` / node `ObsidianPlugin` — "DECIDED: Connections is Mac-live ONLY … the static-sidecar tier was REJECTED." |
| ASR language sync: two-device round-trip owed (sync-contract change) | 3437–3438 | DONE-SINCE | "✅ CLOSED 2026-08-11 … CONFIRMED WORKING BOTH WAYS on device" (Tuur quote, phone builds 133→134), recorded later in the same doc (outside this slice but the closing entry is the direct resolution of this exact owed item). |

---

## THE MONTHLY DIGEST — the plan (3452–3499)

Whole plan is **FOLDED** → `i15` (idea, not yet noded as a roadmap node) and into SPEC.md's
"Parked ideas that are NOT decisions today" (SPEC.md:1544-1552, "monthly digest"). Its own open
tail:

| item | line | verdict | id / why |
|---|---|---|---|
| OPEN: cadence — monthly only, or weekly too? | 3496 | OPEN | Unresolved in `i15`'s text; no decision recorded. |
| OPEN: does the digest also land in Review as a pinned month card, or vault-only at first? | 3497 | OPEN | Same — unresolved. |
| OPEN: does an all-quiet month produce a digest or silence? (author's own rec: silence, no-bad-information doctrine) | 3498–3499 | OPEN | Unresolved; no-bad-information doctrine is a live principle (SPEC.md consent/lifecycle section) but this specific application is not decided. |

---

## NEXT CHUNK — `includeAudioInExport` needs to sync (3505–3522)

Duplicate of the item already covered under "ONE export engine" (line 2971). **OPEN**, folded into
node `SharedExport`'s "parked" note — not double-counted in the total.

---

## Done sections with no open tail (3526–3593, 3636–3647, 4086–4111)

"Unrated notes open as normal notes + importance drift" (3526), "two iPad-parity fixes" (3552),
"lighter Mac note header" (3576, Tuur-confirmed 2026-08-12 — "nothing owed on this trio"), "View
thread retired" (3636), and the m1b amendments (4086) are closed with no unresolved item recorded
in the text itself. No rows.

---

## Connections TIGHTNESS lens — DEFERRED (3597–3632)

Whole section **FOLDED** → `i13` (roadmap idea) — the design (3-step lens, live counts, own empty
state, no looser step than 0.45, first-mention scoping) and the build order (vault connected →
histogram → mock → build) are reproduced verbatim in `i13`'s text. Also listed in SPEC.md's parked
ideas (SPEC.md:1544-1552, "tightness lens"). Still gated on the Obsidian vault connecting — no
independent open item beyond that gate.

---

## Connections floating INSPECTOR — ROUND 2 (3651–3684)

| item | line | verdict | id / why |
|---|---|---|---|
| OWED: Tuur's live eyeball — (a) spring on open/close, (b) column re-wrap janky mid-animation, (c) the ⋯ chip | 3682–3684 | SUPERSEDED | This inspector was itself superseded by the later note-view stacking rebuild (b130) and the signed "chrome that belongs" spec (b132, Tuur-confirmed "this looks soo good" 2026-07-24), which replaced the Connections summon/animation mechanism entirely (word-only summon, pinned ◧, panel slides beneath it). The specific spring/chip questioned here no longer describes the shipped UI. |

---

## Chrome that belongs mirrored to Mac — ROUND 1 (3688–3741)

| item | line | verdict | id / why |
|---|---|---|---|
| OWED 1: the whole bar in the real window (Screen Recording not grantable to the shell) | 3697–3698 | OPEN | No later confirmation found for this specific Mac bar eyeball; the Mac note header was separately Tuur-confirmed 2026-08-12 ("i had already checked that, it all looked good") for header/player/panel colours — but that confirmation names those three items specifically, not "the whole bar." Treat as unresolved. |
| OWED 2: the ⋯ chip specifically unverified (Menu can't render in ImageRenderer) | 3699–3702 | DONE-SINCE | Later same document: "-snapshot-inspector is HOSTED … caught that the ⋯ chip wasn't drawing at all (on macOS a Menu label's background never draws — the chip must wrap the MENU, not its label)" — found and fixed in the very next round (3670–3673 area), same section this item sits above. |
| OWED 3: judgement call — quiet→accent summon subtle on Mac's wider dark bg | 3703–3705 | OPEN | No verdict recorded; not mentioned again. |

---

## iPad note view: signed "chrome that belongs" BUILT (3745–3804)

Closed with device confirmations in the text itself ("Tuur device eyeball 2026-07-24: 'this looks
soo good!!'", phone install done, bookmark/ePub sync confirmed working on device). No open rows.
The remaining line — "only the undiagnosed 'could not process', then promote after the book-import
chat lands" — is **DONE-SINCE**: the "could not process" bug is the same iPad-polish saga closed by
commit `b8f8540` and the 2026-08-12 "THE iPAD POLISHES" close, covered above.

---

## iPad note view = direction A (superseded, 3808–3865)

Section header already says superseded by the signed spec above. Its internal "OWED (Tuur)" line
(the live-feel eyeball of build 130, the ◨ corner-pin veto question, and whether the player sits
too far from the text) is **SUPERSEDED** for the same reason as the ROUND 2 inspector row: the
signed "chrome that belongs" spec (b132) locked the final design and Tuur confirmed it on device.
No open row.

---

## iPad chrome build, 2026-07-23 ~19:25 session (3869–3946)

| item | line | verdict | id / why |
|---|---|---|---|
| Owed: Tuur's own eyeball of build 120 on the iPad (note bar both orientations, header, running state) | 3921–3925 | SUPERSEDED | Same reasoning as above — build 120's note bar was rebuilt twice more before the signed spec; Tuur's actual confirmed eyeball is of build 132. |
| Install 120 on the phone, confirm compact layout untouched | 3926–3928 | DONE-SINCE | Phone install explicitly recorded a few lines later in this same section family ("Phone (iPhone 13) install of 132 done 2026-07-24 (compact = layout unchanged)"), a later build than 120, superseding this specific ask. |
| Processing failure "could not process" — still undiagnosed at this point | 3929–3933 | DONE-SINCE | Diagnosed and fixed; see the iPad-polish saga (commit `b8f8540`, closed 2026-08-12). |
| Bookmark + ePub sync round-trips unwitnessed | 3934–3936 | DONE-SINCE | "Bookmark + ePub sync CONFIRMED WORKING on device 2026-07-24 (Tuur)" — same document, a few lines above this item's section. |
| Open with Tuur: the ＋ placement (parked in the bar) | 3937–3938 | FOLDED | Roadmap node `IPadMacVerbs` (done 2026-08-18): "The + chip folded into ⋯ (addRecording joined the shared NoteMenuItem vocabulary)" — the placement question was settled by that change. |
| Open with Tuur: is the Mac's "Mark all as Passing" bulk wording right? | 3939 | OPEN | Not answered anywhere; roadmap `IPadWave1` note still lists "the Mac's 'Mark all as Passing' wording question" as owed as of its current text. |
| Mac popover: Sort ONLY — porting the iPad's place/photo filters to the Mac is a follow-up | 3937 (approx, "SCOPE / OWED") | DROPPED | Same document, later same session (build 126, "Place + Has-photos removed from BOTH apps"): the filters this item proposed porting were removed from both apps instead of ported. The doc itself states the reason. |
| Owed: iPad Filter sheet contents on device (sim stuck landscape) | ~3938 | OPEN | No later device confirmation found. |
| Owed: Mac Dev redeploy to eyeball the Filter popover | ~3938 | OPEN | No later confirmation found. |
| Filter sheet bigger + trimmed — big sheet only sim-verified | 3941–3946 | OPEN | No device confirmation recorded later in the doc or in the live ledgers. |
| Owed: Mac Dev redeploy to eyeball the Date popover; phone install of 126 device round | 3946 | OPEN | Not confirmed later. |

---

## HEADER = THE MAC SIDEBAR — build 121 (open naming calls, ~3944–4015 area)

| item | line | verdict | id / why |
|---|---|---|---|
| Landscape reclaim unverified on sim, Tuur's device-landscape confirm owed | 4005–4008 | OPEN | No later confirmation of the landscape band fix specifically found. |
| Open naming calls: Mac "Upload" vs iPad "Import"; Mac "Skrift + gear" vs iPad "Notes + Select + ⋯" | 4011–4013 | DONE-SINCE | Resolved later the same day, same document (build 122, "HEADER POLISH PASS"): "Import on BOTH apps … the Mac's button was 'Upload'; one word now" and "Identity row: kept Notes + Select (he 'like[s] that the iPad has select'); NOT Skrift+gear." |

---

## Column toggles — build 118 (4017–4031)

| item | line | verdict | id / why |
|---|---|---|---|
| Open, needs live tap-through (a): re-opening the list from the icon didn't restore the column in a scripted run | 4025–4027 | SUPERSEDED | The `NavigationSplitView(columnVisibility:)` two-way sync this bug lived in was deleted wholesale in the note-view stacking rebuild (b130, `1f81136`): "`NavigationSplitView` is GONE… `listVisible`/`connectionsVisible` are the only layout state." The mechanism the bug depended on no longer exists. |
| Open, needs live tap-through (b): ghost player-bar row draws behind the tab strip while the list is hidden | 4028–4031 | SUPERSEDED | Same rebuild — the floating glass capsule this described was replaced by a full-note-width docked bar in the same stacking rebuild, and the bottom-floating-player-standing-down fix is separately recorded fixed in the ~19:25 session fix wave ("bottom floating player stands down at regular width" fix, same document). |

---

## The chapter bug + ePub file sync (4033–4078)

Closed within the document (self-heal shipped, 7 tests, ePub file sync built and device-round
confirmed same week). No open rows except:

| item | line | verdict | id / why |
|---|---|---|---|
| Device round owed: phone uploads on next foreground reconcile → iPad should show attached ePub, must not re-align | 4056–4058 | OPEN | No later confirmation of this exact round-trip found in the doc or live ledgers. |

---

## Mac Places map zooms out (4079–4084)

**DONE-SINCE.** Roadmap node `IPadWave1` shipped log, 2026-07-23pm entry: "Mac map dive clamp (b90
port, Tuur's 7→3+4 repro)" — the fix this bug asked for shipped the same week it was filed.

---

## Original decision list, item 7 (4113–4149)

| item | line | verdict | id / why |
|---|---|---|---|
| Notes list rows on iPad: OPEN — Tuur unconvinced by phone-dialect, decide from mock variant A vs B | ~4139–4147 | DONE-SINCE | Resolved: "m1b RESOLVED (2026-07-23) — Tuur picked B + the correction that closed the verb loop" (same document, later section already covered above as the unrated-note quiet-row build). Also recorded in roadmap `IPadWave1`: "m1b resolved: B + rating-IS-the-flag." |
| Parked/flagged: SHELL last-note-delete leaves a stale pane until a tap | ~4143 | OPEN | No fix recorded anywhere live. |
| Parked/flagged: DETAIL related derivation double-computes at regular width | ~4144 | OPEN | Not in `plan/perf-sweep.md`'s candidate list (which covers different double-scan sites, not this one) or any SPEC R-row. |
| Parked/flagged: BOOKS added a bookmark-toggle chip beyond the mock | ~4145 | OPEN | Not resolved anywhere; not flagged as a mock-drift item in any later mock sign-off. |

---

## ⭐ CONTINUE HERE 2026-07-22 marathon session (4150–4206)

Items 0, 0b are marked done-and-verified in the text itself. Remaining:

| item | line | verdict | id / why |
|---|---|---|---|
| Item 2: walkthrough tail — untouched-note detail fade line, WayOut row peek + Bring back, b90 map trio, "0.1 · Passing" render, Mac unified Notes list eyeball | 4160–4164 | DONE-SINCE | Each of these is separately closed later in the document (fading-search confirmed 2026-07-21; b90 map trio + Mac map dive clamp shipped 2026-07-23pm; Mac header/panel/player Tuur-confirmed 2026-08-12). |
| Item 3: prod promotion decision — profile phone list/search paths first | 4165–4169 | FOLDED | `plan/perf-sweep.md` §2 rows #2 and #5, and SPEC R92 (`MemosListView` per-row corpus scans) directly cover the phone list/search perf audit this asked for — folded into the v2 perf sweep, C278/R92. |
| Item 4: update the iPad's old Skrift Dev build (local-only doctrine risk) | 4170–4172 | OPEN | Generic device-hygiene note, not tracked as a distinct item anywhere; superseded in practice by the many later iPad builds recorded in this same file, but no explicit "old build updated" confirmation exists. |
| Item 5: next build lane candidates — reading-mode redesign, journal-desktop board, Connections owed items | 4173–4175 | FOLDED | Reading-mode redesign = `P9b` (status `planned`) and CLAUDE.md's `audiobook-player-reading-mode` mock, signed off 2026-06-19, not yet built. Journal-desktop = CLAUDE.md's `journal-desktop` mock, signed off 2026-07-11, not yet built (roadmap references journal-desktop §2/§3 as completed pieces only). |

---

## Lifecycle IA overhaul sections (4207–4327)

All items in "🧬 lifecycle IA overhaul: BUILT + MACHINE-VERIFIED" and "🧬 (build record)" are
closed in the text with commits and device confirmations (Tuur walkthroughs, b92 fading-search
confirmed, build 88 on-device verified). No open rows — this whole stretch reads DONE, matching
roadmap node `LifeIA`/`LifeClock` (both would show `status: done` given the volume of confirmed
closes; not independently re-verified line-by-line here since every sub-item already carries its
own resolution in the source text).

---

## ⭐ CONTINUE HERE 2026-07-18 session (4329–4346)

| item | line | verdict | id / why |
|---|---|---|---|
| Item 2: pick a lane — 📤 exportability or 📍 place notes | 4340–4341 | FOLDED | Both sections are covered directly below (place notes → `i` idea/SPEC parked list; exportability gaps → mixed, see below). |
| Item 3: 📖 ePub↔audiobook alignment spikes 1–2 | 4342–4346 | DONE-SINCE | `EPubAlign` roadmap node status is effectively closed per its own text ("THE 📖 LANE IS DONE" appears later in this same slice, backlog ~4150). |

---

## 📍 Place notes with feeling (4348–4375)

Whole direction is **FOLDED** → SPEC.md's "Parked ideas that are NOT decisions today"
(SPEC.md:1544-1552): "place-triggered resurfacing" appears verbatim. No roadmap node exists yet
("NEEDS DESIGN SESSION before code" per the doc's own header — consistent with it staying parked).
The three candidate directions (geofencing resurfacing, explicit intent facet, capture friction —
goo.gl link resolution) are not separately decided; `goo.gl` short-link handling is specifically
addressed by SPEC.md line 1038 / pre-registered-IDENTICAL list (line 1296): "plain cards by design"
— i.e. the capture-friction candidate's goo.gl half is **DECIDED** (kept as-is, not fixed).

---

## 📤 Full exportability — markdown as the durable home (4377–4420)

| item | line | verdict | id / why |
|---|---|---|---|
| Gap 1: attachments never reach the vault from the phone (markdown-only phone publish) | 4390–4396 | DONE-SINCE | Node `SharedExport`, shipped 2026-07-26: "Phone gained photos-as-embeds + audio + the missing Settings front door." |
| Gap 2: location coordinates dropped from frontmatter (placeName only, no lat/lon) | 4397–4399 | DROPPED | SPEC.md D12: "✅ DECIDED 2026-09-22: add `duration` and the created date; skip lat/lon (raw coordinates) and the reminder." |
| Gap 3: YAML should carry all metadata — add lat/lon, duration, createdAt/editedAt, remindAt | 4400–4404 | MIXED — FOLDED/DROPPED | SPEC.md D12: duration + created date **FOLDED** (add); lat/lon + reminder **DROPPED** (skip, explicit decision). `editedAt` is not mentioned in D12 and has no separate clause — **OPEN** for that one field specifically. |
| Gap 4: audiobooks — export bookmarks into a per-book index note (vault face of Commonplace Book) | 4405–4410 | FOLDED | SPEC.md's parked-ideas list (line 1546): "commonplace book" — and `i16`/roadmap node `Commonplace` (title "Commonplace Book + quote cards") exists as a distinct roadmap idea already carrying this. |
| Gap 5: no completeness surface — nothing answers "is my vault a full mirror?" | 4412 | OPEN | No SPEC clause, roadmap node, or BUGS row addresses a vault-completeness/coverage surface. Needs a new roadmap idea or SPEC "Parked ideas" addition. |

---

## OPEN items in this slice

**Count: 37** (distinct — duplicate mentions of the same item collapsed to one, e.g. the timeline
idea and the first export-round ask each appear twice in the source and are counted once).

Five most important, my judgment:

1. **Completeness check for the iPad's Polish model download** (line 3257–3259 area) — the
   "Remove model" escape hatch shipped, but `isModelOnDisk`'s 500 MB floor is still the only
   signal and its own code comment calls it "advisory only… device-owed to confirm." A bad
   partial download can still read as fully downloaded.
2. **No vault-completeness surface** (line 4412) — nothing in the app answers "is my vault a
   full mirror of my notes," despite that being the stated principle behind the whole export
   engine.
3. **Real-device export rounds still unverified** (lines 2913–2914, 2967) — both `SharedExport`
   and `ExportDestinations` ship logs explicitly still carry "Tuur's device round owed"; this is
   the single largest concrete gate between the export work and being trusted on the real vault.
4. **Timeline / "how did my thinking evolve" view** (lines 3208–3209, 3392–3394) — Tuur
   reacted well to the concept twice but it has no design chat, no mock, no roadmap idea entry
   anywhere.
5. **Four open questions to the portfolio-repo chat** (lines 2916–2918, duplicated 2922–2924) —
   `_inspiration` bucket naming, dangling `[[Jack]]` links, a site "type" concept, and whether the
   archive accepts video — none answered in SPEC.md's archive-contract section despite that
   section otherwise being current as of 2026-09-23.
