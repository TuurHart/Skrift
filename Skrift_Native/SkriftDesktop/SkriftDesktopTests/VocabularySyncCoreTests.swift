import XCTest
import SwiftData

/// The SHARED custom-vocabulary reconcile (`Shared/Pipeline/VocabularySyncCore.swift`)
/// — whole-list LWW by `modifiedAt`, one algorithm for phone AND Mac (the Mac used to be
/// consume-only union: Mac-added words never synced, deletions never landed). The phone's
/// `VocabularyCloudSyncTests` pin the same semantics through its adapter; these pin the
/// core directly, including the deletion-propagation case the Mac gains.
@MainActor
final class VocabularySyncCoreTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: VocabularyRecord.self, configurations: config)
    }

    private func records() -> [VocabularyRecord] {
        (try? context.fetch(FetchDescriptor<VocabularyRecord>())) ?? []
    }

    private func reconcile(localWords: [String], localModifiedAt: Date,
                           now: Date = Date()) -> VocabularySyncCore.Outcome {
        let outcome = VocabularySyncCore.reconcile(
            localWords: localWords, localModifiedAt: localModifiedAt,
            records: records(), now: now,
            insert: { self.context.insert($0) },
            delete: { self.context.delete($0) })
        try? context.save()
        return outcome
    }

    // MARK: no carrier yet

    func testFreshDeviceDoesNotCreateEmptyCarrier() {
        let outcome = reconcile(localWords: [], localModifiedAt: .distantPast)
        XCTAssertEqual(outcome, .noop)
        XCTAssertTrue(records().isEmpty, "empty-@-now would LWW-clobber another device's words")
    }

    func testFirstPushSeedsUnstampedLocal() {
        let now = Date()
        let outcome = reconcile(localWords: ["Skrift"], localModifiedAt: .distantPast, now: now)
        XCTAssertEqual(outcome, .pushedLocal(stamp: now, seededLocalStamp: true))
        XCTAssertEqual(records().first?.words, ["Skrift"])
    }

    func testFirstPushKeepsARealLocalStamp() {
        let ts = Date().addingTimeInterval(-60)
        let outcome = reconcile(localWords: ["x"], localModifiedAt: ts)
        XCTAssertEqual(outcome, .pushedLocal(stamp: ts, seededLocalStamp: false))
        XCTAssertEqual(records().first?.modifiedAt, ts)
    }

    // MARK: LWW both directions

    func testNewerRemoteAdopted() {
        let remoteTS = Date().addingTimeInterval(100)
        context.insert(VocabularyRecord(words: ["alpha"], modifiedAt: remoteTS))
        let outcome = reconcile(localWords: ["old"], localModifiedAt: Date())
        XCTAssertEqual(outcome, .adoptRemote(words: ["alpha"], modifiedAt: remoteTS))
    }

    /// The case the Mac gains: a deletion on the other device (newer EMPTY list)
    /// propagates instead of being resurrected by a union.
    func testNewerRemoteDeletionPropagates() {
        let remoteTS = Date().addingTimeInterval(100)
        context.insert(VocabularyRecord(words: [], modifiedAt: remoteTS))
        let outcome = reconcile(localWords: ["keepable"], localModifiedAt: Date())
        XCTAssertEqual(outcome, .adoptRemote(words: [], modifiedAt: remoteTS))
    }

    func testNewerLocalRewritesCarrier() {
        context.insert(VocabularyRecord(words: ["stale"], modifiedAt: .distantPast))
        let ts = Date()
        let outcome = reconcile(localWords: ["fresh"], localModifiedAt: ts)
        XCTAssertEqual(outcome, .pushedLocal(stamp: ts, seededLocalStamp: false))
        XCTAssertEqual(records().first?.words, ["fresh"])
        XCTAssertEqual(records().first?.modifiedAt, ts)
    }

    func testEqualTimestampsNoop() {
        let ts = Date()
        context.insert(VocabularyRecord(words: ["same"], modifiedAt: ts))
        XCTAssertEqual(reconcile(localWords: ["same"], localModifiedAt: ts), .noop)
    }

    func testDuplicateCarriersCollapseToNewest() {
        context.insert(VocabularyRecord(words: ["older"], modifiedAt: Date().addingTimeInterval(50)))
        context.insert(VocabularyRecord(words: ["newest"], modifiedAt: Date().addingTimeInterval(500)))
        _ = reconcile(localWords: ["local"], localModifiedAt: Date())
        XCTAssertEqual(records().count, 1)
        XCTAssertEqual(records().first?.words, ["newest"])
    }
}
