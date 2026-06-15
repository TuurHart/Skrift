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
///   -snapshot-capture <path>    → review surface with the C3 url capture selected
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
        if let p = path("-snapshot-capture")        { MainActor.assumeIsolated { renderCapture(to: p); exit(0) } }
        if let p = path("-snapshot-trash")          { MainActor.assumeIsolated { renderTrash(to: p); exit(0) } }
        if let p = path("-snapshot-people")         { MainActor.assumeIsolated { renderPeople(to: p); exit(0) } }
        if let p = path("-snapshot-names")          { MainActor.assumeIsolated { renderNames(to: p); exit(0) } }
        if let p = path("-snapshot-person-editor")  { MainActor.assumeIsolated { renderPersonEditor(to: p); exit(0) } }
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

    /// C3 capture review: sidebar with the url capture selected + the review pane
    /// showing the source strip, capture banner, props grid (url row), and body.
    /// Corresponds to mock state 3 in capture-items.html.
    /// Triggered by: `-snapshot-capture <path>`
    @MainActor private static func renderCapture(to path: String, scheme: ColorScheme = .dark) {
        let files = DemoSeed.snapshotFiles()
        // The contract url fixture is "demo-capture-url" (see DemoSeed).
        let captureFile = files.first { $0.id == "demo-capture-url" } ?? files.first
        let model = AppModel()
        model.activeID = captureFile?.id
        if let id = captureFile?.id { model.selection = [id] }
        let coordinator = ProcessingCoordinator()

        let view = HStack(spacing: 0) {
            SidebarView(model: model, files: files, coordinator: coordinator, scrollable: false).frame(width: 228)
            NoteDisplayView(file: captureFile, coordinator: coordinator, scrollable: false).frame(maxWidth: .infinity)
        }
        .frame(width: 1180, height: 780)
        .background(Theme.bg)
        writePNG(view, to: path, scheme: scheme)
    }

    /// Recently Deleted sheet — a couple of demo files marked trashed with
    /// staggered ages so the days-remaining countdown shows.
    @MainActor private static func renderTrash(to path: String, scheme: ColorScheme = .dark) {
        let files = DemoSeed.snapshotFiles().prefix(3).enumerated().map { i, f -> PipelineFile in
            f.deletedAt = Date(timeIntervalSinceNow: -Double(i) * 4 * 86_400)   // 0/4/8 days ago
            return f
        }
        let view = RecentlyDeletedView(files: Array(files), interactive: false)
            .background(Theme.bg)
        writePNG(view, to: path, scheme: scheme)
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

    /// Opt-in naming "People in this note" chip bar (mocks/opt-in-naming.html) in its three
    /// states, with INJECTED people so it's deterministic (independent of the on-disk names).
    /// Triggered by: `-snapshot-people <path>`.
    @MainActor private static func renderPeople(to path: String) {
        let hendri = Person(canonical: "[[Hendri Van Niekerk]]", aliases: ["Hendri", "Henry"], short: "Hendri", lastModifiedAt: "x")
        let bruno = Person(canonical: "[[Bruno Aragorn]]", aliases: ["Bruno"], short: "Bruno", lastModifiedAt: "x")
        let tiuri = Person(canonical: "[[Tiuri Hartog]]", aliases: ["Tiuri Hartog", "Tuur"], short: "Tuur", lastModifiedAt: "x")
        let coord = ProcessingCoordinator()

        // State 1 — fresh note, nothing linked: both detected chips OFF.
        let fresh = PipelineFile(id: "s1", filename: "memo.m4a", sourceType: .audio)
        fresh.enhancedCopyedit = "Pizza update on Henry's birthday. Earlier Bruno dropped off the tray."
        fresh.sanitised = fresh.enhancedCopyedit

        // State 2 — tapped Hendri: he's linked (ON, full name), Bruno still OFF.
        let tapped = PipelineFile(id: "s2", filename: "memo.m4a", sourceType: .audio)
        tapped.enhancedCopyedit = "Pizza update on Henry's birthday. Earlier Bruno dropped off the tray."
        tapped.aboutPeople = ["[[Hendri Van Niekerk]]"]
        tapped.sanitised = "Pizza update on [[Hendri Van Niekerk|Henry]]'s birthday. Earlier Bruno dropped off the tray."

        // State 3 — conversation: the matched speaker (Tiuri) is a locked-on chip.
        let convo = PipelineFile(id: "s3", filename: "memo.m4a", sourceType: .audio)
        convo.enhancedCopyedit = "**Tiuri Hartog:** I saw Bruno today\n\n**Speaker 2:** cool"
        convo.sanitised = "**[[Tiuri Hartog]]:** I saw Bruno today\n\n**Speaker 2:** cool"

        func labeled(_ title: String, _ file: PipelineFile) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textMuted)
                PeopleChipBar(file: file, coordinator: coord, interactive: true,
                              peopleOverride: [hendri, bruno, tiuri], onAddPerson: {})
            }
        }
        let view = VStack(alignment: .leading, spacing: 22) {
            labeled("1 · Fresh — nothing linked", fresh)
            labeled("2 · Tapped Hendri — linked + Bruno still off", tapped)
            labeled("3 · Conversation — matched speaker locked-on", convo)
            Spacer()
        }
        .padding(28)
        .frame(width: 480, height: 420, alignment: .topLeading)
        .background(Theme.bg)
        writePNG(view, to: path)
    }

    /// Settings → Names list redesign (mocks/opt-in-naming.html panel 4): avatar · full name
    /// · "aka" aliases · voice chip rows + the "Add person…" row, with INJECTED people.
    /// Triggered by: `-snapshot-names <path>`.
    @MainActor private static func renderNames(to path: String) {
        let people = [
            Person(canonical: "[[Bruno Aragorn]]", aliases: ["Bruno", "Bru"], short: "Bruno",
                   voiceEmbeddings: [VoiceEmbedding(vector: [1])], lastModifiedAt: "x"),
            Person(canonical: "[[Hendri Van Niekerk]]", aliases: ["Henry", "Hendri"], short: "Hendri",
                   voiceEmbeddings: [VoiceEmbedding(vector: [1])], lastModifiedAt: "x"),
            Person(canonical: "[[Tiuri Hartog]]", aliases: ["Tuur", "Thierry"], short: "Tuur",
                   voiceEmbeddings: [VoiceEmbedding(vector: [1])], lastModifiedAt: "x"),
            Person(canonical: "[[Sebastiaan Paap]]", aliases: ["sepp"], short: "Sep", lastModifiedAt: "x"),
        ]
        let view = SettingsView(interactive: false, peopleOverride: people)
            .background(Theme.bg)
        writePNG(view, to: path)
    }

    /// The shared person editor (mocks/opt-in-naming.html panel 3) — labeled fields,
    /// alias-recognition demo, link-display hint, voice state. Triggered by:
    /// `-snapshot-person-editor <path>`.
    @MainActor private static func renderPersonEditor(to path: String) {
        let bruno = Person(canonical: "[[Bruno Aragorn]]", aliases: ["Bruno", "Bru"], short: "Bruno",
                           voiceEmbeddings: [VoiceEmbedding(vector: [1])], lastModifiedAt: "x")
        let view = PersonEditor(request: PersonEditorRequest(person: bruno),
                                onSave: { _, _ in }, onDelete: { _ in }, onClose: {}, interactive: false)
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
                // Don't claim success on a silent write failure (bad path /
                // permissions) — the audit nit: the writer used `try?` and then
                // logged "written" unconditionally, so a missing PNG read as OK.
                do {
                    try png.write(to: URL(fileURLWithPath: path))
                    FileHandle.standardError.write(Data("snapshot written: \(path)\n".utf8))
                } catch {
                    FileHandle.standardError.write(Data("snapshot write FAILED: \(path) — \(error)\n".utf8))
                }
            } else {
                FileHandle.standardError.write(Data("snapshot render failed\n".utf8))
            }
        }
    }
}
#endif
