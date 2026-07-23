import Foundation
import SwiftData

/// iPad/phone adapter for the shared `PolishPromptsSyncCore` reconcile: the local
/// store is `PolishPromptsStore` (UserDefaults — the engine reads it synchronously).
/// Runs on launch + foreground alongside the other sync sweeps, and on a Settings
/// prompt edit (push-on-edit). The algorithm itself is the shared core — identical
/// on the Mac. Runs on EVERY device (phones carry the prompts inert; a phone-side
/// carrier read costs nothing and keeps one code path).
@MainActor
enum PolishPromptsCloudSync {

    static func run(_ repository: NotesRepository, defaults: UserDefaults = .standard) {
        let localBlob = PolishPromptsStore.blob(defaults: defaults)
        let records = repository.allPolishPromptsRecords()
        let outcome = PolishPromptsSyncCore.reconcile(
            localBlob: localBlob,
            localModifiedAt: PolishPromptsStore.modifiedAt(defaults: defaults),
            records: records,
            insert: { repository.context.insert($0) },
            delete: { repository.context.delete($0) })

        switch outcome {
        case .adoptRemote(let blob, let ts):
            PolishPromptsStore.adoptSynced(blob, modifiedAt: ts, defaults: defaults)
            DevLog.log("polishPrompts: adopted synced prompts (stamp \(ts))")
        case .pushedLocal(let ts, seededLocalStamp: true):
            PolishPromptsStore.adoptSynced(localBlob, modifiedAt: ts, defaults: defaults)
        case .pushedLocal, .noop:
            break
        }
        if records.isEmpty, outcome == .noop { return }
        repository.save()
    }
}
