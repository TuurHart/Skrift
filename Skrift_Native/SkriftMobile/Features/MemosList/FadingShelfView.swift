import SwiftUI
import SwiftData

/// The Fading shelf (mock `fading-shelf.html`, signed 2026-07-17): untouched
/// notes past 30 days, counting down to their auto-move into Recently Deleted.
/// One action — Keep (never fades again). Reached from the Notes header ⋯.
struct FadingShelfView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Memo> { $0.deletedAt == nil },
           sort: \Memo.recordedAt, order: .forward) private var memos: [Memo]
    @State private var armed = FadingSweep.armed
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
                        if !armed { firstRunBanner }
                        ForEach(fading) { memo in row(memo) }
                            .listRowBackground(Color.skSurface)
                        footer
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Fading · \(fading.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var firstRunBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("First sweep").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.skAmber)
            Text("These notes qualified from your existing corpus. Nothing moves automatically until you start the timers.")
                .font(.system(size: 12.5)).foregroundStyle(Color.skTextDim)
            HStack(spacing: 10) {
                Button("Start the timers") {
                    FadingSweep.arm()
                    armed = true
                    FadingSweep.run(repository: repository)
                }
                .buttonStyle(.borderedProminent).tint(.skAccent).controlSize(.small)
                Button("Sweep all now") {
                    FadingSweep.sweepAllFading(repository: repository)
                    armed = true
                }
                .buttonStyle(.bordered).controlSize(.small).tint(.skTextDim)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.skAmber.opacity(0.08))
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
        Text("Do nothing and each note moves to Recently Deleted on its day — still restorable for \(TrashPolicy.retentionDays) more days there. Keep = never fades again.")
            .font(.system(size: 11.5)).foregroundStyle(Color.skTextFaint)
            .listRowBackground(Color.clear)
    }

    private func daysLeft(_ memo: Memo) -> Int { MemoLifecycle.daysUntilSweep(memo) }
    private func fadeLabel(_ memo: Memo) -> String {
        let d = daysLeft(memo)
        return d == 0 ? "fades today" : "fades in \(d) day\(d == 1 ? "" : "s")"
    }
}
