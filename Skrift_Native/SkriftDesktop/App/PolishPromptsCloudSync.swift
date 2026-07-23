import Foundation
import SwiftData
import os

/// Mac adapter for the shared `PolishPromptsSyncCore` reconcile (iPad wave v2):
/// the local store is `AppSettings.prompts` (+ `promptsModifiedAt`, the Mac's LWW
/// stamp — bumped by the Settings prompt editors). Runs from `MemoCloudReconciler`
/// on launch / foreground / import, and once when the Settings window closes
/// (push-on-edit without per-keystroke spam). No-op unless CloudKit-Mac sync is on.
/// Mirrors `VocabularyCloudSync` including its fresh-context rule.
@MainActor
enum PolishPromptsCloudSync {
    static func run() {
        var settings = SettingsStore.shared.load()
        guard settings.cloudKitMacSyncEnabled, let container = MemoCloudStore.container else { return }
        // Fresh context — mainContext reads stale after a CloudKit import (the memo-sweep
        // trap); an iPad prompt edit lands in a carrier blob the Mac must read fresh.
        let context = ModelContext(container)
        let records = (try? context.fetch(FetchDescriptor<PolishPromptsRecord>())) ?? []

        let localBlob = PolishPromptsSyncCore.Blob(
            copyEdit: settings.prompts.copyEdit,
            summary: settings.prompts.summary,
            title: settings.prompts.title)
        let outcome = PolishPromptsSyncCore.reconcile(
            localBlob: localBlob,
            localModifiedAt: settings.promptsModifiedAt ?? .distantPast,
            records: records,
            insert: { context.insert($0) },
            delete: { context.delete($0) })

        switch outcome {
        case .adoptRemote(let blob, let ts):
            settings.prompts.copyEdit = blob.copyEdit
            settings.prompts.summary = blob.summary
            settings.prompts.title = blob.title
            settings.promptsModifiedAt = ts
            SettingsStore.shared.save(settings)
            Logger(subsystem: "com.skrift.desktop", category: "promptsync")
                .info("adopted synced polish prompts (stamp \(ts, privacy: .public))")
        case .pushedLocal(let ts, seededLocalStamp: true):
            settings.promptsModifiedAt = ts
            SettingsStore.shared.save(settings)
        case .pushedLocal, .noop:
            break
        }
        if records.isEmpty, outcome == .noop { return }
        try? context.save()
    }
}
