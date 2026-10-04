import XCTest
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import SwiftData

/// Q92 / C68 / C12 / C70 / C238: Tuur dragged five Signal voice clips and one Signal picture
/// onto the Mac sidebar (2026-10-01). The clips merged; the picture vanished — `ingestFile`
/// returned nil for a `.jpeg` and the loop appended nothing: no row, no message. A mixed drop is
/// ONE note in time order with the picture as its own paragraph at its place; "N notes" still
/// gives the picture a note of its own; nothing in a drop is ever silently skipped.
///
/// The P3 corpus fixture (`ingress-p3-five-clips-one-picture`) is the merged RESULT (one
/// audio + one picture at 10.7 s); these tests rebuild its INPUT shape with synthetic clips:
/// five Signal-named clips + a Signal picture whose filename time sits between clip 3 and 4.
@MainActor
final class MacMixedDropTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    /// A real AAC `.m4a`: `seconds` of a 440 Hz tone at `amplitude`.
    private func writeClip(in dir: URL, name: String, seconds: Double, amplitude: Float) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let p = buf.floatChannelData![0]
        for i in 0..<Int(frames) { p[i] = amplitude * sinf(2 * .pi * 440 * Float(i) / 44_100) }
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
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let sink = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(sink, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        return url
    }

    /// Tuur's six files by name. Each clip is 2 s; amplitude rises with the clip number so the
    /// merged file shows WHICH clip sits in which 2 s slot.
    private struct Drop {
        let clips: [URL]      // chat order, 07:44 … 08:06
        let picture: URL      // 08:03:49 — between clip 3 (07:56) and clip 4 (08:04)
    }

    private func signalDrop(in dir: URL) throws -> Drop {
        let names = ["signal-2026-10-01-07-44-33-032.m4a", "signal-2026-10-01-07-46-19-286.m4a",
                     "signal-2026-10-01-07-56-11-865.m4a", "signal-2026-10-01-08-04-01-809.m4a",
                     "signal-2026-10-01-08-06-25-049.m4a"]
        let amps: [Float] = [0.1, 0.2, 0.3, 0.5, 0.8]
        let clips = try zip(names, amps).map { try writeClip(in: dir, name: $0, seconds: 2, amplitude: $1) }
        return Drop(clips: clips, picture: try writeJPEG(in: dir, name: "signal-2026-10-01-080349.jpeg"))
    }

    private func rms(ofSlot slot: Int, in url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        file.framePosition = AVAudioFramePosition((Double(slot) * 2 + 0.5) * rate)
        let n = AVAudioFrameCount(1.0 * rate)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: n)!
        try file.read(into: buf, frameCount: n)
        let p = buf.floatChannelData![0]
        var sum: Float = 0
        for i in 0..<Int(buf.frameLength) { sum += p[i] * p[i] }
        return (sum / Float(max(1, buf.frameLength))).squareRoot()
    }

    private func manifest(of pf: PipelineFile) throws -> [ImageManifestEntry] {
        let url = try XCTUnwrap(pf.workingFolder).appendingPathComponent("image_manifest.json")
        return try JSONDecoder().decode([ImageManifestEntry].self, from: Data(contentsOf: url))
    }

    // MARK: - (a) One note

    func testMixedDropOneNotePlacesThePictureBetweenClip3And4() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let drop = try signalDrop(in: work)
        let ctx = try makeContext()
        // Finder order is arbitrary: picture last, clips 4 and 5 swapped. Time decides (C70).
        let urls = [drop.clips[0], drop.clips[1], drop.clips[2], drop.clips[4], drop.clips[3], drop.picture]

        let created = try await ArrivalPath.run(
            urls: urls, asRecording: false, into: ctx, cloudContext: nil, hooks: .inert,
            service: IngestService(outputDir: work.appendingPathComponent("out")),
            combineAudio: true)

        XCTAssertEqual(created.count, 1, "5 clips + 1 picture + One note = ONE row")
        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(pf.sourceType, .audio)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 1)

        // Clips merged in TIME order, not drop order.
        let audio = URL(fileURLWithPath: pf.path)
        let merged = try AVAudioFile(forReading: audio)
        XCTAssertEqual(Double(merged.length) / merged.fileFormat.sampleRate, 10.0, accuracy: 0.4)
        let r = try (0..<5).map { try rms(ofSlot: $0, in: audio) }
        XCTAssertEqual(r, r.sorted(), "slots rise 0.1 → 0.8: the clips sit in filename-time order")

        // The picture is in the manifest at the boundary of clip 3 and 4 (≈ 6 s) and on disk.
        let entries = try manifest(of: pf)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].offsetSeconds, 6.0, accuracy: 0.3,
                       "08:03:49 sits after the 07:56 clip and before the 08:04 one")
        let imagesDir = try XCTUnwrap(pf.workingFolder).appendingPathComponent("images")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent(entries[0].filename).path))

        // What the transcript pass then writes: one sentence per clip → the picture is its
        // own paragraph between sentence 3 and sentence 4 (C12), nowhere else.
        let sentences = ["Alpha one.", "Bravo two.", "Charlie three.", "Delta four.", "Echo five."]
        var words: [WordTiming] = []
        for (i, s) in sentences.enumerated() {
            let t = Double(i) * 2 + 0.3
            let parts = s.split(separator: " ").map(String.init)
            for (j, w) in parts.enumerated() {
                words.append(WordTiming(word: w, start: t + Double(j) * 0.5, end: t + Double(j) * 0.5 + 0.4))
            }
        }
        let body = BodyV2.committed(BodyV2.Input(text: sentences.joined(separator: " "), words: words,
                                                 manifest: entries, source: .speech))
        let marker = try XCTUnwrap(body.range(of: "[[img_001]]"), "picture marker missing: \(body)")
        let three = try XCTUnwrap(body.range(of: "Charlie"))
        let four = try XCTUnwrap(body.range(of: "Delta"))
        XCTAssertLessThan(three.lowerBound, marker.lowerBound, body)
        XCTAssertLessThan(marker.lowerBound, four.lowerBound, body)
    }

    // MARK: - (b) N notes

    func testMixedDropNNotesGivesFiveAudioNotesAndOnePictureNote() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let drop = try signalDrop(in: work)
        let ctx = try makeContext()

        let created = try await ArrivalPath.run(
            urls: drop.clips + [drop.picture], asRecording: false, into: ctx, cloudContext: nil,
            hooks: .inert, service: IngestService(outputDir: work.appendingPathComponent("out")),
            combineAudio: false)

        XCTAssertEqual(created.filter { $0.sourceType == .audio }.count, 5, "one audio note per clip")
        let pics = created.filter { $0.sourceType != .audio }
        XCTAssertEqual(pics.count, 1, "the picture is never lost: its own note")
        XCTAssertEqual(created.count, 6)
        let pic = try XCTUnwrap(pics.first)
        let entries = try manifest(of: pic)
        XCTAssertEqual(entries.count, 1)
        let imagesDir = try XCTUnwrap(pic.workingFolder).appendingPathComponent("images")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent(entries[0].filename).path))
        XCTAssertEqual(pic.transcript, "[[img_001]]", "the note body is the picture paragraph")
        XCTAssertEqual(pic.transcribeStatus, .done, "a picture note has nothing to transcribe")
        XCTAssertTrue(pic.isLocalImport)
    }

    // MARK: - pictures alone (C68: N photos → always one note)

    func testPicturesAloneMakeOneNote() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let a = try writeJPEG(in: work, name: "signal-2026-10-01-080349.jpeg")
        let b = try writeJPEG(in: work, name: "signal-2026-10-01-080412.jpeg")
        let ctx = try makeContext()

        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [b, a], combineAudio: false, into: ctx)

        XCTAssertEqual(created.count, 1, "N photos → one note")
        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(try manifest(of: pf).count, 2)
        XCTAssertEqual(pf.transcript, "[[img_001]]\n\n[[img_002]]")
    }

    // MARK: - (c) nothing is silently skipped

    /// Every file in a drop ends up in a note OR in the report's `skipped` list - the sidebar
    /// turns that list into a message. Four shapes: One note, N notes, pictures alone, and a
    /// drop with a type nobody imports plus a file that vanished before the copy.
    func testNoDroppedFileIsEverSilentlySkipped() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let drop = try signalDrop(in: work)
        let pdf = work.appendingPathComponent("contract.pdf")
        try Data("%PDF-1.4".utf8).write(to: pdf)
        let gone = work.appendingPathComponent("vanished.m4a")
        let all = drop.clips + [drop.picture, pdf, gone]

        for combine in [true, false] {
            let ctx = try makeContext()
            let out = work.appendingPathComponent("out-\(combine)")
            let report = try await IngestService(outputDir: out)
                .ingestReport(localURLs: all, combineAudio: combine, into: ctx)

            XCTAssertEqual(Set(report.skipped.map(\.lastPathComponent)), ["vanished.m4a"],
                           "a vanished file is REPORTED; the PDF becomes a file capture (combine=\(combine))")
            let pdfCaptures = report.created.filter {
                $0.sourceType == .capture
                    && ($0.audioMetadataJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "").contains("application/pdf")
            }
            XCTAssertEqual(pdfCaptures.count, 1, "the PDF landed in a file capture (combine=\(combine))")
            // The six importable files are all inside rows: the picture in a manifest, the clips
            // as merged/separate audio.
            let rows = report.created
            let pictureInRow = rows.contains { (try? manifest(of: $0))?.count == 1 }
            XCTAssertTrue(pictureInRow, "the picture landed in a note (combine=\(combine))")
            XCTAssertEqual(rows.filter { $0.sourceType == .audio }.count, combine ? 1 : 5)
        }

        // Pictures alone: all of them in the one note, none reported.
        let ctx = try makeContext()
        let b = try writeJPEG(in: work, name: "second.jpeg")
        let report = try await IngestService(outputDir: work.appendingPathComponent("out-pics"))
            .ingestReport(localURLs: [drop.picture, b], combineAudio: false, into: ctx)
        XCTAssertTrue(report.skipped.isEmpty)
        XCTAssertEqual(report.created.count, 1)
        XCTAssertEqual(try manifest(of: try XCTUnwrap(report.created.first)).count, 2)

        // A picture that cannot be read is reported, and the note body never promises it.
        let broken = work.appendingPathComponent("broken.heic")
        try Data([1, 2, 3]).write(to: broken)
        let r2 = try await IngestService(outputDir: work.appendingPathComponent("out-broken"))
            .ingestReport(localURLs: [drop.picture, broken], combineAudio: false, into: try makeContext())
        XCTAssertEqual(r2.skipped.map(\.lastPathComponent), ["broken.heic"])
        XCTAssertEqual(r2.created.first?.transcript, "[[img_001]]", "the marker count matches the files written")
    }

    func testSignalPictureNameReadsAsItsCompactTime() throws {
        let d = try XCTUnwrap(IngestService.dateFromFilename("signal-2026-10-01-080349.jpeg"))
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: d)
        XCTAssertEqual([c.hour, c.minute, c.second], [8, 3, 49], "compact HHMMSS, not the noon default")
    }

    func testBundleOrderIsByTimeWhenEveryNameHasOneElseTheDropOrder() {
        func item(_ n: String, _ k: MixedBundle.Kind, _ h: Int?) -> MixedBundle.Item {
            var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 1; c.hour = h
            return .init(url: URL(fileURLWithPath: "/x/\(n)"), kind: k, date: h == nil ? nil : Calendar.current.date(from: c))
        }
        let timed = [item("p", .picture, 8), item("a", .clip, 7), item("b", .clip, 9)]
        XCTAssertEqual(MixedBundle.ordered(timed).map { $0.url.lastPathComponent }, ["a", "p", "b"])
        let oneUndated = [item("p", .picture, nil), item("a", .clip, 7), item("b", .clip, 9)]
        XCTAssertEqual(MixedBundle.ordered(oneUndated).map { $0.url.lastPathComponent }, ["p", "a", "b"],
                       "an undated name keeps the drop order for the whole bundle")
        let c = MixedBundle.compose(timed) { _ in 5 }
        XCTAssertEqual(c.clips.map(\.lastPathComponent), ["a", "b"])
        XCTAssertEqual(c.pictures.map(\.offsetSeconds), [5], "after one 5 s clip")
        XCTAssertEqual(MixedBundle.compose([item("p", .picture, nil)]) { _ in 5 }.pictures.map(\.offsetSeconds), [0],
                       "a picture with no clip goes to the top")
    }

    func testOneClipAndOnePictureIsOneNoteWithoutAChooser() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let drop = try signalDrop(in: work)
        let ctx = try makeContext()

        // The chooser needs 2+ clips, so the sidebar passes combineAudio false here.
        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [drop.clips[3], drop.picture], combineAudio: false, into: ctx)

        XCTAssertEqual(created.count, 1, "a mixed bundle is one note (C68)")
        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(pf.sourceType, .audio)
        let entries = try manifest(of: pf)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].offsetSeconds, 0, accuracy: 0.01,
                       "08:03:49 is before the 08:04:01 clip → the top of the note")
    }
}
