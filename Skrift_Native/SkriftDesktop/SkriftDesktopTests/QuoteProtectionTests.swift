import XCTest
import Foundation

/// Audiobook quote protection (backlog spec 8, contract C1): the leading "> "
/// blockquote in a capture memo must survive copy-edit BYTE-IDENTICAL; any
/// mismatch falls the file back to the fully-unedited transcript (skip-all).
final class QuoteProtectionTests: XCTestCase {

    // A C1 capture body: quote block on top, blank line, ramble below.
    private let quote = "> Optimism is not the belief that things will go well.\n> It is a stance towards problems."
    private var capture: String { quote + "\n\n" + "I keep coming back to this idea, um, when I think about work." }

    // MARK: - splitLeadingQuote

    func testSplitSeparatesQuoteAndRamble() throws {
        let split = try XCTUnwrap(QuoteProtection.splitLeadingQuote(capture))
        XCTAssertEqual(split.quote, quote)   // byte-exact, no trailing newline
        XCTAssertEqual(split.ramble, "I keep coming back to this idea, um, when I think about work.")
    }

    func testSplitNoQuoteReturnsNil() {
        XCTAssertNil(QuoteProtection.splitLeadingQuote("Just a plain memo about my day."))
        XCTAssertNil(QuoteProtection.splitLeadingQuote(""))
        // A quote NOT at the very top is not a C1 capture block.
        XCTAssertNil(QuoteProtection.splitLeadingQuote("Intro line\n> quoted later"))
    }

    func testSplitQuoteOnlyCaptureHasEmptyRamble() throws {
        let split = try XCTUnwrap(QuoteProtection.splitLeadingQuote(quote))
        XCTAssertEqual(split.quote, quote)
        XCTAssertEqual(split.ramble, "")
    }

    func testSplitDropsMultipleSeparatorBlankLines() throws {
        let split = try XCTUnwrap(QuoteProtection.splitLeadingQuote(quote + "\n\n\n\nramble"))
        XCTAssertEqual(split.ramble, "ramble")
    }

    func testSplitKeepsBareQuoteSeparatorLinesInsideBlock() throws {
        // "> a\n>\n> b" — the bare ">" line belongs to the quote block.
        let multi = "> a\n>\n> b"
        let split = try XCTUnwrap(QuoteProtection.splitLeadingQuote(multi + "\n\nramble"))
        XCTAssertEqual(split.quote, multi)
    }

    // MARK: - strip / reinsert round-trip

    func testRoundTripKeepsQuoteByteIdentical() throws {
        let split = try XCTUnwrap(QuoteProtection.splitLeadingQuote(capture))
        let edited = "I keep coming back to this idea when I think about work."   // LLM cleaned the ramble
        let rejoined = QuoteProtection.reassemble(quote: split.quote, ramble: edited)
        XCTAssertEqual(rejoined, quote + "\n\n" + edited)
        XCTAssertTrue(QuoteProtection.leadingQuoteIntact(original: capture, edited: rejoined))
    }

    func testRoundTripWithUnicodeQuoteCharacters() throws {
        // Curly quotes + em-dash — multi-byte UTF-8, the byte-compare must hold.
        let fancy = "> \u{201C}Problems are soluble \u{2014} that\u{2019}s the claim.\u{201D}"
        let body = fancy + "\n\nmy thoughts"
        let split = try XCTUnwrap(QuoteProtection.splitLeadingQuote(body))
        let rejoined = QuoteProtection.reassemble(quote: split.quote, ramble: "my edited thoughts")
        XCTAssertTrue(QuoteProtection.leadingQuoteIntact(original: body, edited: rejoined))
    }

    func testReassembleEmptyRambleIsQuoteAlone() {
        XCTAssertEqual(QuoteProtection.reassemble(quote: quote, ramble: ""), quote)
    }

    // MARK: - byte-assert

    func testIntactTriviallyTrueWithoutLeadingQuote() {
        XCTAssertTrue(QuoteProtection.leadingQuoteIntact(original: "plain memo", edited: "Plain memo, edited."))
    }

    func testMutatedQuoteFailsAssert() {
        let mutated = capture.replacingOccurrences(of: "Optimism", with: "optimism")
        XCTAssertFalse(QuoteProtection.leadingQuoteIntact(original: capture, edited: mutated))
    }

