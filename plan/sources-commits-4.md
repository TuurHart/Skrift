# Commit-history source ledger — slice 4

Date: 2026-09-23. Rule in force: SPEC.md C276 — a cited document is not a folded document; every
wish or decision gets a verdict.

Commit range: `git rev-list --reverse main` positions 613-850 (first-parent, oldest first).
238 commits, span 2026-06-14 to 2026-06-30. This is the "standalone push" slice: CloudKit sync
Phase 1, the naming-model rewrite (opt-in to opt-out), Phase 2 Obsidian export, Mac-rejoins-via-
CloudKit Phase 8, and the audiobook reading-mode redesign.

## iPad / Mac parity

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Mac sidebar needs search + sort, not just a 3-way filter | 04d08278 | 2026-06-15 | DONE-SINCE | built same day, cites the parity audit (1c0e430b) |
| Mobile "Add voice" should record a real sample, not a placeholder | 63fa5da0 | 2026-06-15 | DONE-SINCE | built same day |
| Mac→CloudKit: the Mac should rejoin as a client of the phone's Memo store (polish flows back to phone) | acdb4458, a2e831a0, 74cb6093, fa458df8 | 2026-06-21/22 | FOLDED | roadmap.yaml "Mac rejoins via CloudKit" node, D67 (prod schema deploy) done 2026-09-22 |
| De-Mac the phone UI: Bonjour pairing becomes an optional fallback, not the primary sync story | b2460e26, fa458df8 | 2026-06-18/22 | FOLDED | roadmap.yaml Mac-rejoins node note: "mobile client (Part A) deleted; CloudKit is the only [path]" |

## Editor / note UI

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| P0: paste into a note, clear it, append via + — the whole note vanishes | c9c06447, 8df6d855, e3e7507e | 2026-06-21 | FOLDED | reframed mid-slice to "appended text doesn't land"; tracked live as BUGS.md D7 ("Append races the original transcription and can silently drop text or audio") and SPEC R73 |
| Custom words added in Settings vanish when you come back | a8d8ab71, e3a1e8e9, 6d30489f | 2026-06-15 | DONE-SINCE | root cause was an unregistered App Groups (Release) capability, fixed same day (6d30489f) |
| "Preserve what was said" is wrong when ASR mishears a name — show the corrected short name, not the raw mishear | 7a7bf8cb | 2026-06-15 | FOLDED | SPEC.md C205 ("registered aliases fix a misheard KNOWN name everywhere... only the first mention links") |
| Two friends both named "Jack" break the opt-in chip bar (same-name collision) | 136571ea | 2026-06-16 | SUPERSEDED | by the opt-out naming rewrite below — the chip bar itself was deleted |
| Full naming/sanitising redesign: flip to opt-out, auto-link known people, kill the chip bar and per-occurrence resolver, in-prose 3-tier UX | dd2f7e30, 4f010c17, bda63878, 5ffb7de7, 67de42fb…ac0728dd | 2026-06-16 | FOLDED | SPEC.md line 1700: "2026-06-16 Naming: opt-out, risk-tiered, known-roster only, no LLM" — the locked decision, chunks 1-5 all shipped |
| Note-editing epic: body selection/autoscroll is broken because it's a non-scrolling UITextView inside a ScrollView | 9d327f81, dc49ef17 | 2026-06-22 | DONE-SINCE | roadmap.yaml "Note-editing overhaul" node: "Re-found the note body on a natively-scrolling text view (fork B)" |
| Capture-rethink: pull capture into the reader via in-place text selection; unify highlight/note/bookmark gesture | 2985bc40 | 2026-06-22 | OPEN | mock-first idea, not found as a built or queued item in roadmap.yaml/SPEC.md — needs a QUEUE.md item or an explicit "deferred" node if it was dropped |

