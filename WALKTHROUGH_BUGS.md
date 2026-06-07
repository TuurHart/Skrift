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
- ☑ **ST2** Names fields now boxed + readable (RingedField) — was wrongly dismissed first pass.
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

## Remaining (walkthrough)
Deferred only: **W2** (I-beam cursor, P3 AppKit quirk) · **R3 inline-in-text resolver** (design). Everything else fixed.
- ☑ **#12** Right-click a sidebar row → Process · Re-transcribe · Redo ▸ · Reveal in Finder · Open in Obsidian · Copy ▸ · Delete (multi-select aware → "Process N / Export N / Delete N").
- ☑ **Add-name** Right-click a body text selection → "Add … as a name" (reliable, user-driven names-graph growth).
- ☑ **#18 / N2** Significance slider disabled until processed.
- ☑ **T2** title wraps (no truncation) + smaller (18–19pt) — first pass was insufficient.

## UI Audit findings (code-based pass, 2026-06-07)
- ⧖ **AUD-P1a** Significance showed false "0.0 · Passing" on unrated notes → "Not rated" until set. (subsumes N2)
- ⧖ **AUD-P1b** Status dots were always-green/cosmetic → removed redundant header trio; footer dots reflect real `modelsLoaded`. (subsumes C1)
- ⧖ **AUD-P2a** No empty-queue state → first-run hint added.
- ⧖ **AUD-P2c-thumb** Scrubber had no drag handle → added a thumb.
- ⧖ **AUD-P2b** Focus rings on form fields → reusable `RingedField` (Settings text/subfolder rows + wizard).
- ☐ **AUD-P2c-unify** Three hand-rolled sliders → extract one component (code quality; low priority; deferred).
- ⧖ **AUD-P3** Row hover/selection now animates; PulseDot respects Reduce Motion; tag-✕ hit target enlarged. (off-4px-grid spacing deferred — faithful web port.)
