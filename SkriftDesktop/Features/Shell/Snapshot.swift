#if DEBUG
import SwiftUI
import AppKit

/// Headless visual verification. Renders a view to a PNG via `ImageRenderer` and
/// exits — no window, no Screen Recording permission. Modes:
///   -snapshot <path>           → the review surface (sidebar | note)
///   -snapshot-settings <path>  → the Settings panel
enum Snapshot {
    nonisolated static func renderIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-snapshot-settings"), i + 1 < args.count {
            MainActor.assumeIsolated { renderSettings(to: args[i + 1]); exit(0) }
        }
        if let i = args.firstIndex(of: "-snapshot-wizard"), i + 1 < args.count {
            MainActor.assumeIsolated { renderWizard(to: args[i + 1]); exit(0) }
        }
        if let i = args.firstIndex(of: "-snapshot-run"), i + 1 < args.count {
            MainActor.assumeIsolated { renderRun(to: args[i + 1]); exit(0) }
        }
        if let i = args.firstIndex(of: "-snapshot-resolver"), i + 1 < args.count {
            MainActor.assumeIsolated { renderResolver(to: args[i + 1]); exit(0) }
        }
        guard let i = args.firstIndex(of: "-snapshot"), i + 1 < args.count else { return }
        MainActor.assumeIsolated { renderReview(to: args[i + 1]); exit(0) }
    }

    @MainActor private static func renderReview(to path: String) {
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
        .environment(\.colorScheme, .dark)
        writePNG(view, to: path)
    }

    @MainActor private static func renderSettings(to path: String) {
        let view = SettingsView(interactive: false)   // sizes to full content (no 660 cap)
            .background(Theme.bg)
            .environment(\.colorScheme, .dark)
        writePNG(view, to: path)
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
        .environment(\.colorScheme, .dark)
        writePNG(view, to: path)
    }

    /// R3 inline resolver: the slim banner (mid-progress) + the candidate popover —
    /// the SwiftUI pieces ImageRenderer can draw. The inline body marks + click flow
    /// live in NSTextView/NSPopover (verified by live-driving, not snapshots).
    @MainActor private static func renderResolver(to path: String) {
        let amb = DemoSeed.snapshotFiles().first?.ambiguousNames ?? []
        let model = InlineResolverModel(fileID: "demo-1", ambiguous: amb)
        model.observedTotal = 3
        model.decisions = [0: .person(model.candidates(for: "Jack").first!)]   // 1 of 3 decided
        model.jumpHandler = {}
        let cands = model.candidates(for: "Jack")
        let view = VStack(alignment: .leading, spacing: 26) {
            InlineResolverBanner(model: model) {}
            ResolverPopover(alias: "Jack", contextBefore: "met up with ", contextAfter: " this morning at the studio",
                            candidates: cands, current: .person(cands[0])) { _ in }
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.hairline.opacity(0.12), lineWidth: 0.5))
            Spacer()
        }
        .padding(40)
        .frame(width: 760, height: 460, alignment: .topLeading)
        .background(Theme.bg)
        .environment(\.colorScheme, .dark)
        writePNG(view, to: path)
    }

    @MainActor private static func renderWizard(to path: String) {
        let view = SetupWizardView(interactive: false)
            .frame(width: 900, height: 620)
            .background(Theme.bg)
            .environment(\.colorScheme, .dark)
        writePNG(view, to: path)
    }

    @MainActor private static func writePNG(_ view: some View, to path: String) {
        let renderer = ImageRenderer(content: view)
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
#endif
