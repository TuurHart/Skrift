import XCTest
import Foundation

/// Q87 — the Mac's per-note "Split speakers" switch (mock `mocks/Q86-split-speakers.html`):
/// the opt-in flag (C102), the one-voice outcome writing NOTHING, Cancel, Flatten keeping the
/// words + fixes + names, and naming from the gutter.
final class SplitSpeakersTests: XCTestCase {
    private struct FourWords: Transcribing {
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
    private struct Voices: Diarizing {
        let count: Int
        func diarize(audioURL: URL, targetSpeakers: Int?) async throws -> DiarizationOutput {
            let segs = count >= 2
                ? [DiarizedSegment(speaker: 0, start: 0, end: 1), DiarizedSegment(speaker: 1, start: 1, end: 2)]
                : [DiarizedSegment(speaker: 0, start: 0, end: 2)]
            return DiarizationOutput(segments: segs, slotNames: [:])
        }
    }

    private func note(_ id: String, transcript: String = "my hand edited words") -> PipelineFile {
        let pf = PipelineFile(id: id, filename: "memo.m4a", path: "/tmp/\(id)", size: 0, sourceType: .audio)
        pf.transcript = transcript
        pf.transcribeStatus = .done
        return pf
    }
    private func runner(voices: Int) -> BatchRunner {
        BatchRunner(transcriber: FourWords(), enhancer: Echo(), settings: .default,
                    people: [], tagWhitelist: [], diarizer: Voices(count: voices))
    }
    private let audio = URL(fileURLWithPath: "/tmp/split.m4a")

    // MARK: opt-in + outcomes

    func testRequestSetsTheOptInFlag() {
        let pf = note("s1")
        XCTAssertFalse(pf.diarizeRequested, "off by default")
        SplitSpeakers.request(pf)
        XCTAssertTrue(pf.diarizeRequested)
        SplitSpeakers.withdraw(pf)
        XCTAssertFalse(pf.diarizeRequested)
    }

    func testTwoVoicesWriteTheTurns() async throws {
        let pf = note("s2")
        SplitSpeakers.request(pf)
        try await runner(voices: 2).run(pf, audioURL: audio, retranscribe: true, requireSplit: true)
        XCTAssertEqual(pf.transcript, "**Speaker 1:** one two\n\n**Speaker 2:** three four")
        XCTAssertTrue(SplitSpeakers.isSplit(pf))
        XCTAssertEqual(SplitSpeakers.settle(pf, error: nil), .split)
        XCTAssertTrue(pf.diarizeRequested, "a split note keeps its opt-in")
    }

    func testOneVoiceWritesNothingAndSwitchFallsBackOff() async {
        let pf = note("s3")
        SplitSpeakers.request(pf)
        do {
            try await runner(voices: 1).run(pf, audioURL: audio, retranscribe: true, requireSplit: true)
            XCTFail("one voice must not commit")
        } catch {
            XCTAssertEqual(error as? BatchRunnerError, .oneVoice)
            XCTAssertEqual(SplitSpeakers.settle(pf, error: error), .oneVoice)
        }
        XCTAssertEqual(pf.transcript, "my hand edited words", "nothing was split, so nothing was replaced")
        XCTAssertEqual(pf.transcribeStatus, .done)
        XCTAssertTrue(pf.wordTimings.isEmpty)
        XCTAssertFalse(pf.diarizeRequested, "the switch falls back off")
        XCTAssertEqual(SplitSpeakersCopy.oneVoice, "Only one voice found. Nothing was split.")
    }

    func testCancelLeavesTheNoteAsItWas() async {
        let pf = note("s4")
        SplitSpeakers.request(pf)
        do {
            try await runner(voices: 2).run(pf, audioURL: audio, retranscribe: true, requireSplit: true,
                                            cancelCheck: { true })
            XCTFail("a cancelled split must not commit")
        } catch {
            XCTAssertEqual(error as? BatchRunnerError, .cancelled)
            XCTAssertEqual(SplitSpeakers.settle(pf, error: error), .cancelled)
        }
        XCTAssertEqual(pf.transcript, "my hand edited words")
        XCTAssertEqual(pf.transcribeStatus, .done)
        XCTAssertFalse(pf.diarizeRequested)
    }

    // MARK: queue

