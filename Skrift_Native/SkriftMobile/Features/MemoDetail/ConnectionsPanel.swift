import SwiftUI
import SwiftData

// The iPad Connections side panel (mock `ipad-app.html` m3, signed off 2026-07-22):
// the phone's footer RELATED card + LINKED FROM strip promoted into a standing
// 300pt trailing pane at regular width. Phone-flavored — the Mac's signed
// `related-panel` idiom (ONE list, Closest⇄Date pill, importance decimals,
// closeness %) minus the Mac-only why-chips/hover-hide. Compact width keeps the
// inline footer card (MemoDetailView owns that branch); ONE `JournalIndexService`
// data source, two presentations.
//
// The panel owns its own derivation (kept out of Shared per the DETAIL brief —
// the conductor decides any Shared move post-wave); backlinks render regardless
// of the AI index (they never depended on it, so consent must not cost them).

// MARK: - Row model + pure logic (unit-tested — no Memo, no main actor)

struct ConnectionRowVM: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let date: Date
    let score: Float        // 0…1 cosine closeness
    let significance: Double // 0 = unrated
}

struct BacklinkVM: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let date: Date
}

enum ConnectionsPanelLogic {
    /// score×100, rounded — the exact closeness, always a %, never a 0.x (so it
    /// can't be misread as the importance decimal; locked in the Mac mock review).
    static func closenessPct(_ score: Float) -> Int { Int((score * 100).rounded()) }

    /// The owner-set importance as a one-decimal readout — "0.8" / "1.0", and
    /// NOTHING when unrated (no fake 0.0). Uses the shared `SignificanceScale`
    /// so the panel, the significance control, and the Mac panel never drift.
    static func importanceText(_ significance: Double) -> String? {
        let step = SignificanceScale.litCount(significance)
        guard step > 0 else { return nil }
        return step == SignificanceScale.stepCount ? "1.0" : "0.\(step)"
    }

    /// Closest = score DESC (best match first); Date = journalDate DESC (most
    /// recent connection first — the oldest-first arc lives behind "View thread").
    static func ordered(_ rows: [ConnectionRowVM], byDate: Bool) -> [ConnectionRowVM] {
        byDate ? rows.sorted { $0.date > $1.date } : rows.sorted { $0.score > $1.score }
    }
}

// MARK: - The standing panel

struct ConnectionsPanel: View {
    let memo: Memo
    var onOpenMemo: (UUID) -> Void = { _ in }
    /// The "View thread" CTA — reuses the existing ThreadView sheet on the page.
    var onViewThread: () -> Void = {}

    private let repository = NotesRepository.shared

    // Remembered app-wide, mock defaults: Closest first, expanded.
    @AppStorage("ipadConnectionsSortByDate") private var sortByDate = false
    @AppStorage("ipadConnectionsCollapsed") private var collapsed = false

    @State private var related: [ConnectionRowVM] = []   // Closest order (score DESC)
    @State private var backlinks: [BacklinkVM] = []
    @State private var threadFirstMention: Date?
    @State private var finding = false                   // a related query is in flight
    @State private var showEnableSheet = false

    private var isActive: Bool { JournalIndexService.shared.isActive }
    private var count: Int { related.count + backlinks.count }

