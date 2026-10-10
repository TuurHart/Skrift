#if DEBUG
import SwiftUI
import SwiftData

/// Q336 (DEBUG only): the body of Settings -> "Test notes (Dev only)" on the Mac. Fill seeds the
/// deterministic fake library into the CloudKit-backed `Memo` store (so it syncs to every Dev
/// device); Remove deletes exactly the marked notes, here and (through sync) everywhere, and the
/// Mac's local pipeline rows made from them. Logic: `TestLibrary` / `TestLibraryRunner` (Shared).
struct TestLibraryMacSection: View {
    var interactive = true
    /// Snapshot injection of the status line (nil = the live runner).
    var statusOverride: String? = nil
    @StateObject private var runner = TestLibraryRunner()
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(TestLibraryRunner.Copy.help)
                .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                pill(TestLibraryRunner.Copy.fillTitle, systemImage: "tray.and.arrow.down", tint: Theme.accent,
                     id: "settings.testlibrary.fill", enabled: !runner.busy) { fill() }
                pill(TestLibraryRunner.Copy.removeTitle, systemImage: "trash", tint: Theme.amber,
                     id: "settings.testlibrary.remove", enabled: !runner.busy && runner.markedCount > 0) { confirmRemove = true }
                if runner.busy { ProgressView().controlSize(.small).scaleEffect(0.8) }
                Spacer(minLength: 0)
            }
            Text(statusOverride ?? (runner.status.isEmpty ? "\(runner.markedCount) test notes here" : runner.status))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("settings.testlibrary.status")
        }
        .onAppear { if interactive, let c = MemoCloudStore.container { runner.refreshCount(container: c) } }
        .confirmationDialog(TestLibraryRunner.Copy.removeConfirm, isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(TestLibraryRunner.Copy.removeTitle, role: .destructive) { remove() }
        }
    }

    private func pill(_ title: String, systemImage: String, tint: Color, id: String, enabled: Bool,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 11))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(enabled ? tint : Theme.textMuted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background((enabled ? tint : Theme.textMuted).opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || !interactive)
        .accessibilityIdentifier(id)
    }

    private func fill() {
        guard let container = MemoCloudStore.container else { return }
        runner.fill(container: container, recordingsDirectory: nil) {
            NamesCloudSync.run()
            MemoCloudReconciler.reconcileSoon()
        }
    }

    private func remove() {
        guard let container = MemoCloudStore.container else { return }
        let removed = IDBox()
        runner.remove(container: container, deleteLocalFiles: { removed.add($0.id.uuidString) }) {
            // The Mac's local pipeline rows made from those notes (their id is the memo's UUID).
            let ctx = SharedStore.container.mainContext
            let ids = removed.all()
            var offset = 0
            while offset < ids.count {
                let chunk = Array(ids[offset..<min(ids.count, offset + 200)])
                let rows = (try? ctx.fetch(FetchDescriptor<PipelineFile>(predicate: #Predicate { chunk.contains($0.id) }))) ?? []
                DesktopTrash.deleteForever(rows, in: ctx)
                offset += chunk.count
            }
            NamesCloudSync.run()
            MemoCloudReconciler.reconcileSoon()
        }
    }
}

/// Ids collected on the background context while Remove runs.
private final class IDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    func add(_ id: String) { lock.lock(); ids.append(id); lock.unlock() }
    func all() -> [String] { lock.lock(); defer { lock.unlock() }; return ids }
}
#endif
