#if DEBUG
import SwiftUI
import AppKit

/// Headless visual verification. Renders a view to a PNG via `ImageRenderer` and
/// exits — no window, no Screen Recording permission. Modes:
///   -snapshot <path>            → the review surface (sidebar | note)
///   -snapshot-light <path>      → the review surface in LIGHT
///   -snapshot-settings <path>   → the Settings panel
///   -snapshot-settings-light p  → the Settings panel in LIGHT
///   -snapshot-wizard <path>     → the first-launch wizard
///   -snapshot-run <path>        → the review surface mid-run
///   -snapshot-resolver <path>   → the inline resolver pieces
enum Snapshot {
    nonisolated static func renderIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        func path(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let p = path("-snapshot-settings-light") { MainActor.assumeIsolated { renderSettings(to: p, scheme: .light); exit(0) } }
        if let p = path("-snapshot-settings")       { MainActor.assumeIsolated { renderSettings(to: p); exit(0) } }
        if let p = path("-snapshot-wizard")         { MainActor.assumeIsolated { renderWizard(to: p); exit(0) } }
        if let p = path("-snapshot-run")            { MainActor.assumeIsolated { renderRun(to: p); exit(0) } }
        if let p = path("-snapshot-resolver")       { MainActor.assumeIsolated { renderResolver(to: p); exit(0) } }
        if let p = path("-snapshot-light")          { MainActor.assumeIsolated { renderReview(to: p, scheme: .light); exit(0) } }
        if let p = path("-snapshot")                { MainActor.assumeIsolated { renderReview(to: p); exit(0) } }
    }

    @MainActor private static func renderReview(to path: String, scheme: ColorScheme = .dark) {
        let files = DemoSeed.snapshotFiles()
        let model = AppModel()
        model.activeID = files.first?.id
        if let id = files.first?.id { model.selection = [id] }
        let coordinator = ProcessingCoordinator()

        let view = HStack(spacing: 0) {
            SidebarView(model: model, files: files, coordinator: coordinator, scrollable: false).frame(width: 228)
            NoteDisplayView(file: files.first, coordinator: coordinator, scrollable: false).frame(maxWidth: .infinity)
        }
        .frame(width: 1180, height: 780)
        .background(Theme.bg)
        writePNG(view, to: path, scheme: scheme)
    }

    @MainActor private static func renderSettings(to path: String, scheme: ColorScheme = .dark) {
        let view = SettingsView(interactive: false)   // sizes to full content (no 660 cap)
            .background(Theme.bg)
        writePNG(view, to: path, scheme: scheme)
    }

    @MainActor private static func renderRun(to path: String) {
        let files = DemoSeed.snapshotFiles()
        let model = AppModel()
        model.activeID = files.first?.id
        let coordinator = ProcessingCoordinator.preview(
            .init(total: 5, done: 2, currentTitle: "Standup notes",
                  loadingLabel: "enhancement model", loadingFraction: 0.45))
        let view = HStack(spacing: 0) {
            SidebarView(model: model, files: files, coordinator: coordinator, scrollable: false).frame(width: 228)
            NoteDisplayView(file: files.first, coordinator: coordinator, scrollable: false).frame(maxWidth: .infinity)
        }
        .frame(width: 1180, height: 780)
        .background(Theme.bg)
        writePNG(view, to: path)
    }

    /// R3 inline resolver: the slim banner (mid-progress) + the candidate popover —
    /// the SwiftUI pieces ImageRenderer can draw. The inline body marks + click flow
    /// live in NSTextView/NSPopover (verified by live-driving, not snapshots).
    @MainActor private static func renderResolver(to path: String) {
        let amb = DemoSeed.snapshotFiles().first?.ambiguousNames ?? []
        let model = InlineResolverModel(fileID: "demo-1", ambiguous: amb)
        model.escalated.insert("jack")   // one alias row (Sam) + one escalated row (Jack)
        model.jumpHandler = {}
        let cands = model.candidates(for: "Sam")
        let view = VStack(alignment: .leading, spacing: 26) {
            InlineResolverBanner(model: model)
            ResolverPopover(mode: .alias, alias: "Sam", contextBefore: "If ", contextAfter: " can test it next week",
                            candidates: cands, current: nil, onPick: { _ in }, onEscalate: {})
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.hairline.opacity(0.12), lineWidth: 0.5))
            Spacer()
        }
        .padding(40)
        .frame(width: 760, height: 480, alignment: .topLeading)
        .background(Theme.bg)
        writePNG(view, to: path)
    }

    @MainActor private static func renderWizard(to path: String) {
        let view = SetupWizardView(interactive: false)
            .frame(width: 900, height: 620)
            .background(Theme.bg)
        writePNG(view, to: path)
    }

    @MainActor private static func writePNG(_ view: some View, to path: String, scheme: ColorScheme = .dark) {
        // Dynamic Theme tokens (NSColor providers) resolve against the CURRENT
        // drawing appearance — not SwiftUI's colorScheme — so pin both: the AppKit
        // appearance for the draw, and the SwiftUI environment for native adaptive
        // bits (materials, etc.).
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua) ?? .currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
            renderer.scale = 2
            if let img = renderer.nsImage,
               let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                FileHandle.standardError.write(Data("snapshot written: \(path)\n".utf8))
            } else {
                FileHandle.standardError.write(Data("snapshot render failed\n".utf8))
            }
        }
    }
}
#endif
