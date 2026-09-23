# Commit source ledger — slice 3

Date built: 2026-09-23. Rule in force: SPEC.md C276 (a cited document is not a folded
document; every wish or decision gets a verdict).

Commit range: `git rev-list --reverse main | sed -n '374,612p'` — 239 commits, hashes
`a97808fe` (2026-06-09) through `197bd393` (2026-06-14). Span: 2026-06-09 to 2026-06-14,
the native-rewrite build sprint (conversation mode, trash, audiobook capture, custom
vocab, capture-items share extension). Every message in the slice was read in full; no
keyword filter.

Context for verdicts: this slice predates SPEC.md entirely (SPEC.md's C/R/D numbering is
from the 2026-09-22 v2-core-rewrite sitting). Almost everything here already shipped
within the slice itself, so most rows are DONE-SINCE citing the commit that built it, or
SUPERSEDED where a later decision (in this slice or in SPEC.md) replaced it outright.

## Conversation mode / diarization

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Split existing memo into speakers after the fact ("user idea") | c223d2d7 | 2026-06-09 | DONE-SINCE | built same commit, "Split speakers" toolbar action |
| Recording forgets the pre-record Conversation toggle | d49c2870 | 2026-06-09 | DONE-SINCE | toggle removed; conversation mode reworked to post-transcript Split-N action, same commit |
| Merge collapsed the WHOLE speaker, not just the tapped line | a6267727 | 2026-06-09 | DONE-SINCE | per-line reassign fixed same commit |
| Speaker turns should be editable + show playback highlight like the rest of the transcript | 6febaecb | 2026-06-09 | DONE-SINCE | built same commit |

## Recording / route robustness

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Opening a memo stops Spotify (session claimed too early) | 3f6d5116 | 2026-06-10 | DONE-SINCE | session claim moved to `play()`, same commit |
| Paste teleports the note to the top | 3f6d5116 | 2026-06-10 | DONE-SINCE | caret-scroll fix same commit |
| Want Copy on a memo row via more than one path (P2) | 3f6d5116 | 2026-06-10 | DONE-SINCE | swipe + long-press Copy added same commit |
| Instant record: opening the recorder should start recording immediately (FAB / append / Siri / widget) — "user decision" | 91caa0e8 | 2026-06-10 | DONE-SINCE | built same commit; FEATURES.md "Record / pause / resume / stop" row still documents this as live behavior |
| Recording with AirPods, pull them out → recording dies; re-insert → still dead | 28794e97, d51de6b6, 76135bd1, 98869be0, fbf8bd2b | 2026-06-12 | DONE-SINCE | closed 1a40fb65 "AirPods P0 closed — round-4 device-verified"; matches memory `project_audio_session_round` (later rounds b114-119 continued tuning, folded there) |
| Give me a pullable device-side log for hardware bugs (implicit — "user-requested" DevLog) | d51de6b6 | 2026-06-12 | DONE-SINCE | `Services/DevLog.swift`, still current per CLAUDE.md "Device debugging" section |

## Audiobooks — capture design (superseded within this slice)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Audiobook quote-capture design (waveform mark-in/out, grains, Hybrid transport) — grill session LOCKED | aca4590a, a6db8e5e, f25a3719 | 2026-06-11/12 | SUPERSEDED | by 6a08df7e (2026-06-13, "retire the audio mark-in/out arm") — the whole audio-marking flow was deleted in favor of text-first capture in the same slice |
| Mini-player buttons too small | a3c9e28f | 2026-06-11 | SUPERSEDED | 104pt bump superseded one day later by 35cb9b9d ("yesterday's 104pt was grotesque") → 72pt is the shipped size, still current per FEATURES.md "Conditional mini-player" row |
| Capture-UX P0s: scrubber wrong-handle bug, can't pan, preload, post-ramble flow, multi-file books (Bound-style) | 7dbebc6e | 2026-06-11 | SUPERSEDED | all fixed same commit, but the whole scrubber UI (CaptureMomentView) was later deleted in 6a08df7e |
| "I don't actually know how to use it properly" — capture screen unclear | 5b85263e | 2026-06-12 | SUPERSEDED | book-time labels/window-pan fixes same commit, but superseded by the text-first capture replacing the whole screen (6a08df7e) |
| Capture design PAUSE (no more CaptureMomentView iteration until a design session) | ed7aafac | 2026-06-12 | SUPERSEDED | pause lifted within the same slice once the Hybrid grill session signed off (13b4f572, 2026-06-12); CaptureMomentView itself later deleted entirely (6a08df7e) |
| Record-tap crash (P0), AirPods still broken, add dev file-logging | ed7aafac, 53ab216a | 2026-06-12 | DONE-SINCE | see Recording section above |
| Karaoke highlight broken on capture memos with a ramble | b957947e, d2e2d1a4 | 2026-06-12 | DONE-SINCE | unified into 3-mode `TranscriptBodyView`, same-day fix |
| Tap-to-seek karaoke should just work, not be an opt-in setting | 08085436 | 2026-06-12 | DONE-SINCE | default flipped ON same commit |

