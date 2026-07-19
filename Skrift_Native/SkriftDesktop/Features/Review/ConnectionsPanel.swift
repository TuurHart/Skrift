import SwiftUI
import SwiftData

// The Connections side-panel (mocks/related-panel.html, signed off 2026-07-16):
// ONE list of this note's semantic neighbourhood with a Date ⇄ Closest sort pill,
// why-chips + the owner-set importance decimal per row, LINKED FROM below (the
// old bottom strip moved in here), and the consent gate living in the panel.
// `ConnectionsPanelBody` is a pure function of its inputs so the snapshot harness
// can render every state without the engine.

// MARK: - Row data

struct ConnectionRow: Identifiable, Equatable {
    let id: UUID
    let fileID: String
    let title: String
    let date: Date
    let score: Float
    /// The significance the USER set on that note; nil/0 = unrated → show nothing.
    let importance: Double?
    let why: [ConnectionWhy]
}

struct ConnectionWhy: Hashable {
    enum Kind { case person, tag, term }
    let kind: Kind
    let text: String
}

struct ConnectionBacklink: Identifiable, Equatable {
    let id: String
    let title: String
    let date: Date
}

// The AI-zone state + its copy live in the SHARED RetrievalGate (one machine for
// this panel and the phone's settings gate). Backlinks render regardless of state —
// they never depended on the AI index, so consent must not cost them.

// MARK: - Model

/// Per-note orchestration: scores from `ConnectionsIndexService`, backlink scan,
/// why-chips, the hover-✕ hide list. Owned by NoteDisplayView (refreshes on note
/// switch even while the panel is collapsed — the toolbar badge needs the count).
@MainActor
@Observable
final class ConnectionsModel {
    private(set) var related: [ConnectionRow] = []     // floor-gated, unhidden, score-DESC
    private(set) var backlinks: [ConnectionBacklink] = []
    /// A query for the CURRENT note is in flight (covers the engine cold load).
    private(set) var querying = false
    private var currentFileID: String?
    var count: Int { related.count + backlinks.count }

    private static let hiddenDefaultsKey = "connectionsHiddenPairs"

    /// The state of the AI zone right now — reads the service live, so views
    /// re-render as it moves; derivation = the shared RetrievalGate machine.
    var state: RetrievalGate {
        let svc = ConnectionsIndexService.shared
        return RetrievalGate.derive(
            enabled: svc.isEnabled, modelDownloaded: svc.isModelDownloaded,
            downloadFraction: svc.downloadFraction,
            sweeping: svc.sweeping, sweepProgress: svc.sweepProgress,
            hasRows: !related.isEmpty, querying: querying)
    }

    func refresh(for file: PipelineFile, context: ModelContext) async {
        if currentFileID != file.id {
            currentFileID = file.id
            related = []          // never show the previous note's rows
        }
        let all = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        backlinks = Self.backlinkScan(for: file, in: all)

        let svc = ConnectionsIndexService.shared
        guard svc.isActive, let uuid = UUID(uuidString: file.id) else {
            related = []
            return
        }
        svc.warmUp()
        querying = true
        defer { querying = false }
        let scores = await svc.relatedScores(to: uuid)
        guard currentFileID == file.id else { return }   // switched away mid-query
        let byID = Dictionary(uniqueKeysWithValues: all.compactMap { f in
            UUID(uuidString: f.id).map { ($0, f) }
        })
        let hidden = Self.hiddenNeighbours(of: file.id)
        related = scores
            .filter { $0.score >= RetrievalTuning.relatedFloor && !hidden.contains($0.memoID.uuidString) }
            .compactMap { hit -> ConnectionRow? in
                guard let f = byID[hit.memoID], f.deletedAt == nil, f.id != file.id else { return nil }
                return ConnectionRow(
                    id: hit.memoID, fileID: f.id,
                    title: f.displayTitle,
                    date: ConnectionsIndexService.journalDate(f),
                    score: hit.score,
                    importance: f.significance,
                    why: Self.whyChips(current: file, other: f))
            }
            .sorted { $0.score > $1.score }
    }

    // ── hover-✕ "not related": a per-note hide list, nothing fancier (v1) ──