    func testSplitJobQueuesOncePerNoteAndCancelsWhileWaiting() {
        var q = RunQueue()
        q.enqueue(.split(id: "a"))
        q.enqueue(.split(id: "a"))
        q.enqueue(.split(id: "b"))
        XCTAssertEqual(q.jobs, [.split(id: "a"), .split(id: "b")])
        XCTAssertTrue(q.jobs.contains(.split(id: "a")))
        XCTAssertTrue(q.removeSplit(id: "a"))
        XCTAssertFalse(q.removeSplit(id: "a"))
        XCTAssertEqual(q.next(), .split(id: "b"))
    }

    // MARK: flatten

    func testFlattenKeepsWordsFixesAndNameChoices() {
        let pf = note("s5", transcript: "**Tiuri Hartog:** So the stall is Saturday.\n\n**Maria Santos:** Nine is early, i think.")
        pf.unlinkedNames = ["Joost"]
        pf.namePicks = ["jack": "[[Jack Smith]]"]
        pf.diarizeRequested = true
        XCTAssertEqual(SplitSpeakers.namedPerson(in: pf, people: []), "Tiuri Hartog")
        XCTAssertTrue(SplitSpeakers.flatten(pf))
        XCTAssertEqual(pf.transcript, "So the stall is Saturday.\n\nNine is early, i think.",
                       "the words stay, with the user's fix ('i think' is not re-transcribed)")
        XCTAssertFalse(SplitSpeakers.isSplit(pf))
        XCTAssertFalse(pf.diarizeRequested)
        XCTAssertEqual(pf.unlinkedNames, ["Joost"])
        XCTAssertEqual(pf.namePicks, ["jack": "[[Jack Smith]]"])
        XCTAssertEqual(pf.enhanceStatus, .pending, "the title and summary are written again for one voice")
        XCTAssertFalse(SplitSpeakers.flatten(pf), "already flat: a safe no-op")
    }

    // MARK: naming from the gutter

    func testNamingASpeakerRenamesAllTheirTurnsButOnlyTheirs() {
        let pf = note("s6", transcript: "**Tiuri Hartog:** a\n\n**Speaker 2:** b\n\n**Tiuri:** c\n\n**Speaker 2:** d")
        XCTAssertEqual(SplitSpeakers.turnCount(of: "Speaker 2", in: pf, people: []), 2)
        XCTAssertEqual(SplitSpeakers.otherSpeakers(than: "Speaker 2", in: pf, people: []), ["Tiuri Hartog", "Tiuri"],
                       "with no roster the two spellings are two labels; with one they are one voice")
        XCTAssertTrue(SplitSpeakers.nameSpeaker(pf, displayed: "Speaker 2", as: "Maria Santos", people: []))
        XCTAssertEqual(pf.transcript,
                       "**Tiuri Hartog:** a\n\n**Maria Santos:** b\n\n**Tiuri:** c\n\n**Maria Santos:** d")
    }

    func testMoveJustThisLineChangesOneTurn() {
        let pf = note("s7", transcript: "**Tiuri:** a\n\n**Speaker 2:** b\n\n**Tiuri:** c\n\n**Speaker 2:** d")
        pf.sanitised = pf.transcript
        XCTAssertTrue(SplitSpeakers.moveLine(pf, turnIndex: 1, to: "Tiuri", people: []))
        XCTAssertEqual(pf.transcript, "**Tiuri:** a b c\n\n**Speaker 2:** d",
                       "only the tapped line moved; the neighbours of the same speaker fold together")
    }

    // MARK: words

    func testEstimateNamesTheNumber() {
        XCTAssertEqual(SplitSpeakersCopy.estimate(durationSeconds: 192), "About 3 minutes for this 3:12 recording.")
        XCTAssertEqual(SplitSpeakersCopy.estimate(durationSeconds: 60), "About 1 minute for this 1:00 recording.")
        XCTAssertTrue(SplitSpeakersCopy.estimate(durationSeconds: 20).hasPrefix("Under a minute"))
    }

    func testEditWarningNamesTheDateOnlyWhenEdited() {
        XCTAssertNil(SplitSpeakersCopy.editWarning(editedAt: nil))
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 28; c.hour = 12
        let d = Calendar(identifier: .gregorian).date(from: c)!
        XCTAssertEqual(SplitSpeakersCopy.editWarning(editedAt: d),
                       "You edited this transcript on 28 Sep. Those edits are replaced.")
    }
}
