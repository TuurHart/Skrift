#if DEBUG
import SwiftUI
import AppKit
import SwiftData

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
        if let p = path("-snapshot-memolinks")      { MainActor.assumeIsolated { renderMemoLinks(to: p); exit(0) } }
        if let p = path("-snapshot-photoblock")     { MainActor.assumeIsolated { renderPhotoBlock(to: p); exit(0) } }
        if let p = path("-snapshot-tags")           { MainActor.assumeIsolated { renderTags(to: p); exit(0) } }
        if let p = path("-snapshot-linkpicker")     { MainActor.assumeIsolated { renderLinkPicker(to: p); exit(0) } }
        if let p = path("-snapshot-connections")    { MainActor.assumeIsolated { renderConnections(to: p); exit(0) } }
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
            TagEditor(file: subject, seedAdding: true, seedDraft: "te")
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
            SidebarView(model: model, files: files, coordinator: coordinator, scrollable: false).frame(width: 228)
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
}
#endif
