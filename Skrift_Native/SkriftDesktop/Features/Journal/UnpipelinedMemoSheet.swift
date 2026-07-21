import SwiftUI
import SwiftData

/// A read-only peek at a synced memo that isn't in the pipeline yet (the Queue
/// band's river-card fallback, mocks/lifecycle-ia-explorations.html #m2) —
/// title, meta, the full transcript, the spine one-liner, and one Process
/// action. Replaces the old dead-end flash ("Not in the queue — this note
/// hasn't been processed on the Mac", RootView.swift:34): clicking an
/// unpipelined river card in Review now opens this instead. Modest by design —
/// this is a peek, not the editor.
struct UnpipelinedMemoSheet: View {
    let memoID: String
    var onClose: () -> Void = {}
    /// Fired after Process writes `significance = 0.1` and kicks the reconcile
    /// sweep — the caller dismisses and jumps to the queue row, which appears
    /// once the sweep ingests it (the existing `@Query` picks it up reactively).
    var onProcessed: (String) -> Void = { _ in }

    @State private var memo: Memo?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if let memo {
                content(memo)
            } else if loaded {
                Spacer(minLength: 0)
                Text("This note may have been removed.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textMuted)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(width: 460, height: 520)
        .background(Theme.bg)
        .task { load() }
        .accessibilityIdentifier("unpipelined-sheet")
    }

    private var header: some View {
        HStack {
            Text("Not processed").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Button(action: onClose) {
                Text("Done").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5) }
    }

    private func content(_ memo: Memo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(WayOutRules.displayTitle(memo))
                .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            HStack(spacing: 10) {
                Text(memo.recordedAt.formatted(date: .abbreviated, time: .omitted))
                if let place = memo.metadata?.location?.placeName { Text(place) }
                if memo.duration > 0 { Text(SkriftFormat.clock(memo.duration)) }
            }
            .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            Text(WayOutRules.oneLiner(for: memo))
                .font(.system(size: 11)).foregroundStyle(Theme.amber)
            ScrollView {
                Text((memo.transcript?.isEmpty == false) ? memo.transcript! : "No transcript yet.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            capsuleButton("Process", prominent: true) { process(memo) }
                .accessibilityIdentifier("unpipelined-sheet.process")
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private func load() {
        defer { loaded = true }
        guard let uuid = UUID(uuidString: memoID), let ctx = MemoCloudStore.container?.mainContext else { return }
        memo = try? ctx.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == uuid })).first
    }

    /// Q2: the one-click minimum flag — same cloud write lane as Keep/Restore
    /// (FadingShelfColumn's `keptAt` precedent), just a different field.
    private func process(_ memo: Memo) {
        memo.significance = 0.1
        try? MemoCloudStore.container?.mainContext.save()
        MemoCloudReconciler.reconcileSoon()
        onProcessed(memoID)
    }
}
