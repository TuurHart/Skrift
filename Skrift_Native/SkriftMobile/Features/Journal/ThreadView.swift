import SwiftUI

/// The arc of an idea (mock screen 4): the seed memo's related set, oldest
/// first, on a vertical rail — header names the FIRST MENTION. Presented as a
/// sheet (the memos stack's path is typed [UUID], so non-memo destinations
/// can't join it); tapping a note dismisses and opens it via MemoOpenBridge.
struct ThreadView: View {
    let seedID: UUID

    private let repository = NotesRepository.shared
    @Environment(\.dismiss) private var dismiss
    @State private var thread: [Memo] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if thread.count < 2 {
                    emptyState
                } else {
                    threadList
                }
            }
            .background(Color.skBg)
            .navigationTitle("Thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        let scores = await JournalIndexService.shared.relatedScores(to: seedID, repository: repository)
        let byID = Dictionary(repository.allMemos().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        thread = JournalIndexService.threadOrder(seedID: seedID, scores: scores, memosByID: byID)
        loaded = true
    }

    private var threadList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                rail
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(thread.first?.displayTitle ?? "Thread")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color.skText)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color.skTextDim)
            if let first = thread.first {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .semibold))
                    Text("First mentioned \(LookbackProvider.journalDate(first).formatted(.dateTime.day().month(.wide).year()))")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.skAccentText)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color.skAccentSoft))
                .padding(.top, 6)
            }
        }
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        let places = Set(thread.compactMap { $0.metadata?.location?.placeName }).count
        let range: String
        if let first = thread.first, let last = thread.last {
            let fd = LookbackProvider.journalDate(first)
            let ld = LookbackProvider.journalDate(last)
            let sameYear = Calendar.current.isDate(fd, equalTo: ld, toGranularity: .year)
            let f = sameYear ? fd.formatted(.dateTime.month(.abbreviated))
                             : fd.formatted(.dateTime.month(.abbreviated).year())
            range = "\(f) → \(ld.formatted(.dateTime.month(.abbreviated).year()))"
        } else { range = "" }
        let placePart = places > 0 ? " · \(places) place\(places == 1 ? "" : "s")" : ""
        return "\(thread.count) notes · \(range)\(placePart)"
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(thread.enumerated()), id: \.element.id) { i, memo in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .strokeBorder(i == 0 ? Color.skAccent : Color.skTextFaint, lineWidth: 2)
                            .background(Circle().fill(i == 0 ? Color.skAccent : Color.skBg))
                            .frame(width: 10, height: 10)
                            .padding(.top, 4)
                        if i < thread.count - 1 {
                            Rectangle().fill(Color.skElev).frame(width: 1.5)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(LookbackProvider.journalDate(memo).formatted(.dateTime.day().month(.abbreviated)))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color.skTextFaint)
                                .textCase(.uppercase)
                            if i == 0 {
                                Text("first mention")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(Color.skTextFaint)
                                    .textCase(.uppercase)
                            }
                            if memo.id == seedID {
                                Text("· this note")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(Color.skAccentText)
                            }
                        }
                        Button {
                            dismiss()
                            MemoOpenBridge.shared.open(memo.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(memo.displayTitle)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Color.skText)
                                    .lineLimit(1)
                                if let t = memo.transcript?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                                    Text(t)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.skTextDim)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.skSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .strokeBorder(memo.id == seedID ? Color.skAccent.opacity(0.55) : .clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 14)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 28))
                .foregroundStyle(Color.skAccent.opacity(0.8))
            Text("No thread yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.skText)
            Text("As more notes touch this idea,\nits arc shows up here.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.skTextDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
