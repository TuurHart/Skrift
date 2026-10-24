import Foundation
import SwiftData

extension ReconcileV2 {

    /// D218 (C155, R47): after an iCloud account switch, the Mac's copy (`SyncHealth.copyVerb`).
    /// Apple wiped the cloud store when the account changed; the Mac's own rows survive,
    /// so each live row becomes a memo again in the new account: the raw words and media through
    /// the one author door (`Author.author`), then its tags, rating, destination, lock, reminder,
    /// chosen title and polish. Only on his tap. A row whose memo the new account already has is
    /// left alone. Saves `cloud`; stamps each copied row's watermark so it counts as linked.
    enum AccountCopy {
        @discardableResult
        static func copy(_ rows: [PipelineFile], into cloud: ModelContext, deviceID: String,
                         now: Date = Date()) -> Int {
            var copied = 0
            for row in rows where row.deletedAt == nil {
                let memo: Memo
                do {
                    guard let authored = try Author.author(row, into: cloud, deviceID: deviceID) else { continue }
                    memo = authored
                } catch {
                    AppLog.cloudkit.error("account copy: \(row.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                    continue
                }
                Writers.pushMeta(row, to: memo)
                memo.destination = row.destination
                memo.locked = row.locked
                memo.remindAt = row.remindAt
                if row.memoTitleIsHis, let t = row.enhancedTitle, !t.isEmpty { memo.title = t }
                do { try Writers.upsertEnhancement(for: row, into: cloud, deviceID: deviceID, now: now) }
                catch { AppLog.cloudkit.error("account copy: polish of \(row.id, privacy: .public) failed: \(String(describing: error), privacy: .public)") }
                row.syncedSourceEditedAt = memo.lastEditedAt
                copied += 1
            }
            do { try cloud.save() } catch {
                AppLog.cloudkit.error("account copy: save failed: \(String(describing: error), privacy: .public)")
            }
            return copied
        }
    }
}
