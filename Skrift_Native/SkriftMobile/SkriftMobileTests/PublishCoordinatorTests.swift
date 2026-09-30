import XCTest
@testable import SkriftMobile

/// PublishCoordinator (standalone Phase 2) — the Obsidian-sink fan-out: which memos publish,
/// policy gating, and paired-mode deferral. Deps injected; writes go to a temp vault.
@MainActor
final class PublishCoordinatorTests: XCTestCase {
    private var sandbox: URL!
    private var vaultRoot: URL!
    private var ledger: ExportLedger!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("skrift-coord-\(UUID().uuidString)")
        vaultRoot = sandbox.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("ledger.json"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: sandbox) }

    /// `processed` = the memos that have a polish. A vault note is a PROCESSED note, so
    /// by default every fixture here is treated as processed and each gate test isolates
    /// the ONE rule it's about.
    private func coordinator(memos: [Memo] = [], enabled: Bool = true, paired: Bool = false,
                             whenPaired: Bool = false,
                             policy: PublishCoordinator.Policy = .all,
                             unprocessed: Set<UUID> = [],
                             enhancement: ((UUID) -> MemoEnhancement?)? = nil) -> PublishCoordinator {
        let publisher = ObsidianPublisher(vaultProvider: { self.vaultRoot }, manageScope: false,
                                          author: "T", peopleProvider: { [] },
                                          ledgerOverride: ledger)
        return PublishCoordinator(
            memosProvider: { memos }, publisher: publisher,
            isMacPaired: { paired }, obsidianEnabled: { enabled },
            publishWhenPaired: { whenPaired }, policy: { policy },
            enhancementProvider: { id in
                if let enhancement { return enhancement(id) }
                return unprocessed.contains(id) ? nil
                    : MemoEnhancement(memoID: id, copyedit: "Polished.", title: "T", summary: "S")
            })
    }

    /// THE RULE (Tuur, 2026-08-11): "only the iPad and the Mac can do that after they
    /// processed the note." An unprocessed memo has nothing to export — the raw ramble
    /// stays inside Skrift. Matches the Mac, whose button says "Process" until a polish
    /// exists and only then "Export to Obsidian".
    func testUnprocessedMemoDoesNotPublish() {
        let m = Memo(title: "T", transcript: "A raw ramble.", significance: 0.5)
        XCTAssertFalse(coordinator(unprocessed: [m.id]).shouldPublish(m),
                       "a vault note is a POLISHED note")
        XCTAssertTrue(coordinator().shouldPublish(m), "…and a processed one publishes")
    }

    /// A pass that produced NOTHING is still a pass (2026-08-26). A bare shared photo, a
    /// three-word note, a link with no comment: processed, no content. The gate used to read
    /// `hasContent`, so these were refused with "Process this note first" forever — and
    /// pressing Process did the identical nothing, because the model had already run.
    func testEmptyPassPublishes() {
        let m = Memo(title: "T", transcript: "Hm.", significance: 0.5)
        let ran = MemoEnhancement(memoID: m.id, processedAt: Date())
        let c = coordinator(memos: [m], enhancement: { _ in ran })
        XCTAssertFalse(ran.hasContent, "nothing to prefer over the raw text")
        XCTAssertTrue(c.shouldPublish(m), "…but it HAS been processed")
        XCTAssertNil(c.exportRefusal(m))
    }

    /// The trap the all-three rule exists for: a note's polished title is also written from
    /// the user's OWN chosen title, so a legacy row carrying only a title was never processed.
    func testMerelyRetitledLegacyRowDoesNotPublish() {
        let m = Memo(title: "T", transcript: "A raw ramble.", significance: 0.5)
        let titleOnly = MemoEnhancement(memoID: m.id, title: "A title I typed")
        let c = coordinator(memos: [m], enhancement: { _ in titleOnly })
        XCTAssertFalse(c.shouldPublish(m))
        XCTAssertEqual(c.exportRefusal(m),
                       "Process this note first — the vault gets the polished note, not the raw one.")
    }

    /// Rows written before `processedAt` existed carry nil and must keep publishing.
    func testLegacyFullyPolishedRowStillPublishes() {
        let m = Memo(title: "T", transcript: "A raw ramble.", significance: 0.5)
        let legacy = MemoEnhancement(memoID: m.id, copyedit: "Polished.", title: "T", summary: "S")
        XCTAssertNil(legacy.processedAt)
        XCTAssertTrue(coordinator(memos: [m], enhancement: { _ in legacy }).shouldPublish(m))
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

    /// `exportRefusal` = `shouldPublish` with its voice on (the silent no-vault iPad,
    /// 2026-08-18): same gates, same order, each naming itself; nil exactly when the
    /// gate would publish. The two live side by side so they can't drift. The first
    /// gate IS the folder — the on/off toggle died the same day (the folder is the
    /// consent; nothing on iOS auto-publishes).
    func testExportRefusalMirrorsTheGate() {
        let c = coordinator()
        let good = Memo(title: "T", transcript: "x"); good.significance = 0.5
        XCTAssertNil(c.exportRefusal(good), "eligible → no refusal")
        XCTAssertTrue(c.shouldPublish(good))

        XCTAssertEqual(coordinator(enabled: false).exportRefusal(good),
                       "No vault folder is set on this device yet. Pick one in Settings → Obsidian.")

        let unrated = coordinator(policy: .importantOnly)
        let raw = Memo(title: "T", transcript: "x")   // significance 0
        XCTAssertTrue(unrated.exportRefusal(raw)!.contains("Rate this note first"))

        let locked = Memo(title: "T", transcript: "x"); locked.significance = 0.5; locked.locked = true
        XCTAssertTrue(c.exportRefusal(locked)!.contains("Locked notes"))

        XCTAssertTrue(coordinator(unprocessed: [good.id]).exportRefusal(good)!
            .contains("Process this note first"))
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
}
