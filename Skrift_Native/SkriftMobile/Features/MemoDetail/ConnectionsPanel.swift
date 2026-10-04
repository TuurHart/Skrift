import SwiftUI
import SwiftData

// The iPad Connections side panel — v2 (Tuur review 2026-07-23): the Mac panel
// COPIED, phone-tokened (mock `ipad-app.html` m3 v2; desktop
// `Features/Review/ConnectionsPanel.swift` is the source anatomy):
// ONE list · Date⇄Closest pill · Date mode = the thread RAIL (oldest first, the
// arc, THIS NOTE highlighted) · why-chips per row (SHARED derivation —
// `ConnectionWhyDerivation`; person chips from `linkedNames`, Q181) · importance
// decimal ONLY when rated · NO closeness % (the Mac keeps it behind hover; touch
// shows none) · long-press = the Mac's
// hover-✕ "not related" hide (same defaults key) · "Show all N" past the
// relatedKMac cap · in-panel consent gate. Open/close lives in the NOTE'S
// header (the collapse toggle was removed 2026-07-23 — on a 13" iPad the note
// is already at its reading measure, so hiding the panel only re-centred the
// same text; the Mac keeps its own collapse, where a narrow window earns it).
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
    /// Whether a note may summon its own Connections panel at all: RATED (the
    /// consent claim — round 5, 2026-07-26: an unrated note has no connections
    /// in either direction, its own panel included) and not locked. One rule
    /// for the capsule AND the sheet render — the two used to re-derive it
    /// separately, and neither consulted the rating (the phone's sibling of
    /// ROUND 9 item 4; the Mac's unrated pane already hid the capsule).
    static func canSummon(_ memo: Memo, isLocked: Bool) -> Bool {
        NoteConsent.isRated(memo) && !isLocked
    }

    // ── Q119: the panel's ONE set of rules, shared with the Mac (pure, tested by
    //    `ConnectionsRulesTests`) ──

    /// The AI zone's state: the Mac's `RetrievalGate.derive`, fed the phone
    /// service's facts. `active` = enabled + model on disk (or the mock index),
    /// so it stands in for both of derive's consent inputs.
    static func panelState(active: Bool, downloadFraction: Double?,
                           sweeping: Bool, sweepProgress: (done: Int, total: Int)?,
                           hasRows: Bool, querying: Bool) -> RetrievalGate {
        RetrievalGate.derive(enabled: active, modelDownloaded: active,
                             downloadFraction: downloadFraction,
                             sweeping: sweeping, sweepProgress: sweepProgress,
                             hasRows: hasRows, querying: querying)
    }

    /// The `[[Name]]` people a body links to, derived with the shared linker over the local
    /// names DB (the phone stores no `sanitised`). Feeds `ConnectionWhyDerivation.chips`.
    static func linkedNames(body: String, source: NoteSourceType = .audio, people: [Person]) -> Set<String> {
        guard !people.isEmpty, !body.isEmpty else { return [] }
        return ConnectionWhyDerivation.wikiNames(
            inSanitised: MemoLinking.linkedTranscript(body, source: source, people: people))
    }

    /// The rows the panel lists: the Mac's cap (`relatedKMac`, earliest kept)
    /// until "Show all N" expands it.
    static func visibleRows(_ rows: [ConnectionRowVM], showAll: Bool) -> [ConnectionRowVM] {
        showAll ? rows : RetrievalTuning.cappedRelated(rows, date: \.date)
    }

    /// "Show all N" appears only past the Mac's cap.
    static func showsShowAll(count: Int) -> Bool { count > RetrievalTuning.relatedKMac }

    /// The row's importance readout + its amber tier: the BUCKETED stop
    /// (`ThreeBallScale`, C210), the same text the Mac prints (legacy 0.7 → "1.0").
    static func importanceReadout(_ significance: Double) -> String? {
        ThreeBallScale.readout(for: significance)
    }
    static func importanceIsTop(_ significance: Double) -> Bool {
        ThreeBallScale.isTopStop(significance)
    }

    /// Closest = score DESC (best match first). Date mode renders the RAIL
    /// (oldest first — the arc), so this only ever orders the flat list.
    static func ordered(_ rows: [ConnectionRowVM], byDate: Bool) -> [ConnectionRowVM] {
        byDate ? rows.sorted { $0.date < $1.date } : rows.sorted { $0.score > $1.score }
    }
}

