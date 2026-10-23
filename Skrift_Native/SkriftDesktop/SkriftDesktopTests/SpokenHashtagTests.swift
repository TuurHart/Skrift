import XCTest
import Foundation

/// Q483 (C275, C85): a spoken hashtag becomes a real tag BY RULE, never by the model — in the body
/// he sees; the raw transcript keeps the words. One shared function (`SpokenHashtags`) for both
/// apps. Fixture: corpus `voice-spoken-hashtags` (the synthetic twin of the real Benfica note).
final class SpokenHashtagTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Case: Decodable { let name: String; let vocabulary: [String]; let raw: String; let shown: String }
        struct Expect: Decodable { let vocabulary: [String]; let shown: String; let cases: [Case] }
        let transcript: String
        let expect: Expect
    }

    private func fixture() throws -> Fixture {
        let url = CorpusSeed.fixtureRoot(file: #filePath).appendingPathComponent("notes/voice-spoken-hashtags/note.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testEveryCorpusCase() throws {
        let f = try fixture()
        XCTAssertGreaterThanOrEqual(f.expect.cases.count, 6)
        for c in f.expect.cases {
            XCTAssertEqual(SpokenHashtags.apply(c.raw, vocabulary: c.vocabulary), c.shown, c.name)
        }
    }

    func testTheBenficaEndingBecomesOneTagLine() throws {
        let f = try fixture()
        let shown = SpokenHashtags.shownBody(f.transcript, vocabulary: f.expect.vocabulary)
        XCTAssertEqual(shown, f.expect.shown)
        XCTAssertTrue(shown.hasSuffix("\n\n#production #cnc #design #gfr"))
        XCTAssertFalse(shown.contains("Okay"), "the trailing Okay after the run is dropped")
    }

    func testIdempotent() throws {
        for c in try fixture().expect.cases {
            let once = SpokenHashtags.apply(c.raw, vocabulary: c.vocabulary)
            XCTAssertEqual(SpokenHashtags.apply(once, vocabulary: c.vocabulary), once, c.name)
        }
    }

    func testAQuoteAndSpeakerTurnsAreLeftAlone() {
        let capture = "> The hashtag is a modern sign.\n\nSo true hashtag books hashtag reading."
        let shown = SpokenHashtags.shownBody(capture, vocabulary: [])
        XCTAssertTrue(shown.hasPrefix("> The hashtag is a modern sign."), "the book quote stays byte-identical")
        XCTAssertTrue(shown.hasSuffix("#books #reading"), shown)
        let turns = "**Tiuri:** Kiln loaded hashtag production.\n\n**Ana:** Nice."
        XCTAssertEqual(SpokenHashtags.shownBody(turns, vocabulary: []), turns, "conversations stay verbatim (C179)")
    }

    // MARK: - by rule, in the Mac's pass

    /// Copy-edits nothing: whatever reaches the body came from the rule.
    private struct VerbatimEnhancer: Enhancing {
        func copyEdit(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { t }
        func title(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "T" }
        func summary(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "" }
    }

    private struct NeverTranscriber: Transcribing {
        struct Asked: Error {}
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            throw Asked()
        }
    }

    func testThePassWritesTagsIntoTheShownBodyAndTheRawKeepsTheWords() async throws {
        let f = try fixture()
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo.m4a", path: "", size: 0, sourceType: .audio)
        pf.transcript = f.transcript
        pf.transcribeStatus = .done
        var settings = AppSettings.default
        settings.customVocabulary = f.expect.vocabulary
        let runner = BatchRunner(transcriber: NeverTranscriber(), enhancer: VerbatimEnhancer(),
                                 settings: settings, people: [], tagWhitelist: [])
        try await runner.run(pf, audioURL: nil)
        XCTAssertEqual(pf.enhancedCopyedit, f.expect.shown)
        XCTAssertEqual(pf.transcript, f.transcript, "the raw transcript keeps the spoken words")
        XCTAssertTrue(pf.compiledText?.contains("#production #cnc #design #gfr") == true)
    }
}
