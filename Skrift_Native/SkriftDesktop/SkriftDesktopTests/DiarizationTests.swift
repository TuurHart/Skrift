import XCTest
import Foundation

/// Desktop conversation-mode logic: the pure fusion/match/attribution primitives
/// (ported from the phone) + the BatchRunner integration that re-emits a multi-speaker
/// transcript as `**[[Person]]:**` / `**Speaker N:**` turns. The Sortformer/wespeaker
/// engine itself is device-only (Engines/, excluded from this host-less target).
final class DiarizationTests: XCTestCase {
    private func w(_ word: String, _ s: Double, _ e: Double) -> WordTiming { WordTiming(word: word, start: s, end: e) }

    // MARK: SpeakerFusion

    func testFusionSplitsTwoSpeakers() {
        let words = [w("Hi", 0, 1), w("there", 1, 2), w("Hello", 3, 4), w("back", 4, 5)]
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 2.5), DiarizedSegment(speaker: 1, start: 2.5, end: 5)]
        XCTAssertEqual(SpeakerFusion.turns(words: words, segments: segs),
                       [.init(speaker: 0, text: "Hi there"), .init(speaker: 1, text: "Hello back")])
    }

    func testFusionFoldsPhantomOneWordIsland() {
        // "Oh" (spk2) sandwiched between spk0 and spk1, timed against spk0 → folds in (parity
        // with the phone; kills Sortformer's over-segmented interjections).
        let words = [w("a", 0, 1), w("b", 1, 2), w("Oh", 2.0, 2.2), w("c", 5, 6), w("d", 6, 7)]
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 2),
                    DiarizedSegment(speaker: 2, start: 2, end: 2.3),
                    DiarizedSegment(speaker: 1, start: 5, end: 7)]
        XCTAssertEqual(SpeakerFusion.turns(words: words, segments: segs),
                       [.init(speaker: 0, text: "a b Oh"), .init(speaker: 1, text: "c d")])
    }

    func testFusionAttributedMarkdownUsesNameClosure() {
        let words = [w("Hi", 0, 1), w("Hello", 3, 4)]
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 2), DiarizedSegment(speaker: 1, start: 2, end: 5)]
        let md = SpeakerFusion.attributedTranscript(words: words, segments: segs) {
            $0 == 0 ? "[[Tiuri Hartog]]" : "Speaker 2"
        }
        XCTAssertEqual(md, "**[[Tiuri Hartog]]:** Hi\n\n**Speaker 2:** Hello")
    }

    // MARK: VoiceMatcher

    func testCosineAndBestMatch() {
        XCTAssertEqual(VoiceMatcher.cosine([1, 0, 0], [1, 0, 0]), 1, accuracy: 1e-5)
        XCTAssertEqual(VoiceMatcher.cosine([1, 2, 3], [1, 2]), 0)   // shape mismatch never matches
        let tiuri = Person(canonical: "[[Tiuri]]", voiceEmbeddings: [VoiceEmbedding(vector: [1, 0, 0])], lastModifiedAt: "x")
        let jane = Person(canonical: "[[Jane]]", voiceEmbeddings: [VoiceEmbedding(vector: [0, 1, 0])], lastModifiedAt: "x")
        XCTAssertEqual(VoiceMatcher.bestMatch(embedding: [0.9, 0.1, 0], people: [jane, tiuri], threshold: 0.5)?.person.displayName, "Tiuri")
        XCTAssertNil(VoiceMatcher.bestMatch(embedding: [0.45, 0.89, 0], people: [tiuri], threshold: 0.5))
    }

    // MARK: isAttributed

    func testIsAttributed() {
        XCTAssertTrue(SpeakerTranscript.isAttributed("**Tiuri:** hi\n\n**Speaker 2:** yo"))
        XCTAssertFalse(SpeakerTranscript.isAttributed("just a plain monologue transcript"))
        XCTAssertFalse(SpeakerTranscript.isAttributed("**Only one:** turn"))   // needs ≥2
        XCTAssertFalse(SpeakerTranscript.isAttributed(nil))
    }

    // MARK: BatchRunner integration

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
    private struct PresetTranscriber: Transcribing {
        let text: String; let timings: [WordTiming]
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            TranscriptionResult(text: text, confidence: 0.9, durationMs: 1, wordTimings: timings, markersInjected: false)
        }
    }
    private struct Echo: Enhancing {
        func copyEdit(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { t }
        func title(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "T" }
        func summary(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "S" }
    }
    private struct StubDiarizer: Diarizing {
        let output: DiarizationOutput
        func diarize(audioURL: URL) async throws -> DiarizationOutput { output }
    }
    /// Simulates the real Gemma copy-edit stripping the `**` bold markers (it drops the
    /// `**Name:**` speaker prefixes — verified on the fixture).
    private struct StrippingEnhancer: Enhancing {
        func copyEdit(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
            t.replacingOccurrences(of: "*", with: "")
        }
        func title(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "T" }
        func summary(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "S" }
    }

    private func twoSpeakerStub(named: [Int: String]) -> StubDiarizer {
        StubDiarizer(output: DiarizationOutput(
            segments: [DiarizedSegment(speaker: 0, start: 0, end: 1), DiarizedSegment(speaker: 1, start: 1, end: 2)],
            slotNames: named))
    }

    func testRunDiarizesMatchedAndUnmatchedSpeakers() async throws {
        let pf = PipelineFile(id: "c1", filename: "m.m4a", path: "/tmp/c1", size: 0, sourceType: .audio)
        let runner = BatchRunner(transcriber: FourWordTranscriber(), enhancer: Echo(), settings: .default,
                                 people: [], tagWhitelist: [], diarizer: twoSpeakerStub(named: [0: "Tiuri Hartog"]))
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/c1.m4a"))
        let t = try XCTUnwrap(pf.transcript)
        XCTAssertTrue(t.contains("**[[Tiuri Hartog]]:** one two"), "matched speaker → canonical link turn; got: \(t)")
        XCTAssertTrue(t.contains("**Speaker 2:** three four"), "unmatched speaker → Speaker N; got: \(t)")
    }

    func testRunSkipsDiarizationWhenConversationModeOff() async throws {
        var settings = AppSettings.default; settings.conversationMode = false
        let pf = PipelineFile(id: "c2", filename: "m.m4a", path: "/tmp/c2", size: 0, sourceType: .audio)
        let runner = BatchRunner(transcriber: FourWordTranscriber(), enhancer: Echo(), settings: settings,
                                 people: [], tagWhitelist: [], diarizer: twoSpeakerStub(named: [0: "Tiuri Hartog"]))
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/c2.m4a"))
        XCTAssertEqual(pf.transcript, "one two three four")   // untouched
    }

    func testRunSkipsDiarizationForAlreadyAttributedTranscript() async throws {
        let attributed = "**Tiuri:** one two\n\n**Roksana:** three four"
        let timings = [WordTiming(word: "one", start: 0, end: 0.5), WordTiming(word: "two", start: 0.5, end: 1),
                       WordTiming(word: "three", start: 1, end: 1.5), WordTiming(word: "four", start: 1.5, end: 2)]
        let pf = PipelineFile(id: "c3", filename: "m.m4a", path: "/tmp/c3", size: 0, sourceType: .audio)
        let runner = BatchRunner(transcriber: PresetTranscriber(text: attributed, timings: timings), enhancer: Echo(),
                                 settings: .default, people: [], tagWhitelist: [],
                                 diarizer: twoSpeakerStub(named: [0: "Should Not Appear"]))
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/c3.m4a"))
        XCTAssertEqual(pf.transcript, attributed)   // phone already split it → not re-diarized
        XCTAssertFalse((pf.transcript ?? "").contains("Should Not Appear"))
    }

    func testConversationSkipsCopyEditSoTurnsSurviveExport() async throws {
        // A label-stripping copy-edit must NOT be applied to a diarized conversation —
        // otherwise the **Speaker N:**/**[[Person]]:** turns vanish from the exported note.
        let pf = PipelineFile(id: "c5", filename: "m.m4a", path: "/tmp/c5", size: 0, sourceType: .audio)
        let runner = BatchRunner(transcriber: FourWordTranscriber(), enhancer: StrippingEnhancer(), settings: .default,
                                 people: [], tagWhitelist: [], diarizer: twoSpeakerStub(named: [0: "Tiuri Hartog"]))
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/c5.m4a"))
        XCTAssertEqual(pf.enhancedCopyedit, pf.transcript, "copy-edit must be skipped for a conversation")
        let s = try XCTUnwrap(pf.sanitised)
        XCTAssertTrue(s.contains("**Speaker 2:**"), "speaker turns must survive into the body; got: \(s)")
        XCTAssertTrue(s.contains("**[[Tiuri Hartog]]:**"), "matched speaker link must survive; got: \(s)")
    }

    func testRunLeavesMonologueUntouched() async throws {
        let pf = PipelineFile(id: "c4", filename: "m.m4a", path: "/tmp/c4", size: 0, sourceType: .audio)
        let oneSpeaker = StubDiarizer(output: DiarizationOutput(
            segments: [DiarizedSegment(speaker: 0, start: 0, end: 2)], slotNames: [:]))
        let runner = BatchRunner(transcriber: FourWordTranscriber(), enhancer: Echo(), settings: .default,
                                 people: [], tagWhitelist: [], diarizer: oneSpeaker)
        try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/c4.m4a"))
        XCTAssertEqual(pf.transcript, "one two three four")   // <2 speakers → plain prose
        XCTAssertTrue(pf.diarizationSegments.isEmpty, "monologue → nothing to retain for enrollment")
    }

    // MARK: Diarization persistence (segments survive for later enrollment)

    func testDiarizationDataRoundTrip() throws {
        let data = DiarizationData(
            segments: [DiarizedSegment(speaker: 0, start: 0, end: 1.5),
                       DiarizedSegment(speaker: 1, start: 1.5, end: 3.25)],
            slotNames: ["0": "Tiuri Hartog", "1": "Roksana"])
        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(DiarizationData.self, from: encoded)
        XCTAssertEqual(decoded, data)
    }

    /// The on-disk JSON must mirror the phone's `DiarizationData` byte-format
    /// (`segments` of `{speaker,start,end}` + a string-keyed `slotNames`) so the two
    /// apps' `diar_<id>.json` sidecars stay interchangeable.
    func testDiarizationDataJSONShapeMatchesPhone() throws {
        let data = DiarizationData(
            segments: [DiarizedSegment(speaker: 0, start: 0, end: 1)],
            slotNames: ["0": "Tiuri Hartog"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(data)) as? [String: Any])
        let segs = try XCTUnwrap(json["segments"] as? [[String: Any]])
        XCTAssertEqual(segs.first?["speaker"] as? Int, 0)
        XCTAssertEqual(segs.first?["start"] as? Double, 0)
        XCTAssertEqual(segs.first?["end"] as? Double, 1)
        XCTAssertEqual((json["slotNames"] as? [String: String])?["0"], "Tiuri Hartog")
    }

    func testDiarizationDataFromOutputStringifiesSlotKeys() {
        let out = DiarizationOutput(
            segments: [DiarizedSegment(speaker: 0, start: 0, end: 1), DiarizedSegment(speaker: 2, start: 1, end: 2)],
            slotNames: [0: "Tiuri Hartog", 2: "Roksana"])
        let data = DiarizationData(out)
        XCTAssertEqual(data.segments, out.segments)
        XCTAssertEqual(data.slotNames, ["0": "Tiuri Hartog", "2": "Roksana"])
    }

    func testSidecarWriteLoadDeleteRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("diar-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let sidecar = DiarizationSidecar()
        XCTAssertNil(sidecar.load(in: folder, id: "memo1"), "nothing written yet")

        let data = DiarizationData(
            segments: [DiarizedSegment(speaker: 0, start: 0, end: 2), DiarizedSegment(speaker: 1, start: 2, end: 4)],
            slotNames: ["0": "Tiuri Hartog"])
        sidecar.write(data, in: folder, id: "memo1")

        // Lands at the phone-compatible `diar_<id>.json` filename.
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("diar_memo1.json").path))
        XCTAssertEqual(sidecar.load(in: folder, id: "memo1"), data)

        sidecar.delete(in: folder, id: "memo1")
        XCTAssertNil(sidecar.load(in: folder, id: "memo1"))
    }

    func testRunPersistsSegmentsForLaterEnrollment() async throws {
        // After a conversation-mode Process, the speaker segments survive on the
        // PipelineFile AND as a `diar_<id>.json` sidecar in the working folder, so a
        // speaker's audio can be re-sliced later to enroll their voice.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("diar-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let audioURL = folder.appendingPathComponent("original.m4a")

        let pf = PipelineFile(id: "persist1", filename: "m.m4a", path: audioURL.path, size: 0, sourceType: .audio)
        let runner = BatchRunner(transcriber: FourWordTranscriber(), enhancer: Echo(), settings: .default,
                                 people: [], tagWhitelist: [], diarizer: twoSpeakerStub(named: [0: "Tiuri Hartog"]))
        try await runner.run(pf, audioURL: audioURL)

        // Field (SwiftData-backed) retains both speakers' time-ranges.
        XCTAssertEqual(Set(pf.diarizationSegments.map(\.speaker)), [0, 1])

        // Sidecar mirrors it, keyed by id, with the matched slot name.
        let loaded = try XCTUnwrap(DiarizationSidecar().load(in: folder, id: "persist1"))
        XCTAssertEqual(loaded.segments, pf.diarizationSegments)
        XCTAssertEqual(loaded.slotNames["0"], "Tiuri Hartog")
        XCTAssertNil(loaded.slotNames["1"], "unmatched slot stays nameless (→ Speaker N)")
    }
}
