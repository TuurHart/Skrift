import SwiftUI

/// The Journal tab home (P8) — built to the signed-off mock
/// `mocks/journal-retrieval.html` screen 1: Looking-back cards, a mini month
/// calendar, and a Places entry. Related/Threads/search arrive with the
/// embedding chunks; this screen is metadata-only.
struct JournalHomeView: View {
    private let repository = NotesRepository.shared
    @ObservedObject private var wall = WallPrinter.shared
    @State private var memos: [Memo] = []
    @State private var entries: [LookbackProvider.Entry] = []
    @State private var important: [Memo] = []
    @State private var thenNow: (then: Memo, now: Memo)?

    enum Route: Hashable { case calendar, map }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            // Unified 30pt screen title (device round 4: all four tabs match).
            HStack {
                ScreenTitle("Review")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 10) {
                    if entries.isEmpty && memos.isEmpty {
                        emptyState
                    } else {
                        if wall.queuedCount > 0 { wallQueueRow }
                        if !important.isEmpty { importantCard }
                        if let pair = thenNow { thenNowCard(pair) }
                        ForEach(entries) { entry in
                            if let memo = memo(entry.id) {
                                LookbackCard(entry: entry, memo: memo)
                            }
                        }
                        calendarCard
                        if !placeMemos.isEmpty { placesCard }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.skBg)
            }
            .background(Color.skBg)
            .toolbar(.hidden, for: .navigationBar)   // root only; pushes keep bars
            .navigationDestination(for: UUID.self) { MemoDetailView(initialID: $0) }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .calendar: JournalCalendarView()
                case .map: JournalMapView()
                }
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        memos = repository.allMemos()
        important = LookbackProvider.importantLately(for: memos)
        entries = LookbackProvider.entries(for: memos,
                                           excluding: Set(important.map(\.id)))
        // Then vs Now arrives async (embedding queries); lookbacks re-derive so
        // the pair's notes never double-show as lookback cards.
        Task {
            let snapshot = memos
            if let pair = await JournalIndexService.shared.thenVsNow(repository: repository) {
                let byID = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                if let then = byID[pair.then], let nowMemo = byID[pair.now] {
                    thenNow = (then, nowMemo)
                    entries = LookbackProvider.entries(
                        for: snapshot,
                        excluding: Set(important.map(\.id)).union([pair.then, pair.now]))
                    return
                }
            }
            thenNow = nil
        }
    }

    /// The juxtaposition card: what you thought THEN, what you said NOW —
    /// arranged, never interpreted.
    private func thenNowCard(_ pair: (then: Memo, now: Memo)) -> some View {
        let months = Calendar.current.dateComponents(
            [.month], from: LookbackProvider.journalDate(pair.then),
            to: LookbackProvider.journalDate(pair.now)).month ?? 6
        return JournalCard {
            VStack(alignment: .leading, spacing: 8) {
                JournalCardHeader(title: "Then vs now")
                JournalMemoRow(memo: pair.then)
                HStack(spacing: 6) {
                    Rectangle().fill(Color.skElev).frame(height: 1)
                    Text("\(months) months later")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.skAccentText)
                        .fixedSize()
                    Rectangle().fill(Color.skElev).frame(height: 1)
                }
                JournalMemoRow(memo: pair.now)
            }
        }
    }

    /// The wall's in-app surface — notifications get dismissed; this row
    /// doesn't. Tap prints everything queued (printer must be reachable).
    private var wallQueueRow: some View {
        JournalCard {
            Button {
                Task { await wall.tryDrain(repository) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "printer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.skAccentText)
                    Text("\(wall.queuedCount) card\(wall.queuedCount == 1 ? "" : "s") waiting for the wall")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.skText)
                    Spacer()
                    Text("Print now")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.skAccentText)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Tier-anchored, unlike the time-anchored lookbacks: every orange note of
    /// the last month — what you DECIDED matters (and what's on the wall).
    private var importantCard: some View {
        JournalCard {
            VStack(alignment: .leading, spacing: 8) {
                JournalCardHeader(title: "Important lately")
                ForEach(important, id: \.id) { memo in
                    HStack(spacing: 6) {
                        JournalMemoRow(memo: memo)
                        if wall.printedAt(memo.id) != nil {
                            Image(systemName: "printer.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.skTextFaint)
                        }
                    }
                }
            }
        }
    }

    private func memo(_ id: UUID) -> Memo? { memos.first { $0.id == id } }

    private var placeMemos: [Memo] { memos.filter { $0.metadata?.location != nil } }

    // ── sections ──

    private var calendarCard: some View {
        JournalCard {
            NavigationLink(value: Route.calendar) {
                VStack(alignment: .leading, spacing: 8) {
                    JournalCardHeader(
                        title: Date().formatted(.dateTime.month(.wide)),
                        trailing: "Calendar ›")
                    MonthGrid(month: Date(),
                              counts: LookbackProvider.dayCounts(for: memos, month: Date()),
                              selectedDay: nil, compact: true, onTap: nil)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var placesCard: some View {
        JournalCard {
            NavigationLink(value: Route.map) {
                VStack(alignment: .leading, spacing: 8) {
                    JournalCardHeader(title: "Places", trailing: "Map ›")
                    JournalMapPreview(memos: placeMemos)
                        .frame(height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .allowsHitTesting(false)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34))
                .foregroundStyle(Color.skAccent.opacity(0.85))
            Text("Review")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.skText)
            Text("As your notes age, past thinking resurfaces here —\na month ago, a year ago, on this day.")
                .font(.system(size: 13))
                .foregroundStyle(Color.skTextDim)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.top, 120)
        .accessibilityIdentifier("journal-empty")
    }
}

// ── shared journal components (used by home / calendar / map) ──

struct JournalCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.skSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct JournalCardHeader: View {
    let title: String
    var accent: String? = nil
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let accent {
                Text(accent.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.skAccentText)
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.skTextFaint)
                .textCase(.uppercase)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skTextFaint)
            }
        }
    }
}

/// One memo row in journal surfaces — deliberately self-contained (the memos
/// list's rows belong to the note-editing lane).
struct JournalMemoRow: View {
    let memo: Memo
    var showTime = false

    var body: some View {
        NavigationLink(value: memo.id) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mic")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.skTextFaint)
                    .frame(width: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(memo.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.skText)
                        .lineLimit(1)
                    if let snippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.skTextDim)
                            .lineLimit(1)
                    }
                    meta
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var snippet: String? {
        memo.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var meta: some View {
        HStack(spacing: 8) {
            if showTime {
                Text(LookbackProvider.journalDate(memo).formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.skTextFaint)
            }
            if let place = memo.metadata?.location?.placeName {
                HStack(spacing: 3) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 8))
                    Text(place).font(.system(size: 9.5))
                }
                .foregroundStyle(Color.skTextFaint)
            }
            ImportanceDots(significance: memo.significance)
        }
        .padding(.top, 2)
    }
}

/// Compact 3-dot importance read-out (the full 10-circle control lives in the
/// editor; cards only need a glanceable level). TIER-mapped, not rounded —
/// device finding 2026-07-07: 0.8 × 3 rounded DOWN, so an orange-tier
/// (Important) note showed 2 dots. 3 = Important, 2 = Useful, 1 = Passing.
struct ImportanceDots: View {
    let significance: Double
    var body: some View {
        let filled = significance >= 0.8 ? 3 : significance >= 0.4 ? 2 : significance > 0 ? 1 : 0
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i < filled ? Color.skAccent.opacity(0.75) : Color.skElev)
                    .frame(width: 5, height: 5)
            }
        }
    }
}

struct LookbackCard: View {
    let entry: LookbackProvider.Entry
    let memo: Memo

    var body: some View {
        JournalCard {
            VStack(alignment: .leading, spacing: 6) {
                JournalCardHeader(
                    title: "· " + entry.date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide)),
                    accent: entry.label)
                JournalMemoRow(memo: memo)
            }
        }
    }
}
