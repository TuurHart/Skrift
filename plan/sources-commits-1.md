# Commit source ledger — slice 1

Date: 2026-09-23. Rule: SPEC.md C276 (a cited document is not a folded document; every
wish or decision gets a verdict).

Range: commits 1-134 in first-parent order (`git rev-list --reverse main | sed -n '1,134p'`).
Span: 2025-10-18 to 2026-05-02. This whole slice predates the native rewrite (June 2026) —
it is the old Python/FastAPI backend + Electron desktop + Expo/React Native mobile app.
Per the brief: an item about that old stack is SUPERSEDED by the native rewrite unless the
wish itself is still unmet in the native apps, in which case it is OPEN.

Ledgers checked: SPEC.md (C1-C282, R1-R94, D1-D100, Decisions log), BUGS.md,
roadmap/roadmap.yaml, FEATURES.md, CLAUDE.md.

## Editor / note UI / prompts

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Batch design: sequential, no batching for Sanitise (manual work), sleep/resume popup, 3-fail stop | 9b775ba5 | 2025-10-18 | SUPERSEDED | native has its own batch model (`BatchRunner`, C180 "Mac is the automatic, unattended batch polisher"); no sleep/resume dialog concept carried over |
| Rename field "confidence" → "significance" across whole stack | 6922ad07 | 2026-04-02 | FOLDED | "significance" is the standing term (SPEC.md:282, `mocks/significance-circles.html`) |
| Rename "Notes folder" → "Obsidian vault folder" in settings | bb61a3c7 | 2026-03-27 | FOLDED | native uses "Obsidian vault" throughout (CLAUDE.md:32, :91) |
| Restructure: NoteDisplay = live note preview, Inspector = pure pipeline | c46ace72 | 2026-04-04 | SUPERSEDED | Electron 3-panel layout is gone; desktop rebuilt native SwiftUI per v5 shell mock |
| Add "Default author" setting; drop redundant `firstMentioned:` field | a08e3036 | 2026-04-04 | FOLDED | carried forward as `MacMemoAuthor` (SPEC.md:254, FEATURES.md:87) |
| AI chat panel — ask questions about a note via the local model | 0a21c16f | 2026-04-09 | SUPERSEDED | explicitly rejected for v2: "no chat/ask" (SPEC.md:1567, Not doing) |
| Export preview — rendered markdown of the note before export | 0a21c16f, ba5a779d | 2026-04-09 | SUPERSEDED | explicitly rejected for v2: "no export preview" (SPEC.md:1567, Not doing) |
| Cmd+F find-in-page with match count | 8157806a | 2026-04-09 | OPEN | no in-note or in-app find/search clause in SPEC.md, FEATURES.md, or BUGS.md; needs a clause or an explicit Not-doing line |
| Summary prompt rewritten: implied first person / present participle ("reflecting on…"), never third person or "The speaker" | dd4df4c1 | 2026-05-01 | OPEN | no clause in SPEC.md pins enhancement-prompt voice/person; unverified whether native's summary prompt still honors this |
| "Where is enhancement happening" confusion (per-file Inspector state + lock banner) | a4f15279 | 2026-05-02 | SUPERSEDED | native's engine/coordinator model (`ProcessingCoordinator`, FEATURES.md:69) replaces the Electron per-file-poll design this fixed |
| Sanitise lock-out declared explicitly out of scope ("per your direction") | a4f15279 | 2026-05-02 | OPEN | no ledger line states sanitise-lockout as a standing non-goal for native; log if it resurfaces |
| Tag suggestions not cleared on force re-transcribe (bug the user noticed) | 6cf1c55d | 2026-05-01 | SUPERSEDED | Electron field-clearing bug in a codebase that no longer exists; not tracked as a live BUGS.md row |
| Mood ring memo-card color tint removed: "visual fluff that didn't add real value" | 24aa703e | 2026-04-03 | SUPERSEDED | never reintroduced (no hits in SPEC.md/FEATURES.md/roadmap.yaml); rejection holds by omission |