    func hide(_ row: ConnectionRow, for file: PipelineFile) {
        var map = UserDefaults.standard.dictionary(forKey: Self.hiddenDefaultsKey) as? [String: [String]] ?? [:]
        map[file.id, default: []].append(row.id.uuidString)
        UserDefaults.standard.set(map, forKey: Self.hiddenDefaultsKey)
        related.removeAll { $0.id == row.id }
    }

    private static func hiddenNeighbours(of fileID: String) -> Set<String> {
        let map = UserDefaults.standard.dictionary(forKey: hiddenDefaultsKey) as? [String: [String]] ?? [:]
        return Set(map[fileID] ?? [])
    }

    // ── backlinks (the old MemoBacklinks strip's scan, unchanged) ──

    /// Who links HERE: `[[memo:<id>|…]]` in any live body, newest first.
    static func backlinkScan(for file: PipelineFile, in all: [PipelineFile]) -> [ConnectionBacklink] {
        let needle = "memo:\(file.id)"
        var found: [ConnectionBacklink] = []
        for f in all where f.id != file.id && f.deletedAt == nil {
            let body = f.sanitised ?? f.enhancedCopyedit ?? f.transcript ?? ""
            if body.contains(needle) {
                found.append(ConnectionBacklink(id: f.id, title: f.queueTitle, date: f.uploadedAt))
            }
        }
        return found.sorted { $0.date > $1.date }
    }

    // ── why-chips: the dumb v1 overlap heuristic (shared people / tags / terms) ──

    static func whyChips(current: PipelineFile, other: PipelineFile) -> [ConnectionWhy] {
        var chips: [ConnectionWhy] = []
        for name in wikiNames(current).intersection(wikiNames(other)).sorted().prefix(2) {
            chips.append(ConnectionWhy(kind: .person, text: name))
        }
        for tag in Set(current.tags).intersection(other.tags).sorted().prefix(2) {
            chips.append(ConnectionWhy(kind: .tag, text: "#\(tag)"))
        }
        if chips.count < 4 {
            let a = contentWordCounts(current), b = contentWordCounts(other)
            let shared = Set(a.keys).intersection(b.keys)
                .sorted { min(a[$0] ?? 0, b[$0] ?? 0) > min(a[$1] ?? 0, b[$1] ?? 0) }
            for term in shared.prefix(4 - chips.count) {
                chips.append(ConnectionWhy(kind: .term, text: term))
            }
        }
        return chips
    }

    /// `[[Name]]` wikilink targets in the sanitised body — people links only
    /// (`[[memo:…]]` note-links excluded).
    private static func wikiNames(_ f: PipelineFile) -> Set<String> {
        guard let body = f.sanitised else { return [] }
        var names = Set<String>()
        var search = body.startIndex
        while let open = body.range(of: "[[", range: search..<body.endIndex),
              let close = body.range(of: "]]", range: open.upperBound..<body.endIndex) {
            let inner = String(body[open.upperBound..<close.lowerBound])
            if !inner.hasPrefix("memo:"), inner.count < 60 {
                names.insert(String(inner.split(separator: "|").first ?? ""))
            }
            search = close.upperBound
        }
        names.remove("")
        return names
    }

    private static let stopWords: Set<String> = [
        "about", "after", "again", "because", "before", "being", "could", "every",
        "first", "going", "little", "maybe", "other", "really", "should", "something",
        "their", "there", "these", "thing", "things", "think", "though", "today",
        "wanna", "where", "which", "while", "would", "gonna", "still", "actually"]

    private static func contentWordCounts(_ f: PipelineFile) -> [String: Int] {
        let body = (f.sanitised ?? f.enhancedCopyedit ?? f.transcript ?? "").lowercased()
        var counts: [String: Int] = [:]
        for word in body.split(whereSeparator: { !$0.isLetter }) {
            guard word.count >= 5, !stopWords.contains(String(word)) else { continue }
            counts[String(word), default: 0] += 1
        }
        return counts
    }
}

// MARK: - Panel (pure body — snapshot-friendly)

