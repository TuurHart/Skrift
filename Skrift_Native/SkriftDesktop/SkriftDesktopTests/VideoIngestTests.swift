import XCTest
import SwiftData
import AVFoundation
import CoreMedia
import CoreVideo

/// Desktop video-ingest: detection, embedded-date parsing, and the end-to-end
/// extract-audio-from-a-real-video path. Host-less (Pipeline + AVFoundation only).
final class VideoIngestTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PipelineFile.self, configurations: config)
        return ModelContext(container)
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Pure detection / date helpers

    func testVideoExtensionSet() {
        XCTAssertTrue(IngestService.supportedVideo.contains("mov"))
        XCTAssertTrue(IngestService.supportedVideo.contains("mp4"))
        XCTAssertTrue(IngestService.supportedVideo.contains("m4v"))
        XCTAssertFalse(IngestService.supportedVideo.contains("m4a"))   // audio, not video
        XCTAssertFalse(IngestService.supportedVideo.contains("md"))
    }

    func testParseISODate() {
        // With fractional seconds (QuickTime style).
        let withFrac = IngestService.parseISODate("2026-04-13T18:15:24.000Z")
        XCTAssertNotNil(withFrac)
        // Without fractional seconds.
        let noFrac = IngestService.parseISODate("2026-04-13T18:15:24Z")
        XCTAssertNotNil(noFrac)
        XCTAssertNil(IngestService.parseISODate("not a date"))
    }

    func testHasVideoTrackFalseForAudioOnly() async throws {
        // An audio-only m4a: no video track → falls through to plain-audio ingest.
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let audioURL = work.appendingPathComponent("voice.m4a")
        try makeSilentAudioFile(at: audioURL, seconds: 1.0)
        XCTAssertFalse(IngestService.hasVideoTrack(audioURL))
    }

    // MARK: - End-to-end (real generated video)

    func testHasVideoTrackTrueForRealVideo() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let videoURL = work.appendingPathComponent("clip.mov")
        try makeVideoFile(at: videoURL, seconds: 1.0, withAudio: true)
        XCTAssertTrue(IngestService.hasVideoTrack(videoURL))
    }

    func testExtractAudioFromVideoProducesPlayableM4A() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let videoURL = work.appendingPathComponent("clip.mov")
        try makeVideoFile(at: videoURL, seconds: 1.0, withAudio: true)

        let out = work.appendingPathComponent("original.m4a")
        try await IngestService.extractAudio(from: videoURL, to: out)

        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        // The extracted file has an audio track and no video track.
        let asset = AVURLAsset(url: out)
        XCTAssertFalse(asset.tracks(withMediaType: .audio).isEmpty, "extracted m4a should carry the audio")
        XCTAssertTrue(asset.tracks(withMediaType: .video).isEmpty, "extracted m4a should have no video")
    }

    func testExtractAudioThrowsForVideoWithoutAudio() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let videoURL = work.appendingPathComponent("silent.mov")
        try makeVideoFile(at: videoURL, seconds: 1.0, withAudio: false)

        let out = work.appendingPathComponent("original.m4a")
        do {
            try await IngestService.extractAudio(from: videoURL, to: out)
            XCTFail("expected noAudioTrack to throw")
        } catch {
            XCTAssertEqual(error as? IngestService.VideoIngestError, .noAudioTrack)
        }
    }

    func testIngestVideoCreatesAudioPipelineFileWithFilenameDate() async throws {
        // A synthetic AVAssetWriter .mov is auto-stamped with an embedded creation date
        // (now) that correctly wins over the filename, so we assert the filename-date
        // FALLBACK helper directly below — the path real videos lacking metadata use.
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let videoURL = work.appendingPathComponent("My life advice 2025-12-18.mov")
        try makeVideoFile(at: videoURL, seconds: 1.0, withAudio: true, creationDate: nil)

        let ctx = try makeContext()
        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [videoURL], into: ctx)

        XCTAssertEqual(created.count, 1)
        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(pf.sourceType, .audio)                       // video → audio after extraction
        XCTAssertNotEqual(pf.transcribeStatus, .done)               // still needs transcription
        XCTAssertTrue(pf.path.hasSuffix("original.m4a"), "extracted audio, not the source video")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pf.path))
        XCTAssertEqual(pf.filename, "My life advice 2025-12-18.mov")  // original name kept for the title
        let fnDate = try XCTUnwrap(IngestService.dateFromFilename("My life advice 2025-12-18.mov"))
        let ymd = Calendar.current.dateComponents([.year, .month, .day], from: fnDate)
        XCTAssertEqual([ymd.year, ymd.month, ymd.day], [2025, 12, 18])
    }

    func testIngestVideoUsesEmbeddedRecordingDate() async throws {
        // An embedded creation date wins over the filename / filesystem date.
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let embedded = ISO8601DateFormatter().date(from: "2023-07-04T09:30:00Z")!
        let videoURL = work.appendingPathComponent("clip.mov")
        try makeVideoFile(at: videoURL, seconds: 1.0, withAudio: true, creationDate: embedded)

        // Sanity: the helper reads it back.
        let readBack = IngestService.embeddedRecordingDate(of: videoURL)
        XCTAssertNotNil(readBack)
        XCTAssertEqual(readBack!.timeIntervalSince1970, embedded.timeIntervalSince1970, accuracy: 1.0)

        let ctx = try makeContext()
        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [videoURL], into: ctx)
        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(pf.uploadedAt.timeIntervalSince1970, embedded.timeIntervalSince1970, accuracy: 1.0)
    }

    func testIngestVideoWritesThumbnailAndManifest() async throws {
        // Video ingest grabs ONE representative frame into `images/img_001.jpg` and
        // writes a phone-shaped `image_manifest.json` (offset 0) — so the existing
        // [[img_001]] marker pipeline renders + exports the frame.
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let videoURL = work.appendingPathComponent("clip.mov")
        try makeVideoFile(at: videoURL, seconds: 1.0, withAudio: true)

        let ctx = try makeContext()
        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [videoURL], into: ctx)
        let pf = try XCTUnwrap(created.first)
        let folder = URL(fileURLWithPath: pf.path).deletingLastPathComponent()

        let thumb = folder.appendingPathComponent("images").appendingPathComponent("img_001.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumb.path), "representative frame missing")

        let manifestData = try Data(contentsOf: folder.appendingPathComponent("image_manifest.json"))
        let entries = try JSONDecoder().decode([ImageManifestEntry].self, from: manifestData)
        XCTAssertEqual(entries, [ImageManifestEntry(filename: "img_001.jpg", offsetSeconds: 0)])
    }

    func testThumbnailFailureDoesNotFailIngest() async throws {
        // A video whose frame can't be grabbed still ingests its audio (the thumbnail
        // is best-effort and logged) — exercised via the helper on a non-video file.
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let audioURL = work.appendingPathComponent("voice.m4a")
        try makeSilentAudioFile(at: audioURL, seconds: 1.0)
        XCTAssertThrowsError(try IngestService.writeVideoThumbnail(from: audioURL, into: work))
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent("image_manifest.json").path))
    }

    // MARK: - Synthetic media generators

    /// Write a short silent AAC-in-m4a file (audio track only) so detection/extraction
    /// can be exercised without a fixture.
    private func makeSilentAudioFile(at url: URL, seconds: Double) throws {
        let sampleRate = 44_100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames   // zeroed = silence
        try file.write(from: buffer)
    }

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
