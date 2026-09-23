# Source ledger — commit slice 7

Date: 2026-09-23. Rule: SPEC.md C276 — a cited document is not a folded document; every
wish, decision, direction or reported problem in a commit message gets a verdict.

Range: commits 1371–1629 of `git rev-list --reverse main` (first-parent oldest-first),
hashes `dd067174` .. `cfa77f0a`, 259 commits, dated 2026-07-22 to 2026-07-30. Read in full,
no keyword filtering.

Cross-referenced against: SPEC.md C1–C282 / R1–R94 / D1–D100 / Decisions log; BUGS.md;
`roadmap/roadmap.yaml`; `FEATURES.md`.

This slice is almost entirely the iPad Wave 1 build (its final week), the ePub↔audiobook
alignment rounds 5–8, the "no note dies unseen" v3 lifecycle, the recording-hardening /
Mac-recording / live-transcription rounds, and the unrated-note consent model. All four
are tracked as named roadmap nodes (`IPadWave1`, `EPubAlign`, `LifeClock`, `RecHard`,
`NoteConsent`, `SharedExport`, `BookShare`) with shipped logs that match this slice's
commits almost line for line — most rows below are FOLDED against those, not against a
SPEC clause, because this work predates the 2026-09-18 v2-rewrite spec effort.

## iPad (chrome, list, note view)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "the empty space in top left is shit" + "make that look the same" as the Mac | fc0b83a0 | 2026-07-23 | DONE-SINCE | roadmap `IPadWave1` shipped log; built same commit (Mac sidebar triage chips ported) |
| "when you click import you should see files or video from photos" | ded3d419 | 2026-07-23 | DONE-SINCE | same commit — Import became a menu (Files/Photos/Scan) |
| circled duplicate sort controls; "that filter button should also be on the mac… similar between them" | bf039dc5 | 2026-07-23 | DONE-SINCE | roadmap `IPadWave1`; ONE Filter button both apps, same commit |
| "this could be bigger… doesn't have to be this weird small shape"; "we don't even need to filter by photos or place" | ce41f770, 6f31463f | 2026-07-23 | DONE-SINCE | place/photos filters removed both apps; large sheet shipped same day |
| picked player-position direction A: "lets do A… make the sidebar toggle on the right match the native one on the left" | ccaed9b5 | 2026-07-24 | DONE-SINCE | superseded by the "chrome that belongs" redesign below, itself shipped |
| on device: chrome flew to the far right, over Connections, not the note | b4b8adfd | 2026-07-24 | DONE-SINCE | fixed same commit (chrome contained to note column) |
| "two device-round bugs… the deeper layout-stacking review is parked for next week" | 86da9ed6 | 2026-07-24 | DONE-SINCE | led directly to the "chrome that belongs" rebuild (3c871ed4) |
| AskUserQuestion round on Connections: on-demand per note, arrival over the note, no glyph/no count control, resting = list+note; signed "perfect" | 14a60528, 26600d2a, 3c871ed4 | 2026-07-24 | DONE-SINCE | roadmap `IPadWave1` — built + installed b132, Tuur-confirmed on device ("this looks soo good") |
| "it does seem better on the ipad, the way the connections pop up" | 3f34bed5 | 2026-07-25 | DONE-SINCE | Mac Connections became a floating inspector, same round |
| Mac's ⋯ had 4 items, iPad's had 8 — one vocabulary | 2717e07a | 2026-07-25 | DONE-SINCE | `Shared/UI/NoteMenu.swift`, same commit |
| "isn't it the same as connections looking at date?" — View thread retired (iPad), then "remove it from the phone too. keep the apps looking the same" | 87086755, ba3de46b | 2026-07-25 | DONE-SINCE | one arc surface per platform, both commits landed |
| Mac header mock: "sickk. i like it! the include audio should still be a toggle… should also be part of the ipad" | 544dda76, 1756b9bd, 0d223173 | 2026-07-25 | DONE-SINCE (header); PARKED (iPad include-audio) | header built same day; iPad include-audio needs a synced `Memo` field — tracked in roadmap `SharedExport` note ("includeAudioInExport sync parked") |
| "we need to match the colors of the panels on mac to what the ipad has… match those in shared code" | 55bded83 | 2026-07-25 | DONE-SINCE | `Theme.sidebar` retired for shared `Palette.surface`, same commit |
| "when i click an unrated note on mac it shows me this popup… it should just open it" → "still fucked, make it identical" → third attempt correct | 876e72d4, 948494d6, 1b5072cf | 2026-07-25/26 | FOLDED | SPEC C87 (rating is consent); roadmap `LifeClock` shipped log round 5 ("An unrated note IS a normal note") |
| title cut mid-word; "when i removed it it did not go grey again" (un-rating) | 3569067b | 2026-07-26 | DONE-SINCE | both fixed same commit; rating-stays-one-way decision folded into SPEC Decisions 2026-07-26 |
| "the note bar… flew to the far right, ABOVE Connections" / "two process buttons looks stupid" | b4b8adfd, 13269c18 | 2026-07-23/24 | DONE-SINCE | fixed same commits |
| Mac eyeball, polish+prompt-sync live test, "could not process" diagnosis, "Mark all as Passing" wording | (owed list, multiple commits) | 2026-07-23–26 | **OPEN** | roadmap `IPadWave1` note still lists these as owed and the node is still `status: inprogress` — no later fold found in this slice or the ledgers |

