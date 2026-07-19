import SwiftUI
import SwiftData

/// The Fading shelf (mock `fading-shelf.html`, signed 2026-07-17): untouched
/// notes past 30 days, counting down to their auto-move into Recently Deleted.
/// One action — Keep (never fades again). Reached from the Notes header ⋯.
struct FadingShelfView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Memo> { $0.deletedAt == nil },
           sort: \Memo.recordedAt, order: .forward) private var memos: [Memo]
    private let repository = NotesRepository.shared

    private var fading: [Memo] {
        MemoLifecycle.partition(memos).fading
            .sorted { MemoLifecycle.fadesAt($0) < MemoLifecycle.fadesAt($1) }   // soonest first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.skBg.ignoresSafeArea()
                if fading.isEmpty {
                    ContentUnavailableView("Nothing is fading",
                                           systemImage: "leaf",
                                           description: Text("Untouched notes land here after \(MemoLifecycle.fadeAfterDays) days."))
                } else {
                    List {
                        ForEach(fading) { memo in row(memo) }
                            .listRowBackground(Color.skSurface)
                        footer
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Fading · \(fading.count)")
            .navigationBarTitleDisplayMode(.inline)
            // Opening the shelf clears the ⋯ dot (unread semantics).
            .onAppear { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "fadingLastSeenAt") }
            .toolbar {
                if !fading.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Sweep all") { FadingSweep.sweepAllFading(repository: repository) }
                            .font(.system(size: 14)).tint(.skTextDim)
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ memo: Memo) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(memo.displayTitle)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.skText)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(memo.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    if let place = memo.metadata?.location?.placeName { Text(place) }
                }
                .font(.system(size: 11.5)).foregroundStyle(Color.skTextFaint)
            }
            Spacer(minLength: 8)
            Text(fadeLabel(memo))
                .font(.system(size: 11)).foregroundStyle(daysLeft(memo) <= 3 ? Color.skRed : Color.skAmber)
            Button("Keep") {
                memo.keptAt = Date()
                repository.save()
            }
            .buttonStyle(.bordered).controlSize(.small).tint(.skAccent)
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        Text("Automatic: each note moves to Recently Deleted on its day — still restorable for \(TrashPolicy.retentionDays) more days there. Keep = never fades again.")
            .font(.system(size: 11.5)).foregroundStyle(Color.skTextFaint)
            .listRowBackground(Color.clear)
    }

    private func daysLeft(_ memo: Memo) -> Int { MemoLifecycle.daysUntilSweep(memo) }
    private func fadeLabel(_ memo: Memo) -> String {
        let d = daysLeft(memo)
        return d == 0 ? "fades today" : "fades in \(d) day\(d == 1 ? "" : "s")"
    }
}
