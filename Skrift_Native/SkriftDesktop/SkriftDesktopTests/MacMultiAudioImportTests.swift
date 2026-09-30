import XCTest
import AVFoundation
import SwiftData

/// Q74 / C68 / C145 / C238: several audio files arriving on the Mac together get the phone's
/// chooser — "One note" (default: clips merged IN ORDER into one file, so ONE row and ONE
/// transcription pass) or "N notes". The merge is the phone's own (`AudioClipMerge`, lifted
/// into Shared/), and every Mac door funnels through `ArrivalPath.run(combineAudio:)`.
@MainActor
final class MacMultiAudioImportTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A real, decodable clip: `seconds` of a 440 Hz tone at `amplitude` (16 kHz mono, CAF).
    /// Distinct amplitudes let the test tell WHICH clip sits where in the merged file.
    private func writeTone(in dir: URL, name: String, seconds: Double, amplitude: Float) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let frames = AVAudioFrameCount(16_000 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let p = buf.floatChannelData![0]
        for i in 0..<Int(frames) { p[i] = amplitude * sinf(2 * .pi * 440 * Float(i) / 16_000) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buf)
        return url
    }

    private func threeClips(in dir: URL) throws -> [URL] {
        [try writeTone(in: dir, name: "a first 2026-09-01.caf", seconds: 1.0, amplitude: 0.1),
         try writeTone(in: dir, name: "b second 2026-09-02.caf", seconds: 1.0, amplitude: 0.4),
         try writeTone(in: dir, name: "c third 2026-09-03.caf", seconds: 1.0, amplitude: 0.8)]
    }

    /// RMS of the middle 0.5 s of clip slot `slot` (each slot 1 s long) in the file at `url`.
    private func rms(ofSlot slot: Int, in url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        file.framePosition = AVAudioFramePosition((Double(slot) + 0.25) * rate)
        let n = AVAudioFrameCount(0.5 * rate)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: n)!
        try file.read(into: buf, frameCount: n)
        let p = buf.floatChannelData![0]
        var sum: Float = 0
        for i in 0..<Int(buf.frameLength) { sum += p[i] * p[i] }
        return (sum / Float(max(1, buf.frameLength))).squareRoot()
    }

    // MARK: - the chooser decision

    func testChooserOnlyAppearsForTwoOrMoreAudioClips() throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let clips = try threeClips(in: work)
        let note = work.appendingPathComponent("note.md")
        try "hello".write(to: note, atomically: true, encoding: .utf8)
        let folder = work.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        XCTAssertEqual(IngestService.audioClips(in: clips).count, 3)
        XCTAssertTrue(AudioImportChoice.needsChoice(clipCount: IngestService.audioClips(in: clips).count))
        XCTAssertFalse(AudioImportChoice.needsChoice(clipCount: IngestService.audioClips(in: [clips[0]]).count),
                       "one clip has nothing to choose")
        XCTAssertEqual(IngestService.audioClips(in: [clips[0], note, folder]).count, 1,
                       "a markdown note and a folder are not voice notes")
        XCTAssertEqual(AudioImportChoice.default, .oneNote, "One note is the default (C68)")
    }

    func testSheetWordingMatchesThePhonesChooser() {
        XCTAssertEqual(AudioImportChoice.oneNote.title(clipCount: 3), "One note")
        XCTAssertEqual(AudioImportChoice.separateNotes.title(clipCount: 3), "3 notes")
        XCTAssertEqual(AudioImportChoice.oneNote.confirmTitle(clipCount: 3), "Save as one note")
        XCTAssertEqual(AudioImportChoice.separateNotes.confirmTitle(clipCount: 3), "Save 3 notes")
    }

    // MARK: - One note

    func testThreeClipsOneNoteMergesInGivenOrderIntoOneRow() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let clips = try threeClips(in: work)
        let ctx = try makeContext()

        let created = try await ArrivalPath.run(
            urls: clips, asRecording: false, into: ctx, cloudContext: nil, hooks: .inert,
            service: IngestService(outputDir: work.appendingPathComponent("out")),
            combineAudio: true)

        XCTAssertEqual(created.count, 1, "3 clips + One note = ONE row, so ONE transcription pass")
        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(pf.sourceType, .audio)
        XCTAssertTrue(pf.path.hasSuffix("original.m4a"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pf.path))
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 1)

        let merged = try AVAudioFile(forReading: URL(fileURLWithPath: pf.path))
        let seconds = Double(merged.length) / merged.fileFormat.sampleRate
        XCTAssertEqual(seconds, 3.0, accuracy: 0.15, "the three 1 s clips end to end")

        let r0 = try rms(ofSlot: 0, in: URL(fileURLWithPath: pf.path))
        let r1 = try rms(ofSlot: 1, in: URL(fileURLWithPath: pf.path))
        let r2 = try rms(ofSlot: 2, in: URL(fileURLWithPath: pf.path))
        XCTAssertLessThan(r0, r1, "clip 1 (quiet) comes before clip 2")
        XCTAssertLessThan(r1, r2, "clip 2 comes before clip 3 (loud)")
    }

    func testOneNoteKeepsTheFirstClipsIdentity() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let clips = try threeClips(in: work)
        let ctx = try makeContext()

        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: clips, combineAudio: true, into: ctx)

        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(pf.filename, "a first 2026-09-01.caf", "named after the first clip")
        let day = Calendar.current.dateComponents([.year, .month, .day], from: pf.uploadedAt)
        XCTAssertEqual([day.year, day.month, day.day], [2026, 9, 1],
                       "dated from the FIRST clip's filename date (C70 ladder)")
    }

    // MARK: - N notes

    func testThreeClipsNNotesMakesThreeRows() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let clips = try threeClips(in: work)
        let ctx = try makeContext()

        let created = try await ArrivalPath.run(
            urls: clips, asRecording: false, into: ctx, cloudContext: nil, hooks: .inert,
            service: IngestService(outputDir: work.appendingPathComponent("out")),
            combineAudio: false)

        XCTAssertEqual(created.count, 3, "N notes = one row per clip, in the given order")
        XCTAssertEqual(created.map(\.filename), clips.map(\.lastPathComponent))
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 3)
    }

    func testDefaultIngestStaysSeparate() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let clips = try threeClips(in: work)
        let ctx = try makeContext()
        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: clips, into: ctx)
        XCTAssertEqual(created.count, 3, "callers that never ask (the -runfile harness) keep today's behaviour")
    }

    // MARK: - mixed bundles

    /// Clips merge; a markdown note in the same drop stays its own note (the Mac has no
    /// photo/annotation composer yet — the merged clips still land as ONE audio note).
    func testMixedBundleMergesTheClipsAndKeepsTheRest() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let clips = try threeClips(in: work)
        let note = work.appendingPathComponent("plan.md")
        try "Buy milk".write(to: note, atomically: true, encoding: .utf8)
        let ctx = try makeContext()

        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [clips[0], note, clips[1], clips[2]], combineAudio: true, into: ctx)

        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(created.first?.sourceType, .audio, "the merged note sits where the first clip was")
        XCTAssertEqual(created.last?.sourceType, .note)
    }

    func testUnreadableClipsFailLoudlyNotSilently() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let a = work.appendingPathComponent("a.m4a"), b = work.appendingPathComponent("b.m4a")
        try Data([0, 1, 2]).write(to: a); try Data([3, 4]).write(to: b)
        let ctx = try makeContext()
        do {
            _ = try await IngestService(outputDir: work.appendingPathComponent("out"))
                .ingest(localURLs: [a, b], combineAudio: true, into: ctx)
            XCTFail("a merge that produced no audio must throw, not mint an empty note")
        } catch {
            XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 0)
        }
    }
}