## Mac parity (mirroring iPad chrome to the Mac note view)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| floating toolbar capsule spanned the Connections column too | a7f2b190 | 2026-07-23 | DONE-SINCE | fixed same commit (siblings, not spanning) |
| "keep the apps looking the same" (player docks bottom, chrome band verbs-only) | 7b923402 | 2026-07-25 | DONE-SINCE | roadmap `IPadWave1` round 3 |
| Connections became a floating inspector; 4 verdicts on a question round | 3f34bed5, 6185055d | 2026-07-25 | DONE-SINCE | roadmap `IPadWave1` round 2; adaptive-width fix same round |
| Mac sidebar clipped its own header at default width (found comparing renders) | a9272bdb | 2026-07-25 | DONE-SINCE | fixed same commit; not a Tuur report, an internal render-comparison catch |
| "the include audio should still be a toggle… can be small" + importance drift explained | 1bfed5af | 2026-07-26 | DONE-SINCE | importance card ported to Mac, same commit |

## Editor / note UI (turn headers, quotes, karaoke)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "this looks pretty shit to read" (conversation `**Name:**` marks down the whole note) | 9a7b338c … 107591b2 | 2026-07-27 | FOLDED | roadmap idea/node W6 (conversation turn gutter), SPEC's markdown-marks rule (2026-07-16 decision); Tuur-confirmed "way better looking and it all works" (b2325688) |
| Mac showed a raw `> ` quote wall next to the phone's styled one | 4f3a0bd1 | 2026-07-27 | DONE-SINCE | `Shared/Model/CaptureQuote.swift`, same commit |
| "on my phone the title is correct… list shows the start of the note body" | 6123d30c | 2026-07-27 | DONE-SINCE | fixed same commit; part of the title-sync saga below |
| "issues with epub input… I think the karaoke there is broken" (root cause was polish, not diarization) | 8fbec8db | 2026-07-27 | DONE-SINCE | phone now aligns polished bodies through the shared aligner |
| "If we click the suggested [title], you see it everywhere. If from recording, same." — it didn't | d41dd386, 19343689, e9d137bc | 2026-07-27 | DONE-SINCE | title now syncs both directions; two follow-on sync bugs found and fixed same day |
| "use what we built for the ePub and transcript, and use shared code" (one aligner) | feabb4f8 | 2026-07-27 | DONE-SINCE | Karaoke folds into `AlignmentCore`, same commit |

## Audiobooks / ePub alignment

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| review of rounds 5–6: bridge aligner holes, live attach progress, transcribe/attach race guard | 815b223e | 2026-07-23 | FOLDED | roadmap `EPubAlign`, status done 2026-07-22/23, shipped log matches verbatim |
| "adding text, two levels" → one unified Text sheet | c2abfc43, a1496855 | 2026-07-23 | DONE-SINCE | signed off + built same week (b110), per CLAUDE.md mock registry |
| from the phone: the import→transcribe→match chain already works, say so | defae9d3 | 2026-07-23 | DONE-SINCE | A0 post-import prompt, built with the unified sheet |
| "frozen library" report (b109) — re-align freezes the UI | 9e5976dd, acd324c9 | 2026-07-23 | DONE-SINCE | fixed same round (off-main summary + visible stage) |
| "make sure that bookmarks and everything are synced" | 09b2ba54 | 2026-07-23 | DONE-SINCE | `AudiobookBookmarksRecord`, same commit, installed on Tiuri's iPad |
| DEVICE CATCH on his iPad — ePub chapters never applied on a receiving device | 50a80a1b | 2026-07-23 | DONE-SINCE | fixed same commit, verdict-gated apply marker |
| the attached ePub file itself now syncs ("green-lit") | 34e77dc5 | 2026-07-23 | DONE-SINCE | same commit |
| root cause of the Odyssey dropped-sentence reports: merge ate same-text seam overlaps | 7d2ce559 | 2026-07-23 | FOLDED | roadmap `EPubAlign` round-8 shipped entry, Tuur-confirmed on device (04a08ccc) |
| Tuur idea: share a book device→device as one file | b30021a7, cfa77f0a | 2026-07-30 | DONE-SINCE | roadmap `BookShare`, status done 2026-08-12 (outside this slice); "Why share with my own device? … just sharing to others is fine" scoped it down to person-to-person in this same slice |