## Capture / share

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Video shared from Photos "vanishes" from the list — keep the real recording date but still land somewhere findable | 4f3f5016, fc5e8188 | 2026-06-14 | DONE-SINCE | FEATURES.md "Video import" row, same-day fix (MemoOpenBridge + added/edited sort) |
| Video import: no playback, squished thumbnail, no source glyph | d98b6fee, e2108ddc, a6608ec7 | 2026-06-15 | DONE-SINCE | FEATURES.md "Video import" row documents all three fixes |
| Desktop should show the same video source glyph/label/date as the phone (unified source taxonomy) | f74c9a47, 1b32834c | 2026-06-15 | DONE-SINCE | FEATURES.md "Video import" row, point (5)/(6) |
| "I can't share a PDF with the app and have it live in there" | 4b7682d9, e3e7507e | 2026-06-21 | DONE-SINCE | FEATURES.md "Share a PDF / document → .file capture" row, extended 2026-07-11/07-15 (text extract + Mac sync) |
| Share extension: add multiple tags at once, comma-separated | c81a1084 | 2026-06-21 | DONE-SINCE | built same day, tag-scroll bug diagnosed as non-existent |

## Audiobooks

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Player redesign: reading-mode e-reader (less chrome, more page), tab-bar IA | 92aee157…4bcca6e8, 441ce387 | 2026-06-19 | DONE-SINCE | FEATURES.md "Audiobook player — reading-mode redesign + tab-bar IA — built 2026-06-19 (build 14)". Note: current CLAUDE.md still lists this mock as "signed off 2026-06-19 — not yet built", which is stale against FEATURES.md and this commit history |
| Per-book audiobook sync with real upload/download % (not a fake bar) | efed09c3, 1f0dcd47, b0c7e41c…d012353d, 974abfd1, 08adbf52, a353a493 | 2026-06-18 | DONE-SINCE | FEATURES.md "Per-book audiobook sync (entry + resume + audio, REAL %)" row |
| Bookmark model is confusing — dedicated Mark button vs Chapters tab that navigates | cc07100a, 1c5f2ba6, cdd5f6cd, 8b4ec223, ebea929a, 85d90cd7 | 2026-06-19/22 | DONE-SINCE | iterated through 5 device rounds to the final dog-ear-on-active-line model (85d90cd7); FEATURES.md "Reading mode" row |
| MP3 audiobooks rejected as "not a playable audiobook" | ffbbff9e, 555336cd | 2026-06-24 | DONE-SINCE | precise-duration fix, bug not a decision |
| Chunk-seam dropped words / merged sentences on run-on sentences | d14095ec | 2026-06-27 | DONE-SINCE | bug fix, not a decision |
| Transcription config differ→different (accent/language handling) | 19d13ac3, 700e9fab, d3bdd41c, fc717cd6 | 2026-06-19 | FOLDED | ended in a user-facing Settings toggle (English/Multilingual, default English) — durable decision, present in shipped code per fc717cd6 |
| "significance" should read "Importance" everywhere | 19d97981 | 2026-06-19 | DONE-SINCE | relabel shipped same day |
| Whole-book pre-transcribe should run off-charger (battery, not just plugged in) | 39202149 | 2026-06-15 | DONE-SINCE | shipped same day |
| Whole-book transcription should survive backgrounding/app-kill (BGProcessingTask) | ade5dde2, d01f70cf | 2026-06-15 | DONE-SINCE | shipped + registration bug fixed same batch |
| Read-along splits sentences oddly at "Mr." / decimals / ellipses | 0a80da00 | 2026-06-15 | DONE-SINCE | NLTokenizer fix, bug not decision |
| Audiobook sync: cover doesn't refresh on receiver; rate-only changes should sync too | a6126e0d | 2026-06-19 | DONE-SINCE | fixed same slice |
| Read-along transcript should sync across devices, not stay device-local | b4b72146 | 2026-06-19 | DONE-SINCE | FEATURES.md per-book sync row, point on transcriptSignature |

