import XCTest
import SwiftData
@testable import SkriftMobile

/// C273 / R86: Markup (`MarkupQuickLook`, `.updateContents`) writes into the photo file, so the
/// un-annotated original is kept aside before presenting and stays recoverable. Drives the real
/// presenter's delegate (no QuickLook on screen) with the file rewrite Markup would do.
@MainActor
final class MarkupOriginalTests: XCTestCase {

    private let fm = FileManager.default
    private func url(_ name: String) -> URL { AppPaths.recordingsDirectory.appendingPathComponent(name) }

    private var cleanupNames: [String] = []
    override func tearDown() {
        cleanupNames.forEach { try? fm.removeItem(at: url($0)) }
        cleanupNames = []
        super.tearDown()
    }

    private let originalBytes = Data("ORIGINAL-PHOTO-BYTES".utf8)

    /// A memo with one manifest photo on disk, its photo asset captured (as after insert).
    private func makeMemo(_ repo: NotesRepository) -> (id: UUID, photo: String) {
        let id = UUID()
        let photo = "photo_\(id.uuidString)_001.jpg"
        cleanupNames += [photo, MarkupOriginal.originalFilename(for: photo)]
        try? fm.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
        fm.createFile(atPath: url(photo).path, contents: originalBytes)
        repo.insert(Memo.make(id: id, audioFilename: "",
                              metadata: MemoMetadata(imageManifest: [ImageManifestEntry(filename: photo, offsetSeconds: 0)])))
        AssetMaterializer.capture(memoID: id, repository: repo)
        return (id, photo)
    }

    /// One Markup round through the presenter: keep the original, Markup rewrites the file
    /// (`didUpdateContentsOf`), dismiss.
    private func markup(_ repo: NotesRepository, id: UUID, photo: String, writing bytes: Data) {
        let mq = MarkupQuickLook()
        let session = MarkupOriginal.begin(memoID: id, filename: photo, repository: repo)
        XCTAssertNotNil(session, "a photo on disk must get a keep-the-original session")
        let ql = mq.prepare(url: url(photo), original: session) { _ in }
        try? bytes.write(to: url(photo))
        mq.previewController(ql, didUpdateContentsOf: url(photo) as NSURL)
        mq.previewControllerDidDismiss(ql)
    }

    private func originals(_ repo: NotesRepository, _ id: UUID) -> [MemoAsset] {
        repo.assets(forMemo: id).filter { $0.kind == MemoAsset.Kind.photoOriginal }
    }

    func testMarkupThenRevertGivesBackTheOriginalBytes() throws {
        let repo = NotesRepository(inMemory: true)
        let (id, photo) = makeMemo(repo)

        markup(repo, id: id, photo: photo, writing: Data("ANNOTATED".utf8))
        XCTAssertEqual(try Data(contentsOf: url(photo)), Data("ANNOTATED".utf8), "Markup saved into the photo")
        XCTAssertTrue(MarkupOriginal.hasOriginal(for: photo, memoID: id, repository: repo),
                      "the menu must offer the revert after a markup")

        XCTAssertTrue(MarkupOriginal.revert(memoID: id, filename: photo, repository: repo))
        XCTAssertEqual(try Data(contentsOf: url(photo)), originalBytes, "revert gives back the original bytes")
        let photoAsset = repo.assets(forMemo: id).first { $0.kind == MemoAsset.Kind.photo }
        XCTAssertEqual(photoAsset?.blob, originalBytes, "the synced photo blob is reverted too")
    }

    func testOriginalIsASyncedAssetOfItsOwnKind() {
        let repo = NotesRepository(inMemory: true)
        let (id, photo) = makeMemo(repo)
        markup(repo, id: id, photo: photo, writing: Data("ANNOTATED".utf8))

        let kept = originals(repo, id)
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.blob, originalBytes)
        XCTAssertEqual(kept.first?.filename, MarkupOriginal.originalFilename(for: photo))
        XCTAssertEqual(repo.assets(forMemo: id).filter { $0.kind == MemoAsset.Kind.photo }.count, 1,
                       "the original never joins the photo assets")
    }

    func testOnlyTheFirstMarkupKeepsTheOriginal() throws {
        let repo = NotesRepository(inMemory: true)
        let (id, photo) = makeMemo(repo)

        markup(repo, id: id, photo: photo, writing: Data("FIRST-MARKUP".utf8))
        markup(repo, id: id, photo: photo, writing: Data("SECOND-MARKUP".utf8))

        XCTAssertEqual(originals(repo, id).count, 1, "later markups keep the one original")
        XCTAssertEqual(originals(repo, id).first?.blob, originalBytes, "the original is the untouched photo")
        XCTAssertTrue(MarkupOriginal.revert(memoID: id, filename: photo, repository: repo))
        XCTAssertEqual(try Data(contentsOf: url(photo)), originalBytes)
    }

    func testALookWithoutAnEditKeepsNothing() {
        let repo = NotesRepository(inMemory: true)
        let (id, photo) = makeMemo(repo)
        let mq = MarkupQuickLook()
        let ql = mq.prepare(url: url(photo), original: MarkupOriginal.begin(memoID: id, filename: photo, repository: repo)) { _ in }
        mq.previewControllerDidDismiss(ql)

        XCTAssertTrue(originals(repo, id).isEmpty)
        XCTAssertFalse(MarkupOriginal.hasOriginal(for: photo, memoID: id, repository: repo), "no revert offered")
        XCTAssertFalse(fm.fileExists(atPath: url(MarkupOriginal.originalFilename(for: photo)).path),
                       "the aside copy is dropped")
    }

    func testRevertWithoutAnOriginalDoesNothing() throws {
        let repo = NotesRepository(inMemory: true)
        let (id, photo) = makeMemo(repo)
        XCTAssertFalse(MarkupOriginal.revert(memoID: id, filename: photo, repository: repo))
        XCTAssertEqual(try Data(contentsOf: url(photo)), originalBytes)
    }
}