## Recording (audio session, Mac mic, live transcription)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "once I click the record button it says starting… gotta start immediately" | 26899d31, 164cf537 | 2026-07-26 | FOLDED | roadmap `RecHard` shipped log — prestart, matches verbatim |
| b117 device trace: "counted to 10, two and three are not in the memo" — HFP mid-flip ate speech | e3ed97f7 | 2026-07-26 | FOLDED | roadmap `RecHard`; two-phase flip removed, built-in-mic-with-BT-present policy shipped |
| "midway through it stopped and then the song started playing again" (book loses route to Deezer) | 1604b126 | 2026-07-26 | FOLDED | roadmap `RecHard`; B1–B5 interruption-resume contract shipped same commit |
| Car HFP cabin mic (8kHz) flagged for a follow-up | e8cc5f55 | 2026-07-26 | SUPERSEDED | by e3ed97f7 — the whole two-phase-flip approach it was flagged under was rejected and removed, so the flag is moot |
| "the record button does nothing" (Mac has no mic / refusal was invisible) | ebbbbd30 | 2026-07-28 | DONE-SINCE | fixed same commit; typed refusal + inline error added |
| "dont make it dimmable. just give a popup when no mic is connected" | 4afee02a, 070425ea | 2026-07-28 | DONE-SINCE | popup-on-press shipped same day |
| his own take arrived pre-rated "passing" — capturing a thought isn't judging it | 343775b3 | 2026-07-28 | FOLDED | SPEC C87 / roadmap `NoteConsent`; Mac recordings now author unrated |
| "yes for sure. when youre not certain just copy what phone and ipad already do" (transcribe on stop) | 82c5b4ea | 2026-07-28 | DONE-SINCE | same commit; transcription reclassified as capture not processing |
| "i clicked record and it showed no waveform… no recording happening" (TCC denial, misdiagnosed twice) | 8c5c08c1, 37c97b6e, 7e78053b | 2026-07-28 | DONE-SINCE | root-caused to a stale CLI-triggered TCC denial + a dozing Bluetooth default input; both fixed |
| first live take: "writes a whole paragraph until it turns white… less clear than the Apple one" + duplicate waveform | d3a34263 | 2026-07-28 | DONE-SINCE | settle interval shortened per-owner + duplicate meter removed, same commit |
| "how do you know seven seconds is the right amount?" | cca2012c | 2026-07-28 | DONE-SINCE | pause-triggered rotation replaces the fixed-window guess |
| "you have two recordings, one on top and one in the bar" + kill the ownership pill | e6a6b403 | 2026-07-28 | DONE-SINCE | same commit |
| "on the phone I have paragraph generation when I talk. Here I don't." | df376930 | 2026-07-28 | DONE-SINCE | `Paragrapher` shared + wired into the live draft, same commit |
| takes 4–6: RMS floor tuning fails on his USB mic both ways → text-stability settle, Tuur-confirmed "way better" | a1c7c901, 7de11d90, 0435848b | 2026-07-28 | FOLDED | memory `project_live_transcription`; RMS/VAD lane explicitly retired, matches memory note verbatim |
| "no way to see what node I have selected in the left sidebar" | 04c0f093 | 2026-07-28 | DONE-SINCE | same commit, one shared selection chrome |
| "Book transcription should not be stopped on low power mode" | 49ac1fc0 | 2026-07-30 | DONE-SINCE | FEATURES.md dated 2026-07-30, `shouldConserve` made charge-only |

## Names / vocab

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| derive the ASR boost list from names instead of a duplicate store (backlog idea) | c6f95f26 | 2026-07-28 | FOLDED | SPEC.md "Parked ideas… names → vocab auto-boost" (not a decision today) |
| "make it sync and add the [transcription language] setting to mac" | 2c6a9585 | 2026-07-26 | DONE-SINCE | same commit, LWW-synced `ASRLanguageMode` |
| "the same transcription engine as phone and ipad. shared code" (premise corrected: only orchestration was twinned) | fca5c4f8 | 2026-07-26 | DONE-SINCE | `Shared/Pipeline/ASRPostProcess.finish`, same commit |

