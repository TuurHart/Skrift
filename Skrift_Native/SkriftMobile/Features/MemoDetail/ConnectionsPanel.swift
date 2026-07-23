import SwiftUI
import SwiftData

// The iPad Connections side panel — v2 (Tuur review 2026-07-23): the Mac panel
// COPIED, phone-tokened (mock `ipad-app.html` m3 v2; desktop
// `Features/Review/ConnectionsPanel.swift` is the source anatomy):
// ONE list · Date⇄Closest pill · Date mode = the thread RAIL (oldest first, the
// arc, THIS NOTE highlighted) · why-chips per row (SHARED derivation —
// `ConnectionWhyDerivation`; person chips are Mac-only until the phone grows a
// sanitised layer) · importance decimal ONLY when rated · NO closeness %
// (the Mac keeps it behind hover; touch shows none) · long-press = the Mac's
// hover-✕ "not related" hide (same defaults key) · "Show all N" past the
// relatedKMac cap · in-panel consent gate. Open/close lives in the NOTE'S
// TOOLBAR as the Mac-style count badge (`ConnectionsBadge`); collapsed, the
// panel keeps a zero-width presence so its loader still feeds the badge
// (the 2026-07-13 empty-conditional-task gotcha).
// Compact width keeps the phone's inline footer card — one data source.

// MARK: - Row model + pure logic (unit-tested — no Memo, no main actor)

struct ConnectionRowVM: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let date: Date
    let score: Float         // 0…1 cosine closeness (ordering only — never shown)
    let significance: Double // 0 = unrated
    var why: [ConnectionWhy] = []
}

struct BacklinkVM: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let date: Date
}

enum ConnectionsPanelLogic {
    /// The owner-set importance as a one-decimal readout — "0.8" / "1.0", and
    /// NOTHING when unrated (no fake 0.0). Uses the shared `SignificanceScale`
    /// so the panel, the significance control, and the Mac panel never drift.
    static func importanceText(_ significance: Double) -> String? {
        let step = SignificanceScale.litCount(significance)
        guard step > 0 else { return nil }
        return step == SignificanceScale.stepCount ? "1.0" : "0.\(step)"
    }

    /// Closest = score DESC (best match first). Date mode renders the RAIL
    /// (oldest first — the arc), so this only ever orders the flat list.
    static func ordered(_ rows: [ConnectionRowVM], byDate: Bool) -> [ConnectionRowVM] {
        byDate ? rows.sorted { $0.date < $1.date } : rows.sorted { $0.score > $1.score }
    }
}

/// The toolbar badge's data feed (the Mac keeps its model outside the panel for
/// exactly this — "the toolbar badge needs the count").
@MainActor
@Observable
final class ConnectionsBadge {
    static let shared = ConnectionsBadge()
    private(set) var count = 0
    func set(_ n: Int) { count = n }
}

// MARK: - The standing panel

struct ConnectionsPanel: View {
    let memo: Memo
    var onOpenMemo: (UUID) -> Void = { _ in }
    /// The "View thread" CTA — reuses the existing ThreadView sheet on the page.
    var onViewThread: () -> Void = {}

    private let repository = NotesRepository.shared

    // Remembered app-wide. Closest is the default mode (Mac default).
    @AppStorage("ipadConnectionsSortByDate") private var sortByDate = false
    @AppStorage("ipadConnectionsCollapsed") private var collapsed = false

    @State private var related: [ConnectionRowVM] = []   // score DESC
    @State private var backlinks: [BacklinkVM] = []
    @State private var threadFirstMention: Date?
    @State private var finding = false                   // a related query is in flight
    @State private var showEnableSheet = false
    /// Expanded past the relatedKMac cap ("Show all N"). Resets per note.
    @State private var showAll = false

    private var isActive: Bool { JournalIndexService.shared.isActive }
    private var count: Int { related.count + backlinks.count }

    private static let hiddenDefaultsKey = "connectionsHiddenPairs"   // same shape as the Mac's