    func testDroppedQuoteFailsAssert() {
        XCTAssertFalse(QuoteProtection.leadingQuoteIntact(original: capture, edited: "the ramble only"))
    }

    func testEditedRambleStartingWithBlockquoteFailsAssert() {
        // If the edited ramble itself begins with ">", the re-extracted leading
        // block grows — that corruption must trip the assert.
        let extended = QuoteProtection.reassemble(quote: quote + "\n> sneaky extra line", ramble: "ramble")
        XCTAssertFalse(QuoteProtection.leadingQuoteIntact(original: capture, edited: extended))
    }

    // MARK: - BatchRunner gate (spec 8's skip-all fallback)

    /// Mimics the REAL EnhancementService: protects the quote, edits the ramble.
    private struct ProtectingEnhancer: Enhancing {
        func copyEdit(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
            guard let split = QuoteProtection.splitLeadingQuote(transcript) else { return transcript }
            return QuoteProtection.reassemble(quote: split.quote, ramble: "EDITED " + split.ramble)
        }
        func title(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "A Title" }
        func summary(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "A summary." }
    }

    /// A broken enhancer that rewrites the quote — the gate must catch it.
    private struct ManglingEnhancer: Enhancing {
        func copyEdit(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
            transcript.replacingOccurrences(of: "Optimism", with: "Hope")
        }
        func title(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "A Title" }
        func summary(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "A summary." }
    }

    private func captureFile() -> PipelineFile {
        let pf = PipelineFile(id: "q1", filename: "memo_q.m4a", path: "/tmp/q", size: 0, sourceType: .audio)
        pf.transcript = capture           // trusted phone transcript (capture memos sync as normal memos)
        pf.transcribeStatus = .done
        return pf
    }

    func testRunKeepsProtectedEditAndQuote() async throws {
        let pf = captureFile()
        let runner = BatchRunner(transcriber: FailingTranscriber(), enhancer: ProtectingEnhancer(),
                                 settings: .default, people: [], tagWhitelist: [])
        try await runner.run(pf, audioURL: nil)

        let copyedit = try XCTUnwrap(pf.enhancedCopyedit)
        XCTAssertTrue(copyedit.hasPrefix(quote), "quote survives on top")
        XCTAssertTrue(copyedit.contains("EDITED I keep coming back"), "ramble was copy-edited")
        XCTAssertEqual(pf.enhanceStatus, .done)
    }

    func testRunFallsBackToUneditedTranscriptOnMutatedQuote() async throws {
        let pf = captureFile()
        var settings = AppSettings.default; settings.summaryMinWords = 0   // keep the summary for this short capture
        let runner = BatchRunner(transcriber: FailingTranscriber(), enhancer: ManglingEnhancer(),
                                 settings: settings, people: [], tagWhitelist: [])
        try await runner.run(pf, audioURL: nil)

        XCTAssertEqual(pf.enhancedCopyedit, capture, "skip-all: the fully-unedited body")
        XCTAssertEqual(pf.enhancedTitle, "A Title", "title/summary still generate over the full text")
        XCTAssertEqual(pf.enhancedSummary, "A summary.")
        XCTAssertEqual(pf.enhanceStatus, .done)
    }

    func testRunWithoutQuoteIsUnaffectedByGate() async throws {
        let pf = PipelineFile(id: "q2", filename: "memo.m4a", path: "/tmp/q2", size: 0, sourceType: .audio)
        pf.transcript = "Optimism is a plain word in a plain memo."
        pf.transcribeStatus = .done
        let runner = BatchRunner(transcriber: FailingTranscriber(), enhancer: ManglingEnhancer(),
                                 settings: .default, people: [], tagWhitelist: [])
        try await runner.run(pf, audioURL: nil)

        // No leading quote → the gate passes the (edited) text through untouched.
        XCTAssertEqual(pf.enhancedCopyedit, "Hope is a plain word in a plain memo.")
    }
}

/// Transcription must never run for these files (trusted transcript present).
private struct FailingTranscriber: Transcribing {
    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
        XCTFail("transcribe must not be called for a trusted transcript")
        return TranscriptionResult(text: "", confidence: 0, durationMs: 0, wordTimings: [], markersInjected: false)
    }
}
