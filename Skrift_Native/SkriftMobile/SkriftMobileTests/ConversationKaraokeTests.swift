import XCTest
@testable import SkriftMobile

/// Q183 (C239 / C240 / C124): the phone's CONVERSATION karaoke asks the shared `KaraokeTrack`
/// over all turns' spoken words (as the monologue and the Mac do), split speakers can be
/// cancelled and holds the body read-only, and the assign sheet's count line is one shared rule.
final class ConversationKaraokeTests: XCTestCase {

    private func timings(_ pairs: [(String, Double)]) -> [WordTiming] {
        pairs.map { WordTiming(word: $0.0, start: $0.1, end: $0.1 + 0.4) }
    }

    private func turns(_ pairs: [(String, String)]) -> [SpeakerTranscript.Turn] {
        pairs.map { SpeakerTranscript.Turn(name: $0.0, text: $0.1) }
    }

    func testWordsAreGlobalAcrossTurnsAndPhotoMarkersAreNotSpoken() {
        let t = turns([("Speaker 1", "the meeting [[img_001]] went"), ("Speaker 2", "really  well")])
        XCTAssertEqual(ConversationKaraoke.displayedWords(turns: t), ["the", "meeting", "went", "really", "well"])
        XCTAssertEqual(SpeakerTurnsView.spokenWordCount("the meeting [[img_001]] went"), 3)
    }

    func testExactTrackWhenEveryTimedWordIsShown() {
        let t = turns([("Speaker 1", "the meeting"), ("Speaker 2", "went well")])
        let track = ConversationKaraoke.track(
            turns: t, timings: timings([("the", 0), ("meeting", 1), ("went", 2), ("well", 3)]), duration: 4)
        XCTAssertEqual(track.basis, .exact)
        XCTAssertEqual(track.activeIndex(at: 2.5), 2, "first word of the second turn")
        XCTAssertEqual(track.seekTime(forWord: 3), 3)
    }

    /// A phone-edited conversation (words removed): word N is no longer timing N. The old rule
    /// (`Karaoke.activeWordIndex`) lit word 5 of a 4-word body; the track aligns once instead.
    func testEditedConversationIsAlignedNotIndexed() {
        let t = turns([("Speaker 1", "the meeting [[img_001]]"), ("Speaker 2", "went well")])
        let spoken = timings([("um", 0), ("the", 1), ("meeting", 2), ("you", 3),
                              ("know", 4), ("went", 5), ("really", 6), ("well", 7)])
        let track = ConversationKaraoke.track(turns: t, timings: spoken, duration: 8)
        XCTAssertEqual(track.basis, .aligned)
        XCTAssertEqual(track.activeIndex(at: 5.2), 2)
        XCTAssertEqual(Karaoke.activeWordIndex(spoken, at: 5.2), 5, "the old index rule, now unused here")
        XCTAssertEqual(track.seekTime(forWord: 2), 5, "tapping 'went' seeks to 'went'")
    }

    func testCacheRebuildsOnlyWhenTheTurnsChange() {
        let cache = ConversationKaraokeCache()
        let a = turns([("Speaker 1", "hello there")])
        let tm = timings([("hello", 0), ("there", 1)])
        let first = cache.track(turns: a, timings: tm, duration: 2)
        XCTAssertEqual(first, cache.track(turns: a, timings: tm, duration: 2))
        let edited = cache.track(turns: turns([("Speaker 1", "hello")]), timings: tm, duration: 2)
        XCTAssertEqual(edited.wordCount, 1)
    }

    // MARK: split speakers: read-only + Cancel

    func testBodyIsReadOnlyWhileASplitRuns() {
        XCTAssertEqual(NoteBody.mode(isPlaying: false, status: .done, splitting: true), .reading)
        XCTAssertEqual(NoteBody.mode(isPlaying: false, status: .done, splitting: false), .editing)
        XCTAssertEqual(NoteBody.mode(isPlaying: true, status: .done, splitting: true), .playing)
    }

    @MainActor
    func testStatusKnowsASplitFromAnEnrol() {
        let s = DiarizationStatus.shared
        let id = UUID()
        s.finish()
        XCTAssertFalse(s.isSplitting(id))
        s.begin(id)
        XCTAssertTrue(s.isSplitting(id))
        XCTAssertEqual(s.label(for: id), SplitSpeakersCopy.listening, "the Mac's progress words")
        s.requestCancel(for: UUID())
        XCTAssertFalse(s.cancelRequested, "another note's cancel does nothing")
        s.requestCancel(for: id)
        XCTAssertTrue(s.cancelRequested)
        s.finish()
        XCTAssertFalse(s.cancelRequested)
        s.begin(id, phase: .enrolling)
        XCTAssertFalse(s.isSplitting(id), "learning a voice is naming, not a split")
        s.finish()
    }

    /// Cancel while the diarizer runs: nothing is written, the note is as it was, and the
    /// in-flight marker is cleared.
    private struct CancelsWhileRunning: Diarizing {
        let id: UUID
        func diarize(audioURL: URL, targetSpeakers: Int?) async throws -> DiarizationOutput {
            await MainActor.run { DiarizationStatus.shared.requestCancel(for: id) }
            return DiarizationOutput(segments: [DiarizedSegment(speaker: 0, start: 0, end: 3),
                                                DiarizedSegment(speaker: 1, start: 3, end: 6)], slotNames: [:])
        }
    }

    @MainActor
    func testCancelAbandonsTheSplitAndLeavesTheNoteAsItWas() async throws {
        let repo = NotesRepository(inMemory: true)
        let words = (1...20).map { WordTiming(word: "w\($0)", start: Double($0 - 1) * 0.3,
                                              end: Double($0 - 1) * 0.3 + 0.28) }
        let wt = WordTimingsStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true))
        let id = UUID()
        wt.write(words, for: id)
        let text = words.map(\.word).joined(separator: " ")
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", duration: 6,
                        transcript: text, transcriptStatus: .done, transcriptConfidence: 0.9)
        repo.insert(memo)
        let saver = MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "x"),
                              diarizer: CancelsWhileRunning(id: id), wordTimings: wt,
                              metadataProvider: MockMetadataService())
        let outcome = await saver.diarizeExisting(id: id)
        XCTAssertEqual(outcome, .cancelled)
        let after = try XCTUnwrap(repo.memo(id: id))
        XCTAssertEqual(after.transcript, text)
        XCTAssertNil(after.pendingDiarizationTarget)
        XCTAssertFalse(DiarizationStatus.shared.isSplitting(id))
    }

    // MARK: the assign sheet's line

    func testNamesAllTurnsCountIsOneSharedRule() {
        let transcript = "**Speaker 1:** hi\n\n**Speaker 2:** hello\n\n**Speaker 1:** again\n\n**Speaker 1:** more"
        XCTAssertEqual(SpeakerNaming.turnCount(of: "Speaker 1", in: transcript, people: []), 3)
        XCTAssertEqual(SpeakerNaming.turnCount(of: "Speaker 2", in: transcript, people: []), 1)
        XCTAssertEqual(SplitSpeakersCopy.namesAllTurns(count: 3, speaker: "Speaker 1"),
                       "A person names all 3 of Speaker 1\u{2019}s turns.")
    }
}
