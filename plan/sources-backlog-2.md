# Source ledger — archive/state-2026-09/backlog.md, lines 1163-2576

Date 2026-09-23. Written under SPEC.md C276 ("a cited document is not a folded document").
Range: `sed -n '1163,2576p' archive/state-2026-09/backlog.md`, read in full.
Verdicts checked against SPEC.md (C1-C280 as currently numbered), R1-R94, D1-D100, BUGS.md,
roadmap/roadmap.yaml, plan/perf-sweep.md, and `git log` where a ledger row was silent.

## The app feels slow (line 1163)

| item (short, the doc's words) | line | verdict | id / why |
|---|---|---|---|
| "the app seems kind of slow compared to other apps" — general slowness, launch/foreground pile-up suspected | 1163-1181 | FOLDED | BUGS.md §3 "The app feels slow next to other apps" (same Tuur quote, 2026-08-18); `plan/perf-sweep.md` R90-R94 / C276-C280 name the concrete sites (Mac editor restyle, asset fetch, list corpus scans, `recordingsDirectory` mkdir, nine unconditional sweeps); AUDIT_PLAN.md §2 P1-P7 is the same launch-sweep list this entry names verbatim. |

## Note creation + editing: "Apple Notes is the bar" (line 1185)

| item (short, the doc's words) | line | verdict | id / why |
|---|---|---|---|
| Phone has no text-first note-creation button (iPad got one same day) | 1207 | FOLDED | C112/C114/D28 — "Quick note: a New Note action... CONFIRMED 2026-09-21"; "the app opens into THE LIST, with the New Note action one tap away." |
| Editing feel vs Apple Notes stays OPEN — overlaps the parked capture-as-note/note-editing kickoff (2026-07-07) and a PARKED note-detail mock | 1208-1211 | FOLDED | C113 — "The editor feels like Apple Notes: no lag while typing... Today it is 'quite slow and clunky' (Tuur 2026-09-21)." Same complaint, current clause, explicitly told to profile before rebuilding (matches this entry's own "not a rewrite on suspicion"). |
| capture-as-note (annotation folded into the body) | 1209 (context) | FOLDED | D73 — "BUILDER DEFAULT 2026-09-22 (internal; veto any time) — Capture-as-note." |

## ConnectionsPanel views are twinned and drifted (line 1240)

| item (short, the doc's words) | line | verdict | id / why |
|---|---|---|---|
| Mac and iPad ConnectionsPanel are separate hand-built implementations; card chrome vs bare rows still wants the shared-view fix ("still stands") | 1240-1285 | SUPERSEDED | C232 now specs the two chromes as DELIBERATELY different platform UI (Mac = floating inspector that stays open, iPad = per-note visitor sheet, thread retired on iPad/Mac, kept on the phone card) — not a unify-to-one-view job any more. The concrete gap that survived is R58 ("iPad panel hard-capped at 4 rows with a dead 'Show all'; cap should = the Mac's 7 + Show all") plus C239's general twin-audit ("Connections panel" is named on its known-duplication list, to fold into Shared or mark a deliberate difference — which C232 has now done for the chrome, leaving R58 as the residual). |
| Amber-past-refine-wall colour missing on iPad | 1244-1246 | done in source (skip — text marks it ✅ FIXED 2026-08-14, b148) | n/a |

## Share a book (line 1286)

| item (short, the doc's words) | line | verdict | id / why |
|---|---|---|---|
| `.skriftbook` format, one-option share (audio + ePub if present), person-to-person only — SIGNED OFF + spec | 1286-1403 (spec portion) | FOLDED | C79, C107, C146 — "Book sharing = one `.skriftbook` with audio + ePub + sidecars, never position/..."; "a `.skriftbook` arriving through the share sheet goes to the book importer." |
| "(5) the device round is entirely owed — nothing has been run end-to-end and neither sheet has been looked at" | 1448-1449 | FOLDED | D27 — "✅ DECIDED 2026-09-22: merge to main now; the two-device round stays owed." Same open item, current decision record. |

## ONE rated/unrated rule (line 1407)

| item (short, the doc's words) | line | verdict | id / why |
|---|---|---|---|
| "Still owed: the phone half (`canSummon`) rides the next phone build" | 1443 | DONE-SINCE | The same section (line 1430-1431) already shows `canSummon` routed in the same commit batch ("Routed with zero behavior change: ... ConnectionsPanelLogic.canSummon"); dozens of phone builds have shipped since 2026-07-28 (b134 onward per later sections in this same file), so the "next build" gate has long passed. No open ledger row references `canSummon` as broken today. |

## Audit round 2 — CloudKit races, one aligner, titles everywhere / Mac records (line 1451)

| item (short, the doc's words) | line | verdict | id / why |
|---|---|---|---|
| "OWED: the button's own live run" — Tuur presses Record, talks, stops, confirms end to end (repeated at Rounds 6, 8) | 1642, 1705 | FOLDED | C118 — Tuur's eyeball-owed checklist explicitly lists "the Mac live Record press" as unverified. |
| Round 5: "the ONE manual step" — `tccutil reset Microphone com.skrift.desktop.dev` needed to clear a self-inflicted TCC denial | 1586-1592 | DONE-SINCE | Round 7 (line 1725-1727, same doc) found the denial theory wrong — "the GUI DID prompt and he DID Allow" — and Rounds 7-8 recorded successful hardware-verified captures without that reset. Superseded by its own later rounds. |
| Round 6/7/8 mic-input policy work | 1642-1719 | done in source (skip — marked ✅ FIXED/shipped with test counts) | n/a |
| "OWED before prod promotion: a clean full phone-suite re-run once the host audio stack recovers" | 1716-1717 | FOLDED | roadmap.yaml node `W8` backlog — "clean phone re-run before prod" (same wording). |
| "the mid-take EDIT live check ... never yet human-verified"; "a live-eyeball that the resting note's PARAGRAPHS survive"; "karaoke-after-edit parked decision" | 1799-1802 (and restated 1855, 1884-1886, 1911-1912, 1980-1981) | FOLDED | roadmap.yaml node `W8` backlog: "Still owed before done: the mid-take edit LIVE check (chip + survival), resting-note paragraph eyeball, karaoke-after-edit decision (parked), clean phone re-run before prod." Also C118 lists "the Mac mid-take edit" as unverified. |
| "i17 in-Skrift cursor-follow = design item, mock first, only if Tuur pulls it in" | 1802, 1829-1831 | DROPPED | roadmap.yaml idea node `i17` — "⏸ NEAR-HALF PARKED BY TUUR 2026-07-28 eve ('kind of similar to Scribble… maybe we don't need the Apple version — keep using what we have')." Tuur's own words drop it. |
| "③ `-recordingest` regression re-check at next convenience" | 1982 | DONE-SINCE | Same feature's shipped log (roadmap.yaml lines 2174, 2189) records `-recordingest` was run and proved words-on-arrival + unrated on real takes, 648/0, 2026-07-28 — after this line was written. |
| Round 11 item 2: "waveform moves but no words for a while" on first take — cold-start ASR pre-warm candidate, "Not fixed this session" | 1741-1743 | OPEN | No clause or roadmap backlog row addresses a Mac ASR-model pre-warm-on-Record-press. Would need a new C row or a roadmap backlog line under `W8`/`RecHard` naming this specific cold-start cost. |
| Round 11 item 3: "~20 s ceiling commit" — AMBIVALENT, left as-is, "revisit only if it keeps bothering him" | 1744-1747 | SUPERSEDED | The whole pause/ceiling rotation model this worried about was replaced by TEXT-STABILITY settle (Round 10, same doc, "KILLED RMS FOR GOOD" — settle is now two identical tail decodes, not a timer/ceiling race), confirmed felt-right by Tuur ("way better", Take 6). The ceiling concern no longer applies to the shipped mechanism. |
| "OPEN DECISION: edited takes currently store NO word timings — karaoke for them needs a timings-only file pass... Parked; decide when karaoke-on-unrated actually matters" | 1884-1886 | FOLDED | roadmap.yaml `W8` backlog "karaoke-after-edit decision (parked)" — identical open decision, same live ledger. |
| "The caret/insertion point lands ~6 lines below the click. Unexplained... self-resolved once" | 2161-2163 | OPEN | Not reproduced, not named in any SPEC clause, BUGS row, or roadmap node. Would need a BUGS.md §3 ("reported, not yet diagnosed") row if it recurs — nothing to fold to until it does. |
| Diarization heal "NOT EXERCISABLE on the current store... To exercise: rate one of those two on the phone" | 2170-2175 | DONE-SINCE | C45 — "Late assets (photos, word timings, diarization) heal on the next sweep" is now the general, shipped rule; commit `04dd24d4` ("diarization late-asset heal + trace the live reconcile trigger") built the diarization twin of `adoptLateWordTimings` this entry was waiting on the code for. The specific "can't exercise it yet" note is stale — the heal code exists and is unit-tested. |
| "~~Untrack the generated `Info.plist`s~~ — DONE 2026-07-27" | 2166-2167 | done in source (skip — marked DONE, confirmed still true: `git ls-files` shows no tracked `Info.plist`, commit `2dc451ab`) | n/a |

## Waste audit + CloudKit asset-race fix (line 2178)

| item (short, the doc's words) | line | verdict | id / why |
|---|---|---|---|
| 1. "Sync only lands on APP restart" — the live CloudKit-import trigger appears not to fire; suspect remote-change push/subscription. "⬅ NEXT." | 2215-2217 | OPEN | Commit `04dd24d4` (same day) added trace instrumentation for exactly this ("Tuur's standing report: a phone memo reaches the Mac only after QUITTING AND RELAUNCHING... this logs every trigger") but that commit diagnoses, it does not fix. No later commit, SPEC clause, BUGS row, or roadmap node closes it. Needs a BUGS.md row or an R-clause: "a live CloudKit remote-change import must update the Mac without requiring app restart." |
| 2. "Phone note-list shows the OLD title" even though the Mac's generated title synced | 2218-2219 | DONE-SINCE | Commit `6123d30c` — "fix(📱): the note list shows the Mac's title instead of the body text." |
| 3. "Diarization late-asset heal — the twin of `adoptLateWordTimings`, same pattern" | 2220 | DONE-SINCE | Commit `04dd24d4`, same as above; also generalized under C45. |
| 4. "Re-land the karaoke perf cache (`315206b`, reverted)" | 2221-2223 | OPEN | `git log` confirms `315206b6` was reverted by `d898771e` and never re-landed; no SPEC clause or roadmap node re-raises the karaoke read-along perf cache. Would need a new perf row (plan/perf-sweep.md style) if this still matters. |
| 5. "Untrack the generated `Info.plist` files... Deferred because the open iPad branch has `App/Info.plist` in its diff" | 2224-2226 | DONE-SINCE | Same task, resolved and confirmed above (commit `2dc451ab`; the iPad branch that blocked it has long since merged). |
| 6a. "6 × `DriftedPair` colours (design decisions, iPad branch contests)" | 2227-2228 | OPEN | `DriftedPair` still has 9 call sites in `Skrift_Native` today — never consolidated. Falls under C239's general twin-audit umbrella (`plan/twins.md` is supposed to list every Mac/phone rule-copy and fold or mark it) but is not itself named there yet. |
| 6b. "`SignificanceCircles`/`Theme` dedup (iPad branch contests)" | 2227-2228 | OPEN | Same as above — falls under C239's umbrella, not individually resolved; C240 states the shared-view pattern to use but no commit applies it to SignificanceCircles/Theme since this line. |
| 6c. "`CaptureInboxDrainer.process` 410-line split (device-critical share-ingest, deserves its own round)" | 2228-2229 | OPEN | Confirmed still true in source: `Skrift_Native/SkriftMobile/Services/Capture/CaptureInboxDrainer.swift`, `process(entry:...)` starts at line 128 and runs to the file's closing brace near line 538 — un-split. No clause or roadmap node addresses this refactor. |

## Audio-session round (line 2231) — P1 "Starting…" / book-stops-mid-listen

| item (short, the doc's words) | line | verdict | id / why |
|---|---|---|---|
| "Revisit item (roadmap): AirPods-mic recording for the pocket case needs a flip that can't eat capture" | 2357-2358 | FOLDED | roadmap.yaml node `RecHard` backlog — "Revisit AirPods-mic recording (pocket dictation records from the phone now): needs a flip that can't eat capture — pre-flip BEFORE capture on explicit intent, or accept the phone mic." Verbatim carry-over. |
| "Device round DEFERRED by Tuur 2026-07-26... Do NOT re-chase it; it is not owed" (book stops mid-listen, other app's audio resumes) | 2412-2415 | DROPPED | Tuur's own words in the same line, and roadmap.yaml node `RecHard` backlog independently records: "'Audiobook round (b121) — device test DEFERRED by Tuur 2026-07-26... Not owed.'" Both sources agree this is explicitly not open. |
| "Instrumentation SHIPPED this session (unbuilt — verify it compiles first)" | 2444 | DONE-SINCE | Rounds 6-8 (earlier in this same document, dated after this instrumentation) build and gate repeatedly on Dev using exactly this DevLog instrumentation (e.g. Round 8 "676/0 + full build + vision-check... deployed"), so it compiled and has been exercised many times since. |

## Phone feedback 2026-07-23 — ePub/audiobook-text flow (line 2458)

| item (short, the doc's words) | line | verdict | id / why |
|---|---|---|---|
| P1 · "not all parts of the ePub were displayed/ingested" — whole-ePub ingest bug, corrects an earlier diagnosis | 2465-2468 | OPEN | C227 covers alignment *verdicts* (aligned/partial/rejected) for an ePub already ingested, not ingest-completeness itself. No clause or BUGS row addresses "some parts of an ingested ePub never display." Needs an R-row or BUGS entry naming the ingest path, not the aligner. |
| P2 · "Big-ePub import UX (13-hour book): long load, no progress bar, unclear whether listening can continue" | 2470-2471 | OPEN | No progress-bar or long-import-UX clause found in SPEC.md or roadmap.yaml. |
| P2 · "Block ePub upload while the book is still transcribing — currently undefined" | 2472-2473 | OPEN | No clause guards ePub upload against an in-flight transcription; the only "while transcribing" hit in SPEC.md (C232) is about the Connections embedder yielding the ANE, unrelated. |
| P2 · "Unify the transcribe-book menu with the ePub-upload menu: one 'add text' flow, two levels" | 2474 | DONE-SINCE | roadmap.yaml — "Unified 'Text' sheet + A0 import prompt — SIGNED OFF AND BUILT 2026-07-23, same session (mock = mocks/book-text-unified.html)." Same day, same ask, shipped. |

## One-clock lifecycle: OWED (next session) (line 2567)

| item (short, the doc's words) | line | verdict | id / why |
|---|---|---|---|
| "Deploy Dev both apps + eyeball: peek... quiet-row menu verbs... migration bump check" | 2568-2571 | FOLDED | C118 — "the one-clock walkthrough on both apps" is listed as built-but-Tuur's-eyeball-owed; roadmap.yaml independently confirms "Owed: Tuur walkthroughs only" for the same lifecycle feature. |
| "🧬 walkthrough items phrased in the old vocabulary are OBSOLETE" | 2572-2573 | FOLDED | Same C118 walkthrough-owed item; this is a caution for whoever does that walkthrough, not a separate task. |
| "Prod promotion: one-clock rides along with the 🧬+📖 promotion" | 2574-2576 | DONE-SINCE | Many prod promotions have shipped since 2026-07-22 (this document and SPEC.md both describe work through 2026-09-22/23), so the "next promotion" this refers to has long since happened. |

## OPEN items in this slice

Count: **10**

1. Round 11 item 2 — Mac ASR cold-start pre-warm on Record press (line 1741-1743).
2. Caret/insertion point lands ~6 lines below click, unreproduced (line 2161-2163).
3. Sync only lands on app restart — CloudKit remote-change trigger not firing live, "⬅ NEXT" (line 2215-2217).
4. Re-land the karaoke read-along perf cache, reverted and never redone (line 2221-2223).
5. 6× `DriftedPair` colour duplication, still 9 call sites, not folded (line 2227-2228).
6. `SignificanceCircles`/`Theme` dedup, not folded (line 2227-2228).
7. `CaptureInboxDrainer.process` still a 410-line unsplit function (line 2228-2229).
8. Partial-ePub ingest bug — not all of an ePub displays/ingests (line 2465-2468).
9. Big-ePub import UX — no progress bar, unclear if listening continues (line 2470-2471).
10. Block ePub upload while the book is still transcribing — undefined today (line 2472-2473).
