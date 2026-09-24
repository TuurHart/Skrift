# Mocks source ledger — slice 3 (C276)

Date 2026-09-23. Rule in force: SPEC.md C276, a cited document is not a folded document —
every mock below gets a verdict with evidence. Range: `Skrift_Native/SkriftDesktop/mocks/*.html`
files 49 to the end alphabetically (`phone-polished-display.html` through
`wayout-phone-placement.html`), plus every `*.html` under `roadmap/mocks/`, plus
`Skrift_Native/SkriftDesktop/mocks/text-capture-DESIGN.md`. 28 files total.

## Table

| mock file | screen | verdict | evidence (commit / doc:line) | live id or OPEN |
|---|---|---|---|---|
| phone-polished-display.html | Phone: Mac-polish text visible in-place, editable body, title chooser, summary card | BUILT | commit 9687c363, 2bf5e995; FEATURES.md:300 (built 2026-06-26) | mobile `MemoDetailView.swift`/`NoteBodyView.swift` (macPolish binding) |
| related-panel.html | Mac Connections panel: one list, Date⇄Closest pill, P1 importance decimals, hover-% closeness | BUILT | roadmap.yaml:360-361 (shipped 2026-07-16); SPEC.md:1174 C232 | `SkriftDesktop/Features/Review/ConnectionsPanel.swift` + mobile twin |
| resolver-inline.html | R3: inline-in-text name disambiguation, 3 variants (A popover / B pill / C spotlight) | DECIDED D109 (side-by-side with the shipped in-prose popover at /2-plan; closed if identical) | no citation found in FEATURES.md, backlog.md, SPEC.md, or roadmap.yaml by this filename | needs Tuur |
| review-minimap.html | Review rail: ambient mini-map vs map-first column, 2 variants | BUILT | backlog.md:5882-5891 ("Tuur picked A 2026-07-17") | Mac Review rail (`MKMapSnapshotter`, `PlaceCluster.fitRegion`) |
| review-note-detail.html | Read-only note detail, fixes the purple "Not in the queue" dead-end | SIGNED-OFF-NOT-BUILT (parked) | backlog.md:5800-5804 ("PARKED, Tuur 2026-07-18… mock is sign-off-shaped; build as drawn when revived") | OPEN — no roadmap node |
| share-ingest-wave1.html | Share-ingest sheet: single audio / multi-memo chooser / photos states | BUILT | roadmap.yaml:1127-1145 (node ShareW1, status done, done 2026-07-10) | node `ShareW1` |
| share-ingest-wave2.html | Share-ingest Track B: E1 unified video/PDF sheet, PDF text-in-note, voice-annotate | BUILT | roadmap.yaml:1158-1180 (node ShareW2, status done, done 2026-07-12, "Tuur green-lit Track B as drawn") | node `ShareW2` |
| significance-circles.html | Slider → 10 circles, both apps | BUILT | commit 7cb634d3; live in `Shared/UI/SignificanceCirclesView.swift` | see also OPEN follow-up idea i23 below |
| standalone-audiobook-sync.html | Per-book audiobook sync toggle + upload/download UI | BUILT | FEATURES.md:291 ("Spec: mocks/standalone-audiobook-sync.html") | `Services/Audiobooks/AudiobookCloudSync.swift` |
| standalone-commonplace-book.html | Commonplace Book: Highlights / Daily Review / quote cards | SIGNED-OFF-NOT-BUILT | SPEC.md:544-549 (C119, "approved mocks, nothing built… commonplace book") | roadmap node `P6`, status planned |
| standalone-export-obsidian.html | Standalone export & Obsidian publish, alias editor | BUILT | commit ecff1567 (mock aligned to built backend); FEATURES.md:67, FEATURES.md:70 | `Shared/Export/VaultWrite.swift` + mobile `ObsidianPublisher.swift` |
| standalone-models-polish.html | On-device models & Polish tab (mirrors desktop) | BUILT + SUPERSEDED (closed 2026-09-24: ModelsView/PolishSettingsView exist; title UI = C25) | backlog.md:6915 ("PARKED… held on the mobile title-presentation UI"); STANDALONE_PLAN.md:346 ("on hold until that interaction is figured out") | roadmap node `P4`, status planned; needs Tuur on the UI |
| standalone-naming-review.html | Phone name-linking (iOS), Mac-style resolver | SUPERSEDED | by `mocks/phone-name-linking.html`, FEATURES.md:335 (built 2026-06-25); commit 337685d0 is this mock's own origin | superseded spec: mobile `MemoDetailView.swift`/`PersonEditorView.swift` |
| standalone-onboarding.html | Standalone onboarding & Settings | SIGNED-OFF-NOT-BUILT | SPEC.md:544-549 (C119, "standalone onboarding"); roadmap.yaml:113-115 (node P2 backlog item "Standalone onboarding rewrite") | roadmap node `P2` backlog item, OPEN |
| text-capture.html | Text-first audiobook quote capture, sentence-select | BUILT | backlog.md:8372-8380 (Wave 1 built + installed 2026-06-13); FEATURES.md:161-178 | mobile `Features/Audiobooks/TextCaptureView.swift` |
| unrated-shelf.html | Unrated shelf — notes the Mac isn't processing | SUPERSEDED | by `mocks/lifecycle-ia-explorations.html`, backlog.md:4248-4256 ("same problem, worse room"); SPEC.md:1089 C212 | roadmap node `LifeIA` |
| v2.html | Desktop review-surface shell, critique-applied iteration | EXPLORATION | commit eba5576d ("v5 = locked design") | superseded by v5 |
| v3.html | Desktop review-surface shell, sidebar reworked | EXPLORATION | commit eba5576d ("v5 = locked design") | superseded by v5 |
| v4.html | Desktop review-surface shell, use-driven sidebar | EXPLORATION | commit eba5576d ("v5 = locked design") | superseded by v5 |
| v5.html | Desktop review-surface shell: glyphs, native select, wider body | BUILT | commit eba5576d; CLAUDE.md "Ledgers" section names v5 as the signed-off desktop shell | the shipped `SkriftDesktop` app shell |
| vault-folder-model.html | Vault folder model: Mac adopts the phone's one-folder pick | BUILT | SPEC.md:1340 (D11, "DECIDED 2026-09-22: keep VaultLayout.home as coded"); FEATURES.md:70; commits fadc5c86, f6a89131 | `Shared/Export/VaultLayout.swift` |
| wall-card.html | Wall card print preview, true to WallCardView | BUILT | backlog.md:5442-5445 ("BOTH BUILT same evening, build 43"); FEATURES.md:388 | `Features/Journal/WallPrinter.swift` (`WallCardView`) |
| wayout-phone-placement.html | "On its way out" — where the conveyor lives on the phone | BUILT | backlog.md:4314-4320 (Q-PLACEMENT locked 2026-07-21, pick B; "Build 88 ON DEVICE") | mobile `WayOutView.swift` |
| roadmap/mocks/A-techtree.html | Roadmap viz: decluttered tech-tree | EXPLORATION | roadmap/README.md:13,23 ("A/B/C/D design-exploration mockups… still in mocks/ for rationale") | not built as drawn; superseded direction below |
| roadmap/mocks/B-metro.html | Roadmap viz: metro map | EXPLORATION | roadmap/README.md:13,23 | not built as drawn |
| roadmap/mocks/C-board.html | Roadmap viz: fast-comment board | EXPLORATION | roadmap/README.md:13,23 | not built as drawn |
| roadmap/mocks/D-hybrid.html | Roadmap viz: A+B hybrid metro-tree | SUPERSEDED | commit 0c31d6d6 ("rebuild ROADMAP.html into an interactive metro-tree" — D won); commit 52e71642 ("delete ROADMAP.html — roadmap.yaml is the single source") | superseded by `roadmap/roadmap.yaml` + Tiuri Command Center hub |
| text-capture-DESIGN.md | Text-first capture — design decisions doc (2026-06-13) | BUILT | same evidence as text-capture.html: backlog.md:8372-8380; commit 95ec0565, 1a23b835, 23c8eec8 | mobile `Features/Audiobooks/TextCaptureView.swift` |

