import XCTest
import SwiftData
import Foundation

/// Q514 / C42: a `.done` phone transcript reaches an audio row only when trusted (`userEdited ||
/// confidence ≥ 0.7`), at first contact AND on every later sweep (`ReconcileV2.Ingest.phoneWords`).
/// Before, the fresh-row reflect copied untrusted words onto the row after the ingest gate had
/// dropped them, and a later sweep could put them back over the Mac's own ASR.
@MainActor
final class UntrustedTranscriptRowTests: XCTestCase {

    private var cloudContainer: ModelContainer!
    private var localContainer: ModelContainer!
    private var cloud: ModelContext!
    private var local: ModelContext!
    private var out: URL!
    private let t0 = Date(timeIntervalSince1970: 1_767_225_600)

    override func setUpWithError() throws {
        cloudContainer = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        localContainer = try ModelContainer(for: PipelineFile.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        cloud = ModelContext(cloudContainer)
        local = ModelContext(localContainer)
        out = FileManager.default.temporaryDirectory.appendingPathComponent("q514-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: out) }

    @discardableResult
    private func sweep() -> ReconcileV2.Outcome {
        ReconcileV2.sweep(cloud: cloud, local: local,
                          context: .init(people: [], author: "A", thisDeviceID: "mac-1", now: t0, outputDir: out))
    }

    private func row(_ memo: Memo) throws -> PipelineFile {
        let id = memo.id.uuidString
        return try XCTUnwrap(try local.fetch(FetchDescriptor<PipelineFile>(predicate: #Predicate { $0.id == id })).first)
    }

    /// A rated voice memo with its audio, carrying the phone's words at `confidence`.
    private func voiceMemo(_ words: String, confidence: Double?, edited: Bool = false,
                           status: TranscriptStatus = .done) throws -> Memo {
        let memo = Memo(id: UUID(), audioFilename: "", recordedAt: t0, transcript: words, transcriptStatus: status,
                        transcriptConfidence: confidence, transcriptUserEdited: edited, significance: 0.6, createdAt: t0)
        memo.audioFilename = "memo_\(memo.id.uuidString).m4a"
        cloud.insert(memo)
        cloud.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio, filename: memo.audioFilename, blob: Data("AUDIO".utf8)))
        try cloud.save()
        return memo
    }

    func testAnUntrustedTranscriptNeverLandsOnTheRow() throws {
        let memo = try voiceMemo("Wind noise, probably garbage.", confidence: 0.4)
        sweep()
        let pf = try row(memo)
        XCTAssertNil(pf.transcript, "the phone's untrusted words stay off the row")
        XCTAssertEqual(pf.transcribeStatus, .pending, "the Mac transcribes it itself")
        XCTAssertFalse((pf.compiledText ?? "").contains("garbage"), "and they never reach the body")
        XCTAssertEqual(sweep().updatedIDs, [], "a second sweep still leaves it alone")
        XCTAssertNil(try row(memo).transcript)
    }

    func testTheMacsOwnTranscriptIsNeverReplacedByUntrustedPhoneWords() throws {
        let memo = try voiceMemo("Wind noise, probably garbage.", confidence: 0.4)
        sweep()
        let pf = try row(memo)
        pf.transcript = "The chain on the cargo bike skips under load."   // the Mac's ASR landed
        pf.transcribeStatus = .done
        try local.save()
        sweep()
        XCTAssertEqual(try row(memo).transcript, "The chain on the cargo bike skips under load.")
    }

    func testAHandEditOnThePhoneIsTrustedAndLands() throws {
        let memo = try voiceMemo("Wind noise, probably garbage.", confidence: 0.4)
        sweep()
        memo.transcript = "Fixed by hand: the chain skips."
        memo.transcriptUserEdited = true
        memo.markEdited(t0.addingTimeInterval(60))
        try cloud.save()
        sweep()
        XCTAssertEqual(try row(memo).transcript, "Fixed by hand: the chain skips.")
    }

    func testATrustedTranscriptLandsAtFirstContact() throws {
        let memo = try voiceMemo("Kiln loaded at nine.", confidence: 0.9)
        sweep()
        XCTAssertEqual(try row(memo).transcript, "Kiln loaded at nine.")
        XCTAssertEqual(try row(memo).transcribeStatus, .done)
    }

    /// C97: words still being transcribed on the phone are not final, so they are not the row's.
    func testWordsStillTranscribingNeverLand() throws {
        let memo = try voiceMemo("Kiln load", confidence: 0.9, status: .transcribing)
        sweep()
        XCTAssertNil(try row(memo).transcript)
    }

    /// No audio to re-transcribe: a typed note's words are its body, whatever the confidence.
    func testATypedNotesWordsAlwaysLand() throws {
        let memo = try Memo.newTyped(into: cloud, now: t0)
        memo.transcript = "Typed on the iPad."
        memo.significance = 0.5
        try cloud.save()
        sweep()
        XCTAssertEqual(try row(memo).transcript, "Typed on the iPad.")
    }

    func testThePredicate() {
        let memo = Memo(transcript: "words", transcriptStatus: .done, transcriptConfidence: 0.69)
        XCTAssertNil(ReconcileV2.Ingest.phoneWords(memo, audio: true))
        XCTAssertEqual(ReconcileV2.Ingest.phoneWords(memo, audio: false), "words")
        memo.transcriptConfidence = 0.7
        XCTAssertEqual(ReconcileV2.Ingest.phoneWords(memo, audio: true), "words")
    }
}
