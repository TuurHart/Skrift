import XCTest
import AVFoundation
import CoreMedia
import CoreVideo
@testable import SkriftMobile

final class VideoImportTests: XCTestCase {

    // MARK: - Pure detection / date helpers

    func testIsVideoFile() {
        XCTAssertTrue(MemoSaver.isVideoFile(URL(fileURLWithPath: "/tmp/clip.mov")))
        XCTAssertTrue(MemoSaver.isVideoFile(URL(fileURLWithPath: "/tmp/clip.MP4")))   // case-insensitive
        XCTAssertTrue(MemoSaver.isVideoFile(URL(fileURLWithPath: "/tmp/clip.m4v")))
        XCTAssertFalse(MemoSaver.isVideoFile(URL(fileURLWithPath: "/tmp/voice.m4a")))  // audio
        XCTAssertFalse(MemoSaver.isVideoFile(URL(fileURLWithPath: "/tmp/voice.wav")))
    }

    func testParseCreationDate() {
        XCTAssertNotNil(MemoSaver.parseCreationDate("2026-04-13T18:15:24.000Z"))   // fractional
        XCTAssertNotNil(MemoSaver.parseCreationDate("2026-04-13T18:15:24Z"))       // plain
        XCTAssertNil(MemoSaver.parseCreationDate("nope"))
    }

    // MARK: - Date fallback (no real video needed)

    /// When extraction fails (a non-video placeholder), the memo is marked failed but
    /// the recording date STILL comes from the supplied fallback (the PHAsset date),
    /// never the import time. Proves the date wiring independent of AVFoundation.
    @MainActor
    func testFailedExtractionStillUsesFallbackDate() async {
        let repo = NotesRepository(inMemory: true)
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "unused"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService()
        )
        let id = UUID()
        repo.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                         recordedAt: Date(), transcriptStatus: .transcribing))

        // A bogus "video" file with no audio/video track → extraction fails.
        let fake = FileManager.default.temporaryDirectory.appendingPathComponent("fake_\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: fake.path, contents: Data([0x00, 0x01, 0x02]))
        let fallback = Date(timeIntervalSince1970: 1_600_000_000)   // a fixed past date

        let ok = await saver.importVideoAsync(id: id, source: fake, fallbackDate: fallback)

        XCTAssertFalse(ok, "extraction should fail for a non-media file")
        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.transcriptStatus, .failed)
        XCTAssertEqual(memo?.recordedAt.timeIntervalSince1970 ?? 0, fallback.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - End-to-end with a real generated video

    @MainActor
    func testImportVideoExtractsAudioFrameAndDate() async throws {
        let repo = NotesRepository(inMemory: true)
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "video transcript here"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService()
        )
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        repo.insert(Memo(id: id, audioFilename: filename, recordedAt: Date(), transcriptStatus: .transcribing))

        let embedded = ISO8601DateFormatter().date(from: "2022-05-06T12:00:00Z")!
        let videoURL = FileManager.default.temporaryDirectory.appendingPathComponent("clip_\(UUID().uuidString).mov")
        try makeVideoFile(at: videoURL, seconds: 1.0, withAudio: true, creationDate: embedded)

        let ok = await saver.importVideoAsync(id: id, source: videoURL, fallbackDate: nil)
        XCTAssertTrue(ok)

        let memo = repo.memo(id: id)
        // Audio extracted into the memo's m4a.
        let audio = AppPaths.recordingsDirectory.appendingPathComponent(filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path), "audio not extracted")
        // One frame thumbnail captured + manifested.
        XCTAssertEqual(memo?.metadata?.imageManifest?.count, 1)
        XCTAssertEqual(memo?.metadata?.imageManifest?.first?.filename, "photo_\(id.uuidString)_001.jpg")
        // Marked as a VIDEO source → the list row shows the video glyph.
        XCTAssertEqual(memo?.metadata?.sourceType, MemoMetadata.Source.video)
        XCTAssertTrue(memo?.isVideoImport ?? false)
        let frame = AppPaths.recordingsDirectory.appendingPathComponent("photo_\(id.uuidString)_001.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: frame.path), "frame thumbnail not written")
        // Embedded recording date used (not import time).
        XCTAssertEqual(memo?.recordedAt.timeIntervalSince1970 ?? 0, embedded.timeIntervalSince1970, accuracy: 2.0)
        // Transcript landed (with the [[img_001]] marker from the manifest).
        XCTAssertEqual(memo?.transcriptStatus, .done)
        XCTAssertTrue(memo?.transcript?.contains("[[img_001]]") ?? false)

        // The extracted m4a must be playable by the DETAIL player (AVAudioPlayer),
        // not just readable by the transcriber — the "video transcribes fine but
        // Play does nothing" bug. A loadable player with a real duration proves the
        // export format is fine, so the no-playback bug was purely load TIMING.
        let player = try AVAudioPlayer(contentsOf: audio)
        XCTAssertGreaterThan(player.duration, 0, "extracted audio not playable")
    }

    // MARK: - Synthetic video generator

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
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
            }
        }
        videoInput.markAsFinished()

        if let audioInput {
            appendSilentAudio(to: audioInput, seconds: seconds)
            audioInput.markAsFinished()
        }

        let done = expectation(description: "writer finish")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(writer.status, .completed, "video writer failed: \(String(describing: writer.error))")
    }

    private func appendSilentAudio(to input: AVAssetWriterInput, seconds: Double) {
        let sampleRate = 44_100
        let frameCount = Int(Double(sampleRate) * seconds)
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0,
                                       layout: nil, magicCookieSize: 0, magicCookie: nil,
                                       extensions: nil, formatDescriptionOut: &format)
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
