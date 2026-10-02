import AVFoundation
import SwiftData
import XCTest

/// Q163 (C99 / D131 / R46 / C224): the Mac recorder survives a kill. A take the process
/// never finished leaves `rec_seg_<take>_NNN.m4a` segments + a `rec_ckpt_<take>.json`
/// marker; the launch sweep turns them into a note. Every take here is SYNTHETIC — a sine
/// wave written through the real `RecordingCheckpoint`, a "kill" being "never finalised,
/// marker stamped by a dead run". No microphone, no capture session.
@MainActor
final class MacRecoverySweepTests: XCTestCase {

    // MARK: - fixtures

    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("macsweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: work)
    }

    private var recordings: URL { work.appendingPathComponent("recordings", isDirectory: true) }
    private var quarantine: URL { work.appendingPathComponent("QuarantinedRecordings", isDirectory: true) }

    private func pipelineContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func cloudContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                           cloudKitDatabase: .none)))
    }

    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                       channels: 1, interleaved: false)!

    /// One second of a sine tone — distinct frequencies keep two takes from being byte-twins.
    private func tone(_ hz: Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(format.sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buf.frameLength = n
        let ch = buf.floatChannelData![0]
        for i in 0..<Int(n) { ch[i] = Float(0.3 * sin(2 * Double.pi * hz * Double(i) / format.sampleRate)) }
        return buf
    }

    /// A take that DIED mid-record: `seconds` of tone written through the real checkpoint
    /// (1 s segments so the rotation runs), never finalised, its marker re-stamped as
    /// belonging to an earlier process run. Returns the take id.
    @discardableResult
    private func deadTake(seconds: Int, hz: Double, startedAt: Date, finalized: Bool = false) throws -> String {
        let take = UUID().uuidString
        let cp = RecordingCheckpoint(directory: recordings, takeID: take,
                                     settings: RecordingCore.encoderSettings(for: format),
                                     sampleRate: format.sampleRate, segmentSeconds: 1, startedAt: startedAt)
        for _ in 0..<seconds { try cp.write(tone(hz)) }
        cp.rotate(reason: "test-kill")          // the last close a real kill would have had
        if finalized { cp.finalize() }
        try restampAsEarlierRun(take: take)
        return take
    }

    /// The marker says which process run owns the take; the sweep skips THIS run's takes
    /// (they are live). A dead run's marker is one with a different session id.
    private func restampAsEarlierRun(take: String) throws {
        let url = recordings.appendingPathComponent(RecordingCheckpoint.markerFilename(take: take))
        var marker = try JSONDecoder().decode(RecordingMarker.self, from: Data(contentsOf: url))
        marker.sessionID = "EARLIER-RUN-\(UUID().uuidString)"
        try JSONEncoder().encode(marker).write(to: url, options: .atomic)
    }

    private func sweep(_ ctx: ModelContext, cloud: ModelContext?, transcribed: ((([String]) -> Void))? = nil)
        async -> RecordingSweep.Report {
        var hooks = ArrivalPath.Hooks.inert
        if let transcribed { hooks.transcribe = { transcribed($0) } }
        return await MacRecoverySweep.run(directory: recordings, into: ctx, cloudContext: cloud, hooks: hooks,
                                          service: IngestService(outputDir: work.appendingPathComponent("out")))
    }

    // MARK: - the orphan comes back as a note

    func testAnOrphanSegmentSetBecomesATitledNoteDatedWhenTheTakeStarted() async throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let take = try deadTake(seconds: 3, hz: 440, startedAt: started)
        let ctx = try pipelineContext(), cloud = try cloudContext()
        var transcribed: [String] = []

        let report = await sweep(ctx, cloud: cloud) { transcribed = $0 }

        XCTAssertEqual(report.recovered.count, 1, "the dead take must come back as exactly one note")
        XCTAssertTrue(report.kept.isEmpty && report.cleaned.isEmpty)
        let rows = try ctx.fetch(FetchDescriptor<PipelineFile>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.enhancedTitle, RecordingSweep.recoveredTitle,
                       "the user must be able to SEE the note was recovered")
        XCTAssertEqual(rows.first?.uploadedAt, started, "dated when the take started, not when the sweep ran")
        XCTAssertEqual(transcribed, rows.map(\.id), "a recovered take is transcribed like any capture")

        let memos = try cloud.fetch(FetchDescriptor<Memo>())
        XCTAssertEqual(memos.count, 1)
        XCTAssertEqual(memos.first?.title, RecordingSweep.recoveredTitle)
        XCTAssertEqual(memos.first?.significance, 0, "a recovered capture is unrated, like every capture (D159)")
        XCTAssertGreaterThanOrEqual(memos.first?.duration ?? 0, 2.5,
                                    "all audio up to the last closed segment survives")
        XCTAssertEqual(report.recovered.first.map(\.uuidString), memos.first.map { $0.id.uuidString })

        // Everything the take left behind is gone — it is stored, so the next launch cannot
        // rebuild it a second time.
        XCTAssertTrue(RecordingCheckpoint.takeFiles(take: take, in: recordings).isEmpty)
    }

    func testSegmentsWithNoMarkerAtAllAreStillRecovered() async throws {
        let take = try deadTake(seconds: 2, hz: 523, startedAt: Date())
        try FileManager.default.removeItem(at: recordings.appendingPathComponent(
            RecordingCheckpoint.markerFilename(take: take)))
        let ctx = try pipelineContext()

        let report = await sweep(ctx, cloud: nil)

        XCTAssertEqual(report.recovered.count, 1, "a kill before the marker landed still must not lose the audio")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 1)
    }

    func testACleanlyClosedMainFileWinsOverItsSegments() async throws {
        // A force-quit that delivered willTerminate: main closed, marker finalised.
        let take = UUID().uuidString
        let settings = RecordingCore.encoderSettings(for: format)
        let main = recordings.appendingPathComponent(RecordingCheckpoint.mainFilename(take: take))
        let file = try AVAudioFile(forWriting: main, settings: settings)
        for _ in 0..<2 { try file.write(from: tone(660)) }
        file.close()
        let cp = RecordingCheckpoint(directory: recordings, takeID: take, settings: settings,
                                     sampleRate: format.sampleRate, segmentSeconds: 1)
        try cp.write(tone(660))
        cp.finalize()
        try restampAsEarlierRun(take: take)

        let marker = try JSONDecoder().decode(RecordingMarker.self, from: Data(contentsOf: cp.markerURL))
        XCTAssertTrue(marker.finalized)
        XCTAssertEqual(RecordingSweep.recoverableSources(take: take, marker: marker, in: recordings).map(\.lastPathComponent),
                       [RecordingCheckpoint.mainFilename(take: take)])

        let report = await sweep(try pipelineContext(), cloud: nil)
        XCTAssertEqual(report.recovered.count, 1)
    }

    // MARK: - what must NOT happen

    func testATakeOwnedByThisRunIsNeverSweptOutFromUnderALiveRecording() async throws {
        let take = UUID().uuidString
        let cp = RecordingCheckpoint(directory: recordings, takeID: take,
                                     settings: RecordingCore.encoderSettings(for: format),
                                     sampleRate: format.sampleRate, segmentSeconds: 1)
        try cp.write(tone(440)); try cp.write(tone(440))     // a live take, segment closed
        let ctx = try pipelineContext()

        let report = await sweep(ctx, cloud: nil)

        XCTAssertTrue(report.recovered.isEmpty && report.cleaned.isEmpty && report.kept.isEmpty)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 0)
        XCTAssertFalse(RecordingCheckpoint.takeFiles(take: take, in: recordings).isEmpty,
                       "a live take's files are untouched")
        cp.discard()
    }

    func testAnUnreadableTakeIsQuarantinedNeverDeleted() async throws {
        let take = UUID().uuidString
        let junk = recordings.appendingPathComponent(RecordingCheckpoint.segmentFilename(take: take, index: 1))
        try Data(repeating: 7, count: 2048).write(to: junk)       // a truncated, index-less m4a
        let ctx = try pipelineContext()

        let report = await sweep(ctx, cloud: nil)

        XCTAssertEqual(report.cleaned, [take])
        XCTAssertTrue(report.recovered.isEmpty)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 0, "no empty ghost note")
        XCTAssertFalse(FileManager.default.fileExists(atPath: junk.path), "out of the recordings dir")
        let kept = (try? FileManager.default.contentsOfDirectory(atPath: quarantine.path)) ?? []
        XCTAssertTrue(kept.contains(junk.lastPathComponent), "moved to QuarantinedRecordings, never deleted")
    }

    func testTwoDeadTakesBothComeBackOldestFirst() async throws {
        let older = try deadTake(seconds: 2, hz: 300, startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = try deadTake(seconds: 2, hz: 900, startedAt: Date(timeIntervalSince1970: 1_700_100_000))
        let ctx = try pipelineContext()

        let report = await sweep(ctx, cloud: nil)

        XCTAssertEqual(report.recovered.count, 2)
        XCTAssertTrue(RecordingCheckpoint.takeFiles(take: older, in: recordings).isEmpty)
        XCTAssertTrue(RecordingCheckpoint.takeFiles(take: newer, in: recordings).isEmpty)
        let dates = try ctx.fetch(FetchDescriptor<PipelineFile>(sortBy: [SortDescriptor(\.uploadedAt)])).map(\.uploadedAt)
        XCTAssertEqual(dates, [Date(timeIntervalSince1970: 1_700_000_000), Date(timeIntervalSince1970: 1_700_100_000)])
    }

    // MARK: - R46: a write failure stops the take and titles the note

    func testTheWriteFailureMessageSaysTheTakeStoppedAndWhatIsSafe() {
        let m = MacRecorder.writeFailureMessage
        XCTAssertTrue(m.contains("stopped"))
        XCTAssertTrue(m.contains("saved"), "the user's first question is whether the words are safe")
    }

    func testTitlingATakeWritesTheReasonOnTheRowAndTheSyncedMemo() async throws {
        let ctx = try pipelineContext(), cloud = try cloudContext()
        let id = UUID()
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id).m4a", path: "")
        ctx.insert(pf)
        cloud.insert(Memo(id: id, audioFilename: pf.filename))

        MacTakeTitle.apply(MacRecorder.writeFailureMessage, to: pf, cloudContext: cloud)

        XCTAssertEqual(pf.enhancedTitle, MacRecorder.writeFailureMessage)
        XCTAssertEqual(try cloud.fetch(FetchDescriptor<Memo>()).first?.title, MacRecorder.writeFailureMessage,
                       "the phone must show why too")
    }

    // MARK: - the shared core keeps the phone's on-disk contract

    func testTakeFilenamesRoundTripThroughTheSharedParsers() {
        let take = "ABC-123"
        XCTAssertEqual(RecordingSweep.takeID(fromAudio: RecordingCheckpoint.segmentFilename(take: take, index: 7)), take)
        XCTAssertEqual(RecordingSweep.takeID(fromAudio: RecordingCheckpoint.mainFilename(take: take)), take)
        XCTAssertEqual(RecordingSweep.takeID(fromMarker: RecordingCheckpoint.markerFilename(take: take)), take)
        XCTAssertEqual(RecordingCheckpoint.segmentFilename(take: take, index: 7), "rec_seg_ABC-123_007.m4a")
        XCTAssertNil(RecordingSweep.takeID(fromAudio: "memo_ABC.m4a"), "a finished memo file is never a take")
    }
}
