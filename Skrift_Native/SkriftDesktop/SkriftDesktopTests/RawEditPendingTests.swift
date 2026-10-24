import XCTest
import Foundation

/// C153 / Q486: a raw edit newer than the polish sends the Mac row back to pending and the edit
/// shows until the next pass lands; an edit that lands while a pass runs discards the pass (C38).
@MainActor
final class RawEditPendingTests: XCTestCase {

    private let mac = "mac-1"

    private func polishedRow(_ id: UUID, at t0: Date) -> PipelineFile {
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a")
        pf.transcript = "Original words."
        pf.transcribeStatus = .done
        pf.enhancedCopyedit = "Polished original words."
        pf.sanitised = "Polished original words."
        pf.enhancedTitle = "Original"
        pf.enhanceStatus = .done
        pf.syncedSourceEditedAt = t0
        return pf
    }

    private func memo(_ id: UUID, transcript: String, editedAt: Date, rawEditedAt: Date?) -> Memo {
        let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: Date(),
                     transcript: transcript, transcriptStatus: .done, transcriptConfidence: 0.9,
                     significance: 0.6)
        m.markEdited(editedAt)
        m.transcriptEditedAt = rawEditedAt
        return m
    }

    private func macPolish(_ id: UUID, at: Date) -> MemoEnhancement {
        MemoEnhancement(memoID: id, copyedit: "Polished original words.", title: "Original",
                        enhancedByDeviceID: mac, enhancedAt: at)
    }

    // MARK: - the Mac row

    func testRawEditNewerThanThePolishSendsTheRowBackToPending() {
        let id = UUID(), t0 = Date()
        let pf = polishedRow(id, at: t0)
        pf.pendingPolishBlock = "an appended block of the old words"
        let m = memo(id, transcript: "Edited words.", editedAt: t0.addingTimeInterval(60),
                     rawEditedAt: t0.addingTimeInterval(60))

        XCTAssertTrue(V2.reflect(m, enhancement: macPolish(id, at: t0.addingTimeInterval(30)), to: pf, people: [], author: "", device: mac))
        XCTAssertEqual(pf.enhanceStatus, .pending, "the next pass re-polishes what he wrote")
        XCTAssertNil(pf.enhancedCopyedit, "the stale copy-edit no longer wins the body")
        XCTAssertEqual(pf.sanitised, "Edited words.", "the Mac shows the raw edit until the pass lands")
        XCTAssertEqual(pf.transcript, "Edited words.")
        XCTAssertNil(pf.pendingPolishBlock, "the whole note is polished again, not a block (C152)")
    }

    func testAnOlderBuildWithoutTheRawStampFallsBackToTheMemoEditTime() {
        let id = UUID(), t0 = Date()
        let pf = polishedRow(id, at: t0)
        let m = memo(id, transcript: "Edited words.", editedAt: t0.addingTimeInterval(60), rawEditedAt: nil)

        V2.reflect(m, enhancement: macPolish(id, at: t0.addingTimeInterval(30)), to: pf, people: [], author: "", device: mac)
        XCTAssertEqual(pf.enhanceStatus, .pending)
    }

    func testRawEditOlderThanThePolishKeepsThePolish() {
        let id = UUID(), t0 = Date()
        let pf = polishedRow(id, at: t0)
        let m = memo(id, transcript: "Edited words.", editedAt: t0.addingTimeInterval(10),
                     rawEditedAt: t0.addingTimeInterval(10))

        V2.reflect(m, enhancement: macPolish(id, at: t0.addingTimeInterval(30)), to: pf, people: [], author: "", device: mac)
        XCTAssertEqual(pf.enhanceStatus, .done, "the polish is newer than the edit: it stays")
        XCTAssertEqual(pf.enhancedCopyedit, "Polished original words.")
    }

    func testAPhoneCopyeditEditIsNotARawEdit() {
        // The phone stamps enhancedAt, then memo.editedAt a hair later, for a copy-edit edit —
        // the raw words are unchanged, so the row stays polished.
        let id = UUID(), t0 = Date()
        let pf = polishedRow(id, at: t0)
        let m = memo(id, transcript: "Original words.", editedAt: t0.addingTimeInterval(31), rawEditedAt: nil)
        let phone = MemoEnhancement(memoID: id, copyedit: "Phone-fixed polish.", enhancedByDeviceID: "phone-9",
                                    enhancedAt: t0.addingTimeInterval(30))

        XCTAssertTrue(V2.reflect(m, enhancement: phone, to: pf, people: [], author: "", device: mac))
        XCTAssertEqual(pf.enhanceStatus, .done)
        XCTAssertEqual(pf.enhancedCopyedit, "Phone-fixed polish.")
    }

    func testAStalePhonePolishIsNeverReadoptedOnALaterSweep() {
        let id = UUID(), t0 = Date()
        let pf = polishedRow(id, at: t0)
        let m = memo(id, transcript: "Edited words.", editedAt: t0.addingTimeInterval(60),
                     rawEditedAt: t0.addingTimeInterval(60))
        let phone = MemoEnhancement(memoID: id, copyedit: "Polished original words.", enhancedByDeviceID: "phone-9",
                                    enhancedAt: t0.addingTimeInterval(30))

        V2.reflect(m, enhancement: phone, to: pf, people: [], author: "", device: mac)
        V2.reflect(m, enhancement: phone, to: pf, people: [], author: "", device: mac)
        XCTAssertNil(pf.enhancedCopyedit, "the second sweep must not bring the stale copy-edit back")
        XCTAssertEqual(pf.enhanceStatus, .pending)
    }

    // MARK: - the phone's rule (shared)

    func testThePhoneShowsTheEditUntilTheNextPassLands() {
        let id = UUID(), t0 = Date()
        let m = memo(id, transcript: "Edited words.", editedAt: t0.addingTimeInterval(60),
                     rawEditedAt: t0.addingTimeInterval(60))
        XCTAssertTrue(macPolish(id, at: t0.addingTimeInterval(30)).isStale(for: m), "old polish → raw shows")
        XCTAssertFalse(macPolish(id, at: t0.addingTimeInterval(90)).isStale(for: m), "the next pass shows again")
        // A title or tag edit moves editedAt only — the polish stays.
        let retitled = memo(id, transcript: "Original words.", editedAt: t0.addingTimeInterval(60), rawEditedAt: nil)
        XCTAssertFalse(macPolish(id, at: t0.addingTimeInterval(30)).isStale(for: retitled))
    }

    // MARK: - the post-run race (C38)

    /// The phone's raw edit is reflected onto the row while the pass awaits the model.
    private final class MidRunEdit: @unchecked Sendable {
        var land: () -> Void = {}
        var landed = false
        func fire() { if !landed { landed = true; land() } }
    }

    private struct EditingEnhancer: Enhancing {
        let edit: MidRunEdit
        let during: String
        func copyEdit(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
            if during == "copyEdit" { edit.fire() }
            return "Polished " + t
        }
        func title(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
            if during == "title" { edit.fire() }
            return "Title"
        }
        func summary(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "" }
    }

    private struct NoTranscriber: Transcribing {
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            XCTFail("a trusted transcript is never re-transcribed")
            return TranscriptionResult(text: "", confidence: 0, durationMs: 0, wordTimings: [], markersInjected: false)
        }
    }

    private func runWithEdit(during step: String) async throws -> PipelineFile {
        let id = UUID(), t0 = Date()
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a")
        pf.transcript = "Original words."
        pf.transcribeStatus = .done
        pf.syncedSourceEditedAt = t0
        let edit = MidRunEdit()
        let m = memo(id, transcript: "Edited words.", editedAt: t0.addingTimeInterval(5),
                     rawEditedAt: t0.addingTimeInterval(5))
        edit.land = { V2.reflect(m, enhancement: nil, to: pf, people: [], author: "", device: self.mac) }
        let runner = BatchRunner(transcriber: NoTranscriber(), enhancer: EditingEnhancer(edit: edit, during: step),
                                 settings: AppSettings.default, people: [], tagWhitelist: [])
        try await runner.run(pf, audioURL: nil)
        XCTAssertTrue(edit.landed)
        return pf
    }

    func testAnEditDuringTheCopyEditDiscardsThePass() async throws {
        let pf = try await runWithEdit(during: "copyEdit")
        XCTAssertEqual(pf.enhanceStatus, .pending, "the pass is discarded; the next one polishes the edit")
        XCTAssertNil(pf.enhancedCopyedit, "nothing of the stale pass is written")
        XCTAssertEqual(pf.transcript, "Edited words.")
    }

    func testAnEditAfterTheCopyEditIsWrittenStillDiscardsThePass() async throws {
        // The copy-edit is already on the row when the edit lands; the body the old guard
        // watched was that copy-edit, so only the raw-transcript check catches this one.
        let pf = try await runWithEdit(during: "title")
        XCTAssertEqual(pf.enhanceStatus, .pending)
        XCTAssertNotEqual(pf.enhancedTitle, "Title", "the stale title is never written")
        XCTAssertNil(pf.enhancedCopyedit, "the run's copy-edit of the old words is taken back")
        XCTAssertEqual(pf.sanitised, "Edited words.", "the body is the edit")
        XCTAssertEqual(pf.transcript, "Edited words.")
    }
}
