import XCTest
@testable import SkriftMobile

/// Q99 / C124 with C102, phone side: "Split speakers" on a merged multi-clip note rebuilds the
/// body from the words; the clip starts in `metadata.clipManifest` must go through that rebuild
/// so each clip still opens a paragraph inside its turn.
final class SplitMergedNoteClipParagraphsTests: XCTestCase {
    /// Two voices: 0 speaks 0-3 s (w1-w10), 1 speaks 3-6 s (w11-w20).
    private struct TwoVoices: Diarizing {
        func diarize(audioURL: URL, targetSpeakers: Int?) async throws -> DiarizationOutput {
            DiarizationOutput(segments: [DiarizedSegment(speaker: 0, start: 0, end: 3),
                                         DiarizedSegment(speaker: 1, start: 3, end: 6)], slotNames: [:])
        }
    }

    @MainActor
    private func splitMergedNote(clipManifest: [ClipManifestEntry]?) async throws -> String {
        let repo = NotesRepository(inMemory: true)
        let words = (1...20).map { WordTiming(word: "w\($0)", start: Double($0 - 1) * 0.3,
                                              end: Double($0 - 1) * 0.3 + 0.28) }
        let wt = WordTimingsStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true))
        let id = UUID()
        wt.write(words, for: id)
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", duration: 6,
                        transcript: words.map(\.word).joined(separator: " "),
                        transcriptStatus: .done, transcriptConfidence: 0.9)
        memo.metadata = MemoMetadata(clipManifest: clipManifest)
        repo.insert(memo)
        let saver = MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "x"),
                              diarizer: TwoVoices(), wordTimings: wt, metadataProvider: MockMetadataService())
        let outcome = await saver.diarizeExisting(id: id)
        XCTAssertEqual(outcome, .split)
        return try XCTUnwrap(repo.memo(id: id)?.transcript)
    }

    @MainActor
    func testSplitSpeakersOnAMergedNoteKeepsEachClipStartAsAParagraph() async throws {
        let manifest = [ClipManifestEntry(filename: "a.m4a", startSeconds: 0, recordedAt: nil),
                        ClipManifestEntry(filename: "b.m4a", startSeconds: 2, recordedAt: nil),
                        ClipManifestEntry(filename: "c.m4a", startSeconds: 4, recordedAt: nil)]
        let body = try await splitMergedNote(clipManifest: manifest)
        XCTAssertTrue(SpeakerTranscript.isAttributed(body), body)
        let paras = body.components(separatedBy: "\n\n")
        XCTAssertEqual(paras.count, 4, "two turns, each broken once at a clip start: \(body)")
        XCTAssertTrue(paras[0].hasPrefix("**Speaker 1:** w1 "), body)
        XCTAssertTrue(paras[1].hasPrefix("w8 "), "clip 2 starts a paragraph inside turn 1: \(body)")
        XCTAssertTrue(paras[2].hasPrefix("**Speaker 2:** w11 "), body)
        XCTAssertTrue(paras[3].hasPrefix("w15 "), "clip 3 (4 s, first word at or after it is w15) starts a paragraph inside turn 2: \(body)")
    }

    @MainActor
    func testSplitSpeakersOnASingleClipNoteStaysOneParagraphPerTurn() async throws {
        let body = try await splitMergedNote(clipManifest: nil)
        XCTAssertEqual(body.components(separatedBy: "\n\n").count, 2, body)
    }
}
