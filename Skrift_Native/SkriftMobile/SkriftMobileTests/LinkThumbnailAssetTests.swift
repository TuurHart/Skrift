import XCTest
import SwiftData
@testable import SkriftMobile

/// Q260: the writer side of the link-thumbnail sync. A link capture's downloaded thumbnail
/// (`sharedContent.urlThumbnailUrl`, a relative recordings filename) becomes a `MemoAsset` of
/// kind `thumbnail` — never `photo`, which would join the image manifest — so CloudKit ships it
/// to the Mac's card. A receiving device materializes it back under the same name.
@MainActor
final class LinkThumbnailAssetTests: XCTestCase {

    private let fm = FileManager.default
    private func url(_ name: String) -> URL { AppPaths.recordingsDirectory.appendingPathComponent(name) }

    private func linkMemo(id: UUID, thumb: String?) -> Memo {
        let memo = Memo(id: id, audioFilename: "")
        memo.sharedContent = SharedContent(type: .url, url: "https://example.com/a",
                                           urlTitle: "A page", urlThumbnailUrl: thumb)
        return memo
    }

    func testLinkThumbnailBecomesAThumbnailAsset() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let name = "linkthumb_\(id.uuidString).jpg"
        defer { try? fm.removeItem(at: url(name)) }
        fm.createFile(atPath: url(name).path, contents: Data("JPG".utf8))
        repo.insert(linkMemo(id: id, thumb: name))

        AssetMaterializer.captureMissing(repo)

        let assets = repo.assets(forMemo: id)
        XCTAssertEqual(assets.map(\.kind), [MemoAsset.Kind.thumbnail])
        XCTAssertEqual(assets.first?.filename, name)
        XCTAssertEqual(assets.first?.blob, Data("JPG".utf8))
        XCTAssertTrue(repo.memo(id: id)?.metadata?.imageManifest?.isEmpty ?? true,
                      "a card thumbnail never joins the photo manifest")

        AssetMaterializer.captureMissing(repo)   // idempotent
        XCTAssertEqual(repo.assets(forMemo: id).count, 1)
    }

    func testRemoteOrMissingThumbnailWritesNoAsset() {
        let repo = NotesRepository(inMemory: true)
        repo.insert(linkMemo(id: UUID(), thumb: "https://cdn.example.com/og.jpg"))   // legacy remote value
        repo.insert(linkMemo(id: UUID(), thumb: "linkthumb_\(UUID().uuidString).jpg"))   // file not on disk
        repo.insert(linkMemo(id: UUID(), thumb: nil))

        AssetMaterializer.captureMissing(repo)

        XCTAssertTrue(repo.allAssets().isEmpty)
    }

    func testThumbnailRoundTripsToAnotherDevice() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let name = "linkthumb_\(id.uuidString).jpg"
        defer { try? fm.removeItem(at: url(name)) }
        fm.createFile(atPath: url(name).path, contents: Data("THUMB".utf8))
        repo.insert(linkMemo(id: id, thumb: name))
        AssetMaterializer.captureMissing(repo)          // device A
        try? fm.removeItem(at: url(name))
        AssetMaterializer.materializeMissing(repo)      // device B
        XCTAssertEqual(try? Data(contentsOf: url(name)), Data("THUMB".utf8))
    }
}
