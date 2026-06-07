# Walkthrough bug tracker (2026-06-07 full-use pass)

Status: ☐ open · ⧖ pending build-verify · ☑ fixed

## Systemic
- ☑ **S1** Black-on-dark text fields → `foregroundStyle(Theme.textPrimary)` (wizard name, Settings model-repo, tag draft). `d49a856`

## Setup wizard
- ☑ **W1** Author-name field readable now (S1). `d49a856`
- ☐ **W2** P3 — Cursor stays I-beam after "Get started". Deferred (AppKit cursor quirk; low value).

## Sidebar / top chrome
- ☐ **C1** P2 — Three green health dots unclear. Deferred to ui-audit visual pass (has a tooltip; clarity is a design call).
- ☑ **Q1** Triage now reads "N ready to review · M to process" + explanatory tooltip. (this batch)

## Settings
- ☑ **ST1** Model HF-repo field readable (S1). `d49a856`
- ☑ **ST2** Names fields readable (already themed; verified). 
- ☑ **ST3** Audio/attachments subfolders now have a vault-rooted "Choose…" picker. (this batch)
- ☑ **ST4** High-pass slider now has plain-language help text. (this batch)
- ☑ **ST5** Names list sorted alphabetically on load. (this batch)
- ☑ **ST6** Added an "aliases are spoken nicknames…" hint. (this batch)
- ☐ **ST7** verify — Confirm prompts match Electron. (Wave D)
- ☑ **ST8** Per-note "Include audio in export" toggle + export gates on it. (this batch + `33d45b6`)

## Note review — general
- ☑ **N1** AVAudioPlayer load moved off-main (switch lag), token-guarded. `d49a856`
- ☐ **N2** P3 — Significance editable pre-process. Left as-is (harmless; it persists). Not a clear bug.
- ☑ **N3** ⋯ menu dismisses on outside-click (native Menu). `5664200`
- ☑ **N4** ⋯ menu actions wired (retranscribe + per-step redo). `5664200`
- ☑ **N5** Export shows a transient confirmation toast. (this batch)

## Title chooser
- ☑ **T1** Explicit `selectedTitle` state — no more flip/discard on edit. `d49a856`
- ☑ **T2** Smaller title fonts + wider body column (720→820). `d49a856`

## Resolver
- ☑ **R1** "These are different people" is a real button now. `d49a856`
- ☑ **R2** Resolver card fills the column (in line with body). `d49a856`
- ☑ **R3** Context shows up to 2 lines. (deeper: inline-in-text disambiguation still owed — Wave D)

## Export
- ☑ **E1** Title-derived unique image names + default folder so they export. `33d45b6`
- ☑ **E2** Default folders (no silent drop) instead of erroring. `33d45b6`
- ☑ **E3** Significance rounded to 0.1 (slider snap + %.1f YAML). `d49a856`
- ☐ **E4** verify — Confirm YAML frontmatter structure. (Wave D)
- ☑ **E5** Run bar says "Loading" not false "Downloading". `d49a856`

## Remaining
C1 (dots — ui-audit), W2 (cursor), N2 (left as-is), ST7 + E4 (verify), R3 inline (design). Then the ui-audit visual pass (Wave D).
