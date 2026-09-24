import Foundation
import SwiftData

/// The Mac holds processing and export of a note with two versions until he picks (D139,
/// mock `Q4-edit-conflict.html`: "The Mac does not polish or export a note with two versions
/// until you pick. Its pill replaces Enhancing.").
///
/// The set is refreshed by every CloudKit reconcile sweep (`MemoCloudReconciler.sweep`) and
/// after a pick; ids are `PipelineFile.id` = the memo's UUID string. Readers: the process
/// queue (`ProcessingCoordinator.needsProcessing`), the exporter (`VaultExporter.export`),
/// and the list pill.
enum EditConflictHold {
    private static let lock = NSLock()
    private static var _ids: Set<String> = []

    static var ids: Set<String> {
        get { lock.lock(); defer { lock.unlock() }; return _ids }
        set { lock.lock(); _ids = newValue; lock.unlock() }
    }

    static func isHeld(_ fileID: String) -> Bool { ids.contains(fileID) }

    /// Recompute from the cloud store's memos + heads. Returns the held ids.
    @discardableResult
    static func refresh(memos: [Memo], in cloudContext: ModelContext,
                        thisDevice: String = DeviceID.current()) -> Set<String> {
        let held = Set(EditConflicts.conflictedIDs(in: cloudContext, memos: memos, thisDevice: thisDevice)
            .map(\.uuidString))
        ids = held
        return held
    }
}
