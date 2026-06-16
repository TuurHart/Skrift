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
///   -snapshot-naming <path>     → the opt-out naming tiers + popovers (mocks/naming-review.html)
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
        if let p = path("-snapshot-naming")         { MainActor.assumeIsolated { renderNaming(to: p); exit(0) } }
        if let p = path("-snapshot-capture")        { MainActor.assumeIsolated { renderCapture(to: p); exit(0) } }
        if let p = path("-snapshot-trash")          { MainActor.assumeIsolated { renderTrash(to: p); exit(0) } }
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

    /// Opt-out naming review (mocks/naming-review.html) — the SIGNED-OFF visual language:
    /// the three prose tiers (linked #9d8ff7 / suggested tan dotted / plain) + the two
    /// click-popovers. Pure SwiftUI (the live in-NSTextView body is verified by deploy-eyeball,
    /// like the old resolver). Triggered by: `-snapshot-naming <path>`.
    @MainActor private static func renderNaming(to path: String) {
        // State 1 — calm prose (the mock's example sentence): linked names solid #9d8ff7,
        // suggested names tan + dotted, the rest plain (a repeat, a stoplisted word, an unknown).
        func nm(_ s: String, _ c: Color) -> Text { Text(s).foregroundColor(c) }
        func sug(_ s: String) -> Text {
            Text(s).foregroundColor(Theme.nameSuggest)
                .underline(true, pattern: .dot, color: Theme.nameSuggestLine)
        }
        let prose = nm("Hendri", Theme.nameLink) + Text(" showed up early and we nailed the mix with ")
            + nm("Bruno", Theme.nameLink) + Text(", then ") + sug("Jack") + Text(" swung by with notes — sharp as ever. Hendri reckons we're close to done. I'll send ")
            + sug("Rose") + Text(" the stems tonight; Mariam wants in on the next one.")

        let jack = [NameCandidate(id: "[[Jack Hutton]]", canonical: "[[Jack Hutton]]", short: "Jack"),
                    NameCandidate(id: "[[Jack Tanner]]", canonical: "[[Jack Tanner]]", short: "Jack")]

        func cap(_ t: String) -> some View {
            Text(t).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textMuted)
        }
        let view = VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                cap("1 · AFTER PROCESSING — CALM PROSE")
                prose.font(.system(size: 15)).lineSpacing(6).foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: 520, alignment: .leading)
                HStack(spacing: 16) {
                    (Text("linked").foregroundColor(Theme.nameLink) + Text(" auto · first mention")).font(.system(size: 11)).foregroundColor(Theme.textSecondary)
                    (sug("suggested") + Text(" click to confirm")).font(.system(size: 11)).foregroundColor(Theme.textSecondary)
                    (Text("plain").foregroundColor(Theme.textPrimary) + Text(" word · unknown · repeat")).font(.system(size: 11)).foregroundColor(Theme.textSecondary)
                }
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    cap("2 · CLICK A SUGGESTED NAME")
                    SuggestionPopover(spoken: "Jack", candidates: jack, onPick: { _ in }, onNew: {}, onPlain: {})
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.hairline.opacity(0.12), lineWidth: 0.5))
                }
                VStack(alignment: .leading, spacing: 7) {
                    cap("3 · CLICK A LINKED NAME")
                    // "Change person" lists only SAME-NAME people (the wrong-Jack → right-Jack
                    // fix); a distinctive name has none, so the row hides. Shown here for a Jack.
                    LinkedNamePopover(person: "Jack Hutton", others: ["Jack Tanner"],
                                      canOpen: true, onUnlink: {}, onChange: { _ in }, onOpen: {})
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.hairline.opacity(0.12), lineWidth: 0.5))
                }
            }
            Spacer()
        }
        .padding(34)
        .frame(width: 880, height: 560, alignment: .topLeading)
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
