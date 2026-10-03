import XCTest
import AVFoundation
import CoreMedia
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import SwiftData

/// Q186 (capture-import-13, setexp-92; C68, C239): import bundling and audio export follow ONE
/// rule on phone and Mac.
/// - ONE accept set (`MixedBundle.member`): voice clips + pictures + text + video become one note;
///   a document / book never joins.
/// - The Mac drop: a bundle's `.txt`/`.md` is the note's ANNOTATION (the phone's chat-text rule),
///   not a second note; a video's speech is stitched in its place and its frame is a picture there.
/// - `includeAudioInExport` lives on the synced `Memo` too: the Mac mirrors it both ways and the
///   phone's publisher reads the same field.
@MainActor
final class ImportBundleParityTests: XCTestCase {

    // MARK: - Fixtures

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func writeClip(in dir: URL, name: String, seconds: Double) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let p = buf.floatChannelData![0]
        for i in 0..<Int(frames) { p[i] = 0.3 * sinf(2 * .pi * 440 * Float(i) / 44_100) }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                                       AVNumberOfChannelsKey: 1]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buf)
        return url
    }

    private func writeJPEG(in dir: URL, name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let sink = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(sink, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        return url
    }

    /// A real `.mov` with one held video frame and `seconds` of silent AAC audio.
    private func writeVideo(in dir: URL, name: String, seconds: Double) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let pixelAttrs: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                                         kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput,
                                                           sourcePixelBufferAttributes: pixelAttrs)
        writer.add(videoInput)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000])
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

        let frameCount = Int(44_100 * seconds)
        var asbd = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                                               mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                       formatDescriptionOut: &format)
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                           blockLength: frameCount * 2, blockAllocator: kCFAllocatorDefault,
                                           customBlockSource: nil, offsetToData: 0, dataLength: frameCount * 2,
                                           flags: 0, blockBufferOut: &block)
        if let format, let block {
            CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: frameCount * 2)
            var sample: CMSampleBuffer?
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44_100),
                                            presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
            CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: block, dataReady: true,
                                 makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
                                 sampleCount: frameCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                 sampleSizeEntryCount: 1, sampleSizeArray: [2], sampleBufferOut: &sample)
            if let sample {
                while !audioInput.isReadyForMoreMediaData { usleep(1_000) }
                audioInput.append(sample)
            }
        }
        audioInput.markAsFinished()

        let done = expectation(description: "writer finish")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(writer.status, .completed, "video writer failed: \(String(describing: writer.error))")
        return url
    }

    private func manifest(of pf: PipelineFile) throws -> [ImageManifestEntry] {
        let url = try XCTUnwrap(pf.workingFolder).appendingPathComponent("image_manifest.json")
        return try JSONDecoder().decode([ImageManifestEntry].self, from: Data(contentsOf: url))
    }

    // MARK: - The ONE accept set

    func testTheAcceptSetCoversClipsPicturesVideoAndTextButNoDocumentOrBook() {
        let noTrack: (URL) -> Bool = { _ in false }
        let track: (URL) -> Bool = { _ in true }
        func m(_ name: String, _ probe: (URL) -> Bool) -> MixedBundle.Member? {
            MixedBundle.member(of: URL(fileURLWithPath: "/x/\(name)"), hasVideoTrack: probe)
        }
        XCTAssertEqual(m("a.opus", noTrack), .clip)
        XCTAssertEqual(m("a.M4A", noTrack), .clip)
        XCTAssertEqual(m("a.jpeg", noTrack), .picture)
        XCTAssertEqual(m("a.txt", noTrack), .text, "the Mac used to refuse a bundle's .txt")
        XCTAssertEqual(m("a.md", noTrack), .text)
        XCTAssertEqual(m("a.mov", track), .video)
        XCTAssertEqual(m("a.mp4", noTrack), .clip, "an audio-only mp4 is a voice clip")
        XCTAssertNil(m("a.mkv", noTrack), "a non-audio container with no picture track is not speech")
        XCTAssertNil(m("a.pdf", noTrack))
        XCTAssertNil(m("a.epub", noTrack))
        // Every extension ImportKinds knows resolves the same way in the bundle's set.
        for ext in ImportKinds.audioExtensions { XCTAssertEqual(m("a.\(ext)", noTrack), .clip, ext) }
        for ext in ImportKinds.imageExtensions { XCTAssertEqual(m("a.\(ext)", noTrack), .picture, ext) }
        for ext in ImportKinds.textExtensions { XCTAssertEqual(m("a.\(ext)", noTrack), .text, ext) }
    }

    func testTextsMakeOneAnnotationInBundleOrder() {
        XCTAssertEqual(MixedBundle.annotation(fromTexts: ["  first \n", "", "second"]), "first\n\nsecond")
        XCTAssertNil(MixedBundle.annotation(fromTexts: ["", "  \n "]))
    }

    func testAVideoInTheBundleIsSpeechInPlaceWithItsFrameWhereItStarts() {
        let a = URL(fileURLWithPath: "/x/a.m4a"), v = URL(fileURLWithPath: "/x/v.mov")
        let p = URL(fileURLWithPath: "/x/p.jpg")
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let items: [MixedBundle.Item] = [
            .init(url: p, kind: .picture, date: t0.addingTimeInterval(120)),
            .init(url: v, kind: .video, date: t0.addingTimeInterval(60)),
            .init(url: a, kind: .clip, date: t0),
        ]
        let c = MixedBundle.compose(items) { $0 == a ? 4 : 3 }
        XCTAssertEqual(c.clips, [a, v], "speech in time order, the video's audio in its place")
        XCTAssertEqual(c.pictures, [
            MixedBundle.Placement(url: v, offsetSeconds: 4, isVideoFrame: true),
            MixedBundle.Placement(url: p, offsetSeconds: 7),
        ])
    }

    // MARK: - The Mac drop

    /// capture-import-13: one clip + one picture + one `.txt` → ONE note, the text its annotation
    /// (the phone's chat-text rule), and the annotation reaches the authored `Memo`.
    func testClipPictureAndTextDropIsOneNoteWithTheTextAsAnnotation() async throws {
        let work = makeTempDir()
        let clip = try writeClip(in: work, name: "signal-2026-10-01-07-44-33-032.m4a", seconds: 2)
        let pic = try writeJPEG(in: work, name: "signal-2026-10-01-074500.jpeg")
        let text = work.appendingPathComponent("chat.txt")
        try "Look at this one".write(to: text, atomically: true, encoding: .utf8)
        let ctx = try makeContext()

        let report = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingestReport(localURLs: [text, clip, pic], combineAudio: false, into: ctx)

        XCTAssertEqual(report.created.count, 1, "clip + picture + text = ONE note")
        XCTAssertEqual(report.skipped, [])
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 1)
        let pf = try XCTUnwrap(report.created.first)
        XCTAssertEqual(pf.sourceType, .audio)
        XCTAssertEqual(try manifest(of: pf).count, 1, "the picture rides along")
        XCTAssertEqual(IngestService.bundleAnnotation(in: pf.audioMetadataJSON), "Look at this one")

        let memoCtx = ModelContext(try ModelContainer(
            for: Memo.self, MemoAsset.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
        let memo = try XCTUnwrap(try MacMemoAuthor.author(for: pf, audioURL: nil, into: memoCtx))
        XCTAssertEqual(memo.annotationText, "Look at this one", "the phone reads the same annotation")
    }

    /// A text with no speech in the drop is still a note of its own (nothing to annotate).
    func testALoneTextIsStillItsOwnNote() async throws {
        let work = makeTempDir()
        let text = work.appendingPathComponent("plan.txt")
        try "The plan".write(to: text, atomically: true, encoding: .utf8)
        let ctx = try makeContext()
        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [text], into: ctx)
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created.first?.sourceType, .note)
        XCTAssertNil(IngestService.bundleAnnotation(in: created.first?.audioMetadataJSON))
    }

    /// C68: clip + video + "One note" → ONE note: the video's audio stitched after the clip, its
    /// frame a picture at the boundary, and the video counted by the chooser.
    func testAVideoJoinsTheBundleOnTheMac() async throws {
        let work = makeTempDir()
        let clip = try writeClip(in: work, name: "signal-2026-10-01-07-44-33-032.m4a", seconds: 2)
        let video = try writeVideo(in: work, name: "signal-2026-10-01-07-50-00-000.mov", seconds: 1)
        XCTAssertEqual(IngestService.speechItems(in: [video, clip]), [video, clip],
                       "the chooser counts a video as speech")
        let ctx = try makeContext()

        let report = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingestReport(localURLs: [video, clip], combineAudio: true, into: ctx)

        XCTAssertEqual(report.created.count, 1, "clip + video + One note = ONE row")
        let pf = try XCTUnwrap(report.created.first)
        XCTAssertTrue(report.merged.contains(pf.id))
        let merged = try AVAudioFile(forReading: URL(fileURLWithPath: pf.path))
        XCTAssertEqual(Double(merged.length) / merged.fileFormat.sampleRate, 3.0, accuracy: 0.4)
        let entries = try manifest(of: pf)
        XCTAssertEqual(entries.count, 1, "the video's frame is a picture in the note")
        XCTAssertEqual(entries.first?.offsetSeconds ?? -1, 2.0, accuracy: 0.3, "where the video's speech starts")
        let frame = try XCTUnwrap(pf.workingFolder).appendingPathComponent("images/\(entries[0].filename)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: frame.path))
    }

    /// A lone video still imports exactly as before (movie kept, frame at the top).
    func testALoneVideoKeepsItsOwnImport() async throws {
        let work = makeTempDir()
        let video = try writeVideo(in: work, name: "clip.mov", seconds: 1)
        let ctx = try makeContext()
        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [video], into: ctx)
        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(pf.mediaSource, "video")
        XCTAssertEqual(try manifest(of: pf), [ImageManifestEntry(filename: "img_001.jpg", offsetSeconds: 0)])
    }

    // MARK: - Include audio in export (setexp-92)

    func testIncludeAudioRidesTheSyncedMemoBothWays() {
        let id = UUID()
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a")
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a")
        XCTAssertTrue(memo.includeAudioInExport, "an existing memo keeps today's behaviour")
        XCTAssertFalse(ExportAudioMirror.pull(memo, into: pf), "agreeing pair: no churn")

        memo.includeAudioInExport = false           // switched off on another device
        XCTAssertTrue(ExportAudioMirror.pull(memo, into: pf))
        XCTAssertFalse(pf.includeAudioInExport, "the Mac exporter now skips the audio")

        pf.includeAudioInExport = true              // flipped back on the Mac
        XCTAssertTrue(ExportAudioMirror.push(pf, to: memo))
        XCTAssertTrue(memo.includeAudioInExport, "the phone publisher reads the same value")
        XCTAssertFalse(ExportAudioMirror.push(pf, to: memo))
    }

    func testAMacOptOutGoesOutOnTheAuthoredMemo() throws {
        let c = ModelContext(try ModelContainer(
            for: Memo.self, MemoAsset.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
        let pf = PipelineFile(id: UUID().uuidString, filename: "a.m4a", path: "", size: 1, sourceType: .audio)
        pf.includeAudioInExport = false
        let memo = try XCTUnwrap(try MacMemoAuthor.author(for: pf, audioURL: nil, into: c))
        XCTAssertFalse(memo.includeAudioInExport)
    }
}
