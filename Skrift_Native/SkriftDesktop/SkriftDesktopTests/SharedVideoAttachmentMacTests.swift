import XCTest
import SwiftData
import AVFoundation
import CoreMedia
import CoreVideo

/// Q454 (D210, C63) on the Mac import path: an imported video's kept movie (`source.<ext>`) is the
/// note's inline video attachment (`attachment_manifest.json`, the phone's shape), no frame
/// picture is written, the block reads the kept movie, and the vault export never gets it.
@MainActor
final class SharedVideoAttachmentMacTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PipelineFile.self, configurations: config)
        return ModelContext(container)
    }

    func testImportedVideoIsOneVideoAttachmentAndNoFramePicture() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let videoURL = work.appendingPathComponent("kiln test.mov")
        try makeVideoFile(at: videoURL, seconds: 1.0, withAudio: true)

        let ctx = try makeContext()
        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [videoURL], into: ctx)
        let pf = try XCTUnwrap(created.first)
        let folder = try XCTUnwrap(pf.workingFolder)
        let memoID = try XCTUnwrap(UUID(uuidString: pf.id))

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("images").appendingPathComponent("img_001.jpg").path),
            "the frame is the block's poster, never a picture (D210)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("image_manifest.json").path))

        let entries = MacNoteAttachments.manifest(in: folder)
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.kind, NoteAttachment.Kind.video)
        XCTAssertEqual(entry.filename, VideoKeep.filename(memoID: memoID, sourceExtension: "mov"))
        XCTAssertEqual(entry.name, "kiln test.mov")
        XCTAssertNotNil(entry.durationSeconds)
        XCTAssertTrue(NoteAttachment.isKeptMovie(entry.filename))

        // The block plays the kept movie itself.
        let file = try XCTUnwrap(MacNoteAttachments.fileURL(entry, working: folder))
        XCTAssertEqual(file.lastPathComponent, "source.mov")

        // The synced memo names the same file for both roles: the attachment and the kept movie.
        let shape = ReconcileV2.Author.Shape(pf, memoID: memoID)
        let meta = try XCTUnwrap(shape.metadata.flatMap { try? JSONDecoder().decode(MemoMetadata.self, from: $0) })
        XCTAssertEqual(meta.attachmentManifest?.map(\.filename), [entry.filename])
        XCTAssertEqual(meta.videoFilename, entry.filename)
        XCTAssertTrue(meta.imageManifest?.isEmpty ?? true)
        XCTAssertTrue(shape.photos.isEmpty)

        // The body leads with the one video marker.
        XCTAssertEqual(NoteAttachment.leadingKeptMovie("well I might", manifest: entries), "[[vid_001]]\n\nwell I might")
    }

    func testTheKeptMovieNeverGoesToTheVault() throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let id = UUID()
        let entry = NoteAttachment.keptMovieEntry(filename: VideoKeep.filename(memoID: id, sourceExtension: "mov"),
                                                  originalName: "Video", byteCount: 5, durationSeconds: 6)
        try JSONEncoder().encode([entry]).write(to: work.appendingPathComponent(MacNoteAttachments.manifestName))
        try Data("MOVIE".utf8).write(to: work.appendingPathComponent("source.mov"))
        // Even a stray copy under attachments/ is not exported.
        try FileManager.default.createDirectory(at: MacNoteAttachments.folder(in: work), withIntermediateDirectories: true)
        try Data("MOVIE".utf8).write(to: MacNoteAttachments.folder(in: work).appendingPathComponent(entry.filename))

        let out = try ExportV2Test.export(body: "[[vid_001]]\n\nwords", working: work, title: "Note")
        XCTAssertEqual(out.result.imageCount, 0)
        XCTAssertTrue(out.files.isEmpty, "C63: no video goes to the Obsidian vault: \(out.files)")
        XCTAssertFalse(out.body.contains("vid_001"))
        XCTAssertTrue(out.body.contains("words"))
    }

    // MARK: - tiny real video (copied from VideoIngestTests)

    /// Generate a tiny real video file (one solid frame, optional silent audio) via
    /// AVAssetWriter — gives a genuine video track to detect/extract from. When
    /// `creationDate` is set, it's written as the QuickTime `creationDate` metadata.
    private func makeVideoFile(at url: URL, seconds: Double, withAudio: Bool, creationDate: Date? = nil) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        if let creationDate {
            let item = AVMutableMetadataItem()
            item.identifier = .quickTimeMetadataCreationDate
            item.keySpace = .quickTimeMetadata
            item.value = ISO8601DateFormatter().string(from: creationDate) as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            writer.metadata = [item]
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64,
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        let pixelAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: pixelAttrs)
        XCTAssertTrue(writer.canAdd(videoInput)); writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if withAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ]
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            ai.expectsMediaDataInRealTime = false
            XCTAssertTrue(writer.canAdd(ai)); writer.add(ai)
            audioInput = ai
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // One video frame held for the whole duration.
        let fps: Int32 = 30
        let frameCount = max(1, Int(seconds * Double(fps)))
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, pixelAttrs as CFDictionary, &pb)
        if let pb {
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
                memset(base, 0x7F, CVPixelBufferGetBytesPerRow(pb) * CVPixelBufferGetHeight(pb))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            for i in 0..<frameCount {
                while !videoInput.isReadyForMoreMediaData { usleep(1_000) }
                let t = CMTime(value: CMTimeValue(i), timescale: fps)
                adaptor.append(pb, withPresentationTime: t)
            }
        }
        videoInput.markAsFinished()

        if let audioInput {
            // Append a silent AAC buffer covering the duration.
            appendSilentAudio(to: audioInput, seconds: seconds)
            audioInput.markAsFinished()
        }

        let done = expectation(description: "writer finish")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(writer.status, .completed, "video writer failed: \(String(describing: writer.error))")
    }

    /// Feed one silent PCM sample buffer into an audio writer input.
    private func appendSilentAudio(to input: AVAssetWriterInput, seconds: Double) {
        let sampleRate = 44_100
        let frameCount = Int(Double(sampleRate) * seconds)
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
                                       layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard let format else { return }

        let byteCount = frameCount * 2
        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                           blockLength: byteCount, blockAllocator: kCFAllocatorDefault,
                                           customBlockSource: nil, offsetToData: 0, dataLength: byteCount,
                                           flags: 0, blockBufferOut: &blockBuffer)
        guard let blockBuffer else { return }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: byteCount)

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
                                        presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, dataReady: true,
                             makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
                             sampleCount: frameCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                             sampleSizeEntryCount: 1, sampleSizeArray: [2], sampleBufferOut: &sampleBuffer)
        if let sampleBuffer {
            while !input.isReadyForMoreMediaData { usleep(1_000) }
            input.append(sampleBuffer)
        }
    }
}
