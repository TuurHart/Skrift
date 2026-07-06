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
/// **Inert until enabled.** `container` is a lazy `static let`, so it does NOT init CloudKit
/// until something first touches it (the 8d reconcile loop, gated behind an opt-in setting).
/// It is `nil` when CloudKit is unavailable — under XCTest (so hosted UI tests stay offline)
/// or if the container fails to build (no entitlement / not signed in) — and every caller
/// treats a nil container as "CloudKit-Mac off", falling back to the Bonjour/HTTP path.
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
    /// and — now that Bonjour is being retired — the `NamesRecord` (people + voiceprints) and
    /// `VocabularyRecord` (custom words) carriers, so names + vocab sync phone↔Mac over CloudKit
    /// instead of the LAN `/api/names` endpoints. (The Mac still doesn't join the phone's
    /// audiobook records.) These record types already exist in the CloudKit schema — the phone
    /// created them — so the Mac is just a second client of them.
    static let schema = Schema([Memo.self, MemoAsset.self, MemoEnhancement.self,
                                NamesRecord.self, VocabularyRecord.self])

    /// The CloudKit-backed container, or `nil` when CloudKit is unavailable/disabled.
    static let container: ModelContainer? = makeContainer()

    private static func makeContainer() -> ModelContainer? {
        // Never touch CloudKit under tests — hosted UI tests run offline + deterministic,
        // exactly like the phone's `NotesRepository` (XCTest detection).
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        guard !isTesting else { return nil }

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