## Signed off, not built

**review-note-detail.html** — parked 2026-07-18, not a rejection.
- Read-only note detail replaces the alert-driven dead-end.
- "Process on this Mac" fix for the purple "Not in the queue" state.
- Parked because the Fading lifecycle drained most of the affected audience (untouched old notes now fade themselves out of Review).
- Revive trigger: the alert dead-ends again on a <30d untouched note, or a touched-but-unflagged one.
- Its 2 open questions ride the revival (backlog.md:5804-5809); no live roadmap node.

**standalone-commonplace-book.html** — approved mock, nothing built (SPEC.md C119).
- Highlights feed + Daily Review screen + shareable quote cards (ImageRenderer).
- Named the App Store differentiator ("the headline"), roadmap node `P6`, lane -1, order 5.
- Depends on `P2` (De-Mac the UX), via `P4` (On-device Polish) — roadmap.yaml:1459-1470.
- Status: planned, not started; no build commits found.

**standalone-onboarding.html** — approved mock, nothing built (SPEC.md C119).
- Standalone first-run: on-device record/transcribe value prop replaces the "synced to your Mac" framing.
- A once-ever first-fade explainer card (per backlog.md:4313, tied to the lifecycle "Fading" feature).
- Sits under roadmap node `P2` ("De-Mac the UX") as an unticked backlog item: "Standalone onboarding rewrite" — roadmap.yaml:113.
- `OnboardingView.swift` exists today but still carries Mac-paired copy per STANDALONE_PLAN.md:290-296; the rewrite itself has not shipped.

## Needs Tuur

**resolver-inline.html** — "R3: inline-in-text name disambiguation." Three variants: A (recommended) click-to-resolve popover, B inline token-pill dropdown, C guided spotlight mode. No commit, FEATURES.md row, backlog.md line, or SPEC.md/roadmap.yaml citation names this file. Variant A resembles the in-prose popover that shipped in naming chunk 4 (commit 19979f87, built to `mocks/naming-review.html` — a different, separate mock), but nothing ties `resolver-inline.html` itself to that build. No verdict on record.

**standalone-models-polish.html** — "On-device models & Polish (mirrors desktop)." The underlying behavior decision (title+summary+copy-edit mirroring the Mac) is locked, but the mock's own UI is explicitly on hold: backlog.md:6915 says it's "held on the mobile title-presentation UI — desktop's Suggested/From-recording chooser is wrong for a phone," and STANDALONE_PLAN.md:346 confirms "on hold until that interaction is figured out." Roadmap node `P4` (On-device Polish) is `planned` with no mock citation. Not approved as drawn.

## OPEN count

- BUILT: 14
- SIGNED-OFF-NOT-BUILT: 3 (review-note-detail, standalone-commonplace-book, standalone-onboarding)
- SUPERSEDED: 3 (standalone-naming-review, unrated-shelf, D-hybrid)
- EXPLORATION: 6 (v2, v3, v4, A-techtree, B-metro, C-board)
- UNKNOWN / needs Tuur: 2 (resolver-inline, standalone-models-polish)
- Total: 28
