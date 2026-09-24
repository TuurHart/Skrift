#if DEBUG
import SwiftUI
import AppKit
import SwiftData
import AVFoundation

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
///   -snapshot-inspector <path>  → the Connections inspector floating over the note (HOSTED)
///   -snapshot-livedraft <path>  → the m1/m2/m4 recording draft surface (fixture-driven)
///   -snapshot-sidebar-selection <path> [+ `-light`] → both sidebar row kinds SELECTED,
///                                 side by side (the 2026-07-28 "can't see selection" fix)
enum Snapshot {
    nonisolated static func renderIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        func path(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let p = path("-snapshot-destinations") {
            let w = CGFloat(path("-noteWidth").flatMap { Double($0) } ?? 900)
            MainActor.assumeIsolated { renderDestinations(to: p, width: w); exit(0) }
        }
        if let p = path("-snapshot-settings-light") { MainActor.assumeIsolated { renderSettings(to: p, scheme: .light); exit(0) } }
        if let p = path("-snapshot-settings-hosted") {
            let w = CGFloat(path("-settingsWidth").flatMap { Double($0) } ?? 620)
            MainActor.assumeIsolated { renderSettingsHosted(to: p, width: w); exit(0) }
        }
        if let p = path("-snapshot-settings")       { MainActor.assumeIsolated { renderSettings(to: p); exit(0) } }
        if let p = path("-snapshot-wizard")         { MainActor.assumeIsolated { renderWizard(to: p); exit(0) } }
        if let p = path("-snapshot-run")            { MainActor.assumeIsolated { renderRun(to: p); exit(0) } }
        if let p = path("-snapshot-naming")         { MainActor.assumeIsolated { renderNaming(to: p); exit(0) } }
        if let p = path("-snapshot-capture")        { MainActor.assumeIsolated { renderCapture(to: p); exit(0) } }
        if let p = path("-snapshot-trash")          { MainActor.assumeIsolated { renderTrash(to: p); exit(0) } }
        if let p = path("-snapshot-names")          { MainActor.assumeIsolated { renderNames(to: p); exit(0) } }
        if let p = path("-snapshot-person-editor")  { MainActor.assumeIsolated { renderPersonEditor(to: p); exit(0) } }
        if let p = path("-snapshot-memolinks")      { MainActor.assumeIsolated { renderMemoLinks(to: p); exit(0) } }
        if let p = path("-snapshot-photoblock")     { MainActor.assumeIsolated { renderPhotoBlock(to: p); exit(0) } }
        if let p = path("-snapshot-turns")          { MainActor.assumeIsolated { renderTurns(to: p); exit(0) } }
        if let p = path("-snapshot-turns-light")    { MainActor.assumeIsolated { renderTurns(to: p, scheme: .light); exit(0) } }
        if args.contains("-turncheck")              { MainActor.assumeIsolated { checkTurns(); exit(0) } }
        // -copyeditcheck <input.txt> [-copyeditout <path>] — run the REAL enhancement
        // model's copy-edit on a text file and report what it did (chars/words/newlines
        // in vs out, budget, wall time, identical-to-input). Built 2026-08-18 to answer
        // "does copy-edit even work on a long note" with evidence instead of guesses;
        // exits before the store is touched, so it can run beside a live app.
        if let p = path("-copyeditcheck") {
            checkCopyEdit(input: p, output: path("-copyeditout") ?? p + ".edited.txt",
                          promptFile: path("-copyeditprompt"))
        }
        if args.contains("-miccheck")               { MainActor.assumeIsolated { checkMic(); exit(0) } }
        if args.contains("-recordcheck")            { MainActor.assumeIsolated { checkRecord() } }
        if let p = path("-snapshot-turns-body"), let b = path("-turnsBody") {
            let light = args.contains("-light")
            MainActor.assumeIsolated { renderTurnsBody(to: p, bodyFile: b, scheme: light ? .light : .dark); exit(0) }
        }
        if let p = path("-snapshot-tags")           { MainActor.assumeIsolated { renderTags(to: p); exit(0) } }
        if let p = path("-snapshot-linkpicker")     { MainActor.assumeIsolated { renderLinkPicker(to: p); exit(0) } }
        if let p = path("-snapshot-connections")    { MainActor.assumeIsolated { renderConnections(to: p); exit(0) } }
        if let p = path("-snapshot-inspector")      { MainActor.assumeIsolated { renderInspector(to: p); exit(0) } }
        if let p = path("-snapshot-unrated")        { MainActor.assumeIsolated { renderUnrated(to: p); exit(0) } }
        if let p = path("-snapshot-significance") {
            let light = args.contains("-light")
            MainActor.assumeIsolated { renderSignificance(to: p, scheme: light ? .light : .dark); exit(0) }
        }
        if let p = path("-snapshot-livedraft")      { MainActor.assumeIsolated { renderLiveDraft(to: p); exit(0) } }
        if let p = path("-snapshot-stranded") {
            let light = args.contains("-light")
            MainActor.assumeIsolated { renderStrandedRow(to: p, scheme: light ? .light : .dark); exit(0) }
        }
        if let p = path("-snapshot-sidebar-selection") {
            let light = args.contains("-light")
            MainActor.assumeIsolated { renderSidebarSelection(to: p, scheme: light ? .light : .dark); exit(0) }
        }
        if let p = path("-snapshot-shell") {
            let w = CGFloat(path("-shellWidth").flatMap { Double($0) } ?? 1180)
            let sb = CGFloat(path("-sidebarWidth").flatMap { Double($0) } ?? 228)
            MainActor.assumeIsolated { renderShell(to: p, width: w, sidebar: sb); exit(0) }
        }
        if let p = path("-snapshot-journal")        { MainActor.assumeIsolated { renderJournal(to: p); exit(0) } }
        if let p = path("-snapshot-light")          { MainActor.assumeIsolated { renderReview(to: p, scheme: .light); exit(0) } }
        if let p = path("-snapshot")                { MainActor.assumeIsolated { renderReview(to: p); exit(0) } }
    }

