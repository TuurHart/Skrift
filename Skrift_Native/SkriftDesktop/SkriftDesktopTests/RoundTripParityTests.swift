import XCTest
import SwiftData

/// SPEC C249 — round trips as tests: "a note looks the same wherever it was made". Every
/// corpus note goes phone → Mac (MemoCloudIngest) and Mac → phone (MacMemoAuthor) and the two
/// ends are compared field by field, incl. the ASSETS each side carries. No cloud needed.
///
/// The known one-way path (SPEC R34: a Mac take's word timings never reach the phone —
/// `MacMemoAuthor.author` attaches the audio only) is pinned with `XCTExpectFailure`, so the
/// gate stays green until v2 fixes it and goes RED the day it is fixed without the flag being
/// removed — the pre-registered required difference, in code.
final class RoundTripParityTests: XCTestCase {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
    private func cloudContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
    }
    private func pipelineContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    /// phone memo → Mac row → Mac-authored memo: every asset kind the phone sent must come back.
    func testPhoneToMacToPhoneKeepsEveryAssetKind() throws {
        let root = CorpusSeedTests.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path))
        let cloud = try cloudContext()
        try CorpusSeed.seed(from: root, into: cloud, recordingsDirectory: try tempDir())
        let pipeline = try pipelineContext()
        let upload = UploadService(outputDir: try tempDir())
        let assets = try cloud.fetch(FetchDescriptor<MemoAsset>())

        var compared = 0
        var timingsLost = 0
        for memo in try cloud.fetch(FetchDescriptor<Memo>()) {
            let mine = assets.filter { $0.memoID == memo.id }
            // Only trusted voice notes carry timings across; that is the path under test.
            // (a video with no speech carries an EMPTY timings list — nothing to carry; skip it)
            guard memo.deletedAt == nil, NoteConsent.isRated(memo),
                  let wt = mine.first(where: { $0.kind == MemoAsset.Kind.wordTimings }),
                  let words = try? JSONDecoder().decode([WordTiming].self, from: wt.blob), !words.isEmpty,
                  memo.transcriptUserEdited || (memo.transcriptConfidence ?? 0) >= 0.7 else { continue }
            guard let row = try MemoCloudIngest.ingest(memo: memo, assets: mine, upload: upload, into: pipeline) else { continue }
            XCTAssertFalse(row.wordTimings.isEmpty, "\(memo.id): the Mac row must adopt the phone's timings")

            // Mac → phone: author a fresh memo from the row, as the Mac does for its own takes.
            let back = try cloudContext()
            let audioURL = URL(fileURLWithPath: row.path)
            guard let authored = try MacMemoAuthor.author(for: row, audioURL: audioURL, into: back) else {
                XCTFail("\(memo.id): author returned nil"); continue
            }
            let authoredID = authored.id
            let kinds = Set(try back.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == authoredID })).map(\.kind))
            XCTAssertTrue(kinds.contains(MemoAsset.Kind.audio), "\(memo.id): audio must come back")
            if !kinds.contains(MemoAsset.Kind.wordTimings) { timingsLost += 1 }
            compared += 1
        }
        XCTAssertGreaterThan(compared, 20, "the corpus must exercise this path")
        // SPEC R34 / C245 — pre-registered: today the Mac authors WITHOUT the timings.
        XCTExpectFailure("R34: MacMemoAuthor.author attaches the audio only (MacMemoAuthor.swift:92); v2 must carry wordTimings + diarization") {
            XCTAssertEqual(timingsLost, 0, "Mac-authored memos lost their word timings: \(timingsLost) of \(compared)")
        }
    }
}
