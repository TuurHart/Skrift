import SwiftUI

/// The review surface (right pane): breadcrumb → pinned toolbar bar (transport +
/// actions) → scrollable note content. The properties block, resolver, and the
/// rich body/karaoke land in chunks 3–4; for now the scroll area shows the summary
/// and body text so the toolbar reads in context.
struct NoteDisplayView: View {
    let file: PipelineFile?
    var coordinator: ProcessingCoordinator
    /// Snapshot mode renders the body without a ScrollView (ImageRenderer can't lay
    /// out scroll contents). The live app keeps `true` for real scrolling.
    var scrollable = true
    @Environment(\.modelContext) private var ctx
    @State private var audio = AudioController()
    @State private var author = SettingsStore.shared.load().authorName
    /// Inline name-disambiguation state (R3). Created when the active note has
    /// ambiguous names; preserved across re-renders (holds in-progress choices);
    /// cleared on note switch or once resolution is applied.
    @State private var resolver: InlineResolverModel?

    var body: some View {
        Group {
            if let file {
                content(file)
                    .task(id: file.id) { audio.load(path: file.path) }
                    .onChange(of: file.id, initial: true) { _, _ in syncResolver(file) }
                    .onChange(of: file.ambiguousNames?.count ?? 0, initial: true) { _, _ in syncResolver(file) }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    @ViewBuilder private func content(_ file: PipelineFile) -> some View {
        VStack(spacing: 0) {
            breadcrumb(file)
            toolbarBar(file)
            GeometryReader { geo in
                let colW = min(820, max(320, geo.size.width - 72))
                let body = column(file)
                    .frame(width: colW, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
                if scrollable {
                    ScrollView { body }
                } else {
                    body
                }
            }
        }
    }

    /// The centered reading column: resolver banner → properties → summary → body.
    /// Inline name disambiguation (R3) happens in the body itself; the banner is just
    /// progress + Apply.
    private func column(_ file: PipelineFile) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if let resolver, scrollable {
                InlineResolverBanner(model: resolver) { applyInline(file, resolver) }
            }
            NoteProperties(file: file, author: author, interactive: scrollable)
            if let summary = file.enhancedSummary, !summary.isEmpty {
                summaryAside(summary)
            }
            NoteBody(file: file, audio: audio, interactive: scrollable, onAddName: addName, resolver: scrollable ? resolver : nil)
        }
    }

    /// (Re)create the inline resolver model for the active note. Same model is kept
    /// while the same note still has ambiguous names (so in-progress choices survive
    /// re-renders); recreated on note switch; cleared once names are resolved.
    private func syncResolver(_ file: PipelineFile) {
        let amb = file.ambiguousNames ?? []
        if amb.isEmpty {
            if resolver != nil { resolver = nil }
        } else if resolver?.fileID != file.id {
            resolver = InlineResolverModel(fileID: file.id, ambiguous: amb)
        }
    }

    /// Apply all inline choices at once. Re-enumerate the body's ambiguous mentions in
    /// order and feed the existing order-based apply (offset = ordinal → per-occurrence
    /// path, so two friends named "Jack" resolve independently).
    private func applyInline(_ file: PipelineFile, _ model: InlineResolverModel) {
        let body = file.bestBodyText
        var out: [ResolverDecision] = []
        for aliasLower in model.candidatesByAlias.keys {
            let display = model.displayAlias[aliasLower] ?? aliasLower
            for (i, range) in Sanitiser.plainOccurrences(of: aliasLower, in: body).enumerated() {
                let choice = model.decisions[range.location]
                out.append(ResolverDecision(alias: display, offset: i,
                                            canonical: choice?.candidate?.canonical,
                                            short: choice?.candidate?.short))
            }
        }
        coordinator.applyResolvedNames(file, decisions: out, context: ctx)
        resolver = nil
    }

    /// Add a body text selection to the names DB — the reliable, user-driven way to
    /// grow the names graph (you pick the exact words; no flaky auto-detection).
    private func addName(_ text: String) {
        let canon = NamesMerge.normaliseCanonical(text)
        let key = NamesMerge.keyName(canon)
        guard !key.isEmpty else { return }
        var people = NamesStore.shared.livePeople()
        if people.contains(where: { NamesMerge.keyName($0.canonical).localizedCaseInsensitiveCompare(key) == .orderedSame }) {
            coordinator.flash("“\(key)” is already in your names")
            return
        }
        people.append(Person(canonical: canon, aliases: [text], short: nil, lastModifiedAt: ISO8601.now()))
        _ = NamesStore.shared.writeWithSmartBumps(people)
        coordinator.flash("Added “\(key)” to names")
    }

    private func summaryAside(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13.5))
            .italic()
            .lineSpacing(3)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.accent.opacity(0.4)).frame(width: 2)
            }
    }

    private func breadcrumb(_ file: PipelineFile) -> some View {
        HStack(spacing: 6) {
            Text("Queue").foregroundStyle(Theme.textMuted)
            Text("›").foregroundStyle(Theme.textMuted)
            Text(SkriftFormat.breadcrumbDate(file.uploadedAt)).foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .font(.system(size: 12))
        .padding(.leading, 28)
        .frame(height: 48)
    }

    private func toolbarBar(_ file: PipelineFile) -> some View {
        HStack(spacing: 16) {
            if showsTransport(file) {
                NoteToolbar(audio: audio, durationSeconds: file.durationSeconds)
            } else {
                Spacer()
            }
            NoteActions(file: file, coordinator: coordinator)
        }
        .padding(.horizontal, 28)
        .frame(height: 48)
        .background(Theme.hairline.opacity(0.012))
        .overlay(alignment: .top) { hairline }
        .overlay(alignment: .bottom) { hairline }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textMuted.opacity(0.4))
            Text("Select a note to get started")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hairline: some View {
        Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5)
    }

    /// Audio transport for any non-note source with playable audio — a real file on
    /// disk (locally-ingested memos have no phone-metadata duration; the player reads
    /// the real one) OR a metadata duration (demo notes without a backing file).
    private func showsTransport(_ file: PipelineFile) -> Bool {
        guard file.sourceType != .note else { return false }
        if file.durationSeconds > 0 { return true }
        return !file.path.isEmpty && FileManager.default.fileExists(atPath: file.path)
    }
}