## Capture / share

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Universal capture inbox: share URL/image/text into Skrift without audio | 818a827b, 0c5a4108 | 2026-04-11 | DONE-SINCE | native "Capture items" is the direct descendant (FEATURES.md:141, `Skrift_Native/CAPTURE_CONTRACT.md`) |
| Photo capture during voice recording, timestamped to the transcript | 773dc2c3 | 2026-04-14 | DONE-SINCE | native records photos with contextual metadata (CLAUDE.md app description; the AI-description half is separately SUPERSEDED, next row) |
| Vision pipeline (26B-as-VLM) describing photos into the copy-edit: dropped, "producing weird AI-generated descriptions" | c27a3e29 | 2026-04-27 | FOLDED | now a standing rule: "No vision pipeline" (SPEC.md:1567, Not doing) |
| Live Activity + Dynamic Island for recording, Quick Actions | 80b03777 | 2026-04-11 | DONE-SINCE | native ships Live Activity for recording (FEATURES.md:364) |
| Lock Screen / Control Center widget for quick record | 6f24d3f3 | 2026-04-03 | DONE-SINCE | native ships CC + Lock/Home widgets, Siri start-recording intent (FEATURES.md:365) |
| Pause/resume recording with correct photo timestamps (manual pause button) | 2a6c5790 | 2026-04-15 | OPEN | SPEC C149 covers auto-pause on interruption (call/Siri/alarm) only; a user-pressed manual pause button is not confirmed in any ledger |
| iOS Simulator crash record→review (RN/Fabric mounting race) | 773dc2c3, ef4f0f2e | 2026-04-14 | SUPERSEDED | React-Native/Fabric-specific; native iOS is SwiftUI, no Fabric layer |
| Shift-click range selection in sidebar multi-select | a5c7f6de | 2026-04-12 | FOLDED | native has multi-select + delete in the notes list (FEATURES.md:86); exact gesture parity unconfirmed but the underlying wish is met |
| .opus audio accepted (WhatsApp voice notes) so they flow through the pipeline | b3b10103 | 2026-04-27 | FOLDED | native handles WhatsApp voice-note import as a transcribed memo (BUGS.md:294, roadmap i4) |

## Names / privacy

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Bidirectional names sync API, phone↔Mac, last-write-wins with 90-day tombstones | b3b10103 | 2026-04-27 | FOLDED | direct ancestor of native's `NamesMerge` LWW union sync (CLAUDE.md:40, SPEC.md:1075 D60) |
| On-device sanitise on the phone before sync (phone name-links its own transcript) | a81bde1f | 2026-04-27 | SUPERSEDED | reversed in the CloudKit rewrite — phone now carries RAW transcript only, never sanitised; the Mac does all name-linking (C95, CLAUDE.md:37) |
| FluidAudio Parakeet TDT v3 on-device ASR module for mobile | a48286b1 | 2026-04-27 | DONE-SINCE | native mobile ships on-device FluidAudio/Parakeet transcription (CLAUDE.md app description) |

## Enhancement / scoring

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| LLM-computed "importance" score (0.0-1.0) added as an editable prompt | 50a58422 | 2026-05-01 | SUPERSEDED | v2 explicitly bans this: "No LLM in naming, tagging or importance" (SPEC.md:1564); importance is now three fixed user-set balls (C94, D30) |
| Real cancellation of a running enhancement — Stop actually halts the model, not just the UI stream | a4f15279 | 2026-05-02 | SUPERSEDED | old Python/MLX-in-Electron mechanism; native's engine lifecycle is a different implementation, not tracked as a carried requirement |

## Other / distribution

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Zero-manual-step first-launch setup wizard (auto-detect deps zip, extract, validate) | 149f28de, 776216aa | 2026-04-05 | SUPERSEDED | moot — native apps install as plain iOS/macOS builds (device build / TestFlight), no Python venv or model zip to unpack |

## OPEN items in this slice

Count: 4

1. **Cmd+F find-in-page** (8157806a, 2026-04-09) — no in-app find/search clause anywhere in the live ledgers; confirm whether it's wanted in the native desktop app or was a dropped Electron-only convenience.
2. **Summary-prompt voice: implied first person / present participle, never "The speaker"** (dd4df4c1, 2026-05-01) — a real prompt-quality preference with no SPEC.md clause pinning it; worth checking the native enhancement prompt still writes in this voice.
3. **Sanitise lock-out explicitly out of scope** (a4f15279, 2026-05-02) — a scope decision with no ledger record; log it as a Decision if it comes up again in native (e.g. can sanitise run while enhance is mid-stream).
4. **Manual pause/resume recording button** (2a6c5790, 2026-04-15) — only auto-pause-on-interruption (C149) is confirmed in native; a user-initiated pause button during recording is unverified.
