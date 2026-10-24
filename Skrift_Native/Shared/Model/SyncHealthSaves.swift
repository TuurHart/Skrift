import Foundation
import SwiftData

/// Which notes a local save touched, for `SyncHealth.pending` (C155). A `ModelContext.didSave`
/// carries persistent identifiers; a memo, its enhancement, an asset or an edit head each map to
/// the note's id. Deletes are left out: a deleted row cannot be read back, and the list no longer
/// shows it.
enum SyncHealthSaves {
    static let noteEntities: Set<String> = ["Memo", "MemoEnhancement", "MemoAsset", "MemoEditHead"]

    static func identifiers(in note: Notification) -> [PersistentIdentifier] {
        let info = note.userInfo ?? [:]
        return [ModelContext.NotificationKey.insertedIdentifiers, .updatedIdentifiers]
            .flatMap { info[$0.rawValue] as? [PersistentIdentifier] ?? [] }
    }

    @MainActor
    static func noteIDs(for ids: [PersistentIdentifier], in context: ModelContext) -> Set<UUID> {
        var out = Set<UUID>()
        for pid in ids where noteEntities.contains(pid.entityName) {
            switch context.model(for: pid) {
            case let m as Memo: out.insert(m.id)
            case let e as MemoEnhancement: out.insert(e.memoID)
            case let a as MemoAsset: out.insert(a.memoID)
            case let h as MemoEditHead: out.insert(h.memoID)
            default: break
            }
        }
        return out
    }
}
