import Foundation
import SwiftData
import os

/// Mac→phone TRASH write-back (delete-sync, both directions). The reconciler mirrors a phone
/// trash/restore DOWN onto the local row (`MemoCloudUpdate`); this pushes a MAC trash/restore UP
/// to the shared `Memo.deletedAt`, so the phone hides/shows it too. `Memo.deletedAt` is the one
/// synced carrier both apps already use for soft-delete (14-day retention), so writing it here is
/// exactly the phone's own trash gesture — nothing new on the phone side.
///
/// App-only + gated exactly like the reconcile loop (`cloudKitMacSyncEnabled` + a container);
/// a no-op otherwise. Reads each file's CURRENT `deletedAt` (set moments earlier by `DesktopTrash`)
/// and writes it to the memo — so one call handles both soft-delete and restore. Permanent removal
/// (`deleteForever`) stays device-local: the memo is already soft-deleted in the cloud from the
/// trash that preceded it, and each device purges on its own 14-day timer from the same stamp.
@MainActor
enum MacCloudDeleteSync {
    private static let log = Logger(subsystem: "com.skrift.desktop", category: "cloudkit")

    /// Mirror each file's local trash state onto its synced `Memo`. Safe to call for any files —
    /// non-synced / non-memo rows are skipped, and a memo already at the same state isn't churned.
    static func mirror(_ files: [PipelineFile]) {
        guard SettingsStore.shared.load().cloudKitMacSyncEnabled,
              let container = MemoCloudStore.container else { return }
        let ctx = container.mainContext
        var wrote = false
        for pf in files {
            guard let memoID = MacCloudWriteBack.memoID(for: pf),
                  let memo = (try? ctx.fetch(
                      FetchDescriptor<Memo>(predicate: #Predicate { $0.id == memoID })))?.first else { continue }
            if memo.deletedAt != pf.deletedAt {
                memo.deletedAt = pf.deletedAt
                wrote = true
            }
        }
        if wrote {
            do { try ctx.save() }
            catch { log.error("delete-sync write failed: \(String(describing: error), privacy: .public)") }
        }
    }
}
