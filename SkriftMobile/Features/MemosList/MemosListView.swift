import SwiftUI
import SwiftData

/// Phase 1 **placeholder** memos list — deliberately plain, just enough for the
/// XCUITest to assert seeded data renders. The real reviewed Memos surface is
/// designed (mock-first) in a later phase; don't treat this layout as final.
struct MemosListView: View {
    @Query(sort: \Memo.recordedAt, order: .reverse) private var memos: [Memo]
    @State private var showRecord = false
    @State private var showNames = false

    var body: some View {
        NavigationStack {
            Group {
                if memos.isEmpty {
                    ContentUnavailableView(
                        "No memos yet",
                        systemImage: "waveform",
                        description: Text("Tap the mic to record your first memo.")
                    )
                    .accessibilityIdentifier("memos-empty")
                } else {
                    List {
                        ForEach(Array(memos.enumerated()), id: \.element.id) { index, memo in
                            MemoRow(memo: memo)
                                .accessibilityIdentifier("memo-row-\(index)")
                        }
                    }
                    .accessibilityIdentifier("memos-list")
                }
            }
            .navigationTitle("Memos")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showNames = true
                    } label: {
                        Image(systemName: "person.2.fill")
                    }
                    .accessibilityIdentifier("open-names-button")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await SyncCoordinator().syncAll() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("sync-button")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showRecord = true
                    } label: {
                        Image(systemName: "mic.fill")
                    }
                    .accessibilityIdentifier("new-recording-button")
                }
            }
            .fullScreenCover(isPresented: $showRecord) {
                RecordView()
            }
            .sheet(isPresented: $showNames) {
                NamesListView()
            }
        }
        .accessibilityIdentifier("memos-screen")
    }
}

private struct MemoRow: View {
    let memo: Memo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(durationText)
                Text("·")
                Text(memo.syncStatus == .synced ? "Synced" : "Waiting")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        if let t = memo.transcript?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return String(t.prefix(60))
        }
        return "Voice memo"
    }

    private var durationText: String {
        let total = Int(memo.duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