struct ConnectionsPanelBody: View {
    let state: RetrievalGate
    let related: [ConnectionRow]
    let backlinks: [ConnectionBacklink]
    /// The open note, drawn as the highlighted card on the Date rail.
    let currentTitle: String
    let currentDate: Date
    let currentImportance: Double?
    @Binding var sortByDate: Bool
    var onOpen: (String) -> Void = { _ in }
    var onHide: (ConnectionRow) -> Void = { _ in }
    var onEnable: () -> Void = {}
    var onCollapse: () -> Void = {}

    @State private var hoveredRow: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch state {
                    case .gate: gate
                    case .downloading(let f): downloading(f)
                    case .preparing: preparing
                    case .indexing(let done, let total): indexing(done, total)
                    case .finding: finding
                    case .ready:
                        if related.isEmpty { noConnections } else { relatedSection }
                    }
                    backlinkSection
                }
                .padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .frame(width: 280)
        .background(Theme.sidebar)
        .overlay(alignment: .leading) { Theme.hairline.opacity(0.5).frame(width: 1) }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text("CONNECTIONS")
                .font(.system(size: 10, weight: .bold)).tracking(0.5)
                .foregroundStyle(Theme.textMuted)
            let count = related.count + backlinks.count
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Theme.surfaceHover, in: Capsule())
            }
            Spacer()
            Button(action: onCollapse) {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
            .help("Hide Connections (⌥⌘C)")
        }
        .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 10)
    }

    // ── the one list, two orders ──

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sortPill
                Spacer()
            }
            Text(sortByDate
                 ? "the arc of this idea · first mentioned \(Self.day(threadRows.first?.date))"
                 : "best match first · odd matches sink to the bottom")
                .font(.system(size: 9.5)).foregroundStyle(Theme.textMuted)
                .padding(.top, 4).padding(.bottom, 10)
            if sortByDate { rail } else { flatRows }
        }
        .padding(.top, 2)
    }

    private var sortPill: some View {
        HStack(spacing: 0) {
            pillSegment("Date", on: sortByDate) { sortByDate = true }
            pillSegment("Closest", on: !sortByDate) { sortByDate = false }
        }
        .padding(2)
        .background(Theme.hairline.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
    }

    private func pillSegment(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(on ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(on ? AnyShapeStyle(Theme.surface) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    /// Date mode = the thread: related + this note, oldest first (the arc).
    private struct ThreadEntry: Identifiable {
        let id: UUID
        let row: ConnectionRow?   // nil = the open note itself
        let date: Date
    }

    private var threadRows: [ThreadEntry] {
        var entries = related.map { ThreadEntry(id: $0.id, row: $0, date: $0.date) }
        entries.append(ThreadEntry(id: UUID(), row: nil, date: currentDate))
        return entries.sorted { $0.date < $1.date }
    }

    private var closestID: UUID? { related.max(by: { $0.score < $1.score })?.id }

    private var rail: some View {
        let entries = threadRows
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        Circle()
                            .strokeBorder(entry.row == nil || i == 0 ? Theme.accent : Theme.textMuted, lineWidth: 2)
                            .background(Circle().fill(entry.row == nil ? Theme.accent : .clear))
                            .frame(width: 10, height: 10)
                            .padding(.top, entry.row == nil ? 9 : 3)
                        if i < entries.count - 1 {
                            Rectangle().fill(Theme.surfaceHover).frame(width: 1.5)
                        }
                    }
                    if let row = entry.row {
                        railNode(row, isFirst: i == 0)
                    } else {
                        thisNoteCard(isFirst: i == 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func railNode(_ row: ConnectionRow, isFirst: Bool) -> some View {
        Button { onOpen(row.fileID) } label: {
            VStack(alignment: .leading, spacing: 2) {
                dateLine(date: row.date,
                         flag: isFirst ? "FIRST MENTION" : (row.id == closestID ? "CLOSEST MATCH" : nil),
                         importance: row.importance)
                Text(row.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                whyRow(row.why)
            }
            .padding(.bottom, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(rowTooltip(row))
        .accessibilityIdentifier("connections-rail-row")
    }

    private func thisNoteCard(isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            dateLine(date: currentDate,
                     flag: isFirst ? "FIRST MENTION · THIS NOTE" : "THIS NOTE",
                     importance: currentImportance)
            Text(currentTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
        .padding(.bottom, 14)
        .accessibilityIdentifier("connections-this-note")
    }

    private var flatRows: some View {
        VStack(spacing: 6) {
            ForEach(related) { row in
                Button { onOpen(row.fileID) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(row.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            importanceText(row.importance)
                            if hoveredRow == row.id {
                                Button { onHide(row) } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .help("Not related — hide this pairing")
                                .accessibilityIdentifier("connections-hide")
                            } else {
                                Text(Self.day(row.date))
                                    .font(.system(size: 9.5).monospacedDigit())
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                        whyRow(row.why)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background((hoveredRow == row.id ? Theme.surfaceHover : Theme.hairline.opacity(0.08)),
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline.opacity(0.5), lineWidth: 1))
                .onHover { inside in hoveredRow = inside ? row.id : (hoveredRow == row.id ? nil : hoveredRow) }
                .help(rowTooltip(row))
                .accessibilityIdentifier("connections-flat-row")
            }
        }
    }

    /// Exact closeness lives HERE — always a %, never 0.x, so it can't be misread
    /// as the importance decimal (locked in the mock review).
    private func rowTooltip(_ row: ConnectionRow) -> String {
        let pct = "\(Int((row.score * 100).rounded()))% match"
        let shares = row.why.map(\.text).joined(separator: ", ")
        return shares.isEmpty ? pct : "\(pct) · shares: \(shares)"
    }

    private func dateLine(date: Date, flag: String?, importance: Double?) -> some View {
        HStack(spacing: 6) {
            Text(Self.day(date).uppercased())
                .font(.system(size: 9, weight: .bold).monospacedDigit()).tracking(0.4)
                .foregroundStyle(Theme.textMuted)
            if let flag {
                Text(flag)
                    .font(.system(size: 9, weight: .bold)).tracking(0.4)
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 4)
            importanceText(importance)
        }
    }

    /// P1 (picked): the owner-set importance as the control's own decimal readout —
    /// warm amber past the refine wall, NOTHING when unrated (no fake 0.0).
    @ViewBuilder private func importanceText(_ value: Double?) -> some View {
        let step = SignificanceScale.litCount(value)
        if step > 0 {
            Text(step == SignificanceScale.stepCount ? "1.0" : "0.\(step)")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(SignificanceScale.isRefine(step: step) ? Theme.amber : Theme.accent)
        }
    }

    private func whyRow(_ chips: [ConnectionWhy]) -> some View {
        let shown = chips.prefix(3)
        let extra = chips.count - shown.count
        return HStack(spacing: 4) {
            ForEach(Array(shown), id: \.self) { chip in whyChip(chip) }
            if extra > 0 {
                Text("+\(extra)").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.top, 2)
    }

    private func whyChip(_ chip: ConnectionWhy) -> some View {
        let color: Color = switch chip.kind {
        case .person: Theme.nameLink
        case .tag: Theme.accent
        case .term: Theme.textSecondary
        }
        return Text(chip.text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(color.opacity(chip.kind == .term ? 0.08 : 0.13), in: RoundedRectangle(cornerRadius: 8))
            .lineLimit(1)
    }

    // ── LINKED FROM (the old bottom strip, moved in) ──

    @ViewBuilder private var backlinkSection: some View {
        if state == .ready || !backlinks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Divider().overlay(Theme.hairline.opacity(0.4)).padding(.vertical, 8)
                Text("LINKED FROM")
                    .font(.system(size: 9.5, weight: .bold)).tracking(0.45)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.bottom, 4)
                if backlinks.isEmpty {
                    Text("Nothing links here yet.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                } else {
                    ForEach(backlinks) { link in
                        Button { onOpen(link.id) } label: {
                            HStack(spacing: 7) {
                                Text("↩").font(.system(size: 11)).foregroundStyle(Theme.accent)
                                Text(link.title).font(.system(size: 11.5))
                                    .foregroundStyle(Theme.textSecondary).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(Self.day(link.date))
                                    .font(.system(size: 9.5).monospacedDigit())
                                    .foregroundStyle(Theme.textMuted)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Theme.hairline.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                        .help("Open “\(link.title)”")
                        .accessibilityIdentifier("connections-backlink")
                    }
                }
            }
        }
    }

    // ── gate + progress states (mock #m4) ──

    private var gate: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24)).foregroundStyle(Theme.accent.opacity(0.9))
                .padding(.top, 40)
            Text(RetrievalGate.Copy.gateTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(RetrievalGate.Copy.gateBody(device: "Mac"))
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // Custom accent capsule (not .borderedProminent — offscreen renders draw
            // system buttons in the inactive-window gray, hiding the CTA).
            Button(action: onEnable) {
                Text(RetrievalGate.Copy.gateCTA)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityIdentifier("connections-enable")
            Text(RetrievalGate.Copy.gateFootnote)
                .font(.system(size: 9.5)).foregroundStyle(Theme.textMuted)
            // A failed download/sweep used to silently re-show this gate with no
            // explanation (the phone's enable flow surfaces its failure; parity).
            if let err = ConnectionsIndexService.shared.lastError {
                Text(err)
                    .font(.system(size: 10)).foregroundStyle(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                    .accessibilityIdentifier("connections-error")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }

    private func downloading(_ fraction: Double) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24)).foregroundStyle(Theme.accent.opacity(0.9))
                .padding(.top, 56)
            Text(RetrievalGate.Copy.downloadingTitle)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
            progressBar(fraction, fill: Theme.accent)
            Text(RetrievalGate.Copy.downloadingSub(fraction: fraction))
                .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }

    /// Bytes done, model compiling for the ANE — the one-time step after the
    /// download that otherwise looks like a freeze (device-found 2026-07-16).
    private var preparing: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24)).foregroundStyle(Theme.accent.opacity(0.9))
                .padding(.top, 56)
            Text(RetrievalGate.Copy.preparingTitle)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
            progressBar(1, fill: Theme.accent)
            Text(RetrievalGate.Copy.preparingSub)
                .font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }

    /// The engine is cold-loading / the first query runs — quiet and honest
    /// (never "No connections yet" while the answer is still unknown).
    private var finding: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 22)).foregroundStyle(Theme.textMuted.opacity(0.6))
                .padding(.top, 48)
            Text(RetrievalGate.Copy.findingTitle)
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Text(RetrievalGate.Copy.findingSub)
                .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private func indexing(_ done: Int, _ total: Int) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 24)).foregroundStyle(Theme.textSecondary)
                .padding(.top, 56)
            Text(RetrievalGate.Copy.indexingTitle)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
            progressBar(total > 0 ? Double(done) / Double(total) : 0, fill: Theme.green)
            Text(RetrievalGate.Copy.indexingSub(done: done, total: total))
                .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }

    private var noConnections: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 22)).foregroundStyle(Theme.textMuted.opacity(0.6))
                .padding(.top, 48)
            Text(RetrievalGate.Copy.emptyTitle)
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Text(RetrievalGate.Copy.emptySub)
                .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    /// Custom determinate bar (offscreen renders draw system ProgressViews
    /// invisibly thin — a plain track+fill is deterministic, mock-faithful).
    private func progressBar(_ fraction: Double, fill: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline.opacity(0.6))
                Capsule().fill(fill)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 8)
    }

    private static func day(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

// MARK: - Live wrapper

/// The live panel: binds the model + service to the pure body and persists the
/// sort choice app-wide (mock decision — remembered, default Date).
struct ConnectionsPanel: View {
    let file: PipelineFile
    let model: ConnectionsModel
    var onOpenMemo: (String) -> Void
    var onCollapse: () -> Void
    @Environment(\.modelContext) private var ctx
    @AppStorage("connectionsSortByDate") private var sortByDate = true

    var body: some View {
        ConnectionsPanelBody(
            state: model.state,
            related: model.related,
            backlinks: model.backlinks,
            currentTitle: file.displayTitle,
            currentDate: ConnectionsIndexService.journalDate(file),
            currentImportance: file.significance,
            sortByDate: $sortByDate,
            onOpen: onOpenMemo,
            onHide: { model.hide($0, for: file) },
            onEnable: { ConnectionsIndexService.shared.enableAndDownload(ctx) },
            onCollapse: onCollapse)
    }
}
