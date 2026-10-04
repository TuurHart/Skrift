import XCTest
import AVFoundation
import SwiftData

/// Q290 / D173: "Add recording" on the Mac appends a take to an EXISTING note through the shared
/// `AudioClipMerge.append` (the phone's stitcher). The append step is data-correctness: the
/// note's own audio and words are never lost, whatever fails.
@MainActor
final class MacAppendRecordingTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacAppendRecordingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func cloudContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    /// `seconds` of a 440 Hz tone at `amplitude`, 16 kHz mono. `aac` writes an m4a (the
    /// recorder's own format); otherwise a CAF of linear PCM.
    private func writeTone(_ name: String, seconds: Double, amplitude: Float, aac: Bool = true) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let frames = AVAudioFrameCount(16_000 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let p = buf.floatChannelData![0]
        for i in 0..<Int(frames) { p[i] = amplitude * sinf(2 * .pi * 440 * Float(i) / 16_000) }
        let settings: [String: Any] = aac
            ? [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000.0, AVNumberOfChannelsKey: 1]
            : format.settings
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buf)
        return url
    }

    private func seconds(_ url: URL) throws -> Double {
        let f = try AVAudioFile(forReading: url)
        return Double(f.length) / f.processingFormat.sampleRate
    }

    /// RMS of `window` seconds starting at `at` in the file.
    private func rms(at: Double, window: Double = 0.3, in url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        file.framePosition = AVAudioFramePosition(at * rate)
        let n = AVAudioFrameCount(window * rate)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: n)!
        try file.read(into: buf, frameCount: n)
        let p = buf.floatChannelData![0]
        var sum: Float = 0
        for i in 0..<Int(buf.frameLength) { sum += p[i] * p[i] }
        return (sum / Float(max(1, buf.frameLength))).squareRoot()
    }

    /// A rated audio row whose `original.m4a` is `base`, with a synced memo + its audio asset.
    private func note(base: URL, transcript: String, cloud: ModelContext) throws -> (PipelineFile, Memo) {
        let id = UUID()
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a", path: base.path)
        pf.transcript = transcript
        pf.transcribeStatus = .done
        pf.wordTimings = [WordTiming(word: "first", start: 0.1, end: 0.4)]
        let memo = Memo(id: id, audioFilename: pf.filename, duration: try seconds(base), recordedAt: Date())
        memo.transcript = transcript
        memo.transcriptStatus = .done
        cloud.insert(memo)
        cloud.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.audio, filename: pf.filename,
                               blob: try Data(contentsOf: base)))
        try cloud.save()
        return (pf, memo)
    }

    // MARK: - the audio step (shared AudioClipMerge.append)

    /// The clip lands AFTER the note's audio, in the same file, and the splice offset is the
    /// base's precise duration.
    func testSpliceAppendsClipAfterBaseInPlace() throws {
        let base = try writeTone("original.m4a", seconds: 1.0, amplitude: 0.1)
        let clip = try writeTone("clip.m4a", seconds: 0.6, amplitude: 0.8)

        let r = try MacAppendRecording.spliceAudio(path: base.path, clip: clip)

        XCTAssertEqual(r.base, 1.0, accuracy: 0.05)
        XCTAssertEqual(r.merged, 1.6, accuracy: 0.1)
        XCTAssertEqual(try seconds(base), r.merged, accuracy: 0.01, "the base file IS the merged file now")
        XCTAssertLessThan(try rms(at: 0.3, in: base), 0.2, "the note's own (quiet) audio comes first")
        XCTAssertGreaterThan(try rms(at: 1.2, in: base), 0.4, "the (loud) clip follows it")
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.path), "the clip is the caller's to delete")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("append_") }
        XCTAssertEqual(leftovers, [], "no temp file left behind")
    }

    /// A base that is not an m4a (a dropped CAF/WAV) keeps its name and still reads back whole.
    func testSpliceKeepsANonM4ABaseReadable() throws {
        let base = try writeTone("original.caf", seconds: 1.0, amplitude: 0.1, aac: false)
        let clip = try writeTone("clip.m4a", seconds: 0.5, amplitude: 0.8)

        let r = try MacAppendRecording.spliceAudio(path: base.path, clip: clip)

        XCTAssertEqual(try seconds(base), r.merged, accuracy: 0.01)
        XCTAssertEqual(r.merged, 1.5, accuracy: 0.1)
    }

    /// An unreadable note audio is a HARD failure: `merge` alone would skip it and write the
    /// clip as the whole note. The base must stay byte-for-byte what it was.
    func testUnreadableBaseThrowsAndKeepsTheBase() throws {
        let base = dir.appendingPathComponent("original.m4a")
        let garbage = Data("not audio at all".utf8)
        try garbage.write(to: base)
        let clip = try writeTone("clip.m4a", seconds: 0.5, amplitude: 0.8)

        XCTAssertThrowsError(try MacAppendRecording.spliceAudio(path: base.path, clip: clip)) {
            XCTAssertEqual($0 as? AudioClipMerge.AppendError, .unreadableBase)
        }
        XCTAssertEqual(try Data(contentsOf: base), garbage)
    }

    /// An unreadable clip leaves the note's audio untouched (no needless re-encode either).
    func testUnreadableClipThrowsAndKeepsTheBase() throws {
        let base = try writeTone("original.m4a", seconds: 1.0, amplitude: 0.1)
        let before = try Data(contentsOf: base)
        let clip = dir.appendingPathComponent("clip.m4a")
        try Data("nope".utf8).write(to: clip)

        XCTAssertThrowsError(try MacAppendRecording.spliceAudio(path: base.path, clip: clip)) {
            XCTAssertEqual($0 as? AudioClipMerge.AppendError, .unreadableAddition)
        }
        XCTAssertEqual(try Data(contentsOf: base), before)
    }

    /// A row with no audio file (a typed note) refuses before anything is read.
    func testNoAudioRowRefuses() {
        let clip = dir.appendingPathComponent("clip.m4a")
        XCTAssertThrowsError(try MacAppendRecording.spliceAudio(path: "", clip: clip)) {
            XCTAssertEqual($0 as? MacAppendRecording.AppendError, .noAudio)
        }
    }

    // MARK: - the words step

    /// The words follow the body after a blank line, the timings move past the base, the row
    /// and the memo both carry the combined trusted transcript, and the memo's audio asset is
    /// the merged file.
    func testLandAppendsWordsTimingsAndSyncsTheMemo() throws {
        let cloud = try cloudContext()
        let base = try writeTone("original.m4a", seconds: 1.0, amplitude: 0.1)
        let clip = try writeTone("clip.m4a", seconds: 0.6, amplitude: 0.8)
        let (pf, memo) = try note(base: base, transcript: "First thought.", cloud: cloud)

        let splice = try MacAppendRecording.spliceAudio(path: pf.path, clip: clip)
        try MacAppendRecording.land(text: " And a second one. ",
                                    timings: [WordTiming(word: "And", start: 0.0, end: 0.2)],
                                    splice: splice, on: pf, memo: memo, cloud: cloud,
                                    people: [], author: "Tuur")

        XCTAssertEqual(pf.transcript, "First thought.\n\nAnd a second one.")
        XCTAssertTrue(pf.transcriptUserEdited)
        XCTAssertEqual(pf.transcribeStatus, .done)
        XCTAssertEqual(pf.wordTimings.count, 2)
        XCTAssertEqual(pf.wordTimings[1].start, splice.base, accuracy: 0.001, "shifted by the splice offset")
        XCTAssertEqual(pf.durationSeconds, splice.merged, accuracy: 0.001)

        XCTAssertEqual(memo.transcript, pf.transcript, "the sweep must not revert the row to the old words")
        XCTAssertTrue(memo.transcriptUserEdited)
        XCTAssertEqual(memo.duration, splice.merged, accuracy: 0.001)
        let memoID = memo.id
        let audio = try XCTUnwrap(try cloud.fetch(FetchDescriptor<MemoAsset>(
            predicate: #Predicate { $0.memoID == memoID })).first { $0.kind == MemoAsset.Kind.audio })
        XCTAssertEqual(audio.blob, try Data(contentsOf: base), "the synced audio is the merged file")
        XCTAssertEqual(audio.byteCount, audio.blob.count)
    }

    /// A polished note shows its copy-edit: the new words land there too, and the polish is
    /// written back as this Mac's so the sweep can't restore the old copy-edit over it.
    func testLandOnAPolishedNoteExtendsTheCopyEditAndWritesItBack() throws {
        let cloud = try cloudContext()
        let base = try writeTone("original.m4a", seconds: 1.0, amplitude: 0.1)
        let clip = try writeTone("clip.m4a", seconds: 0.5, amplitude: 0.8)
        let (pf, memo) = try note(base: base, transcript: "first thought", cloud: cloud)
        pf.enhancedCopyedit = "First thought."
        pf.enhancedTitle = "Thoughts"

        let splice = try MacAppendRecording.spliceAudio(path: pf.path, clip: clip)
        try MacAppendRecording.land(text: "second thought", timings: [], splice: splice,
                                    on: pf, memo: memo, cloud: cloud, people: [], author: "Tuur",
                                    deviceID: "this-mac")

        XCTAssertEqual(pf.enhancedCopyedit, "First thought.\n\nsecond thought")
        XCTAssertTrue(pf.bestBodyText.contains("second thought"), "the shown body holds the new words")
        let memoID = memo.id
        let enh = try XCTUnwrap(try cloud.fetch(FetchDescriptor<MemoEnhancement>(
            predicate: #Predicate { $0.memoID == memoID })).first)
        XCTAssertEqual(enh.enhancedByDeviceID, "this-mac")
        XCTAssertTrue(enh.copyedit.contains("second thought"))
    }

    /// The engine heard nothing: the audio + duration land, the body is left as it was.
    func testLandWithNoWordsKeepsTheBody() throws {
        let cloud = try cloudContext()
        let base = try writeTone("original.m4a", seconds: 1.0, amplitude: 0.1)
        let clip = try writeTone("clip.m4a", seconds: 0.5, amplitude: 0.0)
        let (pf, memo) = try note(base: base, transcript: "Only this.", cloud: cloud)

        let splice = try MacAppendRecording.spliceAudio(path: pf.path, clip: clip)
        try MacAppendRecording.land(text: "  ", timings: [], splice: splice, on: pf, memo: memo,
                                    cloud: cloud, people: [], author: "Tuur")

        XCTAssertEqual(pf.transcript, "Only this.")
        XCTAssertFalse(pf.transcriptUserEdited)
        XCTAssertEqual(memo.transcript, "Only this.")
        XCTAssertEqual(memo.duration, splice.merged, accuracy: 0.001)
    }

    // MARK: - the menu gate

    func testOfferedOnlyOnAnUnlockedAudioNoteWithAudio() {
        let audio = PipelineFile(filename: "a.m4a", path: "/tmp/a/original.m4a", sourceType: .audio)
        XCTAssertTrue(MacAppendRecording.isOffered(audio, locked: false))
        XCTAssertFalse(MacAppendRecording.isOffered(audio, locked: true))
        audio.transcribeStatus = .processing
        XCTAssertFalse(MacAppendRecording.isOffered(audio, locked: false), "a running pass would overwrite it")
        XCTAssertFalse(MacAppendRecording.isOffered(
            PipelineFile(filename: "n.md", path: "/tmp/n/original.md", sourceType: .note), locked: false))
        XCTAssertFalse(MacAppendRecording.isOffered(PipelineFile(filename: "x.m4a"), locked: false))
    }
}
