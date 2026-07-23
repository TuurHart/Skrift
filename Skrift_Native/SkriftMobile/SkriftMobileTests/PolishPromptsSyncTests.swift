import XCTest
import SwiftData
@testable import SkriftMobile

/// The prompt-sync LWW core (shared with the Mac — twin suite there) + the
/// iPad-side `PolishPromptsStore` semantics. Mirrors `VocabularyCloudSyncTests`'
/// shape: pure reconcile over in-memory records, store round-trips over a
/// throwaway UserDefaults suite.
final class PolishPromptsSyncTests: XCTestCase {

    private var inserted: [PolishPromptsRecord] = []
    private var deleted: [PolishPromptsRecord] = []

    override func setUp() {
        super.setUp()
        inserted = []; deleted = []
    }

    private func reconcile(local: PolishPromptsSyncCore.Blob, stamp: Date,
                           records: [PolishPromptsRecord],
                           now: Date = Date()) -> PolishPromptsSyncCore.Outcome {
        PolishPromptsSyncCore.reconcile(
            localBlob: local, localModifiedAt: stamp, records: records, now: now,
            insert: { self.inserted.append($0) },
            delete: { self.deleted.append($0) })
    }

    private func edited(_ text: String) -> PolishPromptsSyncCore.Blob {
        var blob = PolishPromptsSyncCore.Blob.defaults
        blob.copyEdit = text
        return blob
    }

    // MARK: - fresh-device guard

    func testFreshDeviceAllDefaultMintsNoCarrier() {
        let outcome = reconcile(local: .defaults, stamp: .distantPast, records: [])
        XCTAssertEqual(outcome, .noop)
        XCTAssertTrue(inserted.isEmpty, "a default-@-now carrier would clobber real tuning via LWW")
    }

    func testEditedLocalWithNoCarrierPushes() {
        let stamp = Date(timeIntervalSince1970: 1_000_000)
        let outcome = reconcile(local: edited("my voice"), stamp: stamp, records: [])
        XCTAssertEqual(outcome, .pushedLocal(stamp: stamp, seededLocalStamp: false))
        XCTAssertEqual(inserted.first?.copyEdit, "my voice")
    }

    func testDefaultBlobWithRealStampStillPropagates() {
        // A genuine "reset to defaults" has a real stamp — it must reach the carrier.
        let stamp = Date(timeIntervalSince1970: 2_000_000)
        let outcome = reconcile(local: .defaults, stamp: stamp, records: [])
        XCTAssertEqual(outcome, .pushedLocal(stamp: stamp, seededLocalStamp: false))
    }

    // MARK: - LWW both directions + collapse

    func testNewerCarrierAdopted() {
        let carrier = PolishPromptsRecord(copyEdit: "mac voice", summary: "s", title: "t",
                                          modifiedAt: Date(timeIntervalSince1970: 5_000))
        let outcome = reconcile(local: .defaults, stamp: Date(timeIntervalSince1970: 1_000),
                                records: [carrier])
        guard case .adoptRemote(let blob, let ts) = outcome else {
            return XCTFail("expected adoptRemote, got \(outcome)")
        }
        XCTAssertEqual(blob.copyEdit, "mac voice")
        XCTAssertEqual(ts, Date(timeIntervalSince1970: 5_000))
    }

    func testNewerLocalOverwritesCarrier() {
        let carrier = PolishPromptsRecord(copyEdit: "old", summary: "s", title: "t",
                                          modifiedAt: Date(timeIntervalSince1970: 1_000))
        let stamp = Date(timeIntervalSince1970: 9_000)
        let outcome = reconcile(local: edited("newer"), stamp: stamp, records: [carrier])
        XCTAssertEqual(outcome, .pushedLocal(stamp: stamp, seededLocalStamp: false))
        XCTAssertEqual(carrier.copyEdit, "newer")
        XCTAssertEqual(carrier.modifiedAt, stamp)
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

    // MARK: - the iPad store (UserDefaults round-trips)

    private func freshDefaults() -> UserDefaults {
        let name = "PolishPromptsSyncTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testStoreDefaultsUntilEdited() {
        let d = freshDefaults()
        XCTAssertEqual(PolishPromptsStore.copyEdit(defaults: d), PolishPrompts.copyEdit)
        XCTAssertEqual(PolishPromptsStore.modifiedAt(defaults: d), .distantPast)
        XCTAssertFalse(PolishPromptsStore.isEdited(.copyEdit, defaults: d))
    }

    func testStoreEditStampsAndReads() {
        let d = freshDefaults()
        PolishPromptsStore.setText("tighter, drier", for: .summary, defaults: d)
        XCTAssertEqual(PolishPromptsStore.summary(defaults: d), "tighter, drier")
        XCTAssertTrue(PolishPromptsStore.isEdited(.summary, defaults: d))
        XCTAssertNotEqual(PolishPromptsStore.modifiedAt(defaults: d), .distantPast)
        // The untouched prompts keep the shared defaults.
        XCTAssertEqual(PolishPromptsStore.copyEdit(defaults: d), PolishPrompts.copyEdit)
    }

    func testStoreResetToDefaultClearsOverrideButKeepsStamp() {
        let d = freshDefaults()
        PolishPromptsStore.setText("custom", for: .title, defaults: d)
        PolishPromptsStore.setText(PolishPrompts.title, for: .title, defaults: d)
        XCTAssertFalse(PolishPromptsStore.isEdited(.title, defaults: d))
        // The reset is a real edit — its stamp must win LWW so it propagates.
        XCTAssertNotEqual(PolishPromptsStore.modifiedAt(defaults: d), .distantPast)
    }

    func testAdoptSyncedDoesNotMintANewEditStamp() {
        let d = freshDefaults()
        let ts = Date(timeIntervalSince1970: 7_777)
        var blob = PolishPromptsSyncCore.Blob.defaults
        blob.copyEdit = "mac voice"
        PolishPromptsStore.adoptSynced(blob, modifiedAt: ts, defaults: d)
        XCTAssertEqual(PolishPromptsStore.copyEdit(defaults: d), "mac voice")
        XCTAssertEqual(PolishPromptsStore.modifiedAt(defaults: d), ts)
    }
}
