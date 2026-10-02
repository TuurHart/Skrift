import XCTest
@testable import SkriftMobile

/// Q227 (C115): the lock flow's "is this note in your vault?" check asks the same ledger
/// the writer wrote, keyed on the vault HOME (`<pick>/Skrift`), not on the picked root.
/// A pick that is not itself named Skrift is the case where the two keys differ.
@MainActor
final class LockFlowExportedCheckTests: XCTestCase {
    private static let bookmarkKey = "skrift.obsidian.vaultBookmark"
    private var sandbox: URL!
    private var savedBookmark: Data?

    override func setUpWithError() throws {
        savedBookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey)
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("skrift-lockcheck-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if let savedBookmark { UserDefaults.standard.set(savedBookmark, forKey: Self.bookmarkKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.bookmarkKey) }
        try? FileManager.default.removeItem(at: sandbox)
    }

    func testExportedNoteInPickedFolderNotNamedSkriftCountsAsPublished() throws {
        // A pick named something other than "Skrift" and holding no Skrift notes yet, so
        // the writer homes into <pick>/Skrift.
        let pick = sandbox.appendingPathComponent("MyVault", isDirectory: true)
        try FileManager.default.createDirectory(at: pick, withIntermediateDirectories: true)
        try ObsidianVault.setVault(pick)

        let memo = Memo(title: "Lock check", transcript: "Something worth exporting.", significance: 0.5)
        XCTAssertFalse(PublishCoordinator.hasPublished(memo), "nothing exported yet")

        let publisher = ObsidianPublisher(
            vaultProvider: { ObsidianVault.resolveVault() }, manageScope: false,
            author: "T", peopleProvider: { [] },
            enhancementProvider: { id in
                MemoEnhancement(memoID: id, copyedit: "Polished.", title: "Lock check", summary: "S")
            })
        guard case .written = try publisher.publish(memo) else {
            return XCTFail("the export should have written the note")
        }

        XCTAssertTrue(PublishCoordinator.hasPublished(memo),
                      "the lock flow must see a note the writer exported")
    }
}
