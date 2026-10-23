import XCTest
import SwiftData
import Foundation

/// Q481 (C152, C223): text appended to a polished note shows in the body he sees, and the pass
/// it sends the note back for polishes ONLY the new block — the earlier copy-edit, title and
/// summary stay. Fixture: corpus `voice-en-append-after-polish`.
final class AppendAfterPolishTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Enhancement: Decodable { let copyedit: String; let title: String; let summary: String }
        struct Expect: Decodable {
            let appendRaw: String, appendPolished: String
            let rawAfterAppend: String, bodyAfterAppend: String, bodyAfterPass: String
        }
        let id: String
        let transcript: String
        let enhancement: Enhancement
        let expect: Expect
    }

    private func fixture() throws -> Fixture {
        let url = CorpusSeed.fixtureRoot(file: #filePath)
            .appendingPathComponent("notes/voice-en-append-after-polish/note.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// Copy-edits from a table (the fixture's raw → polished), and counts every call.
    private final class TableEnhancer: Enhancing, @unchecked Sendable {
        let table: [String: String]
        private(set) var copyEdits: [String] = []
        private(set) var titles = 0, summaries = 0
        init(_ table: [String: String]) { self.table = table }
        func copyEdit(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
            copyEdits.append(t)
            return table[t] ?? t
        }
        func title(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
            titles += 1; return "NEW TITLE"
        }
        func summary(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
            summaries += 1; return "NEW SUMMARY"
        }
    }

    /// A note with its words already in: the pass must never ask for ASR.
    private struct NeverTranscriber: Transcribing {
        struct Asked: Error {}
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            throw Asked()
        }
    }

    private func cloudContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// The Mac row as it stands after the phone's append has synced.
    private func rowAfterAppend(_ f: Fixture) -> PipelineFile {
        let pf = PipelineFile(id: f.id, filename: "memo_\(f.id).m4a", path: "", size: 0, sourceType: .audio)
        pf.transcript = f.expect.rawAfterAppend
        pf.transcribeStatus = .done
        pf.enhancedCopyedit = f.expect.bodyAfterAppend
        pf.enhancedTitle = f.enhancement.title
        pf.enhancedSummary = f.enhancement.summary
        pf.pendingPolishBlock = f.expect.appendRaw
        pf.enhanceStatus = .pending
        return pf
    }

    // MARK: - the shared rule

    func testAppendShowsTheBlockAndRemembersItAsPending() throws {
        let f = try fixture()
        let after = AppendPolish.appended(copyedit: f.enhancement.copyedit, pending: "", block: f.expect.appendRaw)
        XCTAssertEqual(after.copyedit, f.expect.bodyAfterAppend, "the new words are in the body he sees")
        XCTAssertEqual(after.pending, f.expect.appendRaw)
        let twice = AppendPolish.appended(copyedit: after.copyedit, pending: after.pending, block: "and one more")
        XCTAssertEqual(twice.pending, f.expect.appendRaw + "\n\nand one more", "two appends, one pending block")
        let picture = AppendPolish.appended(copyedit: f.enhancement.copyedit, pending: "", block: "[[img_001]]",
                                            needsPolish: false)
        XCTAssertEqual(picture.pending, "", "a picture alone asks no pass for anything")
        XCTAssertFalse(AppendPolish.showsPolishedBody("  \n"), "a title-only polish shows the raw already")
    }

    func testSpliceReplacesOnlyTheRawTail() throws {
        let f = try fixture()
        XCTAssertEqual(AppendPolish.splice(copyedit: f.expect.bodyAfterAppend, pending: f.expect.appendRaw,
                                           polished: f.expect.appendPolished), f.expect.bodyAfterPass)
        XCTAssertNil(AppendPolish.splice(copyedit: f.enhancement.copyedit + "\n\nHe rewrote it himself.",
                                         pending: f.expect.appendRaw, polished: f.expect.appendPolished),
                     "his edit of the new words is his: no splice")
        XCTAssertEqual(AppendPolish.splice(copyedit: f.expect.bodyAfterAppend, pending: f.expect.appendRaw,
                                           polished: "  "), f.expect.bodyAfterAppend, "an empty polish keeps the raw words")
    }

    // MARK: - the pass

    func testThePassPolishesOnlyTheNewBlock() async throws {
        let f = try fixture()
        let pf = rowAfterAppend(f)
        let enhancer = TableEnhancer([f.expect.appendRaw: f.expect.appendPolished])
        let runner = BatchRunner(transcriber: NeverTranscriber(), enhancer: enhancer,
                                 settings: .default, people: [], tagWhitelist: [])
        try await runner.run(pf, audioURL: nil)

        XCTAssertEqual(enhancer.copyEdits, [f.expect.appendRaw], "the model saw the new block and nothing else")
        XCTAssertEqual(enhancer.titles, 0)
        XCTAssertEqual(enhancer.summaries, 0)
        XCTAssertEqual(pf.enhancedCopyedit, f.expect.bodyAfterPass)
        XCTAssertEqual(pf.enhancedTitle, f.enhancement.title, "the earlier polish stays")
        XCTAssertEqual(pf.enhancedSummary, f.enhancement.summary)
        XCTAssertNil(pf.pendingPolishBlock)
        XCTAssertEqual(pf.enhanceStatus, .done)
        XCTAssertEqual(pf.transcript, f.expect.rawAfterAppend, "the raw transcript is never rewritten")
        XCTAssertTrue(pf.compiledText?.contains(f.expect.appendPolished) == true, "the draft carries the polished block")
    }

    func testAnEditedTailIsLeftAloneAndNoLongerPending() async throws {
        let f = try fixture()
        let pf = rowAfterAppend(f)
        let edited = f.enhancement.copyedit + "\n\nEight people, max."
        pf.enhancedCopyedit = edited
        let runner = BatchRunner(transcriber: NeverTranscriber(), enhancer: TableEnhancer([:]),
                                 settings: .default, people: [], tagWhitelist: [])
        try await runner.run(pf, audioURL: nil)
        XCTAssertEqual(pf.enhancedCopyedit, edited)
        XCTAssertNil(pf.pendingPolishBlock)
        XCTAssertEqual(pf.enhanceStatus, .done)
    }

    // MARK: - phone → Mac → phone

    func testAPhoneAppendSendsTheRowBackForAPassAndTheWriteBackClearsIt() async throws {
        let f = try fixture()
        let ctx = try cloudContext()
        let id = try XCTUnwrap(UUID(uuidString: f.id))
        let memo = Memo(id: id, audioFilename: "memo_\(f.id).m4a")
        memo.transcript = f.expect.rawAfterAppend
        memo.transcriptUserEdited = true
        ctx.insert(memo)
        let enh = MemoEnhancement(memoID: id, copyedit: f.enhancement.copyedit, title: f.enhancement.title,
                                  summary: f.enhancement.summary, enhancedByDeviceID: "corpus-mac-0001",
                                  enhancedAt: Date(timeIntervalSinceNow: -3600))
        enh.appendBlock(f.expect.appendRaw, deviceID: "phone-1")   // what MemoSaver's append does
        ctx.insert(enh)
        try ctx.save()
        XCTAssertEqual(enh.copyedit, f.expect.bodyAfterAppend)
        XCTAssertEqual(enh.pendingBlock, f.expect.appendRaw)

        // The Mac row as it was before the append: polished, done.
        let pf = PipelineFile(id: f.id, filename: "memo_\(f.id).m4a", path: "", size: 0, sourceType: .audio)
        pf.transcript = f.transcript
        pf.transcribeStatus = .done
        pf.enhancedCopyedit = f.enhancement.copyedit
        pf.enhancedTitle = f.enhancement.title
        pf.enhancedSummary = f.enhancement.summary
        pf.enhanceStatus = .done
        XCTAssertTrue(MemoCloudUpdate.apply(memo: memo, enhancement: enh, to: pf, people: [], author: "",
                                            thisDeviceID: "mac-1"))
        XCTAssertEqual(pf.enhancedCopyedit, f.expect.bodyAfterAppend, "the Mac shows the new words at once")
        XCTAssertEqual(pf.pendingPolishBlock, f.expect.appendRaw)
        XCTAssertEqual(pf.enhanceStatus, .pending, "marked for a pass")
        XCTAssertTrue(WayOutRules.needsProcessing(pf))

        let runner = BatchRunner(transcriber: NeverTranscriber(),
                                 enhancer: TableEnhancer([f.expect.appendRaw: f.expect.appendPolished]),
                                 settings: .default, people: [], tagWhitelist: [])
        try await runner.run(pf, audioURL: nil)
        let written = try XCTUnwrap(MacCloudWriteBack.upsert(for: pf, into: ctx, deviceID: "mac-1", passRan: true))
        XCTAssertEqual(written.copyedit, f.expect.bodyAfterPass)
        XCTAssertEqual(written.pendingBlock, "", "nothing pending once the pass ran")
        XCTAssertEqual(written.title, f.enhancement.title)
    }

    func testAMacAppendMarksTheSameBlock() throws {
        let f = try fixture()
        let pf = PipelineFile(id: f.id, filename: "memo.m4a", path: "/tmp/nonexistent-\(UUID().uuidString).m4a",
                              size: 0, sourceType: .audio)
        pf.transcript = f.transcript
        pf.transcribeStatus = .done
        pf.enhancedCopyedit = f.enhancement.copyedit
        pf.enhanceStatus = .done
        try MacAppendRecording.land(text: f.expect.appendRaw, timings: [], splice: (merged: 10, base: 7),
                                    on: pf, memo: nil, cloud: nil, people: [], author: "")
        XCTAssertEqual(pf.enhancedCopyedit, f.expect.bodyAfterAppend)
        XCTAssertEqual(pf.pendingPolishBlock, f.expect.appendRaw)
        XCTAssertEqual(pf.enhanceStatus, .pending)
        XCTAssertEqual(pf.transcript, f.expect.rawAfterAppend)
    }
}
