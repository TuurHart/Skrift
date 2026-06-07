import XCTest
import Foundation

private struct StubTranscriber: Transcribing {
    let text: String
    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
        TranscriptionResult(text: text, confidence: 0.9, durationMs: 1, wordTimings: [], markersInjected: false)
    }
}

private struct TimingTranscriber: Transcribing {
    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
        TranscriptionResult(text: "one two three", confidence: 0.9, durationMs: 1,
                            wordTimings: [WordTiming(word: "one", start: 0, end: 0.5),
                                          WordTiming(word: "two", start: 0.5, end: 1.0),
                                          WordTiming(word: "three", start: 1.0, end: 1.5)],
                            markersInjected: false)
    }
}

private final class CallTracker: @unchecked Sendable { var transcribeCalled = false }

private struct TrackingTranscriber: Transcribing {
    let tracker: CallTracker
    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
        tracker.transcribeCalled = true
        return TranscriptionResult(text: "SHOULD NOT BE USED", confidence: 0, durationMs: 0, wordTimings: [], markersInjected: false)
    }
}

/// Echoes the transcript as the copy-edit so the name-link step sees the names.
private struct EchoEnhancer: Enhancing {
    func copyEdit(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { transcript }
    func title(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "A Title" }
    func summary(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "A summary." }
}

final class BatchRunnerTests: XCTestCase {

    func testFullRunPopulatesAllStepsAndLinksNames() async throws {
        let pf = PipelineFile(id: "1", filename: "memo.m4a", path: "/tmp/x", size: 0, sourceType: .audio)
        let runner = BatchRunner(
            transcriber: StubTranscriber(text: "Nick and I met today. Nick is great."),
            enhancer: EchoEnhancer(),
            settings: .default,
            people: [Person(canonical: "[[Nick Jansen]]", aliases: ["Nick"], short: "Nick", lastModifiedAt: "2026-01-01T00:00:00.000Z")],
            tagWhitelist: []
        )
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/x.m4a"))

        XCTAssertEqual(pf.transcribeStatus, .done)
        XCTAssertEqual(pf.enhanceStatus, .done)
        XCTAssertEqual(pf.transcript, "Nick and I met today. Nick is great.")
        XCTAssertEqual(pf.enhancedCopyedit, "Nick and I met today. Nick is great.")
        XCTAssertEqual(pf.enhancedTitle, "A Title")
        XCTAssertEqual(pf.enhancedSummary, "A summary.")
        XCTAssertEqual(pf.sanitised, "[[Nick Jansen]] and I met today. Nick is great.")  // first→link, rest→short
        let compiled = try XCTUnwrap(pf.compiledText)
        XCTAssertTrue(compiled.contains("title: A Title"))
        XCTAssertTrue(compiled.hasSuffix("[[Nick Jansen]] and I met today. Nick is great."))
    }

    func testPresetTitleIsPreservedAsLLMBecomesSuggestion() async throws {
        // A phone/user-set title must survive the run; the LLM title becomes the suggestion.
        let pf = PipelineFile(id: "3", filename: "memo.m4a", path: "/tmp/z", size: 0, sourceType: .audio)
        pf.enhancedTitle = "User Title"
        let runner = BatchRunner(
            transcriber: StubTranscriber(text: "Some words here."),
            enhancer: EchoEnhancer(),
            settings: .default,
            people: [],
            tagWhitelist: []
        )
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/z.m4a"))

        XCTAssertEqual(pf.enhancedTitle, "User Title")   // not clobbered
        XCTAssertEqual(pf.titleSuggested, "A Title")      // LLM result kept as the suggestion
    }

    func testWordTimingsPersistedFromTranscribe() async throws {
        // A2: timings were computed by the transcriber then discarded — assert the
        // run now persists them (and that they round-trip through the JSON blob).
        let pf = PipelineFile(id: "wt", filename: "memo.m4a", path: "/tmp/wt", size: 0, sourceType: .audio)
        let runner = BatchRunner(transcriber: TimingTranscriber(), enhancer: EchoEnhancer(),
                                 settings: .default, people: [], tagWhitelist: [])
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/wt.m4a"))

        XCTAssertEqual(pf.wordTimings.count, 3)
        XCTAssertEqual(pf.wordTimings.first?.word, "one")
        XCTAssertEqual(pf.wordTimings.last?.end, 1.5)
        XCTAssertNotNil(pf.wordTimingsJSON)   // persisted as a blob
    }

    func testTrustedTranscriptSkipsTranscription() async throws {
        let pf = PipelineFile(id: "2", filename: "memo.m4a", path: "/tmp/y", size: 0, sourceType: .audio)
        pf.transcript = "preset transcript"
        pf.transcribeStatus = .done
        let tracker = CallTracker()
        let runner = BatchRunner(
            transcriber: TrackingTranscriber(tracker: tracker),
            enhancer: EchoEnhancer(),
            settings: .default,
            people: [],
            tagWhitelist: []
        )
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/y.m4a"))

        XCTAssertFalse(tracker.transcribeCalled)            // trusted transcript → skip ASR
        XCTAssertEqual(pf.transcript, "preset transcript")
        XCTAssertEqual(pf.enhanceStatus, .done)
        XCTAssertEqual(pf.enhancedCopyedit, "preset transcript")
    }
}
