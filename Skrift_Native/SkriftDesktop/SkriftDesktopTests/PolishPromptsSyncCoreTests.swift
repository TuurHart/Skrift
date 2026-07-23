import XCTest
// The host-less UnitTests bundle compiles Shared/Pipeline + Shared/Model directly
// (no app import) — this file tests the SHARED core only; the Mac's settings.json
// bridging lives in App/ (integration-verified live).

/// Desktop twin of the phone's `PolishPromptsSyncTests` core cases (the Shared
/// twin-test rule): whole-blob LWW, the fresh-device guard, carrier collapse.
final class PolishPromptsSyncCoreTests: XCTestCase {

    private var inserted: [PolishPromptsRecord] = []
    private var deleted: [PolishPromptsRecord] = []

    override func setUp() {
        super.setUp()
        inserted = []; deleted = []
    }

    private func reconcile(local: PolishPromptsSyncCore.Blob, stamp: Date,
                           records: [PolishPromptsRecord]) -> PolishPromptsSyncCore.Outcome {
        PolishPromptsSyncCore.reconcile(
            localBlob: local, localModifiedAt: stamp, records: records,
            insert: { self.inserted.append($0) },
            delete: { self.deleted.append($0) })
    }

    func testFreshDeviceAllDefaultMintsNoCarrier() {
        let outcome = reconcile(local: .defaults, stamp: .distantPast, records: [])
        XCTAssertEqual(outcome, .noop)
        XCTAssertTrue(inserted.isEmpty)
    }

    func testNewerCarrierAdopted() {
        let carrier = PolishPromptsRecord(copyEdit: "ipad voice", summary: "s", title: "t",
                                          modifiedAt: Date(timeIntervalSince1970: 5_000))
        let outcome = reconcile(local: .defaults, stamp: Date(timeIntervalSince1970: 1_000),
                                records: [carrier])
        guard case .adoptRemote(let blob, _) = outcome else {
            return XCTFail("expected adoptRemote, got \(outcome)")
        }
        XCTAssertEqual(blob.copyEdit, "ipad voice")
    }

    func testNewerLocalOverwritesCarrier() {
        let carrier = PolishPromptsRecord(copyEdit: "old", summary: "s", title: "t",
                                          modifiedAt: Date(timeIntervalSince1970: 1_000))
        var local = PolishPromptsSyncCore.Blob.defaults
        local.copyEdit = "mac newer"
        let stamp = Date(timeIntervalSince1970: 9_000)
        let outcome = reconcile(local: local, stamp: stamp, records: [carrier])
        XCTAssertEqual(outcome, .pushedLocal(stamp: stamp, seededLocalStamp: false))
        XCTAssertEqual(carrier.copyEdit, "mac newer")
    }

    func testDuplicateCarriersCollapseToNewest() {
        let old = PolishPromptsRecord(copyEdit: "a", summary: "s", title: "t",
                                      modifiedAt: Date(timeIntervalSince1970: 1_000))
        let new = PolishPromptsRecord(copyEdit: "b", summary: "s", title: "t",
                                      modifiedAt: Date(timeIntervalSince1970: 2_000))
        _ = reconcile(local: .defaults, stamp: .distantPast, records: [old, new])
        XCTAssertTrue(deleted.contains(where: { $0 === old }))
        XCTAssertFalse(deleted.contains(where: { $0 === new }))
    }
}
