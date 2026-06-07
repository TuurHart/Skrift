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
    /// The banner asks "Who is X?" per alias (auto-applies); the body marks the
    /// mentions and handles the per-occurrence "different people" case (R3).
    private func column(_ file: PipelineFile) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if let resolver, scrollable, !resolver.isEmpty {
                InlineResolverBanner(model: resolver)
            }
            NoteProperties(file: file, author: author, interactive: scrollable)
            if let summary = file.enhancedSummary, !summary.isEmpty {
                summaryAside(summary)
            }
            NoteBody(file: file, audio: audio, interactive: scrollable, onAddName: addName, onAddAlias: addAlias, resolver: scrollable ? resolver : nil)
        }
    }

    /// (Re)create the inline resolver model for the active note + wire its actions.
    /// Kept while the same note still has ambiguous names (in-progress choices survive
    /// re-renders); recreated on note switch; cleared once all names are resolved.
    private func syncResolver(_ file: PipelineFile) {
        let amb = file.ambiguousNames ?? []
        if amb.isEmpty {
            if resolver != nil { resolver = nil }
        } else if resolver?.fileID != file.id {
            let m = InlineResolverModel(fileID: file.id, ambiguous: amb)
            wireResolver(m, file)
            resolver = m
        }
    }

    private func wireResolver(_ m: InlineResolverModel, _ file: PipelineFile) {
        m.onResolveAlias = { [weak m] alias, choice in
            guard let m else { return }
            resolveAlias(file, m, alias: alias, choice: choice)
        }
        m.onEscalate = { [weak m] alias in m?.escalated.insert(alias.lowercased()); m?.styleVersion += 1 }
        m.onDeescalate = { [weak m] alias in
            let k = alias.lowercased(); m?.escalated.remove(k); m?.occDecisions[k] = nil; m?.styleVersion += 1
        }
        m.onDecideOccurrence = { [weak m] alias, loc, choice in
            guard let m else { return }
            m.occDecisions[alias.lowercased(), default: [:]][loc] = choice
            maybeApplyEscalated(file, m, alias: alias)
        }
    }

    /// "Who is X?" answered with one person (or plain) → apply to EVERY mention at
    /// once (first → `[[Canonical]]`, rest → the alias) and clear the alias.
    private func resolveAlias(_ file: PipelineFile, _ m: InlineResolverModel, alias: String, choice: ResolverChoice) {
        let body = file.bestBodyText
        let text: String
        switch choice {
        case let .person(c):
            text = Sanitiser.applyResolvedNames(text: body, decisions: [(alias: m.display(alias), canonical: c.canonical, short: c.short)])
        case .plain:
            text = body   // leave every mention plain
        }
        commitResolution(file, m, alias: alias, text: text)
    }

    /// Escalated ("different people"): once every mention of the alias has a choice,
    /// apply them per-occurrence (distinct people stay distinct) and clear the alias.
    private func maybeApplyEscalated(_ file: PipelineFile, _ m: InlineResolverModel, alias: String) {
        let body = file.bestBodyText
        let occ = Sanitiser.plainOccurrences(of: alias, in: body)
        guard !occ.isEmpty, occ.allSatisfy({ m.choice(alias: alias, location: $0.location) != nil }) else { return }
        let ordered: [(canonical: String?, short: String?)] = occ.map {
            if case let .person(c) = m.choice(alias: alias, location: $0.location) { return (c.canonical, c.short) }
            return (nil, nil)
        }
        let text = Sanitiser.applyResolvedOccurrences(text: body, byAlias: [m.display(alias): ordered])
        commitResolution(file, m, alias: alias, text: text)
    }

    /// Persist a resolved alias: update the body, trim it from `ambiguousNames`, drop
    /// it from the live model, recompile. When none remain, dismiss the resolver.
    private func commitResolution(_ file: PipelineFile, _ m: InlineResolverModel, alias: String, text: String) {
        file.sanitised = text
        let remaining = (file.ambiguousNames ?? []).filter { $0.alias.lowercased() != alias.lowercased() }
        file.ambiguousNames = remaining.isEmpty ? nil : remaining
        file.sanitiseStatus = .done
        file.compiledText = Compiler.compile(file: file, author: author)
        file.lastActivityAt = Date()
        try? ctx.save()
        m.removeAlias(alias)
        if m.isEmpty { resolver = nil }
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

    /// Add a body selection as an ALIAS of an existing person (right-click → "Add … as
    /// → alias of <person>"). Lets the names graph grow without inventing duplicates —
    /// e.g. mark "Tuur" as another alias of [[Tiuri Hartog]]. (Cross-person duplicate
    /// aliases are allowed on purpose — that's exactly the two-Jacks ambiguity.)
    private func addAlias(_ word: String, to canonical: String) {
        let alias = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else { return }
        var people = NamesStore.shared.livePeople()
        guard let i = people.firstIndex(where: { $0.canonical == canonical }) else {
            coordinator.flash("That name isn’t in your list anymore"); return
        }
        let name = NamesMerge.keyName(canonical)
        if people[i].aliases.contains(where: { $0.localizedCaseInsensitiveCompare(alias) == .orderedSame }) {
            coordinator.flash("“\(alias)” is already an alias of \(name)"); return
        }
        people[i].aliases.append(alias)
        people[i].lastModifiedAt = ISO8601.now()
        _ = NamesStore.shared.writeWithSmartBumps(people)
        coordinator.flash("Added “\(alias)” as an alias of \(name)")
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

    /// Context line — what you're looking at + when. (Was a "Queue ›" breadcrumb, but
    /// that implied navigation that doesn't exist; the note list is always in the
    /// sidebar, so this just names the source + date.)
    private func breadcrumb(_ file: PipelineFile) -> some View {
        HStack(spacing: 7) {
            Text(sourceLabel(file)).foregroundStyle(Theme.textSecondary)
            Text("·").foregroundStyle(Theme.textMuted)
            Text(SkriftFormat.breadcrumbDate(file.uploadedAt)).foregroundStyle(Theme.textMuted)
            Spacer()
        }
        .font(.system(size: 12))
        .padding(.leading, 28)
        .frame(height: 48)
    }

    private func sourceLabel(_ file: PipelineFile) -> String {
        switch file.sourceType {
        case .audio: return "Voice memo"
        case .note: return "Apple Note"
        case .capture: return "Capture"
        }
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
