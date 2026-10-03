import XCTest
import Foundation

/// Q99 / C124 with C102: a merged multi-clip note that is split into speakers keeps one
/// paragraph per clip INSIDE the turns. The diarisation rebuild re-emits the body from the words,
/// so the clip starts have to go through it again.
final class SplitMergedNoteClipParagraphsTests: XCTestCase {
    /// 20 run-on words, 0.3 s apart, no full stop and no pause: only the clip starts can break them.
    private static let words: [WordTiming] = (1...20).map {
        WordTiming(word: "w\($0)", start: Double($0 - 1) * 0.3, end: Double($0 - 1) * 0.3 + 0.28)
    }
    private struct Run: Transcribing {
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            TranscriptionResult(text: SplitMergedNoteClipParagraphsTests.words.map(\.word).joined(separator: " "),
                                confidence: 0.9, durationMs: 1,
                                wordTimings: SplitMergedNoteClipParagraphsTests.words, markersInjected: false)
        }
    }
    private struct Echo: Enhancing {
        func copyEdit(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { t }
        func title(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "T" }
        func summary(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "S" }
    }
    /// Two voices: 0 speaks 0-3 s (w1-w10), 1 speaks 3-6 s (w11-w20).
    private struct TwoVoices: Diarizing {
        func diarize(audioURL: URL, targetSpeakers: Int?) async throws -> DiarizationOutput {
            DiarizationOutput(segments: [DiarizedSegment(speaker: 0, start: 0, end: 3),
                                         DiarizedSegment(speaker: 1, start: 3, end: 6)], slotNames: [:])
        }
    }

    func testSplitSpeakersOnAMergedNoteKeepsEachClipStartAsAParagraph() async throws {
        // Three 2 s clips: starts at 2 s (inside voice 0's turn) and 4 s (inside voice 1's turn).
        let pf = PipelineFile(id: "q99", filename: "merged.m4a", path: "/tmp/q99", size: 0, sourceType: .audio)
        pf.transcribeStatus = .done
        SplitSpeakers.request(pf)
        let runner = BatchRunner(transcriber: Run(), enhancer: Echo(), settings: .default,
                                 people: [], tagWhitelist: [], diarizer: TwoVoices())
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/q99.m4a"),
                             clipStarts: [2, 4], retranscribe: true, requireSplit: true)

        let body = try XCTUnwrap(pf.transcript)
        XCTAssertTrue(SpeakerTranscript.isConversation(body), body)
        let paras = body.components(separatedBy: "\n\n")
        XCTAssertEqual(paras.count, 4, "two turns, each broken once at a clip start: \(body)")
        XCTAssertTrue(paras[0].hasPrefix("**Speaker 1:** w1 "), body)
        XCTAssertTrue(paras[1].hasPrefix("w8 "), "clip 2 starts a paragraph inside turn 1: \(body)")
        XCTAssertTrue(paras[2].hasPrefix("**Speaker 2:** w11 "), body)
        XCTAssertTrue(paras[3].hasPrefix("w15 "), "clip 3 (4 s, first word at or after it is w15) starts a paragraph inside turn 2: \(body)")
    }

    func testWithoutClipStartsTheTurnsStayWhole() async throws {
        let pf = PipelineFile(id: "q99b", filename: "plain.m4a", path: "/tmp/q99b", size: 0, sourceType: .audio)
        pf.transcribeStatus = .done
        SplitSpeakers.request(pf)
        let runner = BatchRunner(transcriber: Run(), enhancer: Echo(), settings: .default,
                                 people: [], tagWhitelist: [], diarizer: TwoVoices())
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/q99b.m4a"),
                             retranscribe: true, requireSplit: true)
        XCTAssertEqual((pf.transcript ?? "").components(separatedBy: "\n\n").count, 2, pf.transcript ?? "nil")
    }
}
