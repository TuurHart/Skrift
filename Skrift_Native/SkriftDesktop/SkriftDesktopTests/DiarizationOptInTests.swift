import XCTest
import Foundation

/// C102: diarization is opt-in PER NOTE. Tuur 2026-09-27 (prod Mac): videos dragged in from
/// Photos came out diarized. Cause: the old build's `conversationMode = true` default was
/// PERSISTED into settings.json, and the batch runner still honoured that global flag on load.
final class DiarizationOptInTests: XCTestCase {
    private struct FourWordTranscriber: Transcribing {
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            TranscriptionResult(text: "one two three four", confidence: 0.9, durationMs: 1,
                                wordTimings: [WordTiming(word: "one", start: 0, end: 0.5),
                                              WordTiming(word: "two", start: 0.5, end: 1.0),
                                              WordTiming(word: "three", start: 1.0, end: 1.5),
                                              WordTiming(word: "four", start: 1.5, end: 2.0)],
                                markersInjected: false)
        }
    }
    private struct Echo: Enhancing {
        func copyEdit(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { t }
        func title(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "T" }
        func summary(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "S" }
    }
    private struct TwoSpeakerStub: Diarizing {
        func diarize(audioURL: URL, targetSpeakers: Int?) async throws -> DiarizationOutput {
            DiarizationOutput(segments: [DiarizedSegment(speaker: 0, start: 0, end: 1),
                                         DiarizedSegment(speaker: 1, start: 1, end: 2)], slotNames: [:])
        }
    }

    /// A settings.json exactly as the OLD prod build wrote it: `conversationMode: true`.
    private func legacySettingsFile() throws -> URL {
        var s = AppSettings.default
        s.conversationMode = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("optin-\(UUID().uuidString).json")
        try JSONEncoder().encode(s).write(to: url)
        return url
    }

    /// A video dragged in from Photos: sourceType .audio, a .mov path, Mac-transcribed.
    private func macImport(id: String) -> PipelineFile {
        PipelineFile(id: id, filename: "IMG_0042.mov", path: "/tmp/\(id)", size: 0, sourceType: .audio)
    }

    func testMacImportWithNoOptInIsAMonologue() async throws {
        let pf = macImport(id: "optin1")
        let runner = BatchRunner(transcriber: FourWordTranscriber(), enhancer: Echo(), settings: .default,
                                 people: [], tagWhitelist: [], diarizer: TwoSpeakerStub())
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/optin1.mov"))
        XCTAssertEqual(pf.transcript, "one two three four")
        XCTAssertTrue(pf.diarizationSegments.isEmpty)
    }

    func testPersistedGlobalConversationFlagNoLongerDiarizesAMacImport() async throws {
        let url = try legacySettingsFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let loaded = SettingsStore(fileURL: url).load()
        let pf = macImport(id: "optin2")
        let runner = BatchRunner(transcriber: FourWordTranscriber(), enhancer: Echo(), settings: loaded,
                                 people: [], tagWhitelist: [], diarizer: TwoSpeakerStub())
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/optin2.mov"))
        XCTAssertEqual(pf.transcript, "one two three four",
                       "a legacy settings.json conversationMode=true must not diarize; got: \(pf.transcript ?? "")")
        XCTAssertTrue(pf.diarizationSegments.isEmpty)
    }

    func testNoteThatOptedInIsDiarized() async throws {
        let pf = macImport(id: "optin3")
        pf.diarizeRequested = true
        let runner = BatchRunner(transcriber: FourWordTranscriber(), enhancer: Echo(), settings: .default,
                                 people: [], tagWhitelist: [], diarizer: TwoSpeakerStub())
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/optin3.mov"))
        XCTAssertEqual(pf.transcript, "**Speaker 1:** one two\n\n**Speaker 2:** three four")
        XCTAssertEqual(pf.diarizationSegments.count, 2)
    }
}
