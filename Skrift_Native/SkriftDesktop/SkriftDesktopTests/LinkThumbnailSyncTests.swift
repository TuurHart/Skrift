import XCTest
import SwiftData
import Foundation

/// Q260 (C78): a phone link capture's downloaded thumbnail travels as a `MemoAsset` of kind
/// `thumbnail` and lands beside the Mac's capture folder, where `captureThumbnailURL` finds it —
/// at first ingest, and through the late-asset heal when the row synced after the Memo.
final class LinkThumbnailSyncTests: XCTestCase {

    private func memoryContext() throws -> ModelContext {
        let container = try ModelContainer(for: PipelineFile.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func linkMemo(thumb: String?) -> Memo {
        let memo = Memo(id: UUID(), audioFilename: "", recordedAt: Date(),
                        transcriptStatus: .done, significance: 0.6, annotationText: "Read later.")
        var obj: [String: Any] = ["type": "url", "url": "https://example.com/a", "urlTitle": "A page"]
        if let thumb { obj["urlThumbnailUrl"] = thumb }
        memo.sharedContentData = try! JSONSerialization.data(withJSONObject: obj)
        return memo
    }

    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

    func testThumbnailAssetLandsWhereTheCardLooks() throws {
        let name = "linkthumb_\(UUID().uuidString).jpg"
        let memo = linkMemo(thumb: name)
        let asset = MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.thumbnail, filename: name, blob: jpeg)
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: [asset],
                                                          upload: UploadService(outputDir: makeTempDir()),
                                                          into: try memoryContext()))
        let url = try XCTUnwrap(pf.captureThumbnailURL, "the card must find the synced thumbnail")
        XCTAssertEqual(url.lastPathComponent, name)
        XCTAssertEqual(try Data(contentsOf: url), jpeg)
        // Never a photo: no images/ folder, no manifest, so no [[img_NNN]] marker can claim it.
        let folder = try XCTUnwrap(pf.workingFolder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("images").path))
        XCTAssertTrue(pf.captureImageURLs.isEmpty)
    }

    func testLateThumbnailAssetIsHealedIntoTheCaptureFolder() throws {
        let name = "linkthumb_\(UUID().uuidString).jpg"
        let memo = linkMemo(thumb: name)
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: [],
                                                          upload: UploadService(outputDir: makeTempDir()),
                                                          into: try memoryContext()))
        XCTAssertNil(pf.captureThumbnailURL, "no asset yet → globe tile")

        let asset = MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.thumbnail, filename: name, blob: jpeg)
        XCTAssertTrue(MemoPhotoMaterializer.materializeMissing(memo: memo, pf: pf, fetchAssets: { [asset] }))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(pf.captureThumbnailURL)), jpeg)

        // Steady state: the file exists, so the sweep never fetches asset rows again.
        var fetched = false
        XCTAssertFalse(MemoPhotoMaterializer.materializeMissing(memo: memo, pf: pf,
                                                                fetchAssets: { fetched = true; return [asset] }))
        XCTAssertFalse(fetched)
    }

    func testLegacyRemoteThumbnailIsNeverFetchedOrWritten() throws {
        let memo = linkMemo(thumb: "https://cdn.example.com/og.jpg")
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: [],
                                                          upload: UploadService(outputDir: makeTempDir()),
                                                          into: try memoryContext()))
        var fetched = false
        XCTAssertFalse(MemoPhotoMaterializer.materializeMissing(memo: memo, pf: pf,
                                                                fetchAssets: { fetched = true; return [] }))
        XCTAssertFalse(fetched)
        XCTAssertNil(pf.captureThumbnailURL)
        XCTAssertNil(MemoAsset.Kind.linkThumbnailFilename(memo.sharedContent))
    }

    func testAMemoWithoutAThumbnailWritesNoThumbnailFile() throws {
        let memo = linkMemo(thumb: nil)
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: [],
                                                          upload: UploadService(outputDir: makeTempDir()),
                                                          into: try memoryContext()))
        XCTAssertNil(pf.captureThumbnailURL)
        let folder = try XCTUnwrap(pf.workingFolder)
        let jpgs = (try FileManager.default.contentsOfDirectory(atPath: folder.path)).filter { $0.hasSuffix(".jpg") }
        XCTAssertTrue(jpgs.isEmpty)
    }
}
