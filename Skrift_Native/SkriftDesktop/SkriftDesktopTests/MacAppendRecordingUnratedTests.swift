import XCTest
import AVFoundation
import SwiftData

/// Q531 / D173: "Add recording" on an UNRATED voice note on the Mac, like the phone's +. The take
/// is joined onto the synced `Memo` (audio asset, raw transcript, shifted word timings) and the
/// note stays unrated: no `PipelineFile` is made and nothing is queued. The "recorded" clip is a
/// generated tone; no microphone.
@MainActor
final class MacAppendRecordingUnratedTests: XCTestCase {

    private var dir: URL!
    private var memoIDs: [UUID] = []

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacAppendRecordingUnratedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        memoIDs.forEach { MemoNoteProjection.discardMedia(for: $0) }
    }

    private func cloudContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func writeTone(_ name: String, seconds: Double, amplitude: Float) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let frames = AVAudioFrameCount(16_000 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let p = buf.floatChannelData![0]
        for i in 0..<Int(frames) { p[i] = amplitude * sinf(2 * .pi * 440 * Float(i) / 16_000) }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000.0, AVNumberOfChannelsKey: 1])
        try file.write(from: buf)
        return url
    }

    private func seconds(_ url: URL) throws -> Double {
        let f = try AVAudioFile(forReading: url)
        return Double(f.length) / f.processingFormat.sampleRate
    }

    /// An UNRATED voice note as the phone syncs it: a memo (significance 0) with its audio asset
    /// and one word-timings asset.
    private func unratedVoiceNote(base: URL, transcript: String, cloud: ModelContext) throws -> Memo {
        let id = UUID()
        memoIDs.append(id)
        let name = "memo_\(id.uuidString).m4a"
        let memo = Memo(id: id, audioFilename: name, duration: try seconds(base), recordedAt: Date())
        memo.transcript = transcript
        memo.transcriptStatus = .done
        cloud.insert(memo)
        cloud.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.audio, filename: name,
                               blob: try Data(contentsOf: base)))
        let first = TimingAssets.wordTimingsBlob([WordTiming(word: "first", start: 0.1, end: 0.4)])!
        cloud.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.wordTimings,
                               filename: TimingAssets.wordTimingsFilename(for: id), blob: first))
        try cloud.save()
        return memo
    }

    // MARK: - the menu

    func testAnUnratedVoiceNoteOffersAddRecordingInTheUnratedMenu() throws {
        let cloud = try cloudContext()
        let base = try writeTone("base.m4a", seconds: 1.0, amplitude: 0.1)
        let memo = try unratedVoiceNote(base: base, transcript: "First thought.", cloud: cloud)
        XCTAssertEqual(memo.significance, 0, "the note is unrated")

        let projection = MemoNoteProjection.materialisedFile(for: memo, cloud: cloud)
        XCTAssertFalse(projection.path.isEmpty, "the audio is on disk, as the entry needs")
        let offered = MacAppendRecording.isOfferedOnUnrated(projection, locked: projection.locked,
                                                            memoStatus: memo.transcriptStatus)
        XCTAssertTrue(offered)

        let entries = MacUnratedMenu.entries(rated: false, locked: false, canUndoTidyUp: false,
                                             canAddRecording: offered)
        XCTAssertEqual(entries, [.process, .item(.addRecording), .item(.lock), .item(.copyTranscript),
                                 .item(.copyMarkdown), .item(.delete)])
        XCTAssertEqual(MacUnratedMenu.label(.item(.addRecording)), NoteMenuItem.addRecording.label,
                       "the same entry label as the phone")
        XCTAssertFalse(MacUnratedMenu.entries(rated: false, locked: false, canUndoTidyUp: false)
            .contains(.item(.addRecording)), "off by default: existing callers are unchanged")
    }

    func testALockedUnratedNoteDoesNotOfferIt() throws {
        let cloud = try cloudContext()
        let base = try writeTone("base.m4a", seconds: 1.0, amplitude: 0.1)
        let memo = try unratedVoiceNote(base: base, transcript: "Private.", cloud: cloud)
        memo.locked = true

        let projection = MemoNoteProjection.materialisedFile(for: memo, cloud: cloud)
        XCTAssertTrue(projection.locked)
        XCTAssertFalse(MacAppendRecording.isOfferedOnUnrated(projection, locked: projection.locked,
                                                             memoStatus: memo.transcriptStatus))
    }

    func testNotOfferedWhileThePhoneIsStillTranscribingIt() throws {
        let cloud = try cloudContext()
        let base = try writeTone("base.m4a", seconds: 1.0, amplitude: 0.1)
        let memo = try unratedVoiceNote(base: base, transcript: "", cloud: cloud)
        memo.transcriptStatus = .transcribing

        let projection = MemoNoteProjection.materialisedFile(for: memo, cloud: cloud)
        XCTAssertFalse(MacAppendRecording.isOfferedOnUnrated(projection, locked: false,
                                                             memoStatus: memo.transcriptStatus))
    }

    func testATypedNoteWithNoAudioIsNotOffered() throws {
        let cloud = try cloudContext()
        let memo = Memo(id: UUID(), audioFilename: "", duration: 0, recordedAt: Date())
        memo.transcript = "typed"
        cloud.insert(memo)
        try cloud.save()
        let projection = MemoNoteProjection.materialisedFile(for: memo, cloud: cloud)
        XCTAssertFalse(MacAppendRecording.isOfferedOnUnrated(projection, locked: false, memoStatus: .done))
    }

    // MARK: - the append

    /// The audio asset is the joined audio, the raw transcript the old body + a blank line + the
    /// clip's words, the clip's word timings are shifted past the base, and no PipelineFile exists.
    func testAppendingAClipWritesJoinedAudioAndTranscriptToTheMemoOnly() throws {
        let cloud = try cloudContext()
        let rows = ModelContext(try ModelContainer(for: PipelineFile.self,
                                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let base = try writeTone("base.m4a", seconds: 1.0, amplitude: 0.1)
        let clip = try writeTone("clip.m4a", seconds: 0.6, amplitude: 0.8)
        let memo = try unratedVoiceNote(base: base, transcript: "First thought.", cloud: cloud)
        let baseBytes = try Data(contentsOf: base)

        // The pane's own path: the projection materialises the audio from the synced blob.
        let projection = MemoNoteProjection.materialisedFile(for: memo, cloud: cloud)
        let audioURL = URL(fileURLWithPath: projection.path)
        XCTAssertEqual(try Data(contentsOf: audioURL), baseBytes)

        let splice = try MacAppendRecording.spliceAudio(path: projection.path, clip: clip)
        try MacAppendRecording.landOnMemo(
            text: " And a second one. ", timings: [WordTiming(word: "And", start: 0.0, end: 0.2)],
            splice: splice, audioURL: audioURL, memo: memo, cloud: cloud)

        XCTAssertEqual(memo.transcript, "First thought.\n\nAnd a second one.")
        XCTAssertTrue(memo.transcriptUserEdited)
        XCTAssertEqual(memo.transcriptStatus, .done)
        XCTAssertEqual(memo.significance, 0, "the note stays unrated")
        XCTAssertEqual(memo.duration, splice.merged, accuracy: 0.001)
        XCTAssertGreaterThan(memo.duration, 1.5)

        let memoID = memo.id
        let assets = try cloud.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == memoID }))
        let audio = try XCTUnwrap(assets.first { $0.kind == MemoAsset.Kind.audio })
        XCTAssertEqual(audio.blob, try Data(contentsOf: audioURL), "the synced audio is the spliced file")
        XCTAssertNotEqual(audio.blob, baseBytes)
        XCTAssertEqual(audio.byteCount, audio.blob.count)
        XCTAssertEqual(try seconds(audioURL), splice.merged, accuracy: 0.05)

        let timings = try JSONDecoder().decode(
            [WordTiming].self, from: try XCTUnwrap(assets.first { $0.kind == MemoAsset.Kind.wordTimings }).blob)
        XCTAssertEqual(timings.map(\.word), ["first", "And"])
        XCTAssertEqual(timings[1].start, splice.base, accuracy: 0.001, "shifted past the base audio")

        XCTAssertEqual(try rows.fetchCount(FetchDescriptor<PipelineFile>()), 0, "no PipelineFile is created")
    }

    /// The words are appended to the RAW transcript even when the note shows names linked.
    func testAppendKeepsTheRawTranscriptNotTheLinkedDisplayText() throws {
        let cloud = try cloudContext()
        let base = try writeTone("base.m4a", seconds: 1.0, amplitude: 0.1)
        let clip = try writeTone("clip.m4a", seconds: 0.5, amplitude: 0.8)
        let memo = try unratedVoiceNote(base: base, transcript: "Met Nik today.", cloud: cloud)
        let projection = MemoNoteProjection.materialisedFile(for: memo, cloud: cloud)
        projection.sanitised = "Met [[Nick Jansen]] today."   // what the pane shows; never the memo's text

        let splice = try MacAppendRecording.spliceAudio(path: projection.path, clip: clip)
        try MacAppendRecording.landOnMemo(text: "More.", timings: [], splice: splice,
                                          audioURL: URL(fileURLWithPath: projection.path), memo: memo, cloud: cloud)
        XCTAssertEqual(memo.transcript, "Met Nik today.\n\nMore.")
    }

    /// The engine heard nothing: audio + duration land, the body is left as it was.
    func testNoWordsKeepsTheBodyButAddsTheAudio() throws {
        let cloud = try cloudContext()
        let base = try writeTone("base.m4a", seconds: 1.0, amplitude: 0.1)
        let clip = try writeTone("clip.m4a", seconds: 0.5, amplitude: 0.0)
        let memo = try unratedVoiceNote(base: base, transcript: "Only this.", cloud: cloud)
        let projection = MemoNoteProjection.materialisedFile(for: memo, cloud: cloud)

        let splice = try MacAppendRecording.spliceAudio(path: projection.path, clip: clip)
        try MacAppendRecording.landOnMemo(text: "  ", timings: [], splice: splice,
                                          audioURL: URL(fileURLWithPath: projection.path), memo: memo, cloud: cloud)
        XCTAssertEqual(memo.transcript, "Only this.")
        XCTAssertFalse(memo.transcriptUserEdited)
        XCTAssertEqual(memo.duration, splice.merged, accuracy: 0.001)
    }
}
