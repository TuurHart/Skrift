import XCTest
@testable import SkriftMobile

/// Q186 / setexp-92: the phone's publisher honours the note's synced "Include audio in export"
/// switch (`Memo.includeAudioInExport`, set on the Mac) instead of always copying the audio.
/// Bundle text uses the shared `MixedBundle.annotation` rule the Mac drop uses.
final class ExportAudioSettingTests: XCTestCase {
    private var sandbox: URL!
    private var picked: URL!
    private var vaultRoot: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("skrift-q186-\(UUID().uuidString)")
        picked = sandbox.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        vaultRoot = VaultLayout.home(forPicked: picked)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func publisher(audio: Data) -> ObsidianPublisher {
        ObsidianPublisher(vaultProvider: { self.picked }, manageScope: false,
                          author: "Tiuri", peopleProvider: { [] },
                          photosProvider: { _ in [:] },
                          audioProvider: { _ in audio },
                          ledgerOverride: ExportLedger(fileURL: sandbox.appendingPathComponent("ledger.json")))
    }

    func testAudioIsCopiedByDefault() throws {
        let memo = Memo(audioFilename: "memo_x.m4a", title: "Spoken", transcript: "Body.")
        XCTAssertTrue(memo.includeAudioInExport)
        guard case .written = try publisher(audio: Data([1, 2, 3])).publish(memo) else { return XCTFail() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultRoot.appendingPathComponent("Recordings/Spoken.m4a").path))
    }

    func testAudioIsSkippedWhenTheNoteOptsOut() throws {
        let memo = Memo(audioFilename: "memo_x.m4a", title: "Quiet", transcript: "Body.")
        memo.includeAudioInExport = false
        guard case .written = try publisher(audio: Data([1, 2, 3])).publish(memo) else { return XCTFail() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultRoot.appendingPathComponent("Recordings/Quiet.m4a").path),
                       "the Mac's opt-out holds on the phone too")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultRoot.appendingPathComponent("Quiet.md").path))
    }

    func testBundleTextIsTheSharedAnnotationRule() {
        XCTAssertEqual(MixedBundle.annotation(fromTexts: [" Look at this \n"]), "Look at this")
        XCTAssertNil(MixedBundle.annotation(fromTexts: ["   "]))
    }
}
