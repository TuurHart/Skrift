import XCTest
import SwiftData
import Foundation

/// 8d tests for the reconcile sweep (`MemoCloudReconciler.sweep`): it pulls every eligible
/// synced Memo (+ assets) from the CloudKit store into the local pipeline store, dedups on a
/// repeat sweep, and honors the significance gate / `processEverything` override.
@MainActor
final class MemoCloudReconcilerTests: XCTestCase {

    /// In-memory mirror of the CloudKit Memo store.
    private func cloudContext() throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    /// In-memory mirror of the local pipeline store.
    private func localContext() throws -> ModelContext {
        let c = try ModelContainer(for: PipelineFile.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    /// Seed a synced memo + its audio asset into the cloud context.
    private func seedMemo(_ cloud: ModelContext, significance: Double, bytes: String = "AUDIO") {
        let memo = Memo(id: UUID(), audioFilename: "memo_\(UUID().uuidString).m4a", recordedAt: Date(),
                        transcript: "hi", transcriptStatus: .done, transcriptConfidence: 0.9,
                        significance: significance)
        let asset = MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio,
                              filename: MemoCloudIngest.audioFilename(for: memo), blob: Data(bytes.utf8))
        cloud.insert(memo)
        cloud.insert(asset)
    }

    private func pipelineCount(_ ctx: ModelContext) -> Int {
        (try? ctx.fetchCount(FetchDescriptor<PipelineFile>())) ?? 0
    }

    func testSweepIngestsEligibleMemos() throws {
        let cloud = try cloudContext(), local = try localContext()
        seedMemo(cloud, significance: 0.5)
        seedMemo(cloud, significance: 0.8)
        seedMemo(cloud, significance: 0)     // gated out (flag-to-send)
        try cloud.save()

        let created = MemoCloudReconciler.sweep(from: cloud, into: local, processEverything: false).created
        XCTAssertEqual(created, 2, "two rated memos ingest; the significance-0 one stays on the phone")
        XCTAssertEqual(pipelineCount(local), 2)
    }

    func testSecondSweepDedups() throws {
        let cloud = try cloudContext(), local = try localContext()
        seedMemo(cloud, significance: 0.5)
        try cloud.save()

        XCTAssertEqual(MemoCloudReconciler.sweep(from: cloud, into: local, processEverything: false).created, 1)
        // A second reconcile (foreground/import) must not duplicate already-ingested memos.
        XCTAssertEqual(MemoCloudReconciler.sweep(from: cloud, into: local, processEverything: false).created, 0)
        XCTAssertEqual(pipelineCount(local), 1)
    }

    func testProcessEverythingIngestsUnratedMemos() throws {
        let cloud = try cloudContext(), local = try localContext()
        seedMemo(cloud, significance: 0)
        try cloud.save()

        XCTAssertEqual(MemoCloudReconciler.sweep(from: cloud, into: local, processEverything: false).created, 0)
        XCTAssertEqual(MemoCloudReconciler.sweep(from: cloud, into: local, processEverything: true).created, 1,
                       "the 'process everything' override ingests significance-0 memos")
        XCTAssertEqual(pipelineCount(local), 1)
    }

    // MARK: - Same-id duplicate rows (the 2026-07-12 clone incident, Mac side)

    /// Seed one memo row with explicit id/content into the cloud context.
    private func seedRow(_ cloud: ModelContext, id: UUID, transcript: String,
                         deletedAt: Date? = nil, withAsset: Bool = true) {
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                        recordedAt: Date(timeIntervalSince1970: 1_000_000),
                        transcript: transcript, transcriptStatus: .done,
                        transcriptConfidence: 0.9, significance: 0.5, deletedAt: deletedAt)
        cloud.insert(memo)
        if withAsset {
            cloud.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio,
                                   filename: MemoCloudIngest.audioFilename(for: memo),
                                   blob: Data("AUDIO".utf8)))
        }
    }

    /// Two ALIVE same-id rows with DIVERGING content (the pair the phone deliberately
    /// never auto-heals): the sweep must reconcile against ONE keeper, and a repeat
    /// sweep must be a no-op — before the canonical-rows fix the two rows took turns
    /// rewriting the single PipelineFile every sweep (recompile + re-export churn).
    func testDivergentSameIDRowsDoNotChurn() throws {
        let cloud = try cloudContext(), local = try localContext()
        let id = UUID()
        seedRow(cloud, id: id, transcript: "short")
        seedRow(cloud, id: id, transcript: "the considerably longer keeper transcript", withAsset: false)
        try cloud.save()

        let first = MemoCloudReconciler.sweep(from: cloud, into: local, processEverything: false)
        XCTAssertEqual(first.created, 1, "one id → one PipelineFile")
        XCTAssertEqual(pipelineCount(local), 1)
        let pf = try XCTUnwrap((try? local.fetch(FetchDescriptor<PipelineFile>()))?.first)
        XCTAssertEqual(pf.transcript, "the considerably longer keeper transcript",
                       "the keeper (most content) wins, not fetch order")

        let second = MemoCloudReconciler.sweep(from: cloud, into: local, processEverything: false)
        XCTAssertEqual(second.created, 0)
        XCTAssertTrue(second.updatedIDs.isEmpty,
                      "repeat sweep is a NO-OP — no flip-flop between the divergent rows")
        XCTAssertEqual(pf.transcript, "the considerably longer keeper transcript")
    }

    /// A healed pair (alive keeper + trashed, blob-detached clone) reconciles to the
    /// keeper's content — the trashed clone never shadows it.
    func testTrashedCloneNeverShadowsTheKeeper() throws {
        let cloud = try cloudContext(), local = try localContext()
        let id = UUID()
        seedRow(cloud, id: id, transcript: "clone (already trashed by the phone)", deletedAt: Date(), withAsset: false)
        seedRow(cloud, id: id, transcript: "keeper")
        try cloud.save()

        let outcome = MemoCloudReconciler.sweep(from: cloud, into: local, processEverything: false)
        XCTAssertEqual(outcome.created, 1)
        let pf = try XCTUnwrap((try? local.fetch(FetchDescriptor<PipelineFile>()))?.first)
        XCTAssertEqual(pf.transcript, "keeper")
        XCTAssertTrue(MemoCloudReconciler.sweep(from: cloud, into: local,
                                                processEverything: false).updatedIDs.isEmpty)
    }
}