## Names / voice

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Two same-named diarization slots collapse when renaming one (rename/enroll should be slot-aware) | 580acdc8, 083f2231 | 2026-06-15 | DONE-SINCE | shipped + hardened same day |
| Custom-vocab short names (Tuur/Tiuri) are false-positive prone — over-fire on similar audio | 11703692 | 2026-06-15 | DONE-SINCE | trust-guard tightened same day (VocabularyTrust) |
| Naming — non-negotiable build guards: FP guards, skip non-prose spans, re-scan on roster collision, matcher stays strict (no fuzzy) | bda63878, ac0728dd | 2026-06-16 | FOLDED | part of the locked NAMING_MODEL.md design, SPEC.md line 1700 |
| "Change person" should only offer same-name alternatives, not any unrelated person | ba1c7797 | 2026-06-16 | DONE-SINCE | fixed same day, builds on 3fc55a1 |
| Phone should get the same in-prose name-linking UX as the Mac (tap-to-resolve, tiers) | 337685d0, d6ad8be0, 09cee374, 950097fe, 1fc62b3b | 2026-06-25 | DONE-SINCE | FEATURES.md "Phone in-place name-linking" row |

## Export / privacy (Obsidian)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Phone should be able to export standalone to Obsidian without the Mac (Phase 2 backend) | da9097f3…be24bd1d | 2026-06-21 | FOLDED | standalone $0.69/CloudKit/one-way-publish decision, SPEC.md line 1701-1702 |
| I WILL edit exported notes in Obsidian — pure overwrite export is wrong, never clobber my edit | 9eabc729 | 2026-06-22 | SUPERSEDED | by the 2026-07-26 "one vault-write engine" decision (SPEC.md line 1690-1691: "never write over what isn't provably ours; moved notes are never respawned") — same intent, later and more general rule |
| Reconsider the whole export/conflict model; explore alternatives (daily-note append, round-trip guard, etc.) | 337685d0 (OBSIDIAN_EXPORT_ALTERNATIVES.md) | 2026-06-22 | SUPERSEDED | resolved by the 2026-07-26 one-vault-write-engine decision above |

## Lifecycle / rating

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Standalone export policy: publish everything, or only "important" (significance>0) memos | be24bd1d | 2026-06-21 | FOLDED | mirrors the Mac's flag-to-send / flag-to-process framing, confirmed live: roadmap.yaml line 340 "significance microcopy fixed to flag-to-PROCESS" |

## Recording

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Long recording doesn't need live captions the whole time — auto-drop after N seconds to save battery | edc4de6c | 2026-06-22 | DONE-SINCE | Settings toggle shipped same day, default 1 min |
| Live-transcription toggle icon vanished (off state had no glyph) | 119831f2 | 2026-06-17 | DONE-SINCE | bug fix, invalid SF Symbol swapped |
| Diarization ("Split speakers") stops silently if you background the app mid-run | 94a33d40 | 2026-06-21 | DONE-SINCE | keep-alive + recovery shipped same day, mirrors the transcription-recovery pattern |
| Stuck transcription after a cold-launch auto-record gets killed before the model loads | f2e82c80 | 2026-06-17 | DONE-SINCE | recoverStuckTranscriptions shipped same day |

## Other (infra, ledgers, tooling)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Read three old milestone snapshots while away, compile a history backfill (no vault contents) | 8bd01590, 516df384 | 2026-06-21 | DONE-SINCE | roadmap.yaml history eras (H_elec/H_rn/H_desk/H_mob/H_conv) now carry full dated shipped: logs per 79d37227 |
| Roadmap visualization: keep it as ONE generated view, not a second hand-copied source | 0c31d6d6, 65192c2d | 2026-06-19/21 | SUPERSEDED | ROADMAP.html itself was later deleted 2026-06-29 (52e71642) — roadmap.yaml + the Tiuri Command Center hub is now the single source, matching the very principle these commits argued for |
| App icon: one universal icon per config, no light/dark variants | a184d2b2 | 2026-06-17 | DONE-SINCE | shipped same day |

## OPEN items in this slice

Count: 1.

1. **Capture-rethink — in-reader selection unifying highlight/note/bookmark** (commit 2985bc40, 2026-06-22): a real design direction ("pull capture into the reader via in-place text selection... bookmark vs note = same gesture, different keepsake... missing middle tier = a plain HIGHLIGHT") that was recorded as a brainstorm but is not visible as a built feature, a roadmap.yaml node, or an explicit "deferred" marker in the current ledgers. Needs either a roadmap.yaml node (planned/deferred) or confirmation it was folded into a later capture-items pass under a different name.