    var body: some View {
        Group {
            if collapsed {
                // Zero-width presence: the .task below must keep firing while
                // hidden so the toolbar badge stays fresh (never EmptyView).
                Color.clear.frame(width: 1)
            } else {
                expanded
            }
        }
        .background(Color.skBg.ignoresSafeArea())
        .task(id: memo.id) {
            showAll = false
            await load()
        }
        // The enable sheet turned the index on → re-derive when it dismisses.
        .onChange(of: showEnableSheet) { _, showing in
            if !showing { Task { await load() } }
        }
        .sheet(isPresented: $showEnableSheet) { enableSheet }
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
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.skBorder).frame(width: 0.5).ignoresSafeArea()
        }
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
                Image(systemName: "chevron.right.2")
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

    // ── the AI zone: gate / finding / empty / the one list, two orders ──

    @ViewBuilder private var aiZone: some View {
        if !isActive {
            gate
        } else if finding && related.isEmpty {
            findingState
        } else if related.isEmpty {
            emptyState
        } else {
            relatedSection
        }
    }

    /// Both modes list the closest `relatedKMac` until expanded (the Mac's cap).
    private var visibleRelated: [ConnectionRowVM] {
        showAll ? related : RetrievalTuning.cappedRelated(related, date: \.date)
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sortPill
            Text(sortByDate
                 ? "the arc of this idea · first mentioned \(Self.day(threadRows.first?.date))"
                 : (visibleRelated.count < related.count
                    ? "best match first · showing \(visibleRelated.count) of \(related.count)"
                    : "best match first · odd matches sink to the bottom"))
                .font(.system(size: 10)).foregroundStyle(Color.skTextFaint)
                .padding(.top, 6).padding(.bottom, 10)
            if sortByDate { rail } else { flatRows }
            if related.count > RetrievalTuning.relatedKMac {
                Button { showAll.toggle() } label: {
                    Text(showAll ? "Show fewer" : "Show all \(related.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.skTextDim)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ipad-connections-show-all")
            }
            threadCTA.padding(.top, 4)
        }
        .padding(.top, 2)
    }

    private var sortPill: some View {
        // Mac segment order: Date | Closest (Closest = the default mode).
        HStack(spacing: 0) {
            pillSegment("Date", on: sortByDate) { sortByDate = true }
            pillSegment("Closest", on: !sortByDate) { sortByDate = false }
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
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(on ? AnyShapeStyle(Color.skSurface) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // ── Closest mode: flat rows (title · importance · date · why-chips) ──

    private var flatRows: some View {
        VStack(spacing: 6) {
            ForEach(visibleRelated) { row in
                Button { onOpenMemo(row.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(row.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.skText)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let imp = ConnectionsPanelLogic.importanceText(row.significance) {
                                Text(imp)
                                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Color.skAccentText)
                            }
                            Text(Self.day(row.date))
                                .font(.system(size: 10.5).monospacedDigit())
                                .foregroundStyle(Color.skTextFaint)
                        }
                        whyRow(row.why)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) { hide(row) } label: {
                        Label("Not related — hide", systemImage: "xmark")
                    }
                }
                .accessibilityIdentifier("ipad-connections-row")
            }
        }
    }

    // ── Date mode: the thread rail (the Mac's arc, verbatim) ──

    private struct ThreadEntry: Identifiable {
        let id: UUID
        let row: ConnectionRowVM?   // nil = the open note itself
        let date: Date
    }

    private var threadRows: [ThreadEntry] {
        var entries = visibleRelated.map { ThreadEntry(id: $0.id, row: $0, date: $0.date) }
        entries.append(ThreadEntry(id: memo.id, row: nil, date: LookbackProvider.journalDate(memo)))
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
                            .strokeBorder(entry.row == nil || i == 0 ? Color.skAccent : Color.skTextFaint,
                                          lineWidth: 2)
                            .background(Circle().fill(entry.row == nil ? Color.skAccent : .clear))
                            .frame(width: 10, height: 10)
                            .padding(.top, entry.row == nil ? 9 : 3)
                        if i < entries.count - 1 {
                            Rectangle().fill(Color.skElev).frame(width: 1.5)
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

    private func railNode(_ row: ConnectionRowVM, isFirst: Bool) -> some View {
        Button { onOpenMemo(row.id) } label: {
            VStack(alignment: .leading, spacing: 2) {
                dateLine(date: row.date,
                         flag: isFirst ? "FIRST MENTION" : (row.id == closestID ? "CLOSEST MATCH" : nil),
                         importance: row.significance)
                Text(row.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.skText)
                    .lineLimit(2).multilineTextAlignment(.leading)
                whyRow(row.why)
            }
            .padding(.bottom, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { hide(row) } label: {
                Label("Not related — hide", systemImage: "xmark")
            }
        }
        .accessibilityIdentifier("ipad-connections-rail-row")
    }

    private func thisNoteCard(isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            dateLine(date: LookbackProvider.journalDate(memo),
                     flag: isFirst ? "FIRST MENTION · THIS NOTE" : "THIS NOTE",
                     importance: memo.significance)
            Text(memo.displayTitle)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.skText)
                .lineLimit(2)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skAccentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Color.skAccent.opacity(0.4), lineWidth: 1))
        .padding(.bottom, 14)
        .accessibilityIdentifier("ipad-connections-this-note")
    }

    private func dateLine(date: Date, flag: String?, importance: Double) -> some View {
        HStack(spacing: 6) {
            Text(Self.day(date))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Color.skTextFaint)
            if let flag {
                Text(flag)
                    .font(.system(size: 8.5, weight: .bold)).tracking(0.4)
                    .foregroundStyle(Color.skAccentText)
            }
            Spacer(minLength: 4)
            if let imp = ConnectionsPanelLogic.importanceText(importance) {
                Text(imp)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.skAccentText)
            }
        }
    }

    // ── why-chips (shared derivation; person chips arrive when the phone
    //    grows a sanitised name layer — tags + terms carry the why for now) ──

    @ViewBuilder private func whyRow(_ chips: [ConnectionWhy]) -> some View {
        if !chips.isEmpty {
            HStack(spacing: 4) {
                ForEach(chips, id: \.self) { chip in
                    HStack(spacing: 3) {
                        if chip.kind == .person {
                            Image(systemName: "person.fill").font(.system(size: 7.5))
                        }
                        Text(chip.kind == .term ? "“\(chip.text)”" : chip.text)
                            .font(.system(size: 9.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.skTextDim)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.skElev, in: Capsule())
                }
            }
            .padding(.top, 3)
        }
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
                            Text(Self.day(link.date))
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

    // MARK: - Hide list (the Mac's hover-✕, long-press on touch; same key)

    private func hide(_ row: ConnectionRowVM) {
        var map = UserDefaults.standard.dictionary(forKey: Self.hiddenDefaultsKey) as? [String: [String]] ?? [:]
        map[memo.id.uuidString, default: []].append(row.id.uuidString)
        UserDefaults.standard.set(map, forKey: Self.hiddenDefaultsKey)
        related.removeAll { $0.id == row.id }
        ConnectionsBadge.shared.set(count)
    }

    private static func hiddenNeighbours(of memoID: UUID) -> Set<String> {
        let map = UserDefaults.standard.dictionary(forKey: hiddenDefaultsKey) as? [String: [String]] ?? [:]
        return Set(map[memoID.uuidString] ?? [])
    }

    // MARK: - Derivation (main actor; mirrors MemoPageView's footer loaders)

    private func load() async {
        let target = memo.id
        let scanned = await scanBacklinks()
        guard memo.id == target else { return }   // switched notes mid-scan
        backlinks = scanned
        guard isActive else {
            related = []; threadFirstMention = nil; finding = false
            ConnectionsBadge.shared.set(count)
            return
        }
        finding = true
        defer { if memo.id == target { finding = false } }  // don't clear a newer note's spinner
        let scores = await JournalIndexService.shared.relatedScores(to: target, repository: repository)
        guard memo.id == target else { return }   // switched notes mid-query
        let byID = Dictionary(repository.allMemos().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let copyeditByID = Dictionary(
            repository.allEnhancements().map { ($0.memoID, $0.copyedit) },
            uniquingKeysWith: { a, _ in a })
        func bodyOf(_ m: Memo) -> String {
            let polished = copyeditByID[m.id]
            return (polished?.isEmpty == false ? polished : m.transcript) ?? ""
        }
        let hidden = Self.hiddenNeighbours(of: target)
        let currentTags = memo.tags
        let currentBody = bodyOf(memo)
        related = scores
            .filter { $0.score >= RetrievalTuning.relatedFloor && $0.memoID != target
                      && !hidden.contains($0.memoID.uuidString) }
            .sorted { $0.score > $1.score }
            .prefix(RetrievalTuning.relatedK)
            .compactMap { hit in
                byID[hit.memoID].map { m in
                    ConnectionRowVM(
                        id: m.id, title: m.displayTitle,
                        date: LookbackProvider.journalDate(m),
                        score: hit.score, significance: m.significance,
                        why: ConnectionWhyDerivation.chips(
                            currentNames: [], currentTags: currentTags, currentBody: currentBody,
                            otherNames: [], otherTags: m.tags, otherBody: bodyOf(m)))
                }
            }
        threadFirstMention = JournalIndexService
            .threadOrder(seedID: target, scores: scores, memosByID: byID)
            .first.map { LookbackProvider.journalDate($0) }
        ConnectionsBadge.shared.set(count)
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

    private static func day(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
