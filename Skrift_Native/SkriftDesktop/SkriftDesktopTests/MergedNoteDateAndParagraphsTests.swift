import XCTest
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import SwiftData

private struct NoEnhance: Enhancing {
    func copyEdit(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { transcript }
    func title(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "T" }
    func summary(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "S" }
}

/// Q96 / C124 / C70 / D35. Tuur dropped five Signal clips from 1 Oct (07:44 ... 08:06) plus a
/// picture on the Mac on 2 Oct. They merged into one note, but the header read "Fri, 2 Oct
/// 2026" (Mac) and "Today . 08:08" (phone): the import moment, not Thu 1 Oct 07:44. And the
/// body ran a clip boundary into the middle of one paragraph.
///
/// Cause 1 (date): `ArrivalPath.run` backfills `uploadedAt` from the merged file's EMBEDDED
/// creation date, which for a stitched file is the stitch moment.
/// Cause 2 (paragraphs): the clip starts were never kept, so the transcript pass could only
/// paragraph on pauses and sentence ends, and a clip boundary mid-sentence stayed in one.
@MainActor
final class MergedNoteDateAndParagraphsTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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
        try AVAudioFile(forWriting: url, settings: settings).write(from: buf)
        return url
    }

    private func writeJPEG(in dir: URL, name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let sink = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(sink, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        return url
    }

    /// Tuur's drop: five 2 s clips + one picture between clip 3 and 4, in a scrambled Finder order.
    private func signalDrop(in dir: URL) throws -> [URL] {
        let names = ["signal-2026-10-01-07-44-33-032.m4a", "signal-2026-10-01-07-46-19-286.m4a",
                     "signal-2026-10-01-07-56-11-865.m4a", "signal-2026-10-01-08-04-01-809.m4a",
                     "signal-2026-10-01-08-06-25-049.m4a"]
        let c = try names.map { try writeClip(in: dir, name: $0, seconds: 2) }
        let pic = try writeJPEG(in: dir, name: "signal-2026-10-01-080349.jpeg")
        return [c[2], pic, c[0], c[4], c[1], c[3]]
    }

    private var first: Date {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 1; c.hour = 7; c.minute = 44; c.second = 33
        return Calendar.current.date(from: c)!
    }

    /// What `AudioMetadata.recordingDate` does (that file is in the app target, not this bundle):
    /// the container's embedded creation date, else nil.
    private func embeddedDate(_ url: URL) async -> Date? {
        let asset = AVURLAsset(url: url)
        guard let item = (try? await asset.load(.creationDate)) ?? nil else { return nil }
        return (try? await item.load(.dateValue)) ?? nil
    }

    // MARK: - date

    func testMergedNoteIsDatedToTheFirstClipsFilenameTimeNotTheImportMoment() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let urls = try signalDrop(in: work)
        let ctx = try makeContext()
        let before = Date()

        // The real backfill reads the stitched file's own embedded date ...
        let live = ArrivalPath.Hooks(recordingDate: { await self.embeddedDate($0) }, reconcileSoon: {},
                                     transcribe: { _ in }, transcribeImport: { _ in })
        let created = try await ArrivalPath.run(
            urls: urls, asRecording: false, into: ctx, cloudContext: nil, hooks: live,
            service: IngestService(outputDir: work.appendingPathComponent("out")), combineAudio: true)
        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(pf.uploadedAt.timeIntervalSince1970, first.timeIntervalSince1970, accuracy: 1,
                       "recordedAt = the first clip's filename time (Thu 1 Oct 07:44:33), not the import moment")
        XCTAssertLessThan(pf.uploadedAt, before.addingTimeInterval(-3600), "nowhere near the import moment")

        // ... and a container that claims "now" as its creation date must not win either.
        let ctx2 = try makeContext()
        let stamping = ArrivalPath.Hooks(recordingDate: { _ in Date() }, reconcileSoon: {},
                                         transcribe: { _ in }, transcribeImport: { _ in })
        let again = try await ArrivalPath.run(
            urls: urls, asRecording: false, into: ctx2, cloudContext: nil, hooks: stamping,
            service: IngestService(outputDir: work.appendingPathComponent("out2")), combineAudio: true)
        XCTAssertEqual(try XCTUnwrap(again.first).uploadedAt.timeIntervalSince1970, first.timeIntervalSince1970,
                       accuracy: 1, "a stitched note ignores the stitched file's embedded date")
    }

    func testASingleClipStillTakesItsEmbeddedDate() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let clip = try writeClip(in: work, name: "signal-2026-10-01-07-44-33-032.m4a", seconds: 2)
        let embedded = Date(timeIntervalSince1970: 1_700_000_000)
        let hooks = ArrivalPath.Hooks(recordingDate: { _ in embedded }, reconcileSoon: {},
                                      transcribe: { _ in }, transcribeImport: { _ in })
        let created = try await ArrivalPath.run(
            urls: [clip], asRecording: false, into: try makeContext(), cloudContext: nil, hooks: hooks,
            service: IngestService(outputDir: work.appendingPathComponent("out")), combineAudio: true)
        XCTAssertEqual(try XCTUnwrap(created.first).uploadedAt, embedded, "C70 ladder: embedded date first")
    }

    // MARK: - clip manifest

    func testTheMergedNoteKeepsEachClipsStartAndTimeInItsManifest() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let urls = try signalDrop(in: work)
        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: urls, combineAudio: true, into: try makeContext())
        let pf = try XCTUnwrap(created.first)

        let url = try XCTUnwrap(pf.workingFolder).appendingPathComponent("clip_manifest.json")
        let m = try JSONDecoder().decode([MixedBundle.ClipEntry].self, from: Data(contentsOf: url))
        XCTAssertEqual(m.map(\.filename), ["signal-2026-10-01-07-44-33-032.m4a", "signal-2026-10-01-07-46-19-286.m4a",
                                           "signal-2026-10-01-07-56-11-865.m4a", "signal-2026-10-01-08-04-01-809.m4a",
                                           "signal-2026-10-01-08-06-25-049.m4a"], "filename-time order")
        for (i, e) in m.enumerated() { XCTAssertEqual(e.startSeconds, Double(i) * 2, accuracy: 0.3) }
        XCTAssertTrue(m.allSatisfy { $0.recordedAt != nil }, "each clip's own time is kept")
        XCTAssertEqual(IngestService.clipStarts(forAudioAt: pf.path).count, 4, "four boundaries, none before clip 1")
    }

    // MARK: - paragraphs

    /// Tuur's note: a clip boundary lands mid-sentence ("...a pause between every word so the" |
    /// "Um this is gonna be a hard one to fix"), with NO pause and no full stop. Words run on
    /// continuously (0.5 s each, no gap), 4 words per 2 s clip.
    private func runOnWords() -> (text: String, words: [WordTiming]) {
        let clips = ["a little pause between every", "word so the um this",
                     "is gonna be a hard", "one to fix and then", "some more words after that"]
        var words: [WordTiming] = []
        for (c, line) in clips.enumerated() {
            for (j, w) in line.split(separator: " ").enumerated() {
                let t = Double(c) * 2 + Double(j) * 0.4
                words.append(WordTiming(word: String(w), start: t, end: t + 0.35))
            }
        }
        return (words.map(\.word).joined(separator: " "), words)
    }

    func testEachClipStartsItsOwnParagraphEvenMidSentence() {
        let (text, words) = runOnWords()
        let plain = BodyV2.committed(BodyV2.Input(text: text, words: words, source: .speech))
        XCTAssertEqual(plain.components(separatedBy: "\n\n").count, 1, "without the manifest the clips run together")

        let body = BodyV2.committed(BodyV2.Input(text: text, words: words, source: .speech,
                                                 clipStarts: [2, 4, 6, 8]))
        let paras = body.components(separatedBy: "\n\n")
        XCTAssertEqual(paras.count, 5, body)
        XCTAssertTrue(paras[1].hasPrefix("word so the"), body)
        XCTAssertTrue(paras[2].hasPrefix("is gonna"), body)
        XCTAssertFalse(body.contains("07:"), "no per-message time in the body (D35)")
        XCTAssertFalse(body.contains("2026"), "no per-message date in the body (D35)")
    }

    func testClipBreaksSurviveAPicturePlacedFirst() {
        let (text, words) = runOnWords()
        let pic = [ImageManifestEntry(filename: "img_001.jpg", offsetSeconds: 6.0)]
        // Pictures first (as `ASRPostProcess.finish` commits them), then the runner's own pass.
        let placed = BodyV2.committed(BodyV2.Input(text: text, words: words, manifest: pic, source: .speech))
        let body = BodyV2.committed(BodyV2.Input(text: placed, words: words, manifest: pic, source: .speech,
                                                 clipStarts: [2, 4, 6, 8]))
        let paras = body.components(separatedBy: "\n\n")
        XCTAssertEqual(paras.filter { !$0.hasPrefix("[[img_") }.count, 5, "five clip paragraphs: \(body)")
        XCTAssertEqual(paras.filter { $0.hasPrefix("[[img_") }.count, 1, "and the picture on its own: \(body)")
    }

    /// The Mac's transcript pass (BatchRunner) hands the merged note's starts to the body.
    func testBatchRunnerBreaksTheMergedNoteAtEachClip() async throws {
        let (text, words) = runOnWords()
        struct Stub: Transcribing {
            let text: String; let words: [WordTiming]
            func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
                TranscriptionResult(text: text, confidence: 0.9, durationMs: 1, wordTimings: words, markersInjected: false)
            }
        }
        let pf = PipelineFile(id: "m", filename: "signal-x.m4a", path: "/tmp/x", size: 0, sourceType: .audio)
        let runner = BatchRunner(transcriber: Stub(text: text, words: words), enhancer: NoEnhance(),
                                 settings: .default, people: [], tagWhitelist: [])
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/x.m4a"),
                             clipStarts: [2, 4, 6, 8], stopAfterTranscribe: true)
        XCTAssertEqual((pf.transcript ?? "").components(separatedBy: "\n\n").count, 5, pf.transcript ?? "nil")
    }

    /// Ingress P1/P3 shape end to end on the Mac: five clips + a picture in, one note whose
    /// clip starts the transcript pass will break on, dated to the first clip.
    func testP1ShapeFiveClipsOnePictureOneDatedNoteWithFiveBreaks() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let urls = try signalDrop(in: work)
        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: urls, combineAudio: true, into: try makeContext())
        let pf = try XCTUnwrap(created.first)
        let starts = IngestService.clipStarts(forAudioAt: pf.path)
        let (text, words) = runOnWords()
        let body = BodyV2.committed(BodyV2.Input(text: text, words: words, source: .speech, clipStarts: starts))
        XCTAssertEqual(body.components(separatedBy: "\n\n").count, 5)
    }
}
