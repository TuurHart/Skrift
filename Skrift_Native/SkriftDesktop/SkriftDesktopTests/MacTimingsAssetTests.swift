import XCTest
import SwiftData
import Foundation

/// Q482 (C245, R34): a Mac recording's word timings (and its diarization, when it was split) ride
/// to the phone as the same synced `MemoAsset` kinds, filenames and blob shapes the phone writes,
/// so the phone's karaoke works on a Mac take. Before, the Mac authored the memo with audio only
/// and the timings sat on its own row.
@MainActor
final class MacTimingsAssetTests: XCTestCase {

    /// The phone's `DiarizationData` (SkriftMobile/Services/Diarization/DiarizationStore.swift),
    /// mirrored field for field: what the phone's decoder needs to find in the blob.
    private struct PhoneDiarizationData: Decodable {
        var segments: [DiarizedSegment]
        var slotNames: [String: String]
        var turnSlots: [Int]?
    }

    private func cloudContext() throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    private let words = [WordTiming(word: "Kiln", start: 0.0, end: 0.4),
                         WordTiming(word: "loaded", start: 0.45, end: 0.9),
                         WordTiming(word: "again.", start: 0.95, end: 1.3)]

    /// A take THIS Mac recorded: its memo authored with audio, transcript still empty.
    private func macTake(in cloud: ModelContext) throws -> (Memo, PipelineFile) {
        let id = UUID()
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordingDeviceID: DeviceID.current())
        cloud.insert(memo)
        cloud.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.audio, filename: memo.audioFilename, blob: Data("AUDIO".utf8)))
        try cloud.save()
        let pf = PipelineFile(id: id.uuidString, filename: memo.audioFilename, sourceType: .audio)
        pf.isLocalRecording = true
        pf.transcript = "Kiln loaded again."
        pf.wordTimings = words
        pf.transcribeStatus = .done
        return (memo, pf)
    }

    private func assets(_ kind: String, of id: UUID, in cloud: ModelContext) throws -> [MemoAsset] {
        try cloud.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id && $0.kind == kind }))
    }

    func testAMacRecordingYieldsAWordTimingsAssetInThePhonesShape() throws {
        let cloud = try cloudContext()
        let (memo, pf) = try macTake(in: cloud)
        XCTAssertEqual(try ReconcileV2.Author.reflectTranscripts([pf], into: cloud), 1)

        let wt = try assets(MemoAsset.Kind.wordTimings, of: memo.id, in: cloud)
        XCTAssertEqual(wt.count, 1)
        let asset = try XCTUnwrap(wt.first)
        XCTAssertEqual(asset.filename, "wt_\(memo.id.uuidString).json", "the phone's WordTimingsStore name")
        XCTAssertEqual(try JSONDecoder().decode([WordTiming].self, from: asset.blob), words)
        XCTAssertEqual(asset.byteCount, asset.blob.count)
        XCTAssertTrue(try assets(MemoAsset.Kind.diarization, of: memo.id, in: cloud).isEmpty,
                      "a monologue has no diarization to send")

        // The sweep runs again: nothing doubles.
        XCTAssertEqual(try ReconcileV2.Author.reflectTranscripts([pf], into: cloud), 0)
        XCTAssertEqual(try assets(MemoAsset.Kind.wordTimings, of: memo.id, in: cloud).count, 1)
    }

    func testASplitMacTakeAlsoSendsItsDiarizationInThePhonesShape() throws {
        let cloud = try cloudContext()
        let (memo, pf) = try macTake(in: cloud)
        pf.transcript = "**Tiuri:** Kiln loaded.\n\n**Speaker 2:** Again?\n\n**Tiuri:** Again."
        pf.diarizationSegments = [DiarizedSegment(speaker: 0, start: 0, end: 0.9),
                                  DiarizedSegment(speaker: 1, start: 0.9, end: 1.1),
                                  DiarizedSegment(speaker: 0, start: 1.1, end: 1.3)]
        XCTAssertEqual(try ReconcileV2.Author.reflectTranscripts([pf], into: cloud), 1)

        let dz = try XCTUnwrap(try assets(MemoAsset.Kind.diarization, of: memo.id, in: cloud).first)
        XCTAssertEqual(dz.filename, "diar_\(memo.id.uuidString).json", "the phone's DiarizationStore name")
        let decoded = try JSONDecoder().decode(PhoneDiarizationData.self, from: dz.blob)
        XCTAssertEqual(decoded.segments, pf.diarizationSegments)
        XCTAssertEqual(decoded.slotNames, ["0": "Tiuri", "1": "Speaker 2"])
        XCTAssertEqual(decoded.turnSlots, [0, 1, 0])
        XCTAssertEqual(try assets(MemoAsset.Kind.wordTimings, of: memo.id, in: cloud).count, 1)
    }

    func testAnEditedTakeAuthoredWithItsWordsCarriesItsTimingsAtOnce() throws {
        let cloud = try cloudContext()
        let id = UUID()
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a", sourceType: .audio)
        pf.isLocalRecording = true
        pf.transcript = "Kiln loaded again."
        pf.wordTimings = words
        pf.transcribeStatus = .done
        let memo = try XCTUnwrap(try V2.author(pf, into: cloud))
        let asset = try XCTUnwrap(try assets(MemoAsset.Kind.wordTimings, of: memo.id, in: cloud).first)
        XCTAssertEqual(try JSONDecoder().decode([WordTiming].self, from: asset.blob), words)
    }

    func testTurnsThatDoNotLineUpFallBackToSpeakerLabels() {
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 1), DiarizedSegment(speaker: 1, start: 1, end: 2)]
        let d = TimingAssets.diarization(segments: segs, turnNames: ["Only one turn"])
        XCTAssertEqual(d?.slotNames, ["0": "Speaker 1", "1": "Speaker 2"])
        XCTAssertNil(d?.turnSlots)
        XCTAssertNil(TimingAssets.diarization(segments: [segs[0]], turnNames: []), "one voice is no diarization")
    }
}
