# Commit source ledger — slice 2

Date: 2026-09-23. Rule in force: SPEC.md C276 (a cited document is not a folded document).
Commit range: rev-list --reverse main, positions 135-373 (239 commits), oldest first.
Span: 2026-06-04 to 2026-06-09 (the Electron/Python "overhaul" tail + the mobile+desktop
native rewrite through Phase 9 and the diarization spike). This slice is almost entirely
agent build narration; direct Tuur quotes/attributions are rare and are called out below.

## iPad
None in this slice (iPad track starts later).

## Mac parity / desktop native build
| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| WAIT to converge mobile-native + desktop-native until desktop stabilizes (user's call) | 90639f47 | 2026-06-07 | DONE-SINCE | merged 9e338b6c same day |
| Parity-then-retire the old RN/Electron/Python apps; user decision owed on when | a41c1e4e | 2026-06-07 | DONE-SINCE | archived intact 8b3a409b (convergence reorg); CLAUDE.md confirms `archive/` holds them |
| Noise-reduction slider removed rather than left lying about doing something (explicit user decision, not just a code call) | 90e55652 | 2026-06-07 | DONE-SINCE | shipped in the same commit |
| Auto-suggest-people (auto-detect new names from context) rejected; right-click "Add as name" is the reliable, user-driven alternative | 6e826221 | 2026-06-07 | FOLDED | current design (`Sanitiser` opt-out linking of the known roster only, no new-person auto-detect) matches; FEATURES.md "Phone in-place name-linking" / "Opt-out naming" confirm no auto-suggest-new-person feature exists |
| Dev/prod bundle-ID split (own OS data container, "Skrift Dev" name, promote = additive migration), deferred to after the mobile batch (user's call) | f7aeee92, 5415b52e, ebd777e5 | 2026-06-08 | DONE-SINCE | shipped same window; now standing architecture in CLAUDE.md "Dev vs prod" section; roadmap.yaml:1915 |
| Send feedback (record+type+screenshot → Mail) ported from Shhhcribble | bd70ceb4 | 2026-06-08 | DONE-SINCE (mobile only) | FEATURES.md:358 — mobile ✅, desktop port explicitly "deferred" (➖), not tracked as an open item anywhere else — OPEN for desktop |

## Editor / note UI (desktop review surface)
| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| R3 resolver rework after use-testing: marks too faint, no visible change after apply, should ASK "who is X" and auto-apply, escalate to per-occurrence only when different people | a1db6ceb | 2026-06-07 | DONE-SINCE | shipped in the same commit; still the shape of "Phone in-place name-linking" / desktop resolver per FEATURES.md |
| Walkthrough contrast/title/resolver/significance/label fixes found live with Tuur | d49a8568 | 2026-06-07 | DONE-SINCE | shipped same commit |
| Names-list "gonna get really long" concern | f6b10497 | 2026-06-07 | DONE-SINCE | filter box added same commit |
| "text is black" / dark-on-dark controls kept recurring | 1689ae97 | 2026-06-07 | DONE-SINCE | force-dark appearance fix same commit |
| Karaoke reflow + click-to-seek complaints (two, one root cause) | 0c34cc7e | 2026-06-07 | DONE-SINCE | same-NSTextView fix shipped same commit |

## Capture / share
| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Capture items (share URL/text/image) confirmed cross-track (native Mac drops non-audio uploads); deferred to a coordinated mobile+desktop build after convergence | 90639f47 | 2026-06-07 | DONE-SINCE | built 2026-06-12 per FEATURES.md:311, explicitly "NOT deferred (this row was stale)" |
| Product ideas parked: Backlink Weaver, context-aware enhancement, People Timeline | e226cac0 | 2026-06-07 | OPEN | none of the three names appear anywhere in SPEC.md, FEATURES.md, or roadmap.yaml — needs a clause or an explicit "not doing" if still wanted |
| Import video → transcribe, with the real embedded recording date (not import time) | 3c9978fd | 2026-06-09 | FOLDED | SPEC.md D69/C68 (video handling); FEATURES.md notes video export explicitly cut ("skip them," Tuur) but video **import**-and-transcribe is covered by the same clause family — confirm against D69 text if scope differs |

## Audiobooks
None in this slice (audiobook track starts much later).

## Names
| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "Add '…' as…" should let you pick an EXISTING person as an alias, not always create a new one | 59bef395 | 2026-06-07 | DONE-SINCE | shipped same commit |

## Export / privacy
None distinct in this slice beyond the north-star item below (export destinations land later).

## Lifecycle / rating
| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "only >0 significance is suitable for transfer — don't send stupid messages to the Mac" (flag-to-send gating) | 76da8167 | 2026-06-08 | FOLDED | SPEC.md:423 "flag-to-PROCESS, never flag-to-send" is the CORRECTED model (2026-07-20 per memory) — the original phrasing here was superseded by that correction, but the underlying gate (0 = stays local, >0 syncs) is still live: FEATURES.md:269 "Significance-gated ingest" |
| North star (first stated this session): Skrift feeds Obsidian, doesn't replace it; surface how ideas evolve over time — "this resembles your 2019/2021 notes" via on-device embeddings + a related-past-notes surface | e5f3177b | 2026-06-07 | FOLDED | SPEC.md:1706 Decisions log, verbatim; C231/C232 (Connections panel) build on it |

## Recording
| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Remove on-device Re-transcribe on the phone (explicit user request) | 97a3bf17 | 2026-06-07 | DONE-SINCE | shipped same commit |
| "Why is there an edit field — text should always be editable" | c07d1003 | 2026-06-09 | DONE-SINCE | always-editable inline transcript shipped same commit |
| Significance slider fights the page-swipe gesture (device feedback, three rounds: highPriorityGesture → tap-only → drag restored) | cda04bec, ca05a5bb, d96dafb4 | 2026-06-08/09 | DONE-SINCE | root-caused to the TabView(.page) host and fixed by the ScrollView-paging rewrite (d96dafb4) |
| Liquid Glass reads flat/frosted on device, not the real refractive look wanted | 6bf74dba, b19c688f, 5d606464 | 2026-06-08/09 | DONE-SINCE | root cause was Reduce Motion throttling glass on the A15, not the code; `.clear` style shipped 5d606464; FEATURES.md:57 confirms glass shipped, later de-floated 2026-07-25 |
| "Reverted the glass tint — not the answer" | 34e2689c | 2026-06-09 | SUPERSEDED | by 5d606464/d96dafb4's real fix (ScrollView host + `.clear` style), same week |
| Light-glass-island bar proposal left "untouched pending the user's on-device pick" | b19c688f | 2026-06-09 | SUPERSEDED | by 5d606464 — the actual fix was `.regular`→`.clear` + Reduce Motion diagnosis, not a forced-light island; no island code exists in FEATURES.md's glass history |
| Diarization/conversation mode: use Sortformer (not legacy pyannote DiarizerManager which merges similar voices); bold-name **Speaker:** turns; tag-as-you-go | bdc2a8bd, 4678c1cf, 18b3998a | 2026-06-09 | FOLDED | SPEC.md C102 (opt-in diarization, embedding cosine 0.5); FEATURES.md:251 Sortformer+fuse shipped and hardened |

## Other
| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Native SwiftUI rewrite of the iOS app (leave Expo/RN) | 4b38dadd | 2026-06-05 | DONE-SINCE | whole native rewrite shipped this slice + since; RN app archived |
| Native SwiftUI rewrite of the Mac app (leave Electron/Python) | 0d5c98ac | 2026-06-06 | DONE-SINCE | same |
| Mobile Phase 7 UI LOCKED after 5 user-approved mockup rounds: live transcription while recording, caption-first + on-demand camera, conversation-mode toggle, voice-first Names, Bonjour pairing (QR dropped), single Sort&Filter funnel, full-text search, optional phone-set title, tags = Mac-owned whitelist | 108a86f1 | 2026-06-06 | mixed | live transcription/camera/voice-first-Names/search/title all DONE-SINCE (built same phase); Bonjour pairing SUPERSEDED — CloudKit is now the only transport, "Bonjour/LAN sync fully retired" per CLAUDE.md and SPEC.md:1560 |
| Port the old Electron app's recordings into the native app once feature-complete | e23292fb, c3bb164e | 2026-06-07 | OPEN | still listed as a deferred TODO in MEMORY.md `project_port_electron_notes`; no roadmap.yaml node or SPEC clause covers it |
| Re-ingest ~30 old .m4a recordings from `~/Desktop/Skrift old notes/` | 59e3cb83 | 2026-06-09 | OPEN | same open item as above — never actioned in a live ledger |
| Auto-run orchestrator replacing manual per-step batch buttons (Electron era) | a583ff22, 91297635 | 2026-06-04 | SUPERSEDED | Electron/Python app retired; native `BatchRunner`/`ProcessingCoordinator` is the current equivalent (Phase 6, 41b40c75) |
| Ask-a-question chat feature removed, "superseded by the planned semantic evolve-over-time feature" | c8e1c1cb | 2026-06-04 | FOLDED | the evolve-over-time wish is the north-star (e5f3177b, SPEC.md:1706); chat itself stays cut — not present in native apps |

## OPEN items in this slice

Count: 4

1. **Backlink Weaver, context-aware enhancement, People Timeline** — three product ideas from the Phase-9 backlog handoff (e226cac0, 2026-06-07). None appear in SPEC.md, FEATURES.md, or roadmap.yaml. Needs a roadmap idea entry or an explicit "not doing."
2. **Port the old Electron app's recordings into the native app** — deferred TODO (e23292fb/c3bb164e, 2026-06-07), reconfirmed in MEMORY.md as still pending. No SPEC clause, BUGS row, or roadmap node.
3. **Re-ingest the ~30 old .m4a files under `~/Desktop/Skrift old notes/`** — same gap as #2, named explicitly (59e3cb83, 2026-06-09). Folds into #2 if that's actioned.
4. **Feedback capture on the desktop app** — mobile "Send feedback" (record+type+screenshot→Mail) shipped (bd70ceb4, 2026-06-08); FEATURES.md:358 marks the desktop port "deferred" with no tracking elsewhere. Low priority now that `pull-phone-feedback` covers the workflow, but the row itself is stale.
