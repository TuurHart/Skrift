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

    private var settings: [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
         AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
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

    func testRemoveItemNeverAppearsInRecordingRecovery() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Features/Recording/RecordingRecovery.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(source.contains("removeItem"),
                       "the recovery sweep must never delete a take's own audio — quarantine instead (C288/C99)")
    }
}