    var body: some View {
        Group {
            if collapsed { collapsedTab } else { expanded }
        }
        .background(Color.skBg.ignoresSafeArea())
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.skBorder).frame(width: 0.5).ignoresSafeArea()
        }
        .task(id: memo.id) { await load() }
        // The enable sheet turned the index on → re-derive when it dismisses.
        .onChange(of: showEnableSheet) { _, showing in
            if !showing { Task { await load() } }
        }
        .sheet(isPresented: $showEnableSheet) { enableSheet }
    }

    // ── collapsed = a thin edge tab carrying the count ──

    private var collapsedTab: some View {
        Button { withAnimation(Theme.Motion.snappy) { collapsed = false } } label: {
            VStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.skTextFaint)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.skAccentText)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.skAccentSoft, in: Capsule())
                }
                Text("CONNECTIONS")
                    .font(.system(size: 9, weight: .bold)).tracking(0.5)
                    .foregroundStyle(Color.skTextFaint)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .padding(.top, 18)
            }
            .frame(width: 40)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ipad-connections-expand")
        .accessibilityLabel("Show Connections")
    }

    // ── expanded panel ──

    private var expanded: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    aiZone
                    backlinkSection
                }
                .padding(.horizontal, 16).padding(.bottom, 20)
            }
        }
        .frame(width: Adaptive.sidePanelWidth)
        .accessibilityIdentifier("ipad-connections-panel")
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text("CONNECTIONS")
                .font(.system(size: 11, weight: .bold)).tracking(0.5)
                .foregroundStyle(Color.skTextFaint)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.skTextDim)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Color.skElev, in: Capsule())
            }
            Spacer()
            Button { withAnimation(Theme.Motion.snappy) { collapsed = true } } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.skTextFaint)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ipad-connections-collapse")
            .accessibilityLabel("Hide Connections")
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    // ── the AI zone: gate / finding / empty / the one list ──

    @ViewBuilder private var aiZone: some View {
        if !isActive {
            gate
        } else if finding && related.isEmpty {
            findingState
        } else if related.isEmpty {
            emptyState
        } else {
            relatedList
        }
    }

    private var relatedList: some View {
        let rows = ConnectionsPanelLogic.ordered(related, byDate: sortByDate)
        return VStack(alignment: .leading, spacing: 3) {
            sortPill.padding(.bottom, 8)
            ForEach(rows) { row in
                Button { onOpenMemo(row.id) } label: { rowContent(row) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ipad-connections-row")
            }
            threadCTA.padding(.top, 4)
        }
        .padding(.top, 2)
    }

    private func rowContent(_ row: ConnectionRowVM) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
                .font(.system(size: 13))
                .foregroundStyle(Color.skText)
                .lineLimit(1)
            HStack(spacing: 8) {
                if let imp = ConnectionsPanelLogic.importanceText(row.significance) {
                    Text(imp)
                        .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.skAccentText)
                }
                Text(row.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.skTextFaint)
                Spacer(minLength: 4)
                Text("\(ConnectionsPanelLogic.closenessPct(row.score))%")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(Color.skTextFaint)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var sortPill: some View {
        HStack(spacing: 0) {
            pillSegment("Closest", on: !sortByDate) { sortByDate = false }
            pillSegment("Date", on: sortByDate) { sortByDate = true }
        }
        .padding(2.5)
        .background(Color.skElev, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityIdentifier("ipad-connections-sort")
    }

    private func pillSegment(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Color.skText : Color.skTextDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(on ? AnyShapeStyle(Color.skSurface) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var threadCTA: some View {
        Button(action: onViewThread) {
            HStack(spacing: 7) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 11, weight: .semibold))
                Text("View thread")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 4)
                if let first = threadFirstMention {
                    Text("first mentioned \(first.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.skTextFaint)
                }
            }
            .foregroundStyle(Color.skAccentText)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ipad-connections-thread")
    }

    // ── LINKED FROM (index-independent — always shown when non-empty) ──

    @ViewBuilder private var backlinkSection: some View {
        if !backlinks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("LINKED FROM")
                    .padding(.top, isActive && !related.isEmpty ? 16 : 4)
                    .padding(.bottom, 2)
                ForEach(backlinks) { link in
                    Button { onOpenMemo(link.id) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.turn.up.left")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.skAccent)
                            Text(link.title)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.skTextDim)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(link.date.formatted(.dateTime.day().month(.abbreviated)))
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.skTextFaint)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ipad-connections-backlink")
                }
            }
        }
    }

    // ── consent gate (mirrors the Mac's in-panel gate; shared copy = no drift) ──

    private var gate: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24)).foregroundStyle(Color.skAccent.opacity(0.9))
                .padding(.top, 34)
            Text(RetrievalGate.Copy.gateTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.skText)
                .multilineTextAlignment(.center)
            Text(RetrievalGate.Copy.gateBody(device: "iPad"))
                .font(.system(size: 11)).foregroundStyle(Color.skTextDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { showEnableSheet = true } label: {
                Text(RetrievalGate.Copy.gateCTA)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.skAccent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityIdentifier("ipad-connections-enable")
            Text(RetrievalGate.Copy.gateFootnote)
                .font(.system(size: 9.5)).foregroundStyle(Color.skTextFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private var findingState: some View {
        panelHint(icon: "circle.hexagongrid",
                  title: RetrievalGate.Copy.findingTitle,
                  sub: RetrievalGate.Copy.findingSub)
    }

    private var emptyState: some View {
        panelHint(icon: "circle.hexagongrid",
                  title: RetrievalGate.Copy.emptyTitle,
                  sub: RetrievalGate.Copy.emptySub)
    }

    private func panelHint(icon: String, title: String, sub: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 21)).foregroundStyle(Color.skTextFaint.opacity(0.7))
                .padding(.top, 30)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.skTextDim)
            Text(sub)
                .font(.system(size: 10.5)).foregroundStyle(Color.skTextFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    // The enable flow lives in the real Settings section — present it in a sheet
    // ("routing to Settings") so the download progress + copy stay canonical.
    private var enableSheet: some View {
        NavigationStack {
            Form { JournalIndexSettingsSection() }
                .navigationTitle("Review & search")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showEnableSheet = false }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Derivation (main actor; mirrors MemoPageView's footer loaders)

    private func load() async {
        let target = memo.id
        let scanned = await scanBacklinks()
        guard memo.id == target else { return }   // switched notes mid-scan
        backlinks = scanned
        guard isActive else {
            related = []; threadFirstMention = nil; finding = false
            return
        }
        finding = true
        defer { if memo.id == target { finding = false } }  // don't clear a newer note's spinner
        let scores = await JournalIndexService.shared.relatedScores(to: target, repository: repository)
        guard memo.id == target else { return }   // switched notes mid-query
        let byID = Dictionary(repository.allMemos().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        related = scores
            .filter { $0.score >= RetrievalTuning.relatedFloor && $0.memoID != target }
            .sorted { $0.score > $1.score }
            .prefix(RetrievalTuning.relatedK)
            .compactMap { hit in
                byID[hit.memoID].map { m in
                    ConnectionRowVM(id: m.id, title: m.displayTitle,
                                    date: LookbackProvider.journalDate(m),
                                    score: hit.score, significance: m.significance)
                }
            }
        threadFirstMention = JournalIndexService
            .threadOrder(seedID: target, scores: scores, memosByID: byID)
            .first.map { LookbackProvider.journalDate($0) }
    }

    /// Who links HERE — the same scan as `MemoPageView.recomputeBacklinks`, plus
    /// the linking note's journalDate for the row. A `[[memo:<id>]]` can live in
    /// the raw transcript OR the Mac's polished copyedit, so scan both.
    private func scanBacklinks() async -> [BacklinkVM] {
        let mine = memo.id
        let copyeditByID = Dictionary(
            repository.allEnhancements().map { ($0.memoID, $0.copyedit) },
            uniquingKeysWith: { a, _ in a })
        let others: [(id: UUID, title: String, date: Date, body: String)] = repository.allMemos()
            .filter { $0.id != mine }
            .map { m in
                let body = [m.transcript, copyeditByID[m.id]]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "\n")
                return (m.id, m.title ?? m.firstTranscriptLine ?? "Untitled",
                        LookbackProvider.journalDate(m), body)
            }
        return await Task.detached(priority: .utility) {
            let marker = "[[memo:\(mine.uuidString)"
            let found: [BacklinkVM] = others.compactMap { row in
                guard row.body.contains(marker),
                      MemoLinkSyntax.targets(in: row.body).contains(mine) else { return nil }
                return BacklinkVM(id: row.id, title: String(row.title.prefix(60)), date: row.date)
            }
            return Array(found.sorted { $0.date > $1.date }.prefix(6))
        }.value
    }
}