// MARK: - The standing panel

struct ConnectionsPanel: View {
    let memo: Memo
    var onOpenMemo: (UUID) -> Void = { _ in }
    // No "View thread" CTA: Date mode IS the thread (Tuur 2026-07-25 — "isn't it
    // the same as connections looking at date?"; it is, plus a THIS NOTE marker
    // and a CLOSEST MATCH flag). The sheet survives only on COMPACT, where the
    // Related footer card has no rail to absorb it.
    /// Dismiss the visitor sheet (signed mock ipad-note-chrome-belongs.html:
    /// the ✕ in the header — Connections is a per-note visitor, not a standing
    /// column). nil = no close affordance (defensive; the iPad always passes one).
    var onClose: (() -> Void)? = nil

    private let repository = NotesRepository.shared

    // Remembered app-wide. Date is the default mode, the Mac's default (signed
    // related-panel mock: "remembered, default Date"); one constant for both.
    @AppStorage("ipadConnectionsSortByDate") private var sortByDate = RetrievalTuning.connectionsDefaultSortByDate

    @State private var related: [ConnectionRowVM] = []   // score DESC
    @State private var backlinks: [BacklinkVM] = []
    @State private var finding = false                   // a related query is in flight
    @State private var showEnableSheet = false
    /// Expanded past the relatedKMac cap ("Show all N"). Resets per note.
    @State private var showAll = false

    private var isActive: Bool { JournalIndexService.shared.isActive }
    private var count: Int { related.count + backlinks.count }

    /// The AI zone's state, read live from the service (observable) so the panel
    /// moves through downloading / preparing / indexing like the Mac's.
    private var state: RetrievalGate {
        let svc = JournalIndexService.shared
        return ConnectionsPanelLogic.panelState(
            active: svc.isActive, downloadFraction: svc.downloadFraction,
            sweeping: svc.sweeping, sweepProgress: svc.sweepProgress,
            hasRows: !related.isEmpty, querying: finding)
    }

