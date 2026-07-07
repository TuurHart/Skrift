import SwiftUI

/// The Journal tab home (P8) — built to the signed-off mock
/// `mocks/journal-retrieval.html` screen 1: Looking-back cards, a mini month
/// calendar, and a Places entry. Related/Threads/search arrive with the
/// embedding chunks; this screen is metadata-only.
struct JournalHomeView: View {
    private let repository = NotesRepository.shared
    @State private var memos: [Memo] = []
    @State private var entries: [LookbackProvider.Entry] = []

    enum Route: Hashable { case calendar, map }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if entries.isEmpty && memos.isEmpty {
                        emptyState
                    } else {
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
            .navigationTitle("Journal")
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
        entries = LookbackProvider.entries(for: memos)
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
            Text("Journal")
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
/// editor; cards only need a glanceable level).
struct ImportanceDots: View {
    let significance: Double
    var body: some View {
        let filled = Int((significance * 3).rounded())
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
