import SwiftUI

/// C155 on the Mac (mock Q484): the amber banner under Process, above search. No Show here: the
/// Mac's rows carry the pill themselves. After an account switch, What now opens the sheet.
struct MacSyncHealthBanner: View {
    @Binding var whatNow: Bool
    private var monitor = SyncHealthMonitor.shared

    init(whatNow: Binding<Bool>) { _whatNow = whatNow }

    var body: some View {
        if let banner = monitor.banner(device: "this Mac") {
            SyncHealthBannerView(banner: banner, style: .mac,
                                 actionLabel: banner.opensSheet ? SyncHealth.whatNowVerb : nil,
                                 action: { whatNow = true })
        }
    }
}

/// "Syncing is stopped" on the Mac, with D218's Copy: the Mac's own rows survive a switch
/// (Apple wipes only the cloud store), so it can put them into the new account on his tap.
struct MacSyncWhatNowSheet: View {
    let notesHere: Int
    let onClose: () -> Void

    var body: some View {
        let monitor = SyncHealthMonitor.shared
        SyncWhatNowView(
            content: monitor.health.whatNow(device: "this Mac", deviceKind: "Mac", notesHere: notesHere,
                                            settingsPath: "System Settings"),
            style: .mac,
            onCopy: notesHere > 0 ? {
                MemoCloudReconciler.copyToCurrentAccount()
                onClose()
            } : nil,
            onOK: onClose)
        .frame(width: 420)
    }
}

/// The open note's strip, in the error strip's slot under the toolbar.
struct MacSyncHealthStrip: View {
    let file: PipelineFile
    @State private var whatNow = false
    private var monitor = SyncHealthMonitor.shared

    init(file: PipelineFile) { self.file = file }

    var body: some View {
        let unsynced = monitor.unsynced
        if let id = ReconcileV2.Writers.candidates(for: file).first(where: unsynced.contains),
           let line = monitor.noteLine(for: id) {
            SyncHealthNoteLine(text: line, style: .mac, size: 11.5,
                               onWhatNow: monitor.isStopped ? { whatNow = true } : nil)
                .padding(.horizontal, 18).padding(.vertical, 6)
                .background(Theme.amber.opacity(0.12))
                .sheet(isPresented: $whatNow) {
                    MacSyncWhatNowSheet(notesHere: MemoCloudReconciler.liveRowCount()) { whatNow = false }
                }
        }
    }
}

extension NoteCardModel.Pill {
    /// The Mac row's pill with the not-synced state folded in: its memo id may be the row id or
    /// the one in its filename (`ReconcileV2.Writers.candidates`).
    @MainActor
    static func withSync(_ pill: NoteCardModel.Pill?, file: PipelineFile) -> NoteCardModel.Pill? {
        let unsynced = SyncHealthMonitor.shared.unsynced
        guard !unsynced.isEmpty else { return pill }
        return withSync(pill, unsynced: ReconcileV2.Writers.candidates(for: file).contains(where: unsynced.contains))
    }
}
