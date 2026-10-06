import XCTest
import SwiftData
import AVFoundation
import CoreMedia
import CoreVideo
@testable import SkriftMobile

/// Q287 (C63, C148, D172): a video filed Inspiration / Idea / Project keeps its movie as a
/// synced `MemoAsset` (`video`), and whichever device exports copies it beside the portfolio
/// note. A Personal video's movie never syncs and the Obsidian vault never gets one; a movie
/// over ~200 MB is refused; deleting the note deletes the movie.
@MainActor
final class VideoAssetPhoneTests: XCTestCase {

    private let fm = FileManager.default
    private func recordings(_ name: String) -> URL { AppPaths.recordingsDirectory.appendingPathComponent(name) }
    private func videoAssets(_ repo: NotesRepository, _ id: UUID) -> [MemoAsset] {
        repo.assets(forMemo: id).filter { $0.kind == MemoAsset.Kind.video }
    }

    /// A video memo whose kept movie is on disk, like `MemoSaver.processVideo` leaves it.
    private func keptVideoMemo(_ repo: NotesRepository, bytes: Data = Data("MOVIE".utf8),
                               destination: NoteDestination = .personal) -> (Memo, String) {
        let id = UUID()
        let name = VideoKeep.filename(memoID: id, sourceExtension: "mov")
        fm.createFile(atPath: recordings(name).path, contents: bytes)
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: Date(),
                        transcript: "A bridge that looks like a ribbon.", significance: 0.5)
        var meta = MemoMetadata()
        meta.sourceType = MemoMetadata.Source.video
        meta.videoFilename = name
        memo.metadata = meta
        memo.destination = destination
        repo.insert(memo)
        addTeardownBlock { try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent(name)) }
        return (memo, name)
    }

    // MARK: - the import keeps the movie

    func testImportKeepsTheMovieBesideTheMemo() async throws {
        let repo = NotesRepository(inMemory: true)
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "a lamp"),
            wordTimings: WordTimingsStore(directory: fm.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService())
        let id = UUID()
        repo.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                         recordedAt: Date(), transcriptStatus: .transcribing))
        let source = fm.temporaryDirectory.appendingPathComponent("lamp_\(UUID().uuidString).mov")
        try makeVideoFile(at: source, seconds: 0.5)
        defer { try? fm.removeItem(at: source) }

        let ok = await saver.processVideo(id: id, source: source, fallbackDate: nil)
        XCTAssertTrue(ok)

        let name = try XCTUnwrap(repo.memo(id: id)?.metadata?.videoFilename)
        XCTAssertEqual(name, VideoKeep.filename(memoID: id, sourceExtension: "mov"))
        addTeardownBlock { try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent(name)) }
        XCTAssertEqual(try Data(contentsOf: recordings(name)), try Data(contentsOf: source),
                       "the user's own file is copied, byte for byte")
        XCTAssertTrue(fm.fileExists(atPath: source.path), "the source is never moved or deleted")
        // Still a normal note: audio, frame, transcript.
        XCTAssertEqual(repo.memo(id: id)?.metadata?.sourceType, MemoMetadata.Source.video)
        XCTAssertEqual(repo.memo(id: id)?.metadata?.imageManifest?.count, 1)
    }

    func testAMovieOverTheCapIsRefused() async throws {
        let big = fm.temporaryDirectory.appendingPathComponent("big_\(UUID().uuidString).mov")
        fm.createFile(atPath: big.path, contents: nil)
        let h = try FileHandle(forWritingTo: big)
        try h.truncate(atOffset: UInt64(VideoKeep.maxBytes) + 1)   // sparse: no real 200 MB
        try h.close()
        defer { try? fm.removeItem(at: big) }

        let id = UUID()
        let kept = await MemoSaver.keepMovie(source: big, memoID: id)
        XCTAssertNil(kept)
        XCTAssertFalse(fm.fileExists(atPath: recordings(VideoKeep.filename(memoID: id, sourceExtension: "mov")).path))
        XCTAssertTrue(VideoKeep.shareCardLine(byteCount: VideoKeep.maxBytes + 1).contains("200 MB"),
                      "the share card says so before the import")
    }

    // MARK: - sync follows the destination

    func testMovieSyncsOnlyWhileFiledToThePortfolio() {
        let repo = NotesRepository(inMemory: true)
        let (memo, name) = keptVideoMemo(repo)

        AssetMaterializer.captureMissing(repo)
        XCTAssertTrue(videoAssets(repo, memo.id).isEmpty, "a Personal video never reaches iCloud")

        memo.destination = .idea
        AssetMaterializer.captureMissing(repo)
        let assets = videoAssets(repo, memo.id)
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets.first?.filename, name)
        XCTAssertEqual(assets.first?.blob, Data("MOVIE".utf8))
        XCTAssertTrue(repo.memo(id: memo.id)?.metadata?.imageManifest?.isEmpty ?? true,
                      "the movie is not a photo: no [[img_NNN]] marker can claim it")

        AssetMaterializer.captureMissing(repo)   // idempotent
        XCTAssertEqual(videoAssets(repo, memo.id).count, 1)

        memo.destination = .personal
        AssetMaterializer.captureMissing(repo)
        XCTAssertTrue(videoAssets(repo, memo.id).isEmpty, "filed back to Personal: the synced blob goes")
        XCTAssertTrue(fm.fileExists(atPath: recordings(name).path), "the file stays on this device")
    }

    func testMovieRoundTripsToAnotherDevice() {
        let repo = NotesRepository(inMemory: true)
        let (memo, name) = keptVideoMemo(repo, destination: .project)
        AssetMaterializer.captureMissing(repo)                 // device A
        XCTAssertEqual(videoAssets(repo, memo.id).count, 1)
        try? fm.removeItem(at: recordings(name))
        AssetMaterializer.materializeMissing(repo)             // device B
        XCTAssertEqual(try? Data(contentsOf: recordings(name)), Data("MOVIE".utf8))
    }

    // MARK: - the export copies it

    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = fm.temporaryDirectory.appendingPathComponent("skrift-videoasset-\(UUID().uuidString)")
        try fm.createDirectory(at: sandbox.appendingPathComponent("portfolio"), withIntermediateDirectories: true)
        try fm.createDirectory(at: sandbox.appendingPathComponent("vault"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: sandbox) }

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
                MemoEnhancement(memoID: id, copyedit: "A lamp from one thread.", title: "The thread lamp",
                                summary: "A lamp worth copying.")
            },
            movieProvider: { _ in movie },
            ledgerOverride: ExportLedger(fileURL: sandbox.appendingPathComponent(ledger)))
    }

    private func videoMemo(destination: NoteDestination) -> Memo {
        let m = Memo(audioFilename: "memo.m4a", recordedAt: Date(),
                     transcript: "A lamp from one thread.", significance: 0.5)
        var meta = MemoMetadata()
        meta.sourceType = MemoMetadata.Source.video
        meta.videoFilename = "video_\(m.id.uuidString).mov"
        m.metadata = meta
        m.destination = destination
        return m
    }

    func testPortfolioExportCopiesTheMovieBesideTheNote() throws {
        let movie = sandbox.appendingPathComponent("the-movie.mov")
        try Data("MOVIE".utf8).write(to: movie)
        let outcome = try publisher(movie: movie, ledger: "a.json").publish(videoMemo(destination: .idea))
        guard case .written(let rel) = outcome else { return XCTFail("expected a write, got \(outcome)") }

        let stem = (rel as NSString).deletingPathExtension
        let copied = sandbox.appendingPathComponent("portfolio/_ideas/\(stem).mov")
        XCTAssertEqual(try? Data(contentsOf: copied), Data("MOVIE".utf8), "the pair travels together")
    }

    func testPersonalExportNeverGetsTheMovie() throws {
        let movie = sandbox.appendingPathComponent("the-movie.mov")
        try Data("MOVIE".utf8).write(to: movie)
        _ = try publisher(movie: movie, ledger: "b.json").publish(videoMemo(destination: .personal))

        let found = (fm.enumerator(at: sandbox.appendingPathComponent("vault"),
                                   includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "mov" }
        XCTAssertTrue(found.isEmpty, "a 200 MB clip has no business in the notes vault")
    }

    func testPortfolioNoteWithNoMovieOnThisDeviceStillExports() throws {
        let outcome = try publisher(movie: nil, ledger: "c.json").publish(videoMemo(destination: .project))
        guard case .written = outcome else { return XCTFail("expected a write, got \(outcome)") }
    }

    // MARK: - delete

    func testPermanentDeleteRemovesTheMovieFileAndAsset() {
        let repo = NotesRepository(inMemory: true)
        let (memo, name) = keptVideoMemo(repo, destination: .idea)
        AssetMaterializer.captureMissing(repo)
        XCTAssertEqual(videoAssets(repo, memo.id).count, 1)

        repo.permanentlyDelete(memo)

        XCTAssertFalse(fm.fileExists(atPath: recordings(name).path))
        XCTAssertTrue(repo.assets(forMemo: memo.id).isEmpty)
    }

    // MARK: - tiny synthetic movie (video + silent AAC audio)

    private func makeVideoFile(at url: URL, seconds: Double) throws {
        try? fm.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        videoInput.expectsMediaDataInRealTime = false
        let pixelAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput,
                                                           sourcePixelBufferAttributes: pixelAttrs)
        writer.add(videoInput)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
        audioInput.expectsMediaDataInRealTime = false
        writer.add(audioInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, pixelAttrs as CFDictionary, &pb)
        if let pb {
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
                memset(base, 0x7F, CVPixelBufferGetBytesPerRow(pb) * CVPixelBufferGetHeight(pb))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            for i in 0..<max(1, Int(seconds * 30)) {
                while !videoInput.isReadyForMoreMediaData { usleep(1_000) }
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
            }
        }
        videoInput.markAsFinished()
        appendSilence(to: audioInput, seconds: seconds)
        audioInput.markAsFinished()

        let done = expectation(description: "writer finish")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(writer.status, .completed, "video writer failed: \(String(describing: writer.error))")
    }

    private func appendSilence(to input: AVAssetWriterInput, seconds: Double) {
        let sampleRate = 44_100
        let frameCount = Int(Double(sampleRate) * seconds)
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0,
                                       layout: nil, magicCookieSize: 0, magicCookie: nil,
                                       extensions: nil, formatDescriptionOut: &format)
        guard let format else { return }
        let byteCount = frameCount * 2
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                           blockLength: byteCount, blockAllocator: kCFAllocatorDefault,
                                           customBlockSource: nil, offsetToData: 0, dataLength: byteCount,
                                           flags: 0, blockBufferOut: &block)
        guard let block else { return }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
                                        presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: block, dataReady: true,
                             makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
                             sampleCount: frameCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                             sampleSizeEntryCount: 1, sampleSizeArray: [2], sampleBufferOut: &sample)
        if let sample {
            while !input.isReadyForMoreMediaData { usleep(1_000) }
            input.append(sample)
        }
    }
}
