# Resume prompt — BUILD the audiobook reading-mode redesign (paste into a fresh chat)

Build the **audiobook player reading-mode redesign + tab-bar IA** for SkriftMobile (branch `main`, in
`/Users/tiurihartog/Hackerman/Skrift`). The mock is **signed off** — this is a build session, mock → SwiftUI,
**commit per chunk, keep the unit suite green each chunk.**

## START BY READING, in order
1. `CLAUDE.md` — repo guidance, build/run, dev-vs-prod data safety, the signed-off-mocks list + the ROADMAP update contract.
2. **`Skrift_Native/SkriftDesktop/mocks/audiobook-player-reading-mode.html`** — THE SPEC (signed off 2026-06-19). Build to it. (Render it to actually see it: `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --screenshot=/tmp/m.png file://<abs path>` then Read the PNG.)
3. `STANDALONE_PLAN.md` — the `⭐⭐ RESUME` block at the top of the RESUME section (current state + chunk order).
4. `backlog.md` — the `## 🎧 Audiobook player — reading-experience redesign` section (locked decisions + the 2 defaults + scope).
5. Memory: `project_standalone_app_store` (cross-session record).

## What to build (LOCKED decisions — don't re-ask)
- **Tab-bar IA:** root nav becomes a `TabView` — **Notes · Library · Highlights(soon, dimmed) · Settings**. The audiobook **Library stops being a `.sheet`** (today `MemosListView:130` presents it as a sheet → pull-to-refresh dismisses it). Library + Notes are co-equal.
- **"significance" → "Importance"** (graded slider kept, just relabeled) across the memo/notes UI. (This is the Phase-3 label the user signed off.)
- **Player "reading mode — less chrome, more page":** compressed header (drop "NOW PLAYING"; cover-chip + title + author + chapter in one slim bar; cover-tint ambiance behind the body); **auto-recede** chrome after ~3–4s idle + on scroll, tap to show, never while paused, ~250ms crossfade; **read-along** = past/now/ahead contrast ramp + current word weight+underline (NOT a filled box), now-line pinned ~upper-third, free-scroll with a transient **"Back to playing"** pill; reading column capped ~60–68ch (no iPad full-bleed).
- **"Aa" text settings** popover: size + line-spacing (Tight/Cozy/Loose = 1.5/1.7/1.9) in v1, persisted app-wide (`@AppStorage`); light/sepia/dark reading theme = fast-follow.
- **Bookmarks:** **add = an action** (the "Mark" button in the utility row, toggles a mark at the current spot); **the Chapters/Bookmarks sheet is browse-only** (tap → jump) — fixes today's confusing "Bookmarks tab adds, Chapters tab navigates". A **margin bookmark glyph** sits beside the saved line (anchor it to the line's position, NOT an absolute px offset).
- **Floating play button** (consistency with the memo-detail floating play); skip ±15/30 flank it when controls are up.
- **"Capture this" → "Add note"** = a centered accent chip in the utility row (icons flank it).
- **Read-along states:** not-transcribed nudge ("Transcribe for read-along"), transcribing-in-progress (inline %), bookmarks empty-state.
- **Library:** delete needs a **confirm**. For a SYNCED book → two options: **"Remove from all devices"** (= `AudiobookCloudSync.disableSync`) + **"Remove from this iPhone only"** (= `AudiobookCloudSync.removeDownload`, demoted to neutral). Local-only book → plain "Remove" + Cancel.

## Chunk order (each = its own commit, suite green)
1. **Tab-bar shell** — root `TabView` (Notes · Library · Highlights-placeholder · Settings); Library out of the sheet.
2. **Importance relabel** — significance → "Importance" in the UI.
3. **Player header** — compress + cover-tint ambiance + floating play button.
4. **Reading mode** — auto-recede, pinned now-line, free-scroll + "Back to playing", contrast ramp + word weight/underline.
5. **Aa text settings** — size + spacing, persisted.
6. **Bookmark model** — add-action vs browse-only sheet + margin marker.
7. **Add-note chip** + read-along states (not-transcribed / transcribing / empty bookmarks).
8. **Library delete-confirm** + final polish pass (render-and-eyeball vs the mock).

## How to work (project rules)
- **Gate = the UNIT suite:** `cd Skrift_Native/SkriftMobile && xcodegen generate && xcodebuild test -scheme SkriftMobile -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SkriftMobileTests -derivedDataPath build`. As of build 13 = **439 green**. (The 10 `SkriftMobileUITests` failures are PRE-EXISTING on the iOS-26 sim — not a regression.)
- **Commit per chunk; keep green.** New UI = build to the mock; flag any forced deviation the moment you hit it.
- **Build number** lives in `project.yml` (`CFBundleVersion`, currently **13**) — bump it for each device install (currently 13). Capabilities/prod = Xcode GUI; dev = CLI xcodegen+xcodebuild / Xcode Cmd-R. Device-verify is the USER's step.
- **`main` is local-ahead of origin — do NOT push unless asked.**
- **Update as you go:** `FEATURES.md`, `backlog.md`, `STANDALONE_PLAN.md`, the `project_standalone_app_store` memory, **and `ROADMAP.html`** (flip the `D3` detour node `next`→`done` when the redesign lands, then redeploy the Artifact — see CLAUDE.md's ROADMAP update contract).
- **Gotchas:** SwiftData traps on a raw Codable-struct `@Model` attribute (persist as `Data?` blobs); the device-build UDID trap (`00008110-001208C902EA201E`); sim flake → `xcrun simctl shutdown all; xcrun simctl erase "iPhone 17"`. Audiobook chunk-extraction uses sample-accurate `AVAudioFile` frame reads (not `AVAssetExportSession`) — don't regress read-along word-time alignment.

## Scope
Build the WHOLE redesign now (user chose this over the scoped slice), THEN pivot to **Phase 2 — Export & Obsidian publish** (the ship-blocker). Deeper audiobook *player polish* (sleep timer, clips, annotatable bookmarks) = Phase 9b, later.

## Current state
Build 13 on `main` (local, unpushed). Phase 0 + Phase 1 sync complete (incl. per-book audiobook sync with a real %, cover/transcript/position/rate). 439/439 `SkriftMobileTests` green. Key files you'll touch: the root/app nav + `MemosListView` (tab bar), `Features/Audiobooks/AudiobookPlayerView.swift` + `ReadAlongView.swift` + `ChaptersBookmarksSheet.swift` + `AudiobookLibraryView.swift`, `Services/Audiobooks/Bookmark.swift`/`BookmarkStore`, and the significance UI (`Features/MemoDetail/SignificanceCircles.swift` + wherever it's surfaced) for the Importance relabel.
