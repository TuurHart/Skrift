import Foundation
import SwiftData

/// The Mac's SECOND SwiftData container — a `NSPersistentCloudKitContainer` joined to the
/// SAME private CloudKit database the phone uses, so the Mac can read the phone's synced raw
/// `Memo`s and write its `MemoEnhancement` polish back (`MAC_CLOUDKIT_PLAN.md`, Fork A).
///
/// **Why a second container, separate from `SharedStore`:** the local pipeline store
/// (`SharedStore.container`) holds `PipelineFile`, whose `@Attribute(.unique) id` CloudKit
/// forbids — so `PipelineFile` can never join a CloudKit container. CloudKit-syncable models
/// (`Memo` / `MemoAsset` / `MemoEnhancement`, all default-valued, no unique constraints) live
/// here instead. The two containers coexist; the read bridge (`MemoCloudIngest`, 8b) turns a
/// synced `Memo` into a local `PipelineFile`, and the write-back (8c) upserts a
/// `MemoEnhancement` here after the pipeline enhances a memo-sourced file.
///
/// `container` is a lazy `static let`, so it does NOT init CloudKit until something first
/// touches it (the 8d reconcile loop, gated by `cloudKitMacSyncEnabled`, which defaults ON).
/// It is `nil` when CloudKit is unavailable — under XCTest (so hosted UI tests stay offline)
/// or if the container fails to build (no entitlement / not signed in) — and every caller
/// treats a nil container as "CloudKit-Mac off": the Mac works on its local store only
/// (Bonjour/HTTP sync is retired; CloudKit is the only phone↔Mac transport).
enum MemoCloudStore {
    /// The CloudKit container identifier — MUST match the phone's so both clients share the
    /// user's private zone (compile-time gated, like the phone's `NotesRepository`).
    #if DEBUG
    static let cloudContainerID = "iCloud.com.skrift.mobile.dev"
    #else
    static let cloudContainerID = "iCloud.com.skrift.mobile"
    #endif

    /// The shared CloudKit schema — the `@Model`s the phone registers that the Mac also needs:
    /// the note rows it reads (`Memo`/`MemoAsset`), the enhancement it writes (`MemoEnhancement`),
    /// and the `NamesRecord` (people + voiceprints) and `VocabularyRecord` (custom words)
    /// carriers, so names + vocab sync phone↔Mac over CloudKit. (The Mac doesn't join the
    /// phone's audiobook records.) These record types already exist in the CloudKit schema —
    /// the phone created them — so the Mac is just a second client of them.
    static let schema = Schema([Memo.self, MemoAsset.self, MemoEnhancement.self,
                                NamesRecord.self, VocabularyRecord.self,
                                PolishPromptsRecord.self, MemoEditHead.self])

    /// The CloudKit-backed container, or `nil` when CloudKit is unavailable/disabled.
    static let container: ModelContainer? = makeContainer()

    /// The one sync gate every Mac cloud adapter shares: `container` when Mac CloudKit sync is
    /// switched on (loads settings.json afresh, like the old inline gates), nil when it is off
    /// or there is no container. Checks the switch first, so a sync-off Mac never builds the
    /// CloudKit container.
    static var syncContainer: ModelContainer? {
        #if DEBUG
        // Q313: under `-perfLibrary` the container IS the local, CloudKit-off perf store, so the
        // reconcile sweep that ingests it into PipelineFile rows runs regardless of the sync switch.
        if PerfLibrary.isActive { return container }
        #endif
        return SettingsStore.shared.load().cloudKitMacSyncEnabled ? container : nil
    }

    /// The synced `Memo` with this id (predicate fetch, limit 1), or nil.
    static func memo(id: UUID, context: ModelContext) -> Memo? {
        var d = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private static func makeContainer() -> ModelContainer? {
        // Never touch CloudKit under tests — hosted UI tests run offline + deterministic,
        // exactly like the phone's `NotesRepository` (XCTest detection).
        let isTesting = LaunchArgs.isXCTest
        guard !isTesting else { return nil }

        #if DEBUG
        // Q313: `-perfLibrary` opens perf.store: its own file, CloudKit OFF, never the real store.
        if PerfLibrary.isActive {
            PerfLibrary.resetIfUnseeded()
            return try? ModelContainer(for: schema,
                                       configurations: PerfLibrary.storeConfiguration(schema: schema, url: AppPaths.memoCloudStoreFile))
        }
        // Q37: `-isolatedRun` points the DEV app at an in-memory, non-CloudKit store
        // instead of the real `memo_cloud.store` (which mirrors Tuur's actual synced
        // Dev notes) — so a real-window eyeball/screenshot with `-corpus` never opens
        // the live Dev CloudKit store. DEBUG-only; prod never reads this argument.
        if HeadlessIsolation.isRequested() {   // `-isolatedRun` or any `-snapshot*` (Q303)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try? ModelContainer(for: schema, configurations: config)
        }
        #endif

        let config = ModelConfiguration(
            schema: schema,
            url: AppPaths.memoCloudStoreFile,
            cloudKitDatabase: .private(cloudContainerID)
        )
        // Resilient: a failure (missing entitlement, not signed into iCloud) disables the
        // CloudKit-Mac path rather than crashing (the Mac simply won't sync until iCloud is set up).
        return try? ModelContainer(for: schema, configurations: config)
    }
}