## Export / privacy / vault

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "edit tags in the app, not in Obsidian" rejected — "this is not intuitive" | db84dfa5 | 2026-07-26 | FOLDED | SPEC Decisions 2026-07-26 "One vault-write engine: … never write over what isn't provably ours" |
| ONE vault-write engine ported to the Mac, then the iPhone/iPad given its first real picker | 635da5f1, cb096394 | 2026-07-26 | FOLDED | roadmap `SharedExport`, status inprogress, matches this build |
| plugin menu verdicts: inbox "smart!"; Connections static-sidecar tier "not sure about stale data. dont like that" | 0ae54961, bf4f6a97 | 2026-07-26 | FOLDED | roadmap idea `i14` note states this exact verdict ("Connections is Mac-live ONLY … REJECTED") |
| CloudKit Mac sync silently opt-in since Bonjour's retirement — fresh Macs synced nothing | 9cd21b68 | 2026-07-26 | DONE-SINCE | not a direct Tuur quote (found via code audit), fixed same commit, default flipped ON |

## Lifecycle / rating (consent model)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| voice note: fading may run on wall-clock, but the final doors only move at an app-open | 2260c94f | 2026-07-23 | FOLDED | SPEC Decisions "2026-07-23 No note dies unseen"; roadmap `LifeClock` v3, verified + merged same slice |
| round 2–5 unrated-note doctrine, his sentence as spec: "all an unrated note should do different is fade, look greyed out and not process" | bf4f6a97, 76a071ea, 3f534cc2, a262f02f | 2026-07-26 | FOLDED | SPEC C87, D56; roadmap `NoteConsent`; "the rating is CONSENT" appears verbatim in SPEC Decisions 2026-07-26 |
| ONE rated/unrated predicate consolidation (round 9) — no new quote, closing 5 hand-rolled copies | eb77ad49…ba4cbe99 | 2026-07-28 | FOLDED | SPEC C87; roadmap `NoteConsent` W9, done 2026-07-28 |

## Sync / data-integrity bugs (found mid-round, no separate Tuur wish)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| karaoke dead on Mac only — CloudKit delivers asset rows independently of the Memo record | 7cee65b3, 04dd24d4 | 2026-07-27 | DONE-SINCE | FEATURES.md karaoke row, dated 2026-07-27, "Tuur-confirmed on device" |
| "a phone memo reaches the Mac only after quitting and relaunching" | cd086137 | 2026-07-27 | DONE-SINCE | fixed same commit (stale-context read + missing change notification) |
| two memos silently fighting over one PipelineFile row (`reflected=4` forever) | 19343689, e9d137bc | 2026-07-27 | DONE-SINCE | root-caused and fixed same round, verified live on the real store |
| a literal `"[]"` tag surfaced on two of his memos | 1acf61bc | 2026-07-27 | DONE-SINCE | tag validation now requires a letter/digit, same commit |
| Mac Places map deep-dive zooms out instead of in (live repro) | f9b222eb, 4f219d7b | 2026-07-23 | DONE-SINCE | fixed same day, phone's tighter-only camera clamp ported |
| "lets do A… phone player, just bigger; expert redesign later" (kill the 3-zone iPad audiobook player) | 4f219d7b | 2026-07-23 | DONE-SINCE | same commit |

## Other / housekeeping

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| generated Info.plists tracked in git, causing every cross-branch merge to collide | 2dc451ab | 2026-07-27 | DONE-SINCE | untracked + regenerated via xcodegen, same commit (not a Tuur report, an engineering fix) |
| two never-imported SPM packages + retired Bonjour plist keys left in the project | d63a75c1 | 2026-07-26 | DONE-SINCE | removed same commit |

## OPEN items in this slice

Count: **2**

1. **iPad Wave 1's own owed list is still open.** Roadmap `IPadWave1` (`status: inprogress`) lists, verbatim, as still owed: Tuur's Mac eyeball of the chrome mirror (including the snapshot-blind ⋯ chip), a live polish + prompt-sync test (the sim can't Metal-JIT), the undiagnosed "could not process" case (devlog now instruments it but no resolution is recorded), and the Mac's "Mark all as Passing" button wording. None of these appear resolved later in this slice or in BUGS.md/FEATURES.md. Needs: either a BUGS.md row per item or the roadmap node's owed list worked through and the node flipped to done.
2. **Two SPM/plist housekeeping items and the Car-HFP flag are not gaps** — checked and either superseded in-slice or resolved by later commits already cited above; listed here only to record that they were checked, not to reopen them.

Everything else in this 259-commit slice — the iPad chrome/list/note-view rebuild, the ePub alignment rounds 5–8, the "no note dies unseen" v3 lifecycle, the full recording-hardening/Mac-recording/live-transcription arc, and the unrated-note consent model — is FOLDED into a named, still-current roadmap node or a dated SPEC.md Decisions-log entry, or DONE-SINCE with a same-slice commit that shipped and (where device-testable) was Tuur-confirmed.