## Audiobooks — text-first capture (current flow)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Text-first (read, not listen) capture mode as an A/B alternative to audio-marking | 95ec0565, 2cb3e6cb, 23c8eec8, 1a23b835 | 2026-06-13 | DONE-SINCE | wave 1 built 9e584be3; FEATURES.md "Text-first quote capture" confirms shipped and now the ONLY flow (audio arm retired 6a08df7e) |
| "Your place is saved" reassurance invents a worry that doesn't exist — cut it | 1a23b835 | 2026-06-13 | DONE-SINCE | removed same commit (explicit override of an earlier agent suggestion) |
| "That's double. Don't need that." — re-transcribing the span you just selected is redundant | a0a8cddd | 2026-06-13 | DONE-SINCE | fixed same commit (`buildOutput` carves directly from the already-transcribed window) |
| "mostly text and a small microphone icon. Why doesn't it just have a button to record like all the other versions of the app?" | 29d07341 | 2026-06-13 | DONE-SINCE | full-width Record button made primary affordance, same commit |
| Custom vocab not correcting on device (e.g. "Script"→"Skrift") | ff479617, 8c653d74, 671a0919 | 2026-06-13 | DONE-SINCE | root cause = never pre-warmed; fixed both apps; "vocab RESOLVED on device (Rox + Skrift both work)" per 1ced667f. FEATURES.md "Custom vocabulary sync" (2026-06-18) confirms still-current, cross-device synced |
| "i cannot scroll down. only allows selection from before capture point" | 5a6991f3 | 2026-06-14 | DONE-SINCE | build-your-quote made bidirectional same commit |
| "8 is plenty" — don't let build-your-quote scroll infinitely | daa80f56 | 2026-06-14 | DONE-SINCE | bounded to ~90s back / 8 lines forward, same commit |
| "text lags behind voice" (read-along) | 20682534 | 2026-06-13 | DONE-SINCE | interpolation fix same commit |
| Read-along still trails by about a line | f3284b1d | 2026-06-13 | DONE-SINCE | advance-at-line-end fix same commit |
| Read-along a bit too early / lines "hustle" on change | c9d1698d | 2026-06-13 | DONE-SINCE | lead retuned + uniform font size, same commit |
| Merge the two-step capture screen into one note-style screen (signed-off mock) | 605efec2, 24d6e85a, 6a08df7e | 2026-06-13 | DONE-SINCE | `MergedCaptureView`, current flow per FEATURES.md "Merged capture screen" |
| Control Center / record-widget glyph choice: "User chose option A: quote.opening" | 806645b5 | 2026-06-13 | DONE-SINCE | built same commit |
| Share a video from Photos → voice memo (the one genuinely-open P1 from a backlog audit) | 551f0328 | 2026-06-14 | OPEN | built, but the very mechanism used (delete the capture-inbox entry before import confirms) is now flagged as **BUGS.md D14** ("A capture-inbox entry is deleted before its import is confirmed to succeed" — cites `CaptureInboxDrainer.swift:150` video path, SPEC R84), still unchecked |
| "share-video memo vanishes on device — log for tomorrow" | 197bd393 | 2026-06-14 | OPEN | same root cause as D14 above; never got its own BUGS row beyond D14, no dedicated follow-up commit in or after this slice |

