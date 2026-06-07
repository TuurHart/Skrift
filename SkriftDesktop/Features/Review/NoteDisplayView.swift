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

    var body: some View {
        Group {
            if let file {
                content(file)
                    .task(id: file.id) { audio.load(path: file.path) }
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

    /// The centered reading column: resolver → properties → summary → body.
    private func column(_ file: PipelineFile) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if let amb = file.ambiguousNames, !amb.isEmpty {
                ResolverStrip(occurrences: amb) { decisions in
                    coordinator.applyResolvedNames(file, decisions: decisions, context: ctx)
                }
            }
            NoteProperties(file: file, author: author, interactive: scrollable)
            if let summary = file.enhancedSummary, !summary.isEmpty {
                summaryAside(summary)
            }
            NoteBody(file: file, audio: audio, interactive: scrollable, onAddName: addName)
        }
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

    /// Audio transport only for transcribed audio/capture with a duration (not Apple notes).
    private func showsTransport(_ file: PipelineFile) -> Bool {
        file.sourceType != .note && file.durationSeconds > 0
    }
}
