import XCTest
import Foundation

/// Q504 (C275, C152): words added to a polished note get the pass that polishes only them
/// (`BatchRunner.polishAppendedBlock`), and that pass applies the spoken-hashtag rule too, so
/// "hashtag workshop" said in an added recording becomes `#workshop` like it would in a whole
/// pass. The earlier polish is not touched; a tail he edited himself stays his.
final class AppendSpokenHashtagTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Enhancement: Decodable { let copyedit: String; let title: String; let summary: String }
        let id: String
        let transcript: String
        let enhancement: Enhancement
    }

    /// The polished base: corpus `voice-en-append-after-polish`.
    private func base() throws -> Fixture {
        let url = CorpusSeed.fixtureRoot(file: #filePath)
            .appendingPathComponent("notes/voice-en-append-after-polish/note.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// The model hands back the block unchanged: any tag in the result came from the rule.
    private struct VerbatimEnhancer: Enhancing {
        func copyEdit(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { t }
        func title(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "NEW" }
        func summary(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "NEW" }
    }

    private struct NeverTranscriber: Transcribing {
        struct Asked: Error {}
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            throw Asked()
        }
    }

    private func row(_ f: Fixture, block: String, shown: String? = nil) -> PipelineFile {
        let pf = PipelineFile(id: f.id, filename: "memo_\(f.id).m4a", path: "", size: 0, sourceType: .audio)
        pf.transcript = AppendPolish.joined(f.transcript, block)
        pf.transcribeStatus = .done
        pf.enhancedCopyedit = shown ?? AppendPolish.joined(f.enhancement.copyedit, block)
        pf.enhancedTitle = f.enhancement.title
        pf.enhancedSummary = f.enhancement.summary
        pf.pendingPolishBlock = block
        pf.enhanceStatus = .pending
        return pf
    }

    private func run(_ pf: PipelineFile, vocabulary: [String] = []) async throws {
        var settings = AppSettings.default
        settings.customVocabulary = vocabulary
        try await BatchRunner(transcriber: NeverTranscriber(), enhancer: VerbatimEnhancer(),
                              settings: settings, people: [], tagWhitelist: []).run(pf, audioURL: nil)
    }

    func testATrailingRunInTheAddedWordsBecomesTheTagLine() async throws {
        let f = try base()
        let block = "We should cap it at eight people. Hashtag workshop hashtag pricing. Okay."
        let pf = row(f, block: block)
        try await run(pf)
        XCTAssertEqual(pf.enhancedCopyedit,
                       f.enhancement.copyedit + "\n\nWe should cap it at eight people.\n\n#workshop #pricing")
        XCTAssertNil(pf.pendingPolishBlock)
        XCTAssertEqual(pf.enhancedTitle, f.enhancement.title, "the earlier polish stays")
        XCTAssertTrue(pf.transcript?.hasSuffix(block) == true, "the raw keeps the spoken words")
    }

    func testInlineAndVocabAcronymInTheAddedWords() async throws {
        let f = try base()
        let block = "The C and C needs some hashtag maintenance first. Hashtag studio. C and C hashtag kiln."
        let pf = row(f, block: block)
        try await run(pf, vocabulary: ["CNC"])
        XCTAssertEqual(pf.enhancedCopyedit,
                       f.enhancement.copyedit + "\n\nThe C and C needs some #maintenance first.\n\n#studio #cnc #kiln")
    }

    func testATailHeEditedIsLeftAsHeWroteIt() async throws {
        let f = try base()
        let edited = f.enhancement.copyedit + "\n\nEight people max, hashtag workshop."
        let pf = row(f, block: "we should cap it hashtag workshop", shown: edited)
        try await run(pf)
        XCTAssertEqual(pf.enhancedCopyedit, edited)
        XCTAssertNil(pf.pendingPolishBlock)
    }
}
