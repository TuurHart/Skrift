import XCTest
import SwiftData
import Foundation

/// Q287 (C63, C148, D172, D188): a video keeps its movie as a synced `MemoAsset` of kind
/// `video` whatever its destination. On the Mac that means: a phone video's asset lands as
/// `source.<ext>` in the note's working folder (where the portfolio export looks), also when it
/// syncs after the first ingest; a Mac-imported video writes its own asset (Personal too),
/// keeps it when refiled, and never keeps a movie over the cap.
@MainActor
final class VideoAssetSyncTests: XCTestCase {

    private let movie = Data([0x00, 0x00, 0x00, 0x14, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74])

    private func pipelineContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func cloudContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                           cloudKitDatabase: .none)))
    }

    /// A phone video memo: audio blob + (optionally) the movie asset named by its metadata.
    private func phoneVideo(withMovie: Bool) -> (Memo, [MemoAsset], String) {
        let id = UUID()
        let movieName = VideoKeep.filename(memoID: id, sourceExtension: "MOV")
        var meta = MemoMetadata()
        meta.sourceType = MemoMetadata.Source.video
        meta.videoFilename = movieName
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", duration: 4, recordedAt: Date(),
                        transcriptStatus: .done, significance: 0.6)
        memo.metadataData = try? JSONEncoder().encode(meta)
        memo.transcript = "A lamp that hangs from one thread."
        var assets = [MemoAsset(memoID: id, kind: MemoAsset.Kind.audio,
                                filename: memo.audioFilename, blob: Data([1, 2, 3]))]
        if withMovie {
            assets.append(MemoAsset(memoID: id, kind: MemoAsset.Kind.video, filename: movieName, blob: movie))
        }
        return (memo, assets, movieName)
    }

    // MARK: - the shared rule

    func testTheKeepRule() {
        XCTAssertEqual(MemoAsset.Kind.video, "video")
        XCTAssertTrue(VideoKeep.fits(byteCount: 199_999_999))
        XCTAssertTrue(VideoKeep.fits(byteCount: VideoKeep.maxBytes))
        XCTAssertFalse(VideoKeep.fits(byteCount: VideoKeep.maxBytes + 1))
        let id = UUID()
        XCTAssertEqual(VideoKeep.filename(memoID: id, sourceExtension: "MOV"), "video_\(id.uuidString).mov")
        XCTAssertEqual(VideoKeep.filename(memoID: id, sourceExtension: ""), "video_\(id.uuidString).mov")
        XCTAssertEqual(VideoKeep.macSourceName(forAssetFilename: "video_x.mp4"), "source.mp4")
        XCTAssertFalse(VideoKeep.shareCardLine(byteCount: 1_000).contains("200 MB"))
        XCTAssertTrue(VideoKeep.shareCardLine(byteCount: 300_000_000).contains("200 MB"),
                      "over the cap the card says the movie cannot be kept")
        XCTAssertFalse(VideoKeep.shareCardLine.contains("isn't kept"), "the old claim is gone")
    }

    // MARK: - phone video arrives on the Mac

    func testPhoneMovieAssetLandsAsSourceBesideTheAudio() throws {
        let (memo, assets, _) = phoneVideo(withMovie: true)
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: assets,
                                                          upload: UploadService(outputDir: makeTempDir()),
                                                          into: try pipelineContext()))
        let folder = try XCTUnwrap(pf.workingFolder)
        let kept = try XCTUnwrap(VaultExporter.keptSourceVideo(in: folder), "the export looks for source.<ext>")
        XCTAssertEqual(kept.lastPathComponent, "source.mov")
        XCTAssertEqual(try Data(contentsOf: kept), movie)
    }

    func testNoMovieAssetMeansNoMovieFile() throws {
        let (memo, assets, _) = phoneVideo(withMovie: false)   // a Personal video: nothing synced
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: assets,
                                                          upload: UploadService(outputDir: makeTempDir()),
                                                          into: try pipelineContext()))
        XCTAssertNil(VaultExporter.keptSourceVideo(in: try XCTUnwrap(pf.workingFolder)))
    }

    func testMovieThatSyncsAfterTheFirstIngestIsHealed() throws {
        let (memo, assets, name) = phoneVideo(withMovie: false)
        let pf = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: assets,
                                                          upload: UploadService(outputDir: makeTempDir()),
                                                          into: try pipelineContext()))
        let folder = try XCTUnwrap(pf.workingFolder)
        XCTAssertNil(VaultExporter.keptSourceVideo(in: folder))

        let late = MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.video, filename: name, blob: movie)
        XCTAssertTrue(MemoPhotoMaterializer.materializeMissing(memo: memo, pf: pf, fetchAssets: { [late] }))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(VaultExporter.keptSourceVideo(in: folder))), movie)

        // Steady state: the movie is on disk, so the sweep never fetches asset rows again.
        var fetched = false
        XCTAssertFalse(MemoPhotoMaterializer.materializeMissing(memo: memo, pf: pf,
                                                                fetchAssets: { fetched = true; return [late] }))
        XCTAssertFalse(fetched)
    }

    // MARK: - Mac-imported video goes out

    /// The working folder `IngestService.ingestVideo` writes: original.m4a + source.<ext>.
    private func macVideoRow(movieBytes: Data = Data([9, 9, 9, 9]), destination: NoteDestination,
                             keepMovie: Bool = true) throws -> PipelineFile {
        let root = makeTempDir()
        let folder = root.appendingPathComponent("macvideo", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("AUDIO".utf8).write(to: folder.appendingPathComponent("original.m4a"))
        if keepMovie { try movieBytes.write(to: folder.appendingPathComponent("source.mp4")) }
        let pf = PipelineFile(id: UUID().uuidString, filename: "IMG_0042.MP4",
                              path: folder.appendingPathComponent("original.m4a").path,
                              sourceType: .audio, uploadedAt: Date())
        pf.mediaSource = "video"
        pf.destination = destination
        return pf
    }

    private func videoAssets(_ ctx: ModelContext, _ id: UUID) throws -> [MemoAsset] {
        let kind = MemoAsset.Kind.video
        return try ctx.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id && $0.kind == kind }))
    }

    func testMacVideoFiledIdeaWritesTheMovieAssetAndNamesIt() throws {
        let ctx = try cloudContext()
        let pf = try macVideoRow(destination: .idea)
        let memo = try XCTUnwrap(try MacMemoAuthor.author(for: pf, audioURL: URL(fileURLWithPath: pf.path), into: ctx))
        let name = try XCTUnwrap(memo.metadata?.videoFilename)
        XCTAssertEqual(name, VideoKeep.filename(memoID: memo.id, sourceExtension: "mp4"))
        let assets = try videoAssets(ctx, memo.id)
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets.first?.filename, name)
        XCTAssertEqual(assets.first?.blob, Data([9, 9, 9, 9]))
    }

    func testMacVideoFiledPersonalSyncsNoMovie() throws {
        let ctx = try cloudContext()
        let pf = try macVideoRow(destination: .personal)
        let memo = try XCTUnwrap(try MacMemoAuthor.author(for: pf, audioURL: URL(fileURLWithPath: pf.path), into: ctx))
        XCTAssertEqual(try videoAssets(ctx, memo.id).count, 1, "D188: a Personal video syncs like every other note")
    }

    func testFilingLaterWritesTheMovieAndFilingBackRemovesIt() throws {
        let ctx = try cloudContext()
        let pf = try macVideoRow(destination: .personal)
        let memo = try XCTUnwrap(try MacMemoAuthor.author(for: pf, audioURL: URL(fileURLWithPath: pf.path), into: ctx))
        XCTAssertEqual(try videoAssets(ctx, memo.id).count, 1, "D188: authored Personal, the movie already syncs")

        pf.destination = .project
        // Idempotent: the asset is already there, so a pass inserts nothing.
        XCTAssertFalse(MacMemoAuthor.syncVideoAsset(for: pf, memo: memo, in: ctx))
        try ctx.save()
        XCTAssertEqual(try videoAssets(ctx, memo.id).count, 1)

        pf.destination = .personal
        XCTAssertFalse(MacMemoAuthor.syncVideoAsset(for: pf, memo: memo, in: ctx))
        try ctx.save()
        XCTAssertEqual(try videoAssets(ctx, memo.id).count, 1, "filed back to Personal: the synced blob stays (D188)")
        XCTAssertNotNil(VaultExporter.keptSourceVideo(in: try XCTUnwrap(pf.workingFolder)),
                        "the local file stays on this Mac")
    }

    func testAVideoWithNoKeptMovieNamesNoMovie() throws {
        let ctx = try cloudContext()
        let pf = try macVideoRow(destination: .idea, keepMovie: false)   // over the cap or the copy failed
        let memo = try XCTUnwrap(try MacMemoAuthor.author(for: pf, audioURL: URL(fileURLWithPath: pf.path), into: ctx))
        XCTAssertNil(memo.metadata?.videoFilename)
        XCTAssertTrue(try videoAssets(ctx, memo.id).isEmpty)
    }
}
