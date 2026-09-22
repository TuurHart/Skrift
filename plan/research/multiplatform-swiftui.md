# C240 — how other multiplatform SwiftUI apps share UI/logic, and what it costs

Grow shared code between SkriftMobile (iOS 26 target, `project.yml` floor iOS 18) and
SkriftDesktop (macOS 15 floor, AppKit NSTextView editor, in-process MLX) without drifting
the apps or risking the Mac's editor/model path. Today `Skrift_Native/Shared/` is a plain
source folder (98 files) compiled into both xcodegen targets (mobile 8015 files, desktop
7254); the one proven UI-sharing example is `Shared/UI/NoteCardView.swift` — one view +
per-app `NoteCardStyle`/`NoteCardModel` structs, used by `SidebarView.swift` (desktop) and
`MemosListView.swift` (mobile).

## 1. Apple's one-target "Multiplatform App" template

**What we saw:** Skrift is two Xcode targets, not Apple's single multiplatform target.

**What others found:**
- The template gives one app target for iPhone/iPad/Mac, with a "shared" group for
  data/app-structure/common views and per-platform groups for the rest —
  [Configuring a multiplatform app target, Apple docs](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target); intro at [WWDC22 110371](https://developer.apple.com/videos/play/wwdc2022/110371/) ([notes](https://wwdcnotes.com/documentation/wwdc22-110371-use-xcode-to-develop-a-multiplatform-app/)).
- Forum consensus: you still "cannot build an app 100% with SwiftUI" on the template —
  AppKit/UIKit gets dropped in for gaps — [forums.apple.com/thread/649812](https://developer.apple.com/forums/thread/649812).
- Concrete breakage on a shipped template app: `.fileExporter` returns a **folder** URL on
  macOS, not a file URL (breaks PDF export, no iOS workaround); SwiftUI's Save panel has no
  way to restrict the Mac "File Format" menu to the app's own type (radar FB11876082, open);
  `TextEditor`'s macOS formatting bar is covered by any sidebar —
  [SwiftUI Limits I Encountered, swiftdevjournal.com](https://swiftdevjournal.com/posts/swiftui-limits/).
- A full-app port to one multiplatform SwiftUI codebase (Pulse) hit **85% shared code**,
  with the one AppKit escape hatch being exactly Skrift's own wall: no attributed/
  syntax-highlighted text view, so the author wrote an `NSTextView` wrapper by hand —
  [kean.blog/post/appkit-is-done](https://kean.blog/post/appkit-is-done).

**The fix/workaround:** the template doesn't remove the AppKit escape hatch for text
editing or Mac-only panels — it just puts iOS/Mac source in one target with `#if
os(macOS)` instead of two targets.

**Our next step:** don't adopt the template — the two-target split stays; the useful
transfer is "shared view + per-app style struct," already running in `NoteCardView.swift`.

## 2. Mac Catalyst and "Designed for iPad" on Apple silicon

**What we saw:** no Catalyst option in play — SkriftDesktop is a native AppKit-capable target.

**What others found:**
- Apple: Catalyst exists to "create a Mac version of an iPad app"; an app can instead run
  un-modified as "Designed for iPad" on Apple silicon at ~77% scale, with no Mac idiom —
  [Choosing a User Interface Idiom for Your Mac App, Apple docs](https://developer.apple.com/documentation/uikit/mac_catalyst/choosing_a_user_interface_idiom_for_your_mac_app), discussed at [forums.apple.com/thread/649812](https://developer.apple.com/forums/thread/649812).
- "The State of Mac Catalyst in 2026" thread: Apple ships Music/Podcasts/Maps/Messages/
  FaceTime/Books/Weather on Catalyst; cites third-party adopters **Ice Cubes** and
  **Craft** — [forums.apple.com/thread/811728](https://developer.apple.com/forums/thread/811728) (Jan 2026, no bug specifics given).
- Verified independently (not just the forum claim): Ice Cubes' `.pbxproj` sets
  `SUPPORTS_MACCATALYST = YES`, `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`,
  `TARGETED_DEVICE_FAMILY = "1,2,7"` — one iOS/iPadOS/visionOS build, Mac via Catalyst only
  (from reading `IceCubesApp.xcodeproj/project.pbxproj`, github.com/Dimillian/IceCubesApp).
- Craft, despite the forum's Catalyst listing, doesn't use SwiftUI at all: "Craft does not
  use Apple's UI components: they don't use SwiftUI or Autolayout ... built their own
  components from scratch," ~99% shared code across iOS/iPad/Mac/visionOS via a custom
  framework — [Pragmatic Engineer, "Design-first software engineering: Craft"](https://newsletter.pragmaticengineer.com/p/design-first-software-engineering). Treat the
  forum's app list as unverified beyond Ice Cubes.

**The fix/workaround:** Catalyst suits an app that *is* an iPad app wanting a cheap Mac
build; it gives no AppKit access and runs inside the iOS runtime shim, not a first-class
AppKit process.

**Our next step:** none — SkriftDesktop needs AppKit (NSTextView) and in-process native
MLX; Catalyst buys nothing over the existing target and would cost the NSTextView editor.
Not a fit, confirmed from Apple's own idiom-choice doc.

## 3. "Shared SwiftUI view + per-platform style/adapter" — who else does this

**What we saw:** `NoteCardView.swift` is Skrift's only working instance (§ above).

**What others found:**
- NetNewsWire (macOS AppKit + iOS UIKit) is the inverse case — zero shared UI, only
  shared non-UI modules. Layout: `Mac/` (AppKit UI), `iOS/` (UIKit UI), `Modules/`
  (RSCore, RSParser, RSWeb, RSDatabase, account/article/sync) — [Ranchero-Software/NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire), [its CLAUDE.md](https://github.com/Ranchero-Software/NetNewsWire/blob/main/CLAUDE.md).
  This is roughly Skrift's *starting* shape; SwiftUI is why Skrift can go further.
- Ice Cubes (one SwiftUI target, iOS+iPadOS+macOS via Catalyst+visionOS) leans on `#if
  os(...)` inside shared views plus a dedicated `DesignSystem` package for shared look —
  13 local SPM packages confirmed from `Dimillian/IceCubesApp/Packages/` (Account,
  AppAccount, Conversations, DesignSystem, Env, Explore, Lists, MediaUI, Models,
  NetworkClient, Notifications, StatusKit, Timeline; read via GitHub API). No public
  write-up found explaining why they picked in-view `#if os()` over a style-struct layer
  — not found.
- No canonical source names Skrift's exact "one view, per-app style struct" pattern; the
  closest documented analogue is Apple's own guidance to centralize shared interface
  elements (§1).

**The fix/workaround:** n/a — this pattern already works in Skrift.

**Our next step:** audit for other layout-identical view pairs across the two `Features/`
trees before any bigger structural change.

## 4. SPM feature packages vs a shared source folder

**What we saw:** `Shared/` is a plain folder, "compiled into both targets via xcodegen,
not a package" (CLAUDE.md).

**What others found:**
- Ice Cubes and Damus (§5) both use local SPM packages. General case for packages: the
  compiler enforces real module boundaries and only changed packages recompile —
  [Local SPM (Part 1), Guy Cohen](https://medium.com/@guycohendev/local-spm-mastering-modularization-with-swift-package-manager-xcode-15-e37b14c36199), [Modularizing Swift Apps with SPM, Kyle Browning](https://kylebrowning.com/posts/modularizing-swift-apps-with-spm/), [Modular Project Structure with SPM, Santosh Botre](https://santoshbotre01.medium.com/modular-project-structure-with-swift-package-manager-spm-c81fb62c8619).
- Cost side: a local package can declare `platforms: [.iOS(...), .macOS(...)]` and stay
  cross-platform, but each boundary is a new place a `#if canImport(AppKit)` leak can
  hide, plus `xcodegen generate` + clean-build discipline a folder doesn't need. Skrift's
  own project memory already logged one concrete SPM cost in this repo: a fresh
  worktree's `xcodebuild` needs `-skipPackagePluginValidation` or it dies on the mlx-swift
  `CudaBuild` plugin with zero tests run (`memory/feedback_parallel_orchestration.md`,
  per the project's own memory index — a prior project finding, not re-verified here).

**The fix/workaround:** packages buy compiler-enforced boundaries and partial rebuilds; a
folder buys zero package-graph ceremony and has already dodged one class of SPM-plugin
build breakage elsewhere in this repo.

**Our next step:** don't convert `Shared/` to a package wholesale. If it keeps growing,
split along its own existing subfolders (`Pipeline/`, `RetrievalEngine/`, `Export/`,
`UI/`, confirmed via `find Skrift_Native/Shared -maxdepth 2 -type d`) only once a concrete
rebuild-time complaint shows up.

## 5. How real open-source multiplatform Swift apps do it

**What others found:**
- **NetNewsWire** — no shared UI, shared logic via SPM modules (§3).
- **Ice Cubes** — single SwiftUI target + Mac Catalyst (confirmed `SUPPORTS_MACCATALYST =
  YES` in its `.pbxproj`), 13 local SPM feature packages — [Dimillian/IceCubesApp](https://github.com/Dimillian/IceCubesApp).
- **Damus** ("iOS 16.0+ and macOS 13.0+" per its README) — one `Package.swift`, one
  `damus.xcodeproj`, `share extension` + `highlighter action extension`, no `Mac/`-style
  split (from reading `repos/damus-io/damus/contents` via the GitHub API) — an iPad-app-
  on-Mac shape; not found which of Catalyst/"Designed for iPad" it actually uses.
- **Bear** — Bear 2 shipped macOS/iOS/iPadOS July 2023, "C++, Objective-C, and Swift" per
  Wikipedia; no developer statement found on UI/editor code sharing — not found.
- **Craft** — opposite of "share SwiftUI": built a custom cross-platform canvas framework
  to hit ~99% shared code (§2) — a multi-year investment, not a template for Skrift.
- A SwiftUI notes app with a **native Mac rich-text editor** sharing the model while
  keeping two text views: no matching open-source repo found (Bear/Craft/Things are
  closed-source) — not found. The actionable pattern for this comes from a library, §6.

**Our next step:** none of these is a drop-in template for the editor wall; §6 is.

## 6. The wall: NSTextView vs UITextView, and whether one SwiftUI editor works now

**What we saw:** SkriftDesktop's editor is AppKit `NSTextView`; macOS floor is 15.0 (not
26), iOS floor is 18.0 in `SkriftMobile/project.yml`.

**What others found:**
- `TextEditor` gained `AttributedString`/rich-text support at iOS/macOS 26 — but on macOS
  it "looks like a plain text editor with no formatting controls" until the app adds
  `.commands { TextFormattingCommands() }`, and even then the format bar sits behind
  Format ▸ Text ▸ Show Ruler and gets **covered by any sidebar** —
  [SwiftUI Limits I Encountered, swiftdevjournal.com](https://swiftdevjournal.com/posts/swiftui-limits/).
- Live unresolved bug at **macOS 15.5** — Skrift's current Mac floor: `TextEditor` throws
  an out-of-bounds selection error "if you delete text until the input field is empty, and
  then typed again" — a developer reverted to a third-party library over it —
  [Choosing a Text Editor in SwiftUI: Why I Moved to RichTextKit](https://justdoswift.substack.com/p/choosing-a-text-editor-in-swiftui).
- The concrete "share the model, keep two native editors" pattern: **RichTextKit**
  (Daniel Saidi) — a platform-agnostic `RichTextContext` (observable state, e.g.
  `isUnderlined`) is the source of truth; a `RichTextCoordinator` uses Combine to sync it
  into the native view; a `RichTextViewRepresentable` protocol gives `UITextView`/
  `NSTextView` subclasses one surface despite different underlying APIs
  (`attributedText` vs `attributedString()`). Named gotchas: macOS needs an explicit
  scroll-view wrapper; invalid NSRanges crash (needs a `safeRange` helper); bold/italic
  are font traits, underline is a text attribute — different code paths per platform —
  [danielsaidi.com](https://danielsaidi.com/blog/2022/06/13/building-a-rich-text-editor-for-uikit-appkit-and-swiftui), [github.com/danielsaidi/RichTextKit](https://github.com/danielsaidi/RichTextKit).
- Even kean.blog's 85%-shared case (§1) kept exactly one hand-written AppKit wrapper, and
  it was the text view — the same wall, independently arrived at.

**The fix/workaround:** the field's answer to "share the model, keep two editors" is
RichTextKit's shape (shared context model + coordinator + thin protocol per native view),
not waiting on native `TextEditor` — which needs macOS 26 (Skrift floor is 15) and has an
open selection-crash report at 15.5 plus a sidebar-collision bug.

**Our next step:** don't touch the NSTextView editor this pass (out of scope until body
v2). When body v2 starts, prototype RichTextKit's three-piece shape against Skrift's own
model instead of retrying SwiftUI `TextEditor` — confirmed not good enough yet at Skrift's
deployment floor, by a live bug report, not assumption.

## Comparison table

| Approach | Shares | Costs | Fits MLX-in-process Mac + NSTextView? |
|---|---|---|---|
| One-target Multiplatform App template | UI code, up to ~85% in the field | AppKit/UIKit escape hatches for text editing, file panels, Save-format menu | Still needs the NSTextView hatch; re-plumbs two working targets |
| Mac Catalyst | Whole app, one build | No first-class AppKit process, iPad idiom by default | No — loses native NSTextView + in-process MLX |
| "Designed for iPad" (no Catalyst) | Everything, zero work | 77% scaled iPad UI, no Mac idiom | No — worse than Catalyst |
| Shared SwiftUI view + per-app style struct (`NoteCardView`) | Layout/behavior, per-screen | Discipline to keep model/style structs thin | Yes — proven, incremental |
| SPM feature packages | Compiler-enforced boundaries, partial rebuilds | Package-graph ceremony; repo has a known mlx-swift plugin trap | Not yet — no rebuild-time pain to justify it |
| Custom cross-platform framework (Craft) | ~99% | Multi-year framework-building investment | No — outside this pass's scope |
| RichTextKit-style shared editor model | Formatting state only, two native views | Coordinator + protocol plumbing | Deferred to body v2 |

## Recommendation

Keep two apps. Grow `Shared/UI/` using the `NoteCardView` pattern (one view, one `…Model`
struct, one `…Style` struct per app) — not Apple's one-target template, not Catalyst.
Neither survives contact with SkriftDesktop's AppKit NSTextView editor or its in-process
MLX pipeline, and the field's best single-target case (kean.blog, 85% shared) still needed
a hand-rolled AppKit escape hatch for exactly that. Don't convert `Shared/` to an SPM
package yet — no rebuild-time pain justifies the package-graph cost, and this repo already
has one recorded mlx-swift SPM-plugin build trap.

**Rules for `Shared/UI/`:** (1) a view moves there only when *layout and interaction* —
not just look — are identical across apps; per-app difference goes in a `…Style`/`…Model`
struct, never an `#if os()` inside the shared view (deviates from Ice Cubes' in-view
branching on purpose — Skrift's pattern is cleaner). (2) never point a shared view at
AppKit/UIKit directly; the NSTextView editor stays a desktop-only leaf a shared screen
composes around. (3) audit `Features/` in both apps for layout-identical row/list/card
views before inventing new shared components.

**Don't touch:** the MLX-in-process Mac path (no Catalyst, no single-target migration
touches it); the NSTextView editor (explicit brief scope until body v2); `project.yml`
deployment floors (macOS 15 / iOS 18 — raising either to unlock native `TextEditor` rich
text is a separate, larger decision not covered here).

## Things to try first

1. Audit both `Features/` trees for the next `NoteCardView`-shaped candidate (identical
   layout, per-app style) and fold the first one into `Shared/UI/`.
2. Record the macOS-15.5 `TextEditor` selection-crash finding and the RichTextKit
   shared-model shape where body v2 planning will read it, so native `TextEditor` isn't
   re-evaluated from scratch later.
3. Do not start an SPM-package conversion of `Shared/` — no rebuild-time evidence
   justifies it yet, and it would touch every target's build graph including the
   mlx-swift-sensitive desktop one.
