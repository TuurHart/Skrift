import XCTest
@testable import SkriftMobile

/// PublishCoordinator (standalone Phase 2) — the Obsidian-sink fan-out: which memos publish,
/// policy gating, and paired-mode deferral. Deps injected; writes go to a temp vault.
@MainActor
final class PublishCoordinatorTests: XCTestCase {
    private var sandbox: URL!
    private var vaultRoot: URL!
    private var store: ExportStateStore!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("skrift-coord-\(UUID().uuidString)")
        vaultRoot = sandbox.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        store = ExportStateStore(fileURL: sandbox.appendingPathComponent("state.json"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: sandbox) }

    private func coordinator(memos: [Memo] = [], enabled: Bool = true, paired: Bool = false,
                             whenPaired: Bool = false,
                             policy: PublishCoordinator.Policy = .all) -> PublishCoordinator {
        let publisher = ObsidianPublisher(vaultProvider: { self.vaultRoot }, manageScope: false,
                                          stateStore: store, author: "T", peopleProvider: { [] })
        return PublishCoordinator(memosProvider: { memos }, publisher: publisher,
                                  isMacPaired: { paired }, obsidianEnabled: { enabled },
                                  publishWhenPaired: { whenPaired }, policy: { policy })
    }

    func testGateDisabled() {
        XCTAssertFalse(coordinator(enabled: false).shouldPublish(Memo(title: "T", transcript: "x")))
    }

    func testGateDeleted() {
        let m = Memo(title: "T", transcript: "x"); m.deletedAt = Date()
        XCTAssertFalse(coordinator().shouldPublish(m))
    }

    func testGatePairedDefersToMacUnlessOverridden() {
        let m = Memo(title: "T", transcript: "x")
        XCTAssertFalse(coordinator(paired: true, whenPaired: false).shouldPublish(m), "Mac owns export when paired")
        XCTAssertTrue(coordinator(paired: true, whenPaired: true).shouldPublish(m), "override re-enables phone publish")
    }

    func testGateLocked() {
        let m = Memo(title: "T", transcript: "x")
        m.significance = 0.5
        m.locked = true
        XCTAssertFalse(coordinator().shouldPublish(m), "locked notes never reach the plaintext vault")
        m.locked = false
        XCTAssertTrue(coordinator().shouldPublish(m))
    }

    func testGatePolicy() {
        let unrated = Memo(title: "T", transcript: "x", significance: 0)
        let rated = Memo(title: "T", transcript: "x", significance: 0.5)
        XCTAssertFalse(coordinator(policy: .importantOnly).shouldPublish(unrated))
        XCTAssertTrue(coordinator(policy: .importantOnly).shouldPublish(rated))
        XCTAssertTrue(coordinator(policy: .all).shouldPublish(unrated), "all-policy publishes unrated too")
    }

    func testGateEmptyContent() {
        XCTAssertFalse(coordinator().shouldPublish(Memo()), "nothing to export")
    }

    func testPublishAllSummary() {
        let a = Memo(title: "A", transcript: "Body a.", significance: 0.5)
        let b = Memo(title: "B", transcript: "Body b.", significance: 0.5)
        let c = Memo(title: "C", transcript: "Body c.", significance: 0)   // ineligible under importantOnly
        let summary = coordinator(memos: [a, b, c], policy: .importantOnly).publishAll()
        XCTAssertEqual(summary, PublishCoordinator.Summary(written: 2, ineligible: 1))
    }
}