    var body: some View {
        expanded
        // The visitor sheet is an inspector SURFACE (signed 2026-07-24:
        // sidebars on skSurface, note on skBg) — grayer than the note paper
        // it rides over, so it reads as a distinct region.
        .background(Color.skSurface.ignoresSafeArea())
        .task(id: memo.id) {
            showAll = false
            await load()
        }
        // The enable sheet turned the index on → re-derive when it dismisses.
        .onChange(of: showEnableSheet) { _, showing in
            if !showing { Task { await load() } }
        }
        // A sweep just finished → this note may have neighbours now.
        .onChange(of: JournalIndexService.shared.sweeping) { _, now in
            if !now { Task { await load() } }
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
        .frame(width: ConnectionsPanelSpec.panelWidth)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.skBorder).frame(width: 0.5).ignoresSafeArea()
        }
        .accessibilityIdentifier("ipad-connections-panel")
    }

    private var header: some View {
        HStack(spacing: 7) {
            ConnectionsHeaderLabel(count: count, style: .phone)
            Spacer()
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.skTextDim)
                        .frame(width: 26, height: 26)
                        .background(Color.skElev, in: Circle())
                }
                .accessibilityIdentifier("ipad-connections-close")
                .accessibilityLabel(ConnectionsPanelSpec.closeLabel)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    // ── the AI zone: the Mac's RetrievalGate states, then the one list ──

    @ViewBuilder private var aiZone: some View {
        switch state {
        case .gate: gate
        case .downloading(let f):
            progressHint(title: RetrievalGate.Copy.downloadingTitle,
                         sub: RetrievalGate.Copy.downloadingSub(fraction: f),
                         fraction: f, fill: Color.skAccent)
        case .preparing:
            progressHint(title: RetrievalGate.Copy.preparingTitle,
                         sub: RetrievalGate.Copy.preparingSub,
                         fraction: 1, fill: Color.skAccent)
        case .indexing(let done, let total):
            progressHint(title: RetrievalGate.Copy.indexingTitle,
                         sub: RetrievalGate.Copy.indexingSub(done: done, total: total),
                         fraction: total > 0 ? Double(done) / Double(total) : 0,
                         fill: Color.skGreen)
        case .finding: findingState
        case .ready:
            if let err = RetrievalGate.failure(state: state, hasRows: !related.isEmpty,
                                               lastError: JournalIndexService.shared.lastError) {
                unavailableState(err)
            } else if related.isEmpty {
                emptyState
            } else {
                relatedSection
            }
        }
    }

    /// Both modes list the closest `relatedKMac` until expanded (the Mac's cap).
    private var visibleRelated: [ConnectionRowVM] {
        ConnectionsPanelLogic.visibleRows(related, showAll: showAll)
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sortPill
            Text(ConnectionsPanelSpec.subCaption(byDate: sortByDate,
                                                 firstMentioned: Self.day(threadRows.first?.date),
                                                 shown: visibleRelated.count, total: related.count))
                .font(.system(size: 10)).foregroundStyle(Color.skTextFaint)
                .padding(.top, 6).padding(.bottom, 10)
            if sortByDate { rail } else { flatRows }
            if ConnectionsPanelLogic.showsShowAll(count: related.count) {
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
                            if let imp = ConnectionsPanelLogic.importanceReadout(row.significance) {
                                Text(imp)
                                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                                    .foregroundStyle(ConnectionsPanelLogic.importanceIsTop(row.significance)
                                                     ? Color.skAmber : Color.skAccentText)
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
                        Label(ConnectionsPanelSpec.hideLabel, systemImage: ConnectionsPanelSpec.hideIcon)
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
                Label(ConnectionsPanelSpec.hideLabel, systemImage: ConnectionsPanelSpec.hideIcon)
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
        ConnectionDateLine(date: date, flag: flag,
                           readout: ConnectionsPanelLogic.importanceReadout(importance),
                           isTop: ConnectionsPanelLogic.importanceIsTop(importance), style: .phone)
    }

    // ── why-chips: the shared row (cap 3 + "+N", colour per kind) over the shared
    //    derivation; person chips come from the name-linked body (`linkedNames`) ──

    private func whyRow(_ chips: [ConnectionWhy]) -> some View {
        ConnectionWhyRow(chips: chips, style: .phone)
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

    /// A failed lookup/sweep: say so, with the error (C110: never a silent empty).
    func unavailableState(_ error: String) -> some View {   // internal: render test
        VStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 21)).foregroundStyle(Color.skRed.opacity(0.75))
                .padding(.top, 30)
            Text(RetrievalGate.Copy.unavailableTitle)
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.skTextDim)
            Text(error)
                .font(.system(size: 10.5)).foregroundStyle(Color.skTextFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
        .accessibilityIdentifier("ipad-connections-unavailable")
    }

    /// Downloading / preparing / indexing: title, a plain track+fill bar, sub.
    func progressHint(title: String, sub: String, fraction: Double, fill: Color) -> some View {   // internal: render test
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 22)).foregroundStyle(Color.skAccent.opacity(0.9))
                .padding(.top, 34)
            Text(title)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.skText)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.skElev)
                    Capsule().fill(fill)
                        .frame(width: max(0, min(1, fraction)) * geo.size.width)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 8)
            Text(sub)
                .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Color.skTextDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .accessibilityIdentifier("ipad-connections-progress")
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
        ConnectionsPanelSpec.hidePair(note: memo.id.uuidString, neighbour: row.id.uuidString)
        related.removeAll { $0.id == row.id }
    }

    private static func hiddenNeighbours(of memoID: UUID) -> Set<String> {
        ConnectionsPanelSpec.hiddenNeighbours(of: memoID.uuidString)
    }

    // MARK: - Derivation (main actor; mirrors MemoPageView's footer loaders)

    private func load() async {
        let target = memo.id
        let scanned = await scanBacklinks()
        guard memo.id == target else { return }   // switched notes mid-scan
        backlinks = scanned
        guard isActive else {
            related = []; finding = false
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
        // Q181: the real name lists (the Mac's `wikiNames` of its sanitised body), derived
        // on demand with the same shared linker — so a shared person shows a person chip.
        let people = NamesStore.shared.livePeople()
        let currentNames = ConnectionsPanelLogic.linkedNames(body: currentBody, source: memo.linkSource, people: people)
        related = scores
            .filter { $0.score >= RetrievalTuning.relatedFloor && $0.memoID != target
                      && !hidden.contains($0.memoID.uuidString) }
            .sorted { $0.score > $1.score }
            // No prefix here: the view caps at the Mac's `relatedKMac` and offers
            // "Show all N" past it (R58 — the old `.prefix(relatedK = 4)` made
            // "Show all" unreachable).
            .compactMap { hit in
                byID[hit.memoID].map { m in
                    ConnectionRowVM(
                        id: m.id, title: m.displayTitle,
                        date: LookbackProvider.journalDate(m),
                        score: hit.score, significance: m.significance,
                        why: ConnectionWhyDerivation.chips(
                            currentNames: currentNames, currentTags: currentTags, currentBody: currentBody,
                            otherNames: ConnectionsPanelLogic.linkedNames(body: bodyOf(m), source: m.linkSource, people: people),
                            otherTags: m.tags, otherBody: bodyOf(m)))
                }
            }
    }

    /// Who links HERE — the same scan as `MemoPageView.recomputeBacklinks`, plus
    /// the linking note's journalDate for the row. A `[[memo:<id>]]` can live in
    /// the raw transcript OR the Mac's polished copyedit, so scan both.
    private func scanBacklinks() async -> [BacklinkVM] {
        let mine = memo.id
        let copyeditByID = Backlinks.copyeditsByMemoID(repository.allEnhancements())
        let memos = repository.allMemos().filter { $0.id != mine }
        let rows = memos.map { Backlinks.Row(id: $0.id, transcript: $0.transcript, copyedit: copyeditByID[$0.id]) }
        let meta: [UUID: (title: String, date: Date)] = Dictionary(
            memos.map { ($0.id, ($0.ladderTitle(), LookbackProvider.journalDate($0))) },   // C25 ladder
            uniquingKeysWith: { a, _ in a })
        return await Task.detached(priority: .utility) {
            let found: [BacklinkVM] = Backlinks.scan(for: mine, in: rows).compactMap { id in
                guard let m = meta[id] else { return nil }
                return BacklinkVM(id: id, title: String(m.title.prefix(60)), date: m.date)
            }
            return Array(found.sorted { $0.date > $1.date }.prefix(6))
        }.value
    }

    private static func day(_ date: Date?) -> String { ConnectionsPanelSpec.day(date) }
}

extension ConnectionsPanelStyle {
    /// The phone/iPad's colours for the shared panel chrome (`Shared/UI/ConnectionsPanelShared.swift`).
    static let phone = ConnectionsPanelStyle(
        headerTitle: .skTextFaint, countText: .skTextDim, countFill: .skElev,
        dateText: .skTextFaint, flagText: .skAccentText,
        importance: .skAccentText, importanceTop: .skAmber,
        whyPerson: .skNameLinked, whyTag: .skAccentText, whyTerm: .skTextDim,
        whyMore: .skTextFaint)
}
