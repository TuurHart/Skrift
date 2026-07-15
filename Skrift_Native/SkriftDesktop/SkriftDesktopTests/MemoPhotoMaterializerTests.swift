import XCTest
import Foundation

/// The Mac heals a note whose photos arrived AFTER first ingest: `MemoPhotoMaterializer`
/// writes the missing photo files + refreshes `image_manifest.json` so `[[img_NNN]]`
/// markers resolve (they used to render as literal text — the update path never wrote
/// the image files for an already-ingested memo).
final class MemoPhotoMaterializerTests: XCTestCase {

    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("mpm_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    /// An audio memo's working folder is the PARENT of `pf.path` (the `original.<ext>`).
    private func audioFile() -> PipelineFile {
        PipelineFile(id: UUID().uuidString, filename: "m.m4a",
                     path: folder.appendingPathComponent("original.m4a").path, sourceType: .audio)
    }

    private func memo(manifest: [[String: Any]]) -> Memo {
        let blob = try! JSONSerialization.data(withJSONObject: ["tags": [], "imageManifest": manifest])
        return Memo(id: UUID(), audioFilename: "m.m4a", transcript: "t", metadataData: blob)
    }

    private func photoAsset(_ memo: Memo, _ name: String, bytes: String) -> MemoAsset {
        MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.photo, filename: name, blob: Data(bytes.utf8))
    }

    private func manifestFilenames() -> [String] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("image_manifest.json")),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { $0["filename"] as? String }
    }

    private func imageExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("images").appendingPathComponent(name).path)
    }

    func testWritesMissingPhotosAndManifestThenIdempotent() {
        let m = memo(manifest: [["filename": "p_001.jpg", "offsetSeconds": 0.0],
                                ["filename": "p_002.jpg", "offsetSeconds": 3.0]])
        let assets = [photoAsset(m, "p_001.jpg", bytes: "ONE"), photoAsset(m, "p_002.jpg", bytes: "TWO")]

        XCTAssertTrue(MemoPhotoMaterializer.materializeMissing(memo: m, assets: assets, pf: audioFile()))
        XCTAssertTrue(imageExists("p_001.jpg"))
        XCTAssertTrue(imageExists("p_002.jpg"))
        XCTAssertEqual(manifestFilenames(), ["p_001.jpg", "p_002.jpg"], "marker N → the Nth manifest entry")

        // Second sweep: everything is already on disk → no writes.
        XCTAssertFalse(MemoPhotoMaterializer.materializeMissing(memo: m, assets: assets, pf: audioFile()))
    }

    func testHealsANoteMissingItsLaterPhoto() throws {
        // Simulate the bug's leftover state: first ingest wrote only photo #1 + a 1-entry manifest.
        let imagesDir = folder.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try Data("ONE".utf8).write(to: imagesDir.appendingPathComponent("p_001.jpg"))
        try JSONSerialization.data(withJSONObject: [["filename": "p_001.jpg", "offsetSeconds": 0.0]])
            .write(to: folder.appendingPathComponent("image_manifest.json"))

        // The phone since added photo #2 (marker + manifest entry synced; the file never did).
        let m = memo(manifest: [["filename": "p_001.jpg", "offsetSeconds": 0.0],
                                ["filename": "p_002.jpg", "offsetSeconds": 3.0]])
        let assets = [photoAsset(m, "p_001.jpg", bytes: "ONE"), photoAsset(m, "p_002.jpg", bytes: "TWO")]

        XCTAssertTrue(MemoPhotoMaterializer.materializeMissing(memo: m, assets: assets, pf: audioFile()))
        XCTAssertTrue(imageExists("p_002.jpg"), "the missing later photo is now on disk")
        XCTAssertEqual(manifestFilenames(), ["p_001.jpg", "p_002.jpg"], "manifest grew so img_002 resolves")
    }

    func testNoPhotosIsANoOp() {
        let m = memo(manifest: [])
        XCTAssertFalse(MemoPhotoMaterializer.materializeMissing(memo: m, assets: [], pf: audioFile()))
    }
}