## Naming / [[links]]

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Name-linking brackets on EVERY mention, not just the first (Mac diarize path) | c7250808 | 2026-06-10 | DONE-SINCE | Sanitiser fix same commit |
| Per-occurrence resolver should apply INSTANTLY per pick, not wait for all mentions | 3090e707 | 2026-06-11 | DONE-SINCE | fixed same commit |
| Unlink a [[Name]] mention, or all mentions, from the review body (signed-off mock) | 14427325 | 2026-06-11 | DONE-SINCE | built same commit |
| Two-Jacks follow-up: need a "reassign to a different person" option in the unlink popover | dd918feb | 2026-06-11 | DONE-SINCE | built as "Change to →" in d8852eec, 2026-06-12 |
| Names editor is missing the short-name (display nickname) field | 58b0823e | 2026-06-11 | DONE-SINCE | field added same commit |

## Lifecycle / rating

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Trash with 2-week retention, Apple Voice Memos style — "user-locked design" | 42958874, d86cc646 | 2026-06-11 | DONE-SINCE | mobile built same day; desktop mirror c468cd90 (2026-06-13); superseded in DETAIL only by the 2026-07-22/23 "one clock" lifecycle rework (memory `project_lifecycle_one_clock`), which changed how the clock starts but kept 14-day trash |
| Significance slider → 10-circle rating control (signed-off mock, refine-wall cues at 0.8) | abc58c60, bb005545 | 2026-06-11 | SUPERSEDED | by SPEC.md **D30/C94** (decided 2026-09-22): "Importance control = THREE balls (0.3 / 0.6 / 1.0)" — the 10-circle control is explicitly replaced, not merely refined |

## Capture items (share extension)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Capture-items bundle direction locked (share sheet → phone/Mac rendering) | 2583e2da, d9218ba4 | 2026-06-10/11 | DONE-SINCE | built across chunks 1-5, both apps, merged 8d22c1fe/1704f9b9 |
| Share sheet keyboard buries the significance row / no dismiss affordance | 6b95070c | 2026-06-12 | DONE-SINCE | fixed same commit (sim-probe verified) |
| "no way to record a voice message from sharing in safari" — missing piece | 4090cb4e | 2026-06-12 | DONE-SINCE | voice dictation in the share sheet built same commit |
| Export filenames/frontmatter can break Obsidian (":" in Gemma titles, unquoted YAML) | 7799848e | 2026-06-12 | DONE-SINCE | fixed same commit, affects all notes not just captures |

## Weather / misc device settings

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Weather API key typed into Settings never reaches the fetch | cc39f1d8 | 2026-06-11 | DONE-SINCE | Settings↔client key contract fixed same commit |

## Desktop parity

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Summary should be editable in review, not read-only | c7250808 | 2026-06-10 | DONE-SINCE | in-place TextField same commit |
| Video import needs a thumbnail frame, same as the phone | c7250808, 07378ea7 | 2026-06-09/10 | DONE-SINCE | both apps, same slice |
| Drag a file from Photos into the Mac app should ingest it | c7250808 | 2026-06-10 | DONE-SINCE | FilePromiseReceiver path same commit |
| Desktop needs its own Trash / Recently Deleted, mirroring the phone's 14-day retention | c468cd90 | 2026-06-13 | DONE-SINCE | built same commit |
| Liquid Glass visual parity with the mobile playback bar | 57bbed91 | 2026-06-09 | DONE-SINCE | built same commit |

## OPEN items in this slice

Count: **2**

1. **Share a video from Photos can silently lose the note** — `551f0328` built the video-share path by deleting the capture-inbox entry before import is confirmed to succeed; `197bd393` (same day) records the resulting "memo vanishes on device" symptom with no fix landed in this slice. Now tracked as BUGS.md D14 (SPEC R84), still open/unchecked.
2. The same D14 root cause covers audio and file capture-inbox entries too (`CaptureInboxDrainer.swift:221`, `:383-403,531`), built in this slice's capture-items batch (0b15cfcd, cd145933) with the identical delete-before-confirm pattern — never flagged as its own row at the time, only surfaced later as D14.

All other extracted wishes/decisions/reported problems in this slice were fixed within the slice itself (DONE-SINCE) or explicitly superseded by a later decision, either later in this same slice (the audio-marking capture UI, retired for text-first capture) or by the 2026-09-22 SPEC.md sitting (10-circle significance control → three balls, D30/C94).
