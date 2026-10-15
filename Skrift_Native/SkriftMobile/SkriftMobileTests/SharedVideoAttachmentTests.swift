import XCTest
import SwiftData
import AVFoundation
import CoreMedia
import CoreVideo
@testable import SkriftMobile

/// Q454 (D210, D202, C71, C63): a shared or imported video lands as the note's inline video
/// attachment (the Q385 block, small by default), its transcript the body. The kept movie
/// (`source.<ext>` on the Mac, `video_<id>.<ext>` here, D188) is that attachment's file, and the
/// frame is its poster: no "Photo · JPEG image" card, no frame photo in the manifest.
@MainActor
final class SharedVideoAttachmentTests: XCTestCase {

    private let fm = FileManager.default
    private func recordings(_ name: String) -> URL { AppPaths.recordingsDirectory.appendingPathComponent(name) }

    private func saver(_ repo: NotesRepository, text: String = "well I might build the kiln") -> MemoSaver {
        MemoSaver(repository: repo, transcriber: SeededTranscriber(text: text),
                  wordTimings: WordTimingsStore(directory: fm.temporaryDirectory
                      .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
                  metadataProvider: MockMetadataService())
    }

    /// A shared movie as the share door hands it over (`shared_<uuid>.mov`, Q439), imported.
    private func importShared(_ repo: NotesRepository, saver: MemoSaver) async throws -> UUID {
        let id = UUID()
        repo.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: Date(),
                         transcriptStatus: .transcribing))
        let source = fm.temporaryDirectory.appendingPathComponent("shared_\(UUID().uuidString).mov")
        try makeVideoFile(at: source, seconds: 0.6)
        addTeardownBlock {
            let fm = FileManager.default
            try? fm.removeItem(at: source)
            for n in [VideoKeep.filename(memoID: id, sourceExtension: "mov"), "photo_\(id.uuidString)_001.jpg",
                      "memo_\(id.uuidString).m4a"] {
                try? fm.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent(n))
            }
        }
        let ok = await saver.processVideo(id: id, source: source, fallbackDate: nil)
        XCTAssertTrue(ok)
        return id
    }

    func testASharedMovieIsOneVideoAttachmentAndNoPhotoCard() async throws {
        let repo = NotesRepository(inMemory: true)
        let id = try await importShared(repo, saver: saver(repo))
        let memo = try XCTUnwrap(repo.memo(id: id))
        let meta = try XCTUnwrap(memo.metadata)

        // The kept movie is the attachment's file: one entry, kind video, same name.
        let kept = try XCTUnwrap(meta.videoFilename)
        XCTAssertEqual(kept, VideoKeep.filename(memoID: id, sourceExtension: "mov"))
        let entries = try XCTUnwrap(meta.attachmentManifest)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.kind, NoteAttachment.Kind.video)
        XCTAssertEqual(entries.first?.filename, kept)
        XCTAssertEqual(entries.first?.name, "Video", "a machine name (shared_<uuid>.mov) never titles the block")
        XCTAssertGreaterThan(entries.first?.byteCount ?? 0, 0)
        XCTAssertNotNil(entries.first?.durationSeconds, "the block carries its length label (pick 5)")
        XCTAssertTrue(fm.fileExists(atPath: recordings(kept).path))

        // No frame photo: no image manifest, no photo file, no [[img_NNN]] in the body.
        XCTAssertTrue(meta.imageManifest?.isEmpty ?? true, "the frame is the poster, never a photo card (D210)")
        XCTAssertFalse(fm.fileExists(atPath: recordings("photo_\(id.uuidString)_001.jpg").path))
        let body = try XCTUnwrap(memo.transcript)
        XCTAssertFalse(body.contains("[[img_"))

        // One video marker, at the top, the transcript below it.
        let markers = NoteAttachment.markers(in: body)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.kind, NoteAttachment.Kind.video)
        XCTAssertEqual(markers.first?.number, 1)
        XCTAssertTrue(body.hasPrefix("[[vid_001]]\n\n"), body)
        XCTAssertTrue(body.contains("kiln"))
        // The list row and the derived title never read the marker ("vid_001 Well I might…").
        XCTAssertFalse(NoteSnippet.plain(body).contains("vid_"))
        XCTAssertEqual(NoteTitle.firstLine(body)?.hasPrefix("well I might"), true)
        XCTAssertNotNil(NoteAttachment.entry(kind: NoteAttachment.Kind.video, number: 1, manifest: entries))
        XCTAssertEqual(meta.sourceType, MemoMetadata.Source.video)

        // D202: small by default.
        XCTAssertEqual(NoteAttachment.size(of: kept, large: meta.largeAttachments), .small)
    }

    func testReTranscribingKeepsExactlyOneVideoBlock() async throws {
        let repo = NotesRepository(inMemory: true)
        let s = saver(repo)
        let id = try await importShared(repo, saver: s)
        await s.runTranscription(id: id)
        let body = try XCTUnwrap(repo.memo(id: id)?.transcript)
        XCTAssertEqual(NoteAttachment.markers(in: body).count, 1, body)
    }

    func testTheMovieSyncsAsOneAsset() async throws {
        let repo = NotesRepository(inMemory: true)
        let id = try await importShared(repo, saver: saver(repo))
        AssetMaterializer.captureMissing(repo)
        let videos = repo.assets(forMemo: id).filter { $0.kind == MemoAsset.Kind.video }
        XCTAssertEqual(videos.count, 1, "the attachment and the kept movie are one file, one asset")
        XCTAssertEqual(videos.first?.filename, repo.memo(id: id)?.metadata?.videoFilename)
        XCTAssertTrue(repo.assets(forMemo: id).filter { $0.kind == MemoAsset.Kind.photo }.isEmpty)
    }

    func testOnlyAKeptMovieLeadsTheBody() {
        let id = UUID()
        let keptName = VideoKeep.filename(memoID: id, sourceExtension: "mp4")
        XCTAssertTrue(NoteAttachment.isKeptMovie(keptName))
        let attached = NoteAttachment.filename(owner: id, number: 1, kind: NoteAttachment.Kind.video, ext: "mov")
        XCTAssertFalse(NoteAttachment.isKeptMovie(attached), "a video the person put in the body stays where it is")

        let userVideo = NoteAttachment.makeEntry(owner: id, number: 1, originalName: "clip.mov", byteCount: 3)
        XCTAssertEqual(NoteAttachment.leadingKeptMovie("words", manifest: [userVideo]), "words")
        let keptEntry = NoteAttachment.keptMovieEntry(filename: keptName, originalName: "kiln.mp4",
                                                      byteCount: 3, durationSeconds: 6)
        XCTAssertEqual(NoteAttachment.leadingKeptMovie("words", manifest: [userVideo, keptEntry]),
                       "[[vid_002]]\n\nwords")
        XCTAssertEqual(NoteAttachment.leadingKeptMovie(nil, manifest: [keptEntry]), "[[vid_001]]")
        XCTAssertEqual(NoteAttachment.leadingKeptMovie("a\n\n[[vid_001]]", manifest: [keptEntry]), "a\n\n[[vid_001]]",
                       "a moved block stays where the person put it")
        XCTAssertEqual(IngressDispatch.shownVideoName(URL(fileURLWithPath: "/t/kiln test.mov")), "kiln test.mov")
        XCTAssertEqual(IngressDispatch.shownVideoName(URL(fileURLWithPath: "/t/shared_\(UUID().uuidString).mov")), "Video")
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
