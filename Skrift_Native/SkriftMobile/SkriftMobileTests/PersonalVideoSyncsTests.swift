import XCTest
import SwiftData
@testable import SkriftMobile

/// Q332 (D188): the Personal boundary is "never goes to Claude", never "never to iCloud". A
/// video's movie (<= 200 MB) is a synced `MemoAsset` (`video`) whatever the destination; filing
/// Personal <-> Project never deletes it; only the PORTFOLIO export copies the movie out, and
/// no movie ever lands in the Obsidian vault. Supersedes the Personal half of
/// `VideoAssetPhoneTests` (Q287).
@MainActor
final class PersonalVideoSyncsTests: XCTestCase {

    private let fm = FileManager.default
    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = fm.temporaryDirectory.appendingPathComponent("skrift-personalvideo-\(UUID().uuidString)")
        try fm.createDirectory(at: sandbox.appendingPathComponent("portfolio"), withIntermediateDirectories: true)
        try fm.createDirectory(at: sandbox.appendingPathComponent("vault"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: sandbox) }

    private func recordings(_ name: String) -> URL { AppPaths.recordingsDirectory.appendingPathComponent(name) }
    private func videoAssets(_ repo: NotesRepository, _ id: UUID) -> [MemoAsset] {
        repo.assets(forMemo: id).filter { $0.kind == MemoAsset.Kind.video }
    }

    private func keptVideoMemo(_ repo: NotesRepository, destination: NoteDestination) -> (Memo, String) {
        let id = UUID()
        let name = VideoKeep.filename(memoID: id, sourceExtension: "mov")
        fm.createFile(atPath: recordings(name).path, contents: Data("MOVIE".utf8))
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: Date(),
                        transcript: "A diary clip, not for anyone.", significance: 0.5)
        var meta = MemoMetadata()
        meta.sourceType = MemoMetadata.Source.video
        meta.videoFilename = name
        memo.metadata = meta
        memo.destination = destination
        repo.insert(memo)
        addTeardownBlock { try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent(name)) }
        return (memo, name)
    }

    // MARK: - a Personal video keeps its synced movie

    func testAPersonalVideoKeepsItsSyncedMovie() {
        let repo = NotesRepository(inMemory: true)
        let (memo, name) = keptVideoMemo(repo, destination: .personal)

        AssetMaterializer.captureMissing(repo)

        let assets = videoAssets(repo, memo.id)
        XCTAssertEqual(assets.count, 1, "Personal syncs through his own iCloud like every other note")
        XCTAssertEqual(assets.first?.filename, name)
        XCTAssertEqual(assets.first?.blob, Data("MOVIE".utf8))
        AssetMaterializer.captureMissing(repo)   // idempotent
        XCTAssertEqual(videoAssets(repo, memo.id).count, 1)
    }

    func testEveryDestinationSyncsTheMovie() {
        for d in NoteDestination.allCases {
            let repo = NotesRepository(inMemory: true)
            let (memo, _) = keptVideoMemo(repo, destination: d)
            AssetMaterializer.captureMissing(repo)
            XCTAssertEqual(videoAssets(repo, memo.id).count, 1, "destination \(d)")
        }
    }

    func testAPersonalMovieRoundTripsToAnotherDevice() {
        let repo = NotesRepository(inMemory: true)
        let (memo, name) = keptVideoMemo(repo, destination: .personal)
        AssetMaterializer.captureMissing(repo)                 // device A
        try? fm.removeItem(at: recordings(name))
        AssetMaterializer.materializeMissing(repo)             // device B
        XCTAssertEqual(try? Data(contentsOf: recordings(name)), Data("MOVIE".utf8))
        XCTAssertEqual(videoAssets(repo, memo.id).count, 1)
    }

    // MARK: - refiling never deletes it

    func testRefilingPersonalAndProjectNeverDeletesTheMovie() {
        let repo = NotesRepository(inMemory: true)
        let (memo, name) = keptVideoMemo(repo, destination: .project)
        AssetMaterializer.captureMissing(repo)
        XCTAssertEqual(videoAssets(repo, memo.id).count, 1)

        for d in [NoteDestination.personal, .project, .personal, .idea, .personal] {
            memo.destination = d
            AssetMaterializer.captureMissing(repo)
            XCTAssertEqual(videoAssets(repo, memo.id).count, 1, "filed \(d): the synced movie stays")
            XCTAssertTrue(fm.fileExists(atPath: recordings(name).path), "filed \(d): the file stays")
        }
    }

    // MARK: - export rule unchanged

    private func publisher(movie: URL?, ledger: String) -> ObsidianPublisher {
        let root = sandbox.appendingPathComponent("portfolio")
        return ObsidianPublisher(
            vaultProvider: { self.sandbox.appendingPathComponent("vault") },
            portfolioFolderProvider: { d in d.portfolioFolder.map { root.appendingPathComponent($0, isDirectory: true) } },
            portfolioScopeRoot: { root },
            manageScope: false,
            author: "Tiuri Hartog",
            peopleProvider: { [] },
            enhancementProvider: { id in
                MemoEnhancement(memoID: id, copyedit: "A diary clip.", title: "Diary clip", summary: "A clip.")
            },
            movieProvider: { _ in movie },
            ledgerOverride: ExportLedger(fileURL: sandbox.appendingPathComponent(ledger)))
    }

    private func videoMemo(destination: NoteDestination) -> Memo {
        let m = Memo(audioFilename: "memo.m4a", recordedAt: Date(),
                     transcript: "A diary clip.", significance: 0.5)
        var meta = MemoMetadata()
        meta.sourceType = MemoMetadata.Source.video
        meta.videoFilename = "video_\(m.id.uuidString).mov"
        m.metadata = meta
        m.destination = destination
        return m
    }

    private func movFiles(under dir: URL) -> [URL] {
        (fm.enumerator(at: dir, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "mov" }
    }

    func testPersonalExportCopiesNoMovie() throws {
        let movie = sandbox.appendingPathComponent("the-movie.mov")
        try Data("MOVIE".utf8).write(to: movie)
        _ = try publisher(movie: movie, ledger: "p.json").publish(videoMemo(destination: .personal))

        XCTAssertTrue(movFiles(under: sandbox.appendingPathComponent("vault")).isEmpty,
                      "no movie ever goes into the Obsidian vault")
        XCTAssertTrue(movFiles(under: sandbox.appendingPathComponent("portfolio")).isEmpty,
                      "a Personal note is not a portfolio note")
    }

    func testPortfolioExportStillCopiesTheMovie() throws {
        let movie = sandbox.appendingPathComponent("the-movie.mov")
        try Data("MOVIE".utf8).write(to: movie)
        let outcome = try publisher(movie: movie, ledger: "q.json").publish(videoMemo(destination: .project))
        guard case .written = outcome else { return XCTFail("expected a write, got \(outcome)") }
        XCTAssertEqual(movFiles(under: sandbox.appendingPathComponent("portfolio")).count, 1)
        XCTAssertTrue(movFiles(under: sandbox.appendingPathComponent("vault")).isEmpty)
    }

    func testTheShareCardNoLongerSaysPersonalDiscardsTheMovie() {
        XCTAssertFalse(VideoKeep.shareCardLine.contains("only if you file"))
        XCTAssertFalse(VideoKeep.shareCardLine(byteCount: 1_000).contains("200 MB"))
        XCTAssertTrue(VideoKeep.shareCardLine(byteCount: VideoKeep.maxBytes + 1).contains("200 MB"))
    }
}