    /// The Connections panel (mocks/related-panel.html) in four states — pure
    /// `ConnectionsPanelBody` fixtures, no engine, mock-story rows.
    /// Triggered by: `-snapshot-connections <path>`.
    @MainActor private static func renderConnections(to path: String) {
        func days(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: Date())! }
        let rows = [
            ConnectionRow(id: UUID(), fileID: "a", title: "Rooftop garden — first sketch",
                          date: days(-126), score: 0.52, importance: 0.3,
                          why: [ConnectionWhy(kind: .tag, text: "#garden"), ConnectionWhy(kind: .term, text: "planters")]),
            ConnectionRow(id: UUID(), fileID: "b", title: "Planter boxes with Jack",
                          date: days(-104), score: 0.61, importance: 0.6,
                          why: [ConnectionWhy(kind: .person, text: "Jack W."), ConnectionWhy(kind: .tag, text: "#garden")]),
            ConnectionRow(id: UUID(), fileID: "c", title: "Water butt + pump sizing",
                          date: days(-51), score: 0.87, importance: 0.9,
                          why: [ConnectionWhy(kind: .term, text: "pump"), ConnectionWhy(kind: .term, text: "water"),
                                ConnectionWhy(kind: .tag, text: "#garden"), ConnectionWhy(kind: .term, text: "gravity")]),
            ConnectionRow(id: UUID(), fileID: "d", title: "Greywater reuse idea",
                          date: days(-16), score: 0.49, importance: nil,
                          why: [ConnectionWhy(kind: .term, text: "water")]),
            // Past the relatedKMac cap: 9 rows, and the EARLIEST is the WEAKEST
            // match — proves the first-mention guarantee swaps it into the seven.
            ConnectionRow(id: UUID(), fileID: "e", title: "Allotment daydream — the original spark",
                          date: days(-260), score: 0.46, importance: nil,
                          why: [ConnectionWhy(kind: .term, text: "garden")]),
            ConnectionRow(id: UUID(), fileID: "f", title: "Balcony vs rooftop — where to build",
                          date: days(-140), score: 0.58, importance: nil,
                          why: [ConnectionWhy(kind: .tag, text: "#garden")]),
            ConnectionRow(id: UUID(), fileID: "g", title: "Drip lines vs sprinkler heads",
                          date: days(-33), score: 0.72, importance: 0.4,
                          why: [ConnectionWhy(kind: .term, text: "drip"), ConnectionWhy(kind: .term, text: "irrigation")]),
            ConnectionRow(id: UUID(), fileID: "h", title: "Compost bin placement",
                          date: days(-90), score: 0.55, importance: nil,
                          why: [ConnectionWhy(kind: .tag, text: "#garden")]),
            ConnectionRow(id: UUID(), fileID: "i", title: "Rainwater capture maths",
                          date: days(-70), score: 0.66, importance: 0.2,
                          why: [ConnectionWhy(kind: .term, text: "water")]),
        ].sorted { $0.score > $1.score }
        let backlinks = [
            ConnectionBacklink(id: "x", title: "Weekend build plan", date: days(-11)),
            ConnectionBacklink(id: "y", title: "Shopping list — garden centre", date: days(-18)),
        ]
        func panel(_ state: RetrievalGate, related: [ConnectionRow], byDate: Bool) -> some View {
            ConnectionsPanelBody(state: state, related: related, backlinks: backlinks,
                                 currentTitle: "Drip irrigation for the rooftop planters",
                                 currentDate: Date(), currentImportance: 0.8,
                                 sortByDate: .constant(byDate))
        }
        let view = HStack(alignment: .top, spacing: 1) {
            panel(.ready, related: rows, byDate: true)     // Date mode — the rail
            panel(.ready, related: rows, byDate: false)    // Closest mode — flat rows
            panel(.gate, related: [], byDate: true)        // consent gate
            panel(.indexing(done: 34, total: 78), related: [], byDate: true)
        }
        .frame(height: 860)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        hostPNG(view, size: NSSize(width: 280 * 4 + 3, height: 860), to: path)
    }

    /// The `[[` memo-link picker popover, with injected candidates — the deterministic eyeball
    /// for the new Mac link-creation UI (`-snapshot-linkpicker <path>`).
    @MainActor private static func renderLinkPicker(to path: String) {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        let cands = [
            ("Rethinking the desktop rewrite as one native app", -1),
            ("Journal on the Mac — map mode + Looking back", -3),
            ("AirPods route bug — the 4-round P0", -8),
            ("Custom vocab finally works on device", -12),
            ("Books tab: reading mode + e-reader page", -20),
        ].map { (title, days) in
            MemoLinkCandidate(id: UUID(), title: title,
                              subtitle: df.string(from: Calendar.current.date(byAdding: .day, value: days, to: Date())!))
        }
        let view = MemoLinkPopover(candidates: cands, onPick: { _, _ in }, onCancel: {})
            .padding(24).background(Theme.surface)
        hostPNG(view, size: NSSize(width: 348, height: 340), to: path)
    }

    /// Memo-link chips + the LINKED FROM strip need the LIVE editor path (NSTextView) —
    /// ImageRenderer draws a placeholder for NSViewRepresentable, so this render is
    /// HOSTED: an offscreen `NSHostingView` (real AppKit) + `cacheDisplay`, with an
    /// in-memory store so the backlinks fetch works. Triggered by:
    /// `-snapshot-memolinks <path>` (the tool for any future NSTextView-backed surface).
    @MainActor private static func renderMemoLinks(to path: String) {
        guard let container = try? ModelContainer(
            for: PipelineFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        else { return }
        let ctx = container.mainContext
        for f in DemoSeed.snapshotFiles() { ctx.insert(f) }
        try? ctx.save()
        let all = (try? ctx.fetch(FetchDescriptor<PipelineFile>())) ?? []
        guard let source = all.first(where: { $0.id == "demo-1" }),
              let target = all.first(where: { $0.id == "9E8B7C6D-1111-4222-8333-444455556666" })
        else { return }

        // Source (chip in the body, tall pane so nothing clips) stacked over the
        // target (short — its LINKED FROM strip must list the source).
        let view = VStack(spacing: 0) {
            NoteDisplayView(file: source, coordinator: ProcessingCoordinator(), onOpenMemo: { _ in })
                .frame(height: 880)
            Divider().overlay(Theme.accent.opacity(0.4))
            NoteDisplayView(file: target, coordinator: ProcessingCoordinator(), onOpenMemo: { _ in })
                .frame(height: 700)
        }
        .frame(width: 940, height: 1581)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .modelContainer(container)

        hostPNG(view, size: NSSize(width: 940, height: 1581), to: path)
    }

    /// The WHOLE Mac shell — sidebar + note — hosted in real AppKit, so the
    /// sidebar actually draws. The plain `-snapshot` path renders it as one big
    /// placeholder (its search field, Menus and buttons are AppKit-backed), which
    /// means the Mac's list column has never been eyeball-comparable against the
    /// iPad's. Added 2026-07-25 for exactly that comparison.
    /// `-snapshot-shell <path>` · add `-shellWidth <n>` for another window width.
    @MainActor private static func renderShell(to path: String, width: CGFloat, sidebar: CGFloat) {
        guard let container = try? ModelContainer(
            for: PipelineFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        else { return }
        let ctx = container.mainContext
        let files = DemoSeed.snapshotFiles()
        for f in files { ctx.insert(f) }
        try? ctx.save()
        let model = AppModel()
        model.activeID = files.first?.id
        if let id = files.first?.id { model.selection = [id] }
        let coordinator = ProcessingCoordinator()

        let view = HStack(spacing: 0) {
            SidebarView(model: model, files: files, coordinator: coordinator,
                        session: fixtureSession(coordinator: coordinator))
                .frame(width: sidebar)
            NoteDisplayView(file: files.first, coordinator: coordinator, onOpenMemo: { _ in })
                .frame(maxWidth: .infinity)
        }
        .frame(width: width, height: 900)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .modelContainer(container)
        hostPNG(view, size: NSSize(width: width, height: 900), to: path)
    }

    /// The STRANDED row (2026-08-20): a RATED memo with no `PipelineFile` used to render in
    /// no list section at all — queue rows are files, quiet rows are the unrated memos — so
    /// a note that was perfectly safe read as deleted (Tuur, 2026-08-19). This is the floor
    /// under that: it shows up in the list, with a line that says what is actually true
    /// ("waiting for its audio to sync — not queued"), never the spine's "processes on next
    /// run" — it has no row to process with. Shown beside an ordinary quiet (unrated) row so
    /// the two lines can be compared at a glance.
    /// `-snapshot-stranded <path>` · add `-light` for the light theme.
    @MainActor private static func renderStrandedRow(to path: String, scheme: ColorScheme) {
        guard let container = try? ModelContainer(
            for: PipelineFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        else { return }
        let ctx = container.mainContext
        let files = DemoSeed.snapshotFiles()
        for f in files { ctx.insert(f) }
        try? ctx.save()

        // RATED, no PipelineFile — an audiobook quote whose audio blob never synced (the two
        // real ones in the Dev store are from 2026-06-11, invisible until today).
        let stranded = Memo(id: UUID(), audioFilename: "memo_stranded.m4a", duration: 96,
                            recordedAt: Date().addingTimeInterval(-60 * 60 * 20),
                            transcript: "Quote from the book, and what I said back about it.",
                            transcriptStatus: .done, significance: 0.5)
        // …and a typed one, the shape that used to fall through ingest entirely.
        let strandedTyped = Memo(id: UUID(), audioFilename: "",
                                 recordedAt: Date().addingTimeInterval(-60 * 90),
                                 transcript: "Mats was tien jaar.\n\nHij keek naar de zee.",
                                 transcriptStatus: .done, significance: 0.1)
        strandedTyped.metadataData = try? JSONSerialization.data(withJSONObject: ["mediaSource": "typed"])
        let quiet = Memo(id: UUID(), audioFilename: "take.m4a", duration: 51,
                         recordedAt: Date().addingTimeInterval(-60 * 24),
                         transcript: "An unrated take — the ordinary quiet row, for comparison.",
                         transcriptStatus: .done, significance: 0)

        let coordinator = ProcessingCoordinator()
        let model = AppModel()
        let view = SidebarView(model: model, files: files, coordinator: coordinator,
                               session: fixtureSession(coordinator: coordinator),
                               fixtureCloudMemos: [stranded, strandedTyped, quiet])
            .frame(width: 292, height: 800)
            .preferredColorScheme(scheme)
            .modelContainer(container)
        hostPNG(view, size: NSSize(width: 292, height: 800), to: path)
    }

    /// The 2026-07-28 selection-visibility fix ("no way to see what node I have
    /// selected in the left sidebar"): TWO full sidebars side by side — left with a
    /// pipeline row selected, right with a QUIET (unrated) row selected, the kind
    /// that had no selected treatment at all (and the kind every fresh Mac take is).
    /// Quiet rows come from `fixtureCloudMemos`, so the real CloudKit store is never
    /// opened and the render is deterministic. HOSTED (search field, ScrollView).
    /// `-snapshot-sidebar-selection <path>` · add `-light` for the light theme.
    @MainActor private static func renderSidebarSelection(to path: String, scheme: ColorScheme) {
        guard let container = try? ModelContainer(
            for: PipelineFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        else { return }
        let ctx = container.mainContext
        let files = DemoSeed.snapshotFiles()
        for f in files { ctx.insert(f) }
        try? ctx.save()

        // Two quiet (unrated) takes — fresh `recordedAt`, significance 0, ids shared
        // with no `PipelineFile`, so `WayOutRules.unpipelined` lists them both.
        func quietTake(_ text: String, minutesAgo: Double) -> Memo {
            Memo(id: UUID(), audioFilename: "take.m4a", duration: 51,
                 recordedAt: Date().addingTimeInterval(-60 * minutesAgo),
                 transcript: text, transcriptStatus: .done, significance: 0)
        }
        let quietSelected = quietTake("Live take — the floor rides the mic's own silence now", minutesAgo: 24)
        let quietOther = quietTake("Second take — paragraph break after the long pause", minutesAgo: 96)

        let coordinator = ProcessingCoordinator()
        func column(_ label: String, selecting id: String) -> some View {
            let model = AppModel()
            model.activeID = id
            model.selection = [id]
            return VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 10, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                SidebarView(model: model, files: files, coordinator: coordinator,
                            session: fixtureSession(coordinator: coordinator),
                            fixtureCloudMemos: [quietSelected, quietOther])
                    .frame(width: 250)
            }
        }
        let view = HStack(alignment: .top, spacing: 1) {
            column("PIPELINE ROW SELECTED", selecting: files[1].id)
            column("QUIET (UNRATED) ROW SELECTED", selecting: quietSelected.id.uuidString)
        }
        .frame(width: 501, height: 800)
        .background(Theme.hairline.opacity(0.25))
        .preferredColorScheme(scheme)
        .modelContainer(container)
        hostPNG(view, size: NSSize(width: 501, height: 800), to: path)
    }

    /// The Connections INSPECTOR geometry (2026-07-25): the panel slides in OVER the
    /// note's trailing edge instead of taking a column, so what needs proving is
    /// LAYOUT — the note doesn't reflow, the panel starts BELOW the toolbar bar, and
    /// the bar's hairline runs the full note width behind it. HOSTED (real AppKit):
    /// the live panel path needs `scrollable: true`, which `ImageRenderer` can't lay
    /// out. Pass `-snapshot-inspector <path>`; the panel shows its consent gate (no
    /// embedding engine here) — this render is about geometry, not rows.
    @MainActor private static func renderInspector(to path: String) {
        guard let container = try? ModelContainer(
            for: PipelineFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        else { return }
        let ctx = container.mainContext
        for f in DemoSeed.snapshotFiles() { ctx.insert(f) }
        try? ctx.save()
        guard let file = (try? ctx.fetch(FetchDescriptor<PipelineFile>()))?.first(where: { $0.id == "demo-1" })
        else { return }

        UserDefaults.standard.set(true, forKey: "connectionsPanelVisible")
        let view = NoteDisplayView(file: file, coordinator: ProcessingCoordinator(), onOpenMemo: { _ in })
            .frame(width: 952, height: 780)
            .background(Theme.bg)
            .preferredColorScheme(.dark)
            .modelContainer(container)
        hostPNG(view, size: NSSize(width: 952, height: 780), to: path)
    }

    /// **The identity proof** for `MemoNoteProjection` (2026-07-26): the SAME note
    /// content rendered twice side by side — left as a pipelined `PipelineFile`, right
    /// as an unrated `Memo` projected into one. The claim being tested is "an unrated
    /// note is identical to any other note", and the only honest way to check a claim
    /// about pixels is to look at them next to each other. HOSTED (real AppKit): the
    /// body is an NSTextView and the title an NSTextField, both of which the plain
    /// `ImageRenderer` path draws as placeholders — that blindness hid two defects on
    /// 2026-07-25. Triggered by: `-snapshot-unrated <path>`.
    @MainActor private static func renderUnrated(to path: String) {
        guard let container = try? ModelContainer(
            for: PipelineFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        else { return }
        let ctx = container.mainContext

        // Same words, same ambient context, same day — so ANY visible difference is the
        // projection's doing and not the fixture's.
        // Tuur's own note, verbatim — its first line is 90 chars, so the derived
        // title is CUT, which is the state the hard `prefix(80)` used to mangle.
        let body = "Yo claude. I got a problem. Well first off, once I click the record button, it says starting.\n"
            + "Check what the overhead is and why it takes a while. It happened twice, so not a fluke."
        let when = Date()
        // `duration` as a NUMBER — the shape `MemoCloudIngest` writes for every synced
        // note, and the one the reader used to ignore (no chip, no player).
        let meta = try? JSONSerialization.data(withJSONObject: [
            "location": ["placeName": "Cais do Sodré"],
            "weather": ["temperature": 21.0],
            "dayPeriod": DayPeriod.evening.rawValue,
            "duration": 96.0,
        ] as [String: Any])

        // LEFT — an ordinary pipeline row, untitled (so the header shows the greyed
        // derived title, which is exactly the state Tuur described).
        let pipelined = PipelineFile(id: "unrated-cmp", filename: "memo_compare.m4a",
                                     sourceType: .audio, uploadedAt: when)
        pipelined.transcript = body
        pipelined.tags = ["export", "obsidian"]
        pipelined.significance = 0.6
        pipelined.transcribeStatus = .done
        pipelined.audioMetadataJSON = meta
        // A real ingest would have written this; the fixture stands one in so BOTH
        // sides dock a player and the comparison stays fair.
        pipelined.path = projectedAudioStandIn()
        ctx.insert(pipelined)
        try? ctx.save()

        // RIGHT — the same note as an UNRATED memo, through the projection. Never
        // inserted anywhere: that is the point of it.
        let memo = Memo(id: UUID(), audioFilename: "memo_compare.m4a", duration: 96,
                        recordedAt: when, tags: ["export", "obsidian"],
                        transcript: body, transcriptStatus: .done,
                        significance: 0, metadataData: meta)
        let projected = MemoNoteProjection.file(for: memo)
        // Materialise from fake "synced blobs" so the render proves what the live pane
        // does: an unrated note docks a real player and shows its photos.
        MemoNoteProjection.discardMedia(for: memo.id)
        MemoNoteProjection.materialiseMedia(for: memo, into: projected) {
            [MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio,
                       filename: "memo_compare.m4a", blob: Data([0x00, 0x01]))]
        }

        func labelled(_ title: String, _ view: some View) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                view.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        let view = HStack(spacing: 1) {
            labelled("PIPELINED — the reference",
                     NoteDisplayView(file: pipelined, coordinator: ProcessingCoordinator(),
                                     onOpenMemo: { _ in }))
            labelled("UNRATED — projected",
                     // No `capabilities:` — the pane DERIVES `.unrated` from the
                     // projection itself now, so this render also proves the derivation.
                     NoteDisplayView(file: projected, coordinator: ProcessingCoordinator(),
                                     onOpenMemo: { _ in }))
        }
        .frame(width: 1320, height: 760)
        .background(Theme.hairline.opacity(0.25))
        .preferredColorScheme(.dark)
        .modelContainer(container)
        hostPNG(view, size: NSSize(width: 1320, height: 760), to: path)
    }

    /// A disposable in-memory `LiveRecordingSession` for `SidebarView` fixtures that don't
    /// exercise recording — every existing `-snapshot-*` render needs SOME session now that
    /// the sidebar's Record/stop wiring moved off the `MacRecorder` it used to own directly
    /// onto a session RootView hands it (LANES-2026-07-28/BRIEF_LIVEUI.md §7). Its `phase`
    /// stays `.idle` (the frozen skeleton's `start()`/`stop()` are no-ops until LIVE-ENGINE
    /// lands), so every one of these renders looks exactly as it did before this lane.
    @MainActor private static func fixtureSession(coordinator: ProcessingCoordinator) -> LiveRecordingSession {
        let container = try! ModelContainer(
            for: PipelineFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return LiveRecordingSession(coordinator: coordinator, context: container.mainContext)
    }

    /// The m1/m2/m4 recording draft surface (`RecordingDraftBody` — a pure value view, no
    /// `LiveRecordingSession` needed) in its live and settling states: fixture-driven, since
    /// the frozen `LiveRecordingSession`'s `start()`/`stop()` are no-ops until LIVE-ENGINE
    /// fills them in — a real session can't be driven into `.live`/`.settling` yet. Same
    /// story (and text) as the mock's m2/m4 panes. Triggered by: `-snapshot-livedraft <path>`.
    @MainActor private static func renderLiveDraft(to path: String) {
        let settledSoFar = "Call with Jacques about the planter frames — he can weld the corners "
            + "next week if the steel arrives Tuesday. Budget stays under the two hundred we "
            + "said.\n\nHe also offered to look at the balcony rail. I said yes because it saves "
            + "a second trip, and honestly his welds are"

        func pane(_ title: String, _ view: some View) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                view.frame(width: 900, height: 420)
            }
        }
        let view = VStack(spacing: 1) {
            pane("LIVE — settled + wet tail (no pane transport — the sidebar is the transport)", RecordingDraftBody(
                phase: .live, settledText: .constant(settledSoFar),
                wetText: "nicer than what the shop quoted ",
                everEdited: true, elapsedLabel: "1:04"))
            pane("SETTLING — title real, softer wet band (m4, trimmed)", RecordingDraftBody(
                phase: .settling, settledText: .constant(settledSoFar),
                wetText: "nicer than what the shop quoted — worth keeping him close for the autumn list.",
                everEdited: true, elapsedLabel: "1:12"))
        }
        .frame(width: 920, height: 900)
        .background(Theme.hairline.opacity(0.25))
        .preferredColorScheme(.dark)
        hostPNG(view, size: NSSize(width: 920, height: 900), to: path)
    }

    /// A throwaway audio file for the comparison fixture — `showsTransport` wants a
    /// real path on disk, and the point of the render is that BOTH sides look alike.
    @MainActor private static func projectedAudioStandIn() -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-ref.m4a")
        try? Data([0x00, 0x01]).write(to: url)
        return url.path
    }

    /// Tag typeahead (design #1, 2026-07-16): the "+ add tag" field open with a draft,
    /// so the dropdown of matching library tags + the "Create #x" row renders. HOSTED
    /// (real AppKit TextField). Triggered by: `-snapshot-tags <path>`.
    @MainActor private static func renderTags(to path: String) {
        guard let container = try? ModelContainer(
            for: PipelineFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        else { return }
        let ctx = container.mainContext
        // A small library of tagged notes so the typeahead has real matches.
        let libraries: [[String]] = [
            ["work", "ideas", "rewrite"], ["work", "testflight"], ["testing", "device"],
            ["testing", "bugfix"], ["ideas", "product"], ["work", "meeting"], ["reading", "books"],
        ]
        for (i, tags) in libraries.enumerated() {
            let f = PipelineFile(id: "tagseed-\(i)", filename: "n\(i).m4a", sourceType: .audio, uploadedAt: Date())
            f.tags = tags
            ctx.insert(f)
        }
        let subject = PipelineFile(id: "tag-subject", filename: "Subject.m4a", sourceType: .audio, uploadedAt: Date())
        subject.tags = ["testy", "more tags"]
        subject.tagSuggestions = ["rewrite", "swift"]
        ctx.insert(subject)
        try? ctx.save()

        let view = VStack(alignment: .leading, spacing: 8) {
            Text("Tags — typing “te”").font(.system(size: 10)).tracking(0.6).foregroundStyle(Theme.textMuted)
            TagEditorRow(tags: Binding(get: { subject.tags }, set: { subject.tags = $0 }),
                         library: TagLibrary.mostUsedFirst(ctx), style: .mac,
                         seedAdding: true, seedDraft: "te")
            Text("Body — inline “#te” menu").font(.system(size: 10)).tracking(0.6).foregroundStyle(Theme.textMuted)
                .padding(.top, 10)
            TagSuggestList(matches: ["testing", "testflight", "testy"], selected: 0, onPick: { _ in })
        }
        .frame(width: 380, alignment: .leading)
        .padding(28)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .modelContainer(container)
        hostPNG(view, size: NSSize(width: 436, height: 470), to: path)
    }

    /// Image-at-sentence-end reflow (2026-07-16): a photo marker that the injector
    /// dropped MID-SENTENCE must render the sentence WHOLE, then the photo as its own
    /// full-width block beneath it (shared `BodyTransform.snapImages`). HOSTED render
    /// (real NSTextView) with a real on-disk image so the thumbnail actually decodes.
    /// Triggered by: `-snapshot-photoblock <path>`.
    @MainActor private static func renderPhotoBlock(to path: String) {
        guard let container = try? ModelContainer(
            for: PipelineFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        else { return }
        let ctx = container.mainContext

        // A working folder with a stand-in photo + manifest, so `imageURL` resolves.
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("snap-photoblock")
        try? FileManager.default.removeItem(at: work)
        let imagesDir = work.appendingPathComponent("images")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        writeSamplePhoto(to: imagesDir.appendingPathComponent("photo_001.jpg"))
        let manifest: [[String: Any]] = [["filename": "photo_001.jpg", "offsetSeconds": 4.0]]
        try? JSONSerialization.data(withJSONObject: manifest).write(to: work.appendingPathComponent("image_manifest.json"))
        let audio = work.appendingPathComponent("original.m4a")
        try? Data([0]).write(to: audio)

        let f = PipelineFile(id: "photoblock-1", filename: "Morning coffee.m4a", path: audio.path, size: 1, sourceType: .audio)
        f.transcribeStatus = .done; f.sanitiseStatus = .done; f.enhanceStatus = .done
        f.enhancedTitle = "Morning coffee by the river"
        f.titleSuggested = f.enhancedTitle
        f.enhancedSummary = "A quick flat white at the new place, then a walk back along the water."
        // The marker lands MID-SENTENCE (the injector places it at the nearest word);
        // the reflow must show the sentence whole, then the photo block beneath it.
        f.sanitised = "# Morning coffee\n\nI grabbed a coffee at the new place on the corner\n\n[[img_001]]\n\n and it was honestly the best flat white I have had in months.\n\n## The walk back\n\nThen I walked back along the river and the light was perfect. Filing this under #coffee for the archive."
        f.enhancedCopyedit = f.sanitised
        f.significance = 0.5
        f.audioMetadataJSON = try? JSONSerialization.data(withJSONObject: ["duration": "00:01:40"])
        ctx.insert(f)
        try? ctx.save()

        let view = NoteDisplayView(file: f, coordinator: ProcessingCoordinator(), onOpenMemo: { _ in })
            .frame(width: 820, height: 1150)
            .background(Theme.bg)
            .preferredColorScheme(.dark)
            .modelContainer(container)
        hostPNG(view, size: NSSize(width: 820, height: 1150), to: path)
    }

    /// Drive the REAL `MacRecorder` for 3 seconds and report (`-recordcheck`). This is the
    /// path the Record button takes, so it answers "does the engine work" separately from
    /// "does the button reach it". Unlike `-miccheck` this WILL prompt for the mic the first
    /// time; run it with a timeout.
    @MainActor private static func checkRecord() {
        // REFUSE to run before the app has been granted the mic in the GUI. Learned the hard
        // way 2026-07-28: a CLI-launched binary can't present a TCC prompt, so calling
        // `requestAccess` here doesn't ask — it records a DENIAL for the bundle, and from then
        // on the real app fails without ever prompting. Costing the user a trip to System
        // Settings is not a diagnostic's job.
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            print("REFUSING: mic is \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) "
                  + "(not authorized). Press Record in the GUI once to grant it — asking from a "
                  + "CLI run would record a denial instead of prompting.")
            exit(2)
        }
        let rec = MacRecorder()
        Task { @MainActor in
            print("state before: \(rec.state)")
            let ok = await rec.start()
            print("start() → \(ok), state: \(rec.state)")
            guard ok else { exit(1) }
            try? await Task.sleep(for: .seconds(3))
            print("elapsed: \(rec.elapsedLabel), meter: \(rec.meter.bars.map { String(format: "%.2f", $0) }.joined(separator: " "))")
            if let url = rec.stop() {
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                let dur = try? await AVURLAsset(url: url).load(.duration)
                print("WROTE \(url.lastPathComponent) — \(size ?? 0) bytes, \(dur.map { String(format: "%.1fs", $0.seconds) } ?? "?")")
                try? FileManager.default.removeItem(at: url)
            } else {
                print("stop() → nil (nothing captured)")
            }
            exit(0)
        }
        // Keep the process alive for the async work above.
        RunLoop.main.run()
    }

    /// Why the mic isn't recording (`-miccheck`). Deliberately does NOT request access — a TCC
    /// prompt from a CLI-launched binary is how you get a silent stall — it only reports what
    /// the system already thinks, plus whether there is an input device and what format it
    /// offers. A 0 Hz format is the classic "no input selected" tell.
    @MainActor private static func checkMic() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let name: String
        switch status {
        case .authorized: name = "authorized"
        case .denied: name = "DENIED — System Settings ▸ Privacy & Security ▸ Microphone"
        case .restricted: name = "restricted"
        case .notDetermined: name = "notDetermined (never prompted)"
        @unknown default: name = "unknown(\(status.rawValue))"
        }
        print("mic authorization: \(name)")
        print("usage string present: "
              + (Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil ? "yes" : "NO — TCC will kill the process"))
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
        print("input devices: \(devices.isEmpty ? "NONE" : devices.map(\.localizedName).joined(separator: ", "))")
        let engine = AVAudioEngine()
        let f = engine.inputNode.inputFormat(forBus: 0)
        print("inputNode format: \(f.sampleRate) Hz, \(f.channelCount) ch"
              + (f.sampleRate > 0 ? "" : "  ← 0 Hz = no usable input"))
        print("recordings dir: \(AppPaths.recordingsDirectory.path)")
    }

    /// The turn gutter over a REAL note body read from a file, against the LIVE names roster —
    /// the fixture in `renderTurns` can only prove what it was written to prove. Paused above,
    /// mid-playback below. Triggered by:
    /// `-snapshot-turns-body <png> -turnsBody <txt> [-light]`.
    @MainActor private static func renderTurnsBody(to path: String, bodyFile: String, scheme: ColorScheme) {
        guard let body = try? String(contentsOfFile: bodyFile, encoding: .utf8) else {
            print("no body at \(bodyFile)"); return
        }
        func pane(_ title: String, karaoke: Double?) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentText).textCase(.uppercase).kerning(1.1)
                // people: [] → BodyTextView reads the LIVE names DB, the real resolution path.
                BodyTextView(text: .constant(body),
                             karaoke: karaoke.map { BodyTextView.KaraokePlayback(fraction: $0, seekWord: { _ in }) })
                    .frame(width: 820)
            }
            .padding(.horizontal, 26).padding(.vertical, 18)
            .frame(width: 880, alignment: .leading)
            .background(Theme.surface)
        }
        let view = VStack(alignment: .leading, spacing: 14) {
            pane("real note · paused", karaoke: nil)
            pane("real note · playing", karaoke: 0.30)
        }
        .padding(20).background(Theme.bg).preferredColorScheme(scheme)
        hostPNG(view, size: NSSize(width: 920, height: 2600), to: path)
    }

    /// The two things a screenshot of the turn gutter CANNOT prove, checked end-to-end on a
    /// real `BodyTextView` (`-turncheck`, prints PASS/FAIL per case):
    ///  1. the MODEL round-trips — a gutter glyph must reconstruct its `**Name:**` literal
    ///     exactly, or opening a conversation and typing one character rewrites the note;
    ///  2. click-to-seek still lands on the word you clicked — a gutter glyph stands in for a
    ///     literal that can be SEVERAL model words (`**[[Tiuri Hartog]]:**` is two), and the
    ///     word-times are keyed by model word, so every displayed word must translate back to
    ///     the model word with the same text.
    @MainActor private static func checkTurns() {
        func p(_ c: String, _ a: [String], short: String? = nil) -> Person {
            Person(canonical: "[[\(c)]]", aliases: a, short: short, lastModifiedAt: "2026-07-27T00:00:00Z")
        }
        let people = [p("Tiuri Hartog", ["Tiuri Hartog", "Tiuri", "Tuur"], short: "Tiuri"),
                      p("Bulldops", ["Bulldops"])]
        let cases: [(String, String)] = [
            ("conversation", """
             **[[Tiuri Hartog]]:** They get

             **[[Bulldops]]:** together in Droof, that's sort of cellar punk theme.

             **Tiuri:** Droof is a place in Waageningen in the Netherlands.

             **Bulldops:** Yes, where it's where I live.
             """),
            ("with a preamble + photo", """
             A note before anyone speaks.

             [[img_001]]

             **[[Tiuri Hartog]]:** One.

             **Bulldops:** Two.
             """),
            ("not a conversation", "**Note:** one bold lead-in.\n\nOrdinary prose follows."),
            ("tabs + extra spaces", "**Tiuri:**   spaced out\n\n**Bulldops:**\ttabbed"),
        ]
        var failed = false
        for (name, text) in cases {
            let view = BodyTextView(text: .constant(text), people: people)
            let coordinator = view.makeCoordinator()
            let tv = SelfSizingTextView()
            coordinator.render(tv, model: text)
            let round = coordinator.modelString(tv)
            let want = BodyV2Legacy.shown(text).text
            let roundOK = round == want
            // Every DISPLAYED word must translate back to the model word with the same text —
            // that is exactly what a click-to-seek does before it looks up a time.
            let ns = tv.string as NSString
            let words = BodyTextView.Coordinator.wordRanges(tv.string)
            let modelWords = want.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            var mismatch: String?
            for (i, r) in words.enumerated() {
                let shown = ns.substring(with: r)
                if shown.contains("\u{FFFC}") { continue }   // an attachment has no model twin
                let mi = coordinator.modelWordIndex(i, in: tv.textStorage!, words: words)
                guard mi < modelWords.count, modelWords[mi] == shown else {
                    mismatch = "displayed word \(i) \(shown.debugDescription) → model \(mi) "
                             + (mi < modelWords.count ? modelWords[mi].debugDescription : "OUT OF RANGE")
                    break
                }
            }
            let seekOK = mismatch == nil
            if !roundOK || !seekOK { failed = true }
            print("\(roundOK && seekOK ? "PASS" : "FAIL") — \(name): "
                  + "round-trip \(roundOK ? "exact" : "BROKEN"), "
                  + "seek \(seekOK ? "aligned (\(words.count) shown / \(modelWords.count) model)" : "SKEWED")")
            if !roundOK { print("   want: \(want.debugDescription)\n   got:  \(round.debugDescription)") }
            if let m = mismatch { print("   \(m)") }
        }
        print(failed ? "TURNCHECK FAILED" : "TURNCHECK PASSED")
    }

    /// The conversation turn gutter (signed mock `mocks/conversation-turns-D-hifi.html`, E1)
    /// at the real 820pt note measure: paused, then playing (variant b — the accent wash
    /// behind the live turn), then the two cases that must NOT change — a name too long for
    /// the gutter, and an ordinary note whose lone bold lead-in stays inline.
    /// Triggered by: `-snapshot-turns <path>` / `-snapshot-turns-light <path>`.
    @MainActor private static func renderTurns(to path: String, scheme: ColorScheme = .dark) {
        func p(_ canonical: String, _ aliases: [String], short: String? = nil) -> Person {
            Person(canonical: "[[\(canonical)]]", aliases: aliases, short: short,
                   lastModifiedAt: "2026-07-27T00:00:00Z")
        }
        // Injected roster → deterministic: the rule must see that `[[Tiuri Hartog]]` and the
        // later `Tiuri` are ONE speaker, which is what keeps them one colour.
        let people = [p("Tiuri Hartog", ["Tiuri Hartog", "Tiuri", "Tuur"], short: "Tiuri"),
                      p("Bulldops", ["Bulldops"]),
                      p("Bartholomew Fitzgerald-Smythe", ["Bartholomew Fitzgerald-Smythe"])]
        let convo = """
        **[[Tiuri Hartog]]:** They get

        **[[Bulldops]]:** together in Droof, that's sort of cellar punk theme. Okay. Maybe have art and food and you know, I don't know, whatever people are inspired by.

        **Tiuri:** Droof is a place in Waageningen in the Netherlands.

        **Bulldops:** Yes, where it's where I live. A little community. And then I was thinking of also of learning to DJ with Celtic music, because everyone's doing electronic always, especially techno.

        **Tiuri:** So you went to this festival, you saw Celtic music? And then you want to spread it to Wacheningen.

        **Bulldops:** Yeah, like I can DJ on that on that jam.
        """
        let longName = """
        **[[Bartholomew Fitzgerald-Smythe]]:** A name wider than the gutter has to give somewhere — it truncates rather than wrapping, because a turn is one line tall.

        **[[Bulldops]]:** Right, and the spine still ties the wrapped lines back to whoever said them.
        """
        let plain = """
        **Note:** one bold lead-in is not a conversation, so it keeps today's inline styling and never gains a gutter.

        The rest of the note reads at the full measure, exactly as before.
        """
        func pane(_ title: String, _ text: String, karaoke: Double? = nil) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentText).textCase(.uppercase).kerning(1.1)
                BodyTextView(text: .constant(text), people: people,
                             karaoke: karaoke.map { BodyTextView.KaraokePlayback(fraction: $0, seekWord: { _ in }) })
                    .frame(width: 820)
            }
            .padding(.horizontal, 26).padding(.vertical, 18)
            .frame(width: 880, alignment: .leading)
            .background(Theme.surface)
        }
        let view = VStack(alignment: .leading, spacing: 14) {
            pane("E1 · paused", convo)
            pane("E1 · b — playing, wash behind the live turn", convo, karaoke: 0.34)
            pane("long name · truncates in the gutter", longName)
            pane("not a conversation · unchanged", plain)
        }
        .padding(20)
        .background(Theme.bg)
        .preferredColorScheme(scheme)
        hostPNG(view, size: NSSize(width: 920, height: 1500), to: path)
    }

    /// A red-toned stand-in "photo" (the real red-cup note is on-device) — enough to
    /// eyeball the block layout + rounded corners.
    @MainActor private static func writeSamplePhoto(to url: URL, size: NSSize = NSSize(width: 1000, height: 640)) {
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(calibratedRed: 0.80, green: 0.20, blue: 0.17, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(calibratedRed: 0.96, green: 0.60, blue: 0.38, alpha: 1).setFill()
        NSRect(x: 0, y: size.height * 0.60, width: size.width, height: size.height * 0.12).fill()
        img.unlockFocus()
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let jpg = rep.representation(using: .jpeg, properties: [:]) {
            try? jpg.write(to: url)
        }
    }

    /// The Mac Journal (signed mock journal-desktop.html v2) over an injected demo
    /// corpus — Looking-back cards, dot-density calendar, places, slim in-flight row.
    /// Triggered by: `-snapshot-journal <path>`.
    @MainActor private static func renderJournal(to path: String) {
        let cal = Calendar.current
        let now = Date()
        func ago(days: Int = 0, months: Int = 0, years: Int = 0, hour: Int = 10) -> Date {
            var d = cal.date(byAdding: .day, value: -days, to: now)!
            d = cal.date(byAdding: .month, value: -months, to: d)!
            d = cal.date(byAdding: .year, value: -years, to: d)!
            return cal.date(bySettingHour: hour, minute: 12, second: 0, of: d) ?? d
        }
        func memo(_ title: String, _ transcript: String, at date: Date, sig: Double = 0,
                  place: String? = nil, lat: Double = 38.71, lon: Double = -9.14,
                  status: TranscriptStatus = .done, locked: Bool = false,
                  duration: Double = 161) -> Memo {
            let m = Memo(audioFilename: "memo_\(UUID().uuidString).m4a", duration: duration,
                         recordedAt: date, title: title, transcript: transcript,
                         transcriptStatus: status, transcriptConfidence: 0.9, significance: sig)
            if let place {
                m.metadata = MemoMetadata(location: LocationInfo(latitude: lat, longitude: lon, placeName: place))
            }
            m.locked = locked
            return m
        }
        let memos: [Memo] = [
            memo("Walking the Monsanto loop, product doubts",
                 "Kept circling on whether the per-book capture pages are the wedge… the transcription is finally boring — which is the point.",
                 at: ago(years: 1, hour: 9), sig: 0.7, place: "Monsanto trail", lat: 38.73, lon: -9.20),
            memo("Late-night audiobook capture flow",
                 "The quote + ramble pairing works. The reading mode should feel like an e-reader, not a player.",
                 at: ago(months: 1, hour: 22), sig: 0.5, place: "Alfama, Lisbon"),
            memo("Names model, re-derived",
                 "Opt-out beats opt-in for a personal corpus — risk-tiering carries the rest.",
                 at: ago(months: 3, hour: 14), sig: 0.8, place: "Good Friday HQ", lat: 38.72, lon: -9.15),
            memo("Two apps, one contract",
                 "The shared folder finally carries every wire struct. Next: the Mac honours the lock flag on export.",
                 at: ago(hour: 8), sig: 0.8, place: "Good Friday HQ", lat: 38.72, lon: -9.15),
            memo("Fado bar recommendation",
                 "Shared from Maps with a voice ramble — the Tuesday sets are the ones.",
                 at: ago(hour: 13), sig: 0.3, place: "Alfama, Lisbon"),
            memo("", "", at: ago(hour: 17), status: .transcribing),   // in-flight → slim row
            memo("Private thoughts", "should never show", at: ago(days: 1, hour: 21), sig: 0.4, locked: true),
            memo("Café notes on the reading mode", "Margins, serif toggle, tap zones.",
                 at: ago(days: 4, hour: 11), sig: 0.4, place: "Café Janis"),
        ]
        let model = AppModel()
        model.surface = .journal
        let view = JournalView(model: model, coordinator: ProcessingCoordinator(),
                               injectedMemos: memos)
            .frame(width: 1180, height: 940)
            .background(Theme.bg)
            .preferredColorScheme(.dark)
        hostPNG(view, size: NSSize(width: 1180, height: 940), to: path)

        // Second state: map mode (Places clicked) → <path>-map.png.
        let mapModel = AppModel()
        mapModel.surface = .journal
        let mapView = JournalView(model: mapModel, coordinator: ProcessingCoordinator(),
                                  injectedMemos: memos, debugStartInMap: true)
            .frame(width: 1180, height: 940)
            .background(Theme.bg)
            .preferredColorScheme(.dark)
        hostPNG(mapView, size: NSSize(width: 1180, height: 940),
                to: (path as NSString).deletingPathExtension + "-map.png")
    }

    /// Offscreen HOSTED render (real AppKit — NSHostingView + cacheDisplay): the tool
    /// for surfaces ImageRenderer can't draw (NSTextView bodies, MapKit views). Runs
    /// the main runloop briefly so .task loads land before capture.
    /// The importance card in every state it has, both schemes, HOSTED — the
    /// regression fixture for the 2026-08-12 un-twinning (one shared
    /// `SignificanceCirclesView`, two style tables). Rendered before and after the
    /// refactor and compared pixel-for-pixel: the whole claim is that it changes
    /// nothing. Triggered by: `-snapshot-significance <path>`.
    @MainActor private static func renderSignificance(to path: String, scheme: ColorScheme = .dark) {
        // Theme tokens are NSColor providers — they read the APPEARANCE, not
        // SwiftUI's colorScheme, and `hostPNG` draws into a real window. Pin the
        // app appearance so the light pass is actually light (the same trap
        // `writePNG` documents). `NSApplication.shared`, not `NSApp`: the global
        // is still nil this early and reading it traps.
        NSApplication.shared.appearance =
            NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let size = NSSize(width: 340, height: 700)
        // Every branch the view has: unrated, below the wall, on the wall, full,
        // and the Mac-only disabled state.
        let view = VStack(alignment: .leading, spacing: 14) {
            SignificanceCircles(value: .constant(nil))
            SignificanceCircles(value: .constant(0.5))
            SignificanceCircles(value: .constant(0.8))
            SignificanceCircles(value: .constant(1.0))
            SignificanceCircles(value: .constant(0.3), enabled: false)
        }
        .padding(16)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Theme.bg)
        .environment(\.colorScheme, scheme)
        hostPNG(view, size: size, to: path)
    }

    @MainActor private static func hostPNG<V: View>(_ view: V, size: NSSize, to path: String) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
    }

    @MainActor private static func renderReview(to path: String, scheme: ColorScheme = .dark) {
        let files = DemoSeed.snapshotFiles()
        let model = AppModel()
        model.activeID = files.first?.id
        if let id = files.first?.id { model.selection = [id] }
        let coordinator = ProcessingCoordinator()

        let view = HStack(spacing: 0) {
            SidebarView(model: model, files: files, coordinator: coordinator, session: fixtureSession(coordinator: coordinator), scrollable: false).frame(width: 228)
            NoteDisplayView(file: files.first, coordinator: coordinator, scrollable: false).frame(maxWidth: .infinity)
        }
        .frame(width: 1180, height: 780)
        .background(Theme.bg)
        writePNG(view, to: path, scheme: scheme)
    }

    /// The four-destination row in BOTH of its states, at the Mac's real note width —
    /// `-snapshot-destinations <path> [-noteWidth n]`. It exists because the Mac's note
    /// column is far wider than the phone's, and four segments that simply fill the width
    /// is the failure this catches: the mock's proportions do not survive a 1400pt column.
    @MainActor private static func renderDestinations(to path: String, width: CGFloat) {
        let view = VStack(alignment: .leading, spacing: 26) {
            ForEach(NoteDestination.allCases, id: \.self) { d in
                DestinationRowView(destination: .constant(d),
                                   folderLabel: { $0.archiveFolder.map { "\($0)/" } },
                                   onPick: { _ in },
                                   style: .mac)
            }
            Divider().opacity(0.2)
            Text("EXPANDED").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textMuted)
            DestinationRowView(destination: .constant(.idea),
                               folderLabel: { $0.archiveFolder.map { "\($0)/" } },
                               onPick: { _ in },
                               style: .mac,
                               startExpanded: true)
        }
        .padding(28)
        .frame(width: width, alignment: .leading)
        .background(Theme.bg)
        writePNG(view, to: path, scheme: .dark)
    }

    @MainActor private static func renderSettings(to path: String, scheme: ColorScheme = .dark) {
        let view = SettingsView(interactive: false)   // sizes to full content (no 660 cap)
            .background(Theme.bg)
        writePNG(view, to: path, scheme: scheme)
    }

    /// Settings through the HOSTED path (real AppKit), because the plain ImageRenderer
    /// draws its Pickers/Menus/TextFields as yellow placeholders — which is exactly how
    /// a ⋯ chip that never drew slipped through on 2026-07-25. Use this whenever the
    /// thing you changed in Settings IS a system control.
    /// `-snapshot-settings-hosted <path>` · `-settingsWidth <n>`.
    @MainActor private static func renderSettingsHosted(to path: String, width: CGFloat) {
        // `interactive: false` only drops the 660 height CAP (it does not swap controls
        // for text), so the whole panel lays out AND its real AppKit controls draw.
        let view = SettingsView(interactive: false)
            .frame(width: width, height: 2600, alignment: .top)
            .background(Theme.bg)
            .preferredColorScheme(.dark)
        hostPNG(view, size: NSSize(width: width, height: 2600), to: path)
    }

    @MainActor private static func renderRun(to path: String) {
        let files = DemoSeed.snapshotFiles()
        let model = AppModel()
        model.activeID = files.first?.id
        let coordinator = ProcessingCoordinator.preview(
            .init(total: 5, done: 2, currentTitle: "Standup notes",
                  loadingLabel: "enhancement model", loadingFraction: 0.45))
        let view = HStack(spacing: 0) {
            SidebarView(model: model, files: files, coordinator: coordinator, session: fixtureSession(coordinator: coordinator), scrollable: false).frame(width: 228)
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
        // The contract url fixture is "demo-capture-url"; `-snapshot-capture pdf:<path>`
        // renders the PDF file-capture card instead (A3).
        var wanted = "demo-capture-url", out = path
        if path.hasPrefix("pdf:") { wanted = "demo-capture-pdf"; out = String(path.dropFirst(4)) }
        let path = out
        let captureFile = files.first { $0.id == wanted } ?? files.first
        let model = AppModel()
        model.activeID = captureFile?.id
        if let id = captureFile?.id { model.selection = [id] }
        let coordinator = ProcessingCoordinator()

        // HOSTED render (real AppKit): the sidebar's drop-catcher makes ImageRenderer
        // paint the yellow 🚫 placeholder over the whole left pane — hostPNG doesn't.
        let view = HStack(spacing: 0) {
            SidebarView(model: model, files: files, coordinator: coordinator, session: fixtureSession(coordinator: coordinator), scrollable: false).frame(width: 228)
            NoteDisplayView(file: captureFile, coordinator: coordinator, scrollable: false).frame(maxWidth: .infinity)
        }
        .frame(width: 1180, height: 780)
        .background(Theme.bg)
        .preferredColorScheme(scheme)
        hostPNG(view, size: NSSize(width: 1180, height: 780), to: path)
    }

    /// The "On its way out" conveyor (mocks/lifecycle-ia-explorations.html #m3) —
    /// fixture rows in all three sections (fading / deleted / mac-only), a pure-
    /// view fixture injection (like `ConnectionsPanelBody`'s — no engine, no
    /// ModelContext, mock-story rows). The day offsets below reproduce the
    /// mock's own worked example verbatim (3d/22d fading, ~1d/~8d deleted) as a
    /// cheap cross-check that the arithmetic lines up. NOTE: the sidebar band
    /// has no fixture here — the sidebar can't snapshot (known repo
    /// limitation) — the conductor eyeballs it live. Triggered by:
    /// `-snapshot-trash <path>`.
    @MainActor private static func renderTrash(to path: String, scheme: ColorScheme = .dark) {
        func daysAgo(_ n: Int) -> Date { Date(timeIntervalSinceNow: -Double(n) * 86_400) }
        let fading = [
            Memo(audioFilename: "memo_1.m4a", duration: 4, recordedAt: daysAgo(57),
                 transcript: "Okay. Yeah. No. Right. Test two.", transcriptStatus: .done),
            Memo(audioFilename: "memo_2.m4a", duration: 6, recordedAt: daysAgo(38),
                 transcript: "That um it it started at oh what the fuck…", transcriptStatus: .done),
        ]
        let deleted = [
            Memo(audioFilename: "memo_3.m4a", duration: 34, recordedAt: daysAgo(90),
                 transcript: "Shopping list — garden centre", transcriptStatus: .done, deletedAt: daysAgo(13)),
            Memo(audioFilename: "memo_4.m4a", duration: 63, recordedAt: daysAgo(100),
                 transcript: "Voice note", transcriptStatus: .done, deletedAt: daysAgo(6)),
        ]
        // Sighted at deletion (v3) so the snapshot shows mid-run countdowns,
        // not two fresh full-window rows.
        deleted.forEach { $0.trashSeenAt = $0.deletedAt }
        let macOnly = PipelineFile(id: "legacy-bonjour-1", filename: "Old Bonjour upload.m4a",
                                   sourceType: .audio, uploadedAt: daysAgo(120))
        macOnly.deletedAt = daysAgo(3)

        // hostPNG, not writePNG: the column scrolls, and ImageRenderer can't lay
        // out ScrollView contents (the header rendered over an empty body).
        let view = WayOutColumn(fading: fading, deleted: deleted, macOnlyFiles: [macOnly])
            .frame(width: 860, height: 680)
            .background(Theme.bg)
            .preferredColorScheme(scheme)
        hostPNG(view, size: NSSize(width: 860, height: 680), to: path)
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

    /// The -copyeditcheck harness: real model, real escrow, no store. Blocks the
    /// launch thread on a detached task (nothing in the path is MainActor-bound)
    /// and exits from inside it.
    nonisolated private static func checkCopyEdit(input: String, output: String,
                                                  promptFile: String? = nil) -> Never {
        guard let text = try? String(contentsOfFile: input, encoding: .utf8) else {
            print("copyeditcheck: cannot read \(input)"); exit(1)
        }
        func stats(_ s: String) -> String {
            let words = s.split(whereSeparator: \.isWhitespace).count
            let newlines = s.filter { $0 == "\n" }.count
            let paras = s.components(separatedBy: "\n\n").count
            return "\(s.count) chars · \(words) words · \(newlines) newlines · \(paras) paragraphs"
        }
        print("copyeditcheck: IN  \(stats(text))")
        print("copyeditcheck: budget \(PolishPrompts.copyEditTokenBudget(forInput: text)) tokens (est input \(PolishPrompts.estimatedTokens(text)))")
        Task.detached {
            do {
                let t0 = Date()
                var prompts = AppSettings.Prompts()
                if let promptFile, let override = try? String(contentsOfFile: promptFile, encoding: .utf8) {
                    prompts.copyEdit = override
                    print("copyeditcheck: prompt OVERRIDE from \(promptFile) (\(override.count) chars)")
                }
                let edited = try await EnhancementService.shared.copyEdit(
                    text, prompts: prompts, modelRepo: PolishPrompts.defaultModelRepo)
                let dt = Date().timeIntervalSince(t0)
                try edited.write(toFile: output, atomically: true, encoding: .utf8)
                print("copyeditcheck: OUT \(stats(edited)) · \(String(format: "%.1f", dt))s")
                print("copyeditcheck: identical-to-input = \(edited == text)")
                print("copyeditcheck: wrote \(output)")
                exit(0)
            } catch {
                print("copyeditcheck: FAILED — \(error)")
                exit(1)
            }
        }
        dispatchMain()
    }
}
#endif
