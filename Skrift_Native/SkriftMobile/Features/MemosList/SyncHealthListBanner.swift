import SwiftUI

/// C155 on the phone list (mock Q484): the amber banner above search while iCloud is not taking
/// notes. Show / Hide filters the list to the waiting notes (D168 removed the Unsynced chip, so
/// the banner is the only door); after an account switch, What now opens the sheet. Its own view,
/// so the list observes the monitor only through it.
struct SyncHealthListBanner: View {
    @Binding var showUnsynced: Bool
    @Binding var whatNow: Bool
    private var monitor = SyncHealthMonitor.shared

    init(showUnsynced: Binding<Bool>, whatNow: Binding<Bool>) {
        _showUnsynced = showUnsynced
        _whatNow = whatNow
    }

    static var deviceWord: String { Adaptive.isPadIdiom ? "this iPad" : "this iPhone" }

    var body: some View {
        if let banner = monitor.banner(device: Self.deviceWord) {
            let waiting = !monitor.unsynced.isEmpty
            SyncHealthBannerView(
                banner: banner, style: .skrift,
                actionLabel: banner.opensSheet ? SyncHealth.whatNowVerb
                    : waiting ? (showUnsynced ? SyncHealth.hideVerb : SyncHealth.showVerb) : nil,
                action: { if banner.opensSheet { whatNow = true } else { showUnsynced.toggle() } })
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .onChange(of: waiting) { _, now in if !now { showUnsynced = false } }
        }
    }
}

/// "Syncing is stopped" on the phone. The notes count is what this device still holds: Apple
/// wipes a CloudKit store whose account changed, so it is usually 0 here.
struct SyncWhatNowSheet: View {
    let notesHere: Int
    let onClose: () -> Void

    var body: some View {
        SyncWhatNowView(
            content: SyncHealthMonitor.shared.health.whatNow(
                device: SyncHealthListBanner.deviceWord, deviceKind: Adaptive.isPadIdiom ? "iPad" : "iPhone",
                notesHere: notesHere, settingsPath: "Settings"),
            style: .skrift, onOK: onClose)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

extension NotesListGroup {
    /// The list narrowed to `ids` (Show on the banner): empty days drop out.
    static func only(_ groups: [NotesListGroup], ids: Set<UUID>) -> [NotesListGroup] {
        groups.compactMap { g in
            let kept = g.memos.filter { ids.contains($0.id) }
            return kept.isEmpty ? nil : NotesListGroup(title: g.title, memos: kept)
        }
    }
}

/// C155 on the open note (mock Q484): "Not synced yet · <reason>" in the processing line's slot,
/// with What now after an account switch.
struct SyncHealthNoteBand: View {
    let memoID: UUID
    @State private var whatNow = false
    private var monitor = SyncHealthMonitor.shared

    init(memoID: UUID) { self.memoID = memoID }

    var body: some View {
        if let line = monitor.noteLine(for: memoID) {
            SyncHealthNoteLine(text: line, style: .skrift,
                               onWhatNow: monitor.isStopped ? { whatNow = true } : nil)
                .padding(.horizontal, Theme.Space.margin)
                .padding(.top, 8).padding(.bottom, 2)
                .sheet(isPresented: $whatNow) {
                    SyncWhatNowSheet(notesHere: NotesRepository.shared.allMemos().count) { whatNow = false }
                }
        }
    }
}
