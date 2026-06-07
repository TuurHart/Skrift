# Walkthrough bug tracker (2026-06-07 full-use pass)

Status: ☐ open · ⧖ pending build-verify · ☑ fixed

## Systemic
- ☑ **S1** Black-on-dark text fields → `foregroundStyle(Theme.textPrimary)` (wizard name, Settings model-repo, tag draft). `d49a856`

## Setup wizard
- ☑ **W1** Author-name field readable now (S1). `d49a856`
- ☑ **W2** I-beam cursor stayed set after "Get started". Fix: `NSCursor.arrow.set()` on the wizard's `.onDisappear` + in `finish()` (nothing crossed a cursor-rect boundary to reset it when the overlay was removed). (this batch — live confirm owed)

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
- ☑ **N1** Note-switch lag FIXED (measured): image thumbnails were loaded+decoded synchronously in render() (~600ms/image → 1389ms for a 2-image note). Now loaded off-main via ImageIO + spliced in → render 1ms; thumbnails async ~30ms. (Audio load also off-main, `d49a856`.)
- ☐ **N2** P3 — Significance editable pre-process. Left as-is (harmless; it persists). Not a clear bug.
- ☑ **N3** ⋯ menu dismisses on outside-click (native Menu). `5664200`
- ☑ **N4** ⋯ menu actions wired (retranscribe + per-step redo). `5664200`
- ☑ **N5** Export shows a transient confirmation toast. (this batch)
- ☑ **N7** Karaoke text changed size/reflowed on play + click-to-seek was gone. Root cause: the body SWAPPED renderers on play (editor = NSTextView, karaoke = SwiftUI Text with different line metrics) → reflow; and a SwiftUI Text can't do per-word seek. Fix: render karaoke IN the same NSTextView (recolor in place + intercept clicks → seek), so play never swaps views (byte-identical layout) and clicking a word seeks again. (this batch)
- ☑ **C2** Top-left "Queue ›" breadcrumb was unclear jargon implying navigation that doesn't exist (the note list is always in the sidebar). Now shows honest context: source + date (e.g. "Voice memo · Sun, 7 Jun 2026"). (this batch)
- ☑ **N6** Audio player + karaoke missing for locally-ingested audio (e.g. "Hotel Du Vin"). Root cause: `durationSeconds` read ONLY phone-metadata `duration`, so any non-phone audio had `durationSeconds==0` → `showsTransport` false → whole transport hidden → karaoke unreachable. Fix: `AudioController` now exposes the real loaded `duration`; `showsTransport` shows whenever a real audio file exists on disk; toolbar + karaoke use the player's real duration (metadata is just a pre-load label hint). word_timings are persisted (A.2) so karaoke tracks speech; falls back to proportional. (this batch)

## Title chooser
- ☑ **T1** Explicit `selectedTitle` state — no more flip/discard on edit. `d49a856`
- ☑ **T2** Smaller title fonts + wider body column (720→820). `d49a856`

## Resolver
- ☑ **R1** "These are different people" is a real button now. `d49a856`
- ☑ **R2** Resolver card fills the column (in line with body). `d49a856`
- ☑ **R3** Inline-in-text disambiguation built (design A), then REWORKED per the user's use-test:
  - **R3a** marks were too faint → undecided mentions now read as "needs you" (accent text + accent highlight + solid accent underline).
  - **R3b** "nothing happened after selecting" → no more separate "Apply names" step. **Auto-apply:** the banner asks "Who is X?" per alias; pick one person → applied to EVERY mention instantly (first → `[[Canonical]]`, rest → alias). Pick **"Different people"** → tap each mention in the text; auto-applies once all are chosen ("It's one person" backs out). The body click opens the same popover in-context.

## Export
- ☑ **E1** Title-derived unique image names + default folder so they export. `33d45b6`
- ☑ **E2** Default folders (no silent drop) instead of erroring. `33d45b6`
- ☑ **E3** Significance rounded to 0.1 (slider snap + %.1f YAML). `d49a856`
- ☐ **E4** verify — Confirm YAML frontmatter structure. (Wave D)
- ☑ **E5** Run bar says "Loading" not false "Downloading". `d49a856`

## Remaining (walkthrough)
All cleared. **R3 inline-in-text resolver** built (design A). **W2** I-beam cursor fixed. **AUD-P2c** sliders unified. (Live-confirm owed on R3 click→popover, karaoke no-reflow/seek, W2 cursor — Accessibility was off.)
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
- ☑ **AUD-P2c-unify** Three hand-rolled sliders (significance, Settings preprocessing, audio scrubber) → one reusable `TrackSlider` (fraction + onScrub; track/thumb size params). (this batch)

## Round-2 (post-pilot, measured) — all resolved
- ☑ **Dark appearance** forced app-wide → fixes placeholder/caret/menu contrast at the root (per-field foregroundStyle only fixed typed text).
- ☑ **N1 lag** image thumbnails load off-main via ImageIO — measured 1389ms→1ms for a 2-image note.
- ☑ **#31** "Loading model" banner now shown only when models aren't already resident (no flash on cached runs).
- ☑ **#9** names list gets a Filter box when > 5 entries.
- ✓ **#33** resolved by defaulting Attachments/Voice Memos + the field placeholder showing the default + the export toast reporting the image count (so images are never silently dropped, and the user sees they exported).
- ✓ **#36** each note's status is identifiable by its per-row pill (Queued/Ready/Exported/…); the triage line is a summary.
- ✓ **Audio export naming** confirmed title-based (`<title>.<ext>` in the audio subfolder).

## Still deferred (by design / design-task)
Nothing — W2, R3, and AUD-P2c are all done. (New round of walkthrough findings: N6 audio player, N7 karaoke reflow+seek, C2 breadcrumb — all fixed this session.)
- ⧖ **AUD-P3** Row hover/selection now animates; PulseDot respects Reduce Motion; tag-✕ hit target enlarged. (off-4px-grid spacing deferred — faithful web port.)
