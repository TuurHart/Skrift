import XCTest
import Foundation

/// C51 / R9: re-transcribe clears nothing until the new transcript exists. A missing
/// audio file (or an ASR failure) must leave the OLD transcript and every one of its
/// derivatives exactly as they were, with an error on the row — never a silent
/// `transcribeStatus == .done` over an empty/stale transcript (BUGS D2).
///
/// `ProcessingCoordinator` itself isn't in this MLX-free test target (it references the
/// real MLX/FluidAudio services), so these tests drive `BatchRunner.run(retranscribe:)`
/// directly — the actual seam where the old bug lived and where the fix now lives.
final class RetranscribeKeepsTextTests: XCTestCase {

    private struct NewTextTranscriber: Transcribing {
        let text: String
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            TranscriptionResult(text: text, confidence: 0.9, durationMs: 1, wordTimings: [], markersInjected: false)
        }
    }

    private struct FailingTranscriber: Transcribing {
        struct Boom: Error {}
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            throw Boom()
        }
    }

    private struct EchoEnhancer: Enhancing {
        func copyEdit(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { transcript }
        func title(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "New Title" }
        func summary(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "New summary." }
    }

    /// A note with a full OLD result set, as if a prior run had already completed.
    private func makeProcessedFile() -> PipelineFile {
        let pf = PipelineFile(id: "rt-1", filename: "memo.m4a", path: "", size: 0, sourceType: .audio)
        pf.transcript = "The OLD transcript."
        pf.transcribeStatus = .done
        pf.sanitised = "The OLD transcript, sanitised."
        pf.enhancedCopyedit = "The OLD transcript, copy-edited."
        pf.enhancedSummary = "OLD summary."
        pf.titleSuggested = "OLD Title"
        pf.compiledText = "---\ntitle: \"OLD Title\"\n---\n\nOLD compiled body."
        pf.enhanceStatus = .done
        return pf
    }

    // MARK: - Missing audio file → error, nothing cleared

    func testMissingAudioDuringRetranscribeThrowsAndLeavesEverythingIntact() async throws {
        let pf = makeProcessedFile()
        let runner = BatchRunner(transcriber: NewTextTranscriber(text: "SHOULD NEVER BE USED"),
                                 enhancer: EchoEnhancer(), settings: .default, people: [], tagWhitelist: [])

        do {
            try await runner.run(pf, audioURL: nil, retranscribe: true)
            XCTFail("a missing audio file must throw")
        } catch {
            XCTAssertTrue(error is BatchRunnerError, "a missing audio file must be a typed, row-visible error")
        }

        XCTAssertEqual(pf.transcribeStatus, .error, "the row must show an error, not a silent done")
        XCTAssertEqual(pf.transcript, "The OLD transcript.", "nothing is cleared until the new transcript exists")
        XCTAssertEqual(pf.sanitised, "The OLD transcript, sanitised.")
        XCTAssertEqual(pf.enhancedCopyedit, "The OLD transcript, copy-edited.")
        XCTAssertEqual(pf.enhancedSummary, "OLD summary.")
        XCTAssertEqual(pf.titleSuggested, "OLD Title")
        XCTAssertNotNil(pf.compiledText)
    }

    // MARK: - ASR failure → error, nothing cleared

    func testFailedASRDuringRetranscribeLeavesTheOldTranscriptIntact() async throws {
        let pf = makeProcessedFile()
        let runner = BatchRunner(transcriber: FailingTranscriber(),
                                 enhancer: EchoEnhancer(), settings: .default, people: [], tagWhitelist: [])

        do {
            try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/does-not-matter.m4a"), retranscribe: true)
            XCTFail("the ASR failure must propagate")
        } catch {
            XCTAssertTrue(error is FailingTranscriber.Boom)
        }

        XCTAssertEqual(pf.transcribeStatus, .error)
        XCTAssertEqual(pf.transcript, "The OLD transcript.", "a run that fails partway must leave the note untouched")
        XCTAssertEqual(pf.sanitised, "The OLD transcript, sanitised.")
        XCTAssertEqual(pf.enhancedCopyedit, "The OLD transcript, copy-edited.")
    }

    // MARK: - Success → old derivatives cleared and rebuilt from the NEW transcript

    func testSuccessfulRetranscribeReplacesTranscriptAndItsDerivatives() async throws {
        let pf = makeProcessedFile()
        let runner = BatchRunner(transcriber: NewTextTranscriber(text: "The brand new transcript."),
                                 enhancer: EchoEnhancer(), settings: .default, people: [], tagWhitelist: [])

        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/audio.m4a"), retranscribe: true)

        XCTAssertEqual(pf.transcribeStatus, .done)
        XCTAssertEqual(pf.enhanceStatus, .done)
        XCTAssertEqual(pf.transcript, "The brand new transcript.")
        XCTAssertNotEqual(pf.sanitised, "The OLD transcript, sanitised.", "the old derivative must not survive")
        XCTAssertNotEqual(pf.enhancedCopyedit, "The OLD transcript, copy-edited.")
        XCTAssertNotEqual(pf.enhancedSummary, "OLD summary.")
        XCTAssertEqual(pf.titleSuggested, "New Title")
        XCTAssertTrue(try XCTUnwrap(pf.compiledText).contains("The brand new transcript."))
    }

    /// Without `retranscribe: true`, an already-`.done` transcript is trusted and the
    /// ASR never runs — proves the flag, not just the transcript-emptiness, is what
    /// forces the fresh pass.
    func testWithoutRetranscribeFlagATrustedTranscriptIsUntouched() async throws {
        let pf = makeProcessedFile()
        let runner = BatchRunner(transcriber: NewTextTranscriber(text: "SHOULD NOT RUN"),
                                 enhancer: EchoEnhancer(), settings: .default, people: [], tagWhitelist: [])

        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/audio.m4a"))

        XCTAssertEqual(pf.transcript, "The OLD transcript.")
    }
}

/// XCTAssertThrowsError has no async overload in this SDK version — this local
/// helper awaits the throwing expression first, matching the sync assertion's shape.
func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T,
                                  _ errorHandler: (Error) -> Void = { _ in },
                                  file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("expected an error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
