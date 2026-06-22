import Foundation
import SwiftData

/// The reconcile loop for the Mac→CloudKit client (`MAC_CLOUDKIT_PLAN.md`, 8d): pull memos
/// the phone synced over CloudKit into the local pipeline queue, so the Mac processes them
/// exactly as it would a Bonjour upload. The launch / foreground / CloudKit-import TRIGGERS +
/// the `reconcile()` entry point (which resolve the app's containers + settings) live in the
/// app-only `MemoCloudReconciler+Wiring.swift` extension; this file holds the pure, testable
/// `sweep` so it compiles into the host-less test bundle.
///
/// **Coexists with Bonjour.** Gated behind the opt-in `cloudKitMacSync` setting (OFF by
/// default), and `MemoCloudIngest` dedups by memo UUID / embedded filename, so a memo seen
/// via BOTH transports collapses to one `PipelineFile`. The Bonjour/HTTP server is untouched.
@MainActor
enum MemoCloudReconciler {
    /// Set once by `start()` (the App wiring) so the launch/active/import observers register
    /// only once.
    static var didStart = false

    /// Sweep every `Memo` in `cloudContext` into `localContext` (the pipeline store): fetch
    /// each memo's `MemoAsset` blob rows and run `MemoCloudIngest`. Returns how many NEW
    /// `PipelineFile`s were created — gated (significance) / deduped memos return nil from the
    /// ingest and aren't counted. Pure (takes both contexts) so it's unit-testable host-less.
    @discardableResult
    static func sweep(from cloudContext: ModelContext, into localContext: ModelContext,
                      processEverything: Bool) -> Int {
        let memos = (try? cloudContext.fetch(FetchDescriptor<Memo>())) ?? []
        var created = 0
        for memo in memos {
            let memoID = memo.id
            let assets = (try? cloudContext.fetch(
                FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == memoID }))) ?? []
            if (try? MemoCloudIngest.ingest(memo: memo, assets: assets, into: localContext,
                                            processEverything: processEverything)) != nil {
                created += 1
            }
        }
        return created
    }
}
