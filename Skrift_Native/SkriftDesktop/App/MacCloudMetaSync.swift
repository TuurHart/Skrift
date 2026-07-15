import Foundation
import SwiftData
import os

/// Mac→phone metadata write-back — the second half of "widen the narrow Mac→phone channel".
/// The enhancement carrier (`MacCloudWriteBack`) only ever carried body/title/summary, so tags
/// and importance edited on the Mac never reached the phone (and were frozen at first ingest the
/// other way). Both are plain `Memo` fields that already sync, so — exactly like delete-sync —
/// the Mac just writes them onto the synced `Memo`, and the phone reflects them.
///
/// App-only + gated like the reconcile loop (`cloudKitMacSyncEnabled` + a container); a no-op
/// otherwise. Writes each file's CURRENT `tags`/`significance` (set moments earlier by the review
/// UI) onto its memo. No `lastEditedAt` bump — these are synced fields on their own, and NOT
/// bumping it keeps the reconciler's text-reflect echo-quiet. `MemoCloudUpdate` reflects the phone
/// direction with a plain value compare, so a Mac write converges it (no clobber loop).
@MainActor
enum MacCloudMetaSync {
    private static let log = Logger(subsystem: "com.skrift.desktop", category: "cloudkit")

    /// Mirror each file's tags + importance onto its synced `Memo`. Safe for any files — non-synced
    /// / non-memo rows are skipped, and a memo already at the same values isn't churned.
    static func mirror(_ files: [PipelineFile]) {
        guard SettingsStore.shared.load().cloudKitMacSyncEnabled,
              let container = MemoCloudStore.container else { return }
        let ctx = container.mainContext
        var wrote = false
        for pf in files {
            guard let memoID = MacCloudWriteBack.memoID(for: pf),
                  let memo = (try? ctx.fetch(
                      FetchDescriptor<Memo>(predicate: #Predicate { $0.id == memoID })))?.first else { continue }
            if memo.tags != pf.tags { memo.tags = pf.tags; wrote = true }
            if let sig = pf.significance, memo.significance != sig { memo.significance = sig; wrote = true }
        }
        if wrote {
            do { try ctx.save() }
            catch { log.error("meta-sync write failed: \(String(describing: error), privacy: .public)") }
        }
    }
}
