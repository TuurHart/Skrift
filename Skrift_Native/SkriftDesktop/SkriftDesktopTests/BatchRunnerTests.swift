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
        XCTAssertTrue(compiled.contains("title: \"A Title\""))
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

// MARK: - C3 Capture pipeline tests

final class CaptureRunnerTests: XCTestCase {

    private func makeCapture(annotation: String, meta: [String: Any] = [:]) -> PipelineFile {
        let pf = PipelineFile(id: "cap-\(UUID().uuidString)", filename: "capture_test",
                              path: "/tmp/cap", size: 0, sourceType: .capture)
        pf.transcript = annotation
        pf.transcribeStatus = .done
        pf.audioMetadataJSON = try? JSONSerialization.data(withJSONObject: meta)
        return pf
    }

    private func makeRunner(people: [Person] = []) -> BatchRunner {
        BatchRunner(transcriber: StubTranscriber(text: "SHOULD NOT RUN"),
                    enhancer: EchoEnhancer(),
                    settings: .default,
                    people: people,
                    tagWhitelist: [])
    }

    // MARK: Step decisions

    /// Captures never run ASR — transcribeStatus stays .done.
    func testCaptureSkipsTranscription() async throws {
        let tracker = CallTracker()
        let runner = BatchRunner(
            transcriber: TrackingTranscriber(tracker: tracker),
            enhancer: EchoEnhancer(),
            settings: .default,
            people: [],
            tagWhitelist: []
        )
        let pf = makeCapture(annotation: "Some annotation.")
        try await runner.run(pf, audioURL: nil)
        XCTAssertFalse(tracker.transcribeCalled, "ASR must never run for a capture")
        XCTAssertEqual(pf.transcribeStatus, .done)
    }

    /// Captures skip copy-edit — enhancedCopyedit must remain nil.
    func testCaptureSkipsCopyEdit() async throws {
        let pf = makeCapture(annotation: "Try this for the body editor.")
        try await makeRunner().run(pf, audioURL: nil)
        XCTAssertNil(pf.enhancedCopyedit, "copy-edit must be skipped for captures")
        XCTAssertEqual(pf.enhanceStatus, .done)
    }

    /// Title + summary + name-link run on the annotation.
    func testCaptureTitleAndNameLink() async throws {
        let nick = Person(canonical: "[[Nick Jansen]]", aliases: ["Nick"],
                          short: "Nick", lastModifiedAt: "2026-01-01T00:00:00.000Z")
        let pf = makeCapture(annotation: "Nick said this is a good approach.")
        try await makeRunner(people: [nick]).run(pf, audioURL: nil)
        XCTAssertEqual(pf.enhancedTitle, "A Title", "title LLM ran")
        XCTAssertNotNil(pf.enhancedSummary, "summary LLM ran")
        // EchoEnhancer returns the annotation unchanged; Sanitiser links the name.
        XCTAssertTrue((pf.sanitised ?? "").contains("[[Nick Jansen]]"), "name-linked")
    }

    // MARK: Empty annotation — LLM skipped, title from sharedContent

    func testEmptyAnnotationSkipsLLM() async throws {
        let meta: [String: Any] = [
            "sharedContent": ["type": "url",
                              "url": "https://swiftwithmajid.com/2026/05/rich-text-editing",
                              "urlTitle": "Rich text editing in SwiftUI — strategies that work"]
        ]
        let pf = makeCapture(annotation: "", meta: meta)
        let tracker = CallTracker()
        let runner = BatchRunner(transcriber: TrackingTranscriber(tracker: tracker),
                                 enhancer: EchoEnhancer(),
                                 settings: .default, people: [], tagWhitelist: [])
        try await runner.run(pf, audioURL: nil)
        XCTAssertFalse(tracker.transcribeCalled)
        // urlTitle becomes the title.
        XCTAssertEqual(pf.enhancedTitle, "Rich text editing in SwiftUI — strategies that work")
        XCTAssertNil(pf.enhancedSummary, "no summary for empty annotation")
        XCTAssertEqual(pf.enhanceStatus, .done)
    }

    func testEmptyAnnotationFallsBackToTextSnippet() {
        let sc = SharedContent(type: "text", text: "one two three four five six seven eight nine")
        let title = BatchRunner.captureFallbackTitle(sc, existingTitle: nil)
        XCTAssertEqual(title, "one two three four five six seven eight…", "8-word truncation + ellipsis")
    }

    func testEmptyAnnotationFallsBackToImageFilename() {
        let sc = SharedContent(type: "image", fileName: "whiteboard.jpg")
        let title = BatchRunner.captureFallbackTitle(sc, existingTitle: nil)
        XCTAssertEqual(title, "whiteboard.jpg")
    }

    func testEmptyAnnotationDefaultsToCapture() {
        let title = BatchRunner.captureFallbackTitle(nil, existingTitle: nil)
        XCTAssertEqual(title, "Capture")
    }

    func testPresetTitleHonoredForCapture() {
        let sc = SharedContent(type: "url", urlTitle: "Page Title")
        let title = BatchRunner.captureFallbackTitle(sc, existingTitle: "User Set Title")
        XCTAssertEqual(title, "User Set Title", "preset title wins over urlTitle")
    }
}
