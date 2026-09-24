import AVFoundation
import XCTest
@testable import SkriftMobile

/// Q27 / C99 / C288 — an unreadable orphan from a failed recovery sweep is
/// QUARANTINED (moved out of the recordings directory + kept, with a sidecar),
/// never deleted. Device evidence 2026-09-24: the launch sweep deleted 5 legacy
/// `rec_tmp_*` orphans on first launch; an m4a with no moov atom is often
/// rescuable (`tools/rescue-lost-recordings.py`), so deletion risks real data.
@MainActor
final class RecoveryQuarantineTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quarantine_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: MemoSaver.quarantineDirectory(besideRecordings: dir))
    }

    private let rate: Double = 44_100

    private var settings: [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
         AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
    }

    private func tone(seconds: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(rate * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let ch = buf.floatChannelData![0]
        for i in 0..<Int(frames) { ch[i] = 0.3 * sinf(Float(i) * 2 * .pi * 440 / Float(rate)) }
        return buf
    }

    private func pretendPreviousRun(_ cp: RecordingCheckpoint) throws {
        var m = try JSONDecoder().decode(RecordingMarker.self, from: Data(contentsOf: cp.markerURL))
        m.sessionID = "previous-run"
        try JSONEncoder().encode(m).write(to: cp.markerURL)
    }

    private func saver(_ repo: NotesRepository) -> MemoSaver {
        MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "engine words"),
                  wordTimings: WordTimingsStore(directory: dir), metadataProvider: MockMetadataService())
    }

    func testUnreadableOrphanIsQuarantinedByteIdenticalNeverRemoved() async throws {
        let cp = RecordingCheckpoint(directory: dir, takeID: "DEAD", settings: settings,
                                     sampleRate: 44_100, segmentSeconds: 60)
        let junk = Data("not a real moov atom".utf8)
        try junk.write(to: cp.mainURL)
        try pretendPreviousRun(cp)
        XCTAssertFalse(RecordingCheckpoint.isReadableAudio(cp.mainURL), "precondition: unreadable")

        let repo = NotesRepository(inMemory: true)
        let report = await saver(repo).recoverInterruptedRecordings(directory: dir)

        XCTAssertEqual(report.recovered, [])
        XCTAssertEqual(report.cleaned, ["DEAD"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cp.mainURL.path),
                       "gone from the recordings directory")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cp.markerURL.path))

        let quarantineDir = MemoSaver.quarantineDirectory(besideRecordings: dir)
        let quarantinedMain = quarantineDir.appendingPathComponent(cp.mainURL.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantinedMain.path),
                      "moved, not deleted")
        let quarantinedData = try Data(contentsOf: quarantinedMain)
        XCTAssertEqual(quarantinedData, junk, "byte-identical to what was recorded")

        let sidecarURL = quarantineDir.appendingPathComponent("quarantine_DEAD.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path), "sidecar written")
        let sidecar = try JSONDecoder().decode(MemoSaver.QuarantinedTakeSidecar.self,
                                                from: Data(contentsOf: sidecarURL))
        XCTAssertEqual(sidecar.take, "DEAD")
        XCTAssertEqual(sidecar.fileSizes[cp.mainURL.lastPathComponent], junk.count)
    }

    func testQuarantinedTakeIsNeverReSweptIntoANote() async throws {
        let cp = RecordingCheckpoint(directory: dir, takeID: "DEAD", settings: settings,
                                     sampleRate: 44_100, segmentSeconds: 60)
        try Data("not audio".utf8).write(to: cp.mainURL)
        try pretendPreviousRun(cp)

        let repo = NotesRepository(inMemory: true)
        _ = await saver(repo).recoverInterruptedRecordings(directory: dir)
        XCTAssertTrue(repo.allMemos().isEmpty, "no husk note from the first sweep")

        // A second launch sweeps the SAME (now-empty) directory again.
        let secondReport = await saver(repo).recoverInterruptedRecordings(directory: dir)
        XCTAssertEqual(secondReport, MemoSaver.RecordingSweepReport(),
                       "the quarantined take is gone from the swept directory — never seen again")
        XCTAssertTrue(repo.allMemos().isEmpty)
    }

    /// Coordinator finding: after a SUCCESSFUL rebuild, an unfinalized main or a
    /// truncated in-progress segment that never made it into the merged sources
    /// must be quarantined, not deleted alongside the files that DID merge.
    func testRebuildQuarantinesTheUnmergedFilesAliveAlongsideTheRecoveredNote() async throws {
        let cp = RecordingCheckpoint(directory: dir, takeID: "MIXED", settings: settings,
                                     sampleRate: rate, segmentSeconds: 0.5)
        try cp.write(tone(seconds: 0.6))   // closes to rec_seg_MIXED_001.m4a
        try cp.write(tone(seconds: 0.6))   // closes to rec_seg_MIXED_002.m4a
        XCTAssertEqual(cp.marker.segments, ["rec_seg_MIXED_001.m4a", "rec_seg_MIXED_002.m4a"],
                       "precondition: two closed, readable segments")

        // A third segment the process died mid-write on: on disk, unlisted in
        // the marker, and unreadable — never rotated closed.
        let truncatedSeg = Data("truncated segment, no moov atom".utf8)
        try truncatedSeg.write(to: dir.appendingPathComponent("rec_seg_MIXED_003.m4a"))
        // The unfinalized main: on disk for the whole take, also unreadable.
        let mainJunk = Data("unfinalized main, no moov atom either".utf8)
        try mainJunk.write(to: cp.mainURL)
        try pretendPreviousRun(cp)
        XCTAssertFalse(RecordingCheckpoint.isReadableAudio(dir.appendingPathComponent("rec_seg_MIXED_003.m4a")))
        XCTAssertFalse(RecordingCheckpoint.isReadableAudio(cp.mainURL))

        let repo = NotesRepository(inMemory: true)
        let report = await saver(repo).recoverInterruptedRecordings(directory: dir)

        XCTAssertEqual(report.recovered.count, 1, "the note still rebuilds from the two readable segments")
        let memo = try XCTUnwrap(report.recovered.first.flatMap { repo.memo(id: $0) })
        XCTAssertEqual(memo.duration, 1.2, accuracy: 0.1)

        // Nothing of MIXED's is left in the recordings directory.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("MIXED") },
                       [], "every MIXED file left the recordings directory")

        // The unmerged files end up in quarantine, byte-identical.
        let quarantineDir = MemoSaver.quarantineDirectory(besideRecordings: dir)
        let quarantinedSeg = quarantineDir.appendingPathComponent("rec_seg_MIXED_003.m4a")
        let quarantinedMain = quarantineDir.appendingPathComponent(cp.mainURL.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: quarantinedSeg), truncatedSeg, "truncated segment, byte-identical")
        XCTAssertEqual(try Data(contentsOf: quarantinedMain), mainJunk, "main file, byte-identical")

        // The two MERGED segments and the marker are NOT in quarantine — they
        // were consumed into the new memo's audio, not left behind.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: quarantineDir.appendingPathComponent("rec_seg_MIXED_001.m4a").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: quarantineDir.appendingPathComponent("rec_seg_MIXED_002.m4a").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: quarantineDir.appendingPathComponent("rec_ckpt_MIXED.json").path))

        let sidecar = try JSONDecoder().decode(
            MemoSaver.QuarantinedTakeSidecar.self,
            from: Data(contentsOf: quarantineDir.appendingPathComponent("quarantine_MIXED.json")))
        XCTAssertEqual(Set(sidecar.fileSizes.keys), ["rec_seg_MIXED_003.m4a", cp.mainURL.lastPathComponent])
    }

    /// Coordinator finding: a name already in quarantine must never be
    /// overwritten/deleted — a second collision gets a unique suffix.
    func testQuarantineCollisionGetsAUniqueSuffixNeverOverwrites() async throws {
        let quarantineDir = MemoSaver.quarantineDirectory(besideRecordings: dir)
        let firstCopy = Data("first quarantined copy — must survive".utf8)
        try firstCopy.write(to: quarantineDir.appendingPathComponent("rec_tmp_DEAD.m4a"))

        let cp = RecordingCheckpoint(directory: dir, takeID: "DEAD", settings: settings,
                                     sampleRate: rate, segmentSeconds: 60)
        let secondJunk = Data("a second, different DEAD take".utf8)
        try secondJunk.write(to: cp.mainURL)
        try pretendPreviousRun(cp)

        let repo = NotesRepository(inMemory: true)
        _ = await saver(repo).recoverInterruptedRecordings(directory: dir)

        XCTAssertEqual(try Data(contentsOf: quarantineDir.appendingPathComponent("rec_tmp_DEAD.m4a")), firstCopy,
                       "the earlier quarantined copy is untouched")
        XCTAssertEqual(try Data(contentsOf: quarantineDir.appendingPathComponent("rec_tmp_DEAD_2.m4a")), secondJunk,
                       "the new one lands beside it under a suffixed name")
    }

    func testRemoveItemNeverAppearsInRecordingRecovery() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Features/Recording/RecordingRecovery.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(source.contains("removeItem"),
                       "the recovery sweep must never delete a take's own audio — quarantine instead (C288/C99)")
    }
}
