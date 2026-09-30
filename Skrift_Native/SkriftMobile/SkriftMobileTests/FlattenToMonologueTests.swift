import XCTest
@testable import SkriftMobile

/// Q87 — the phone's way back from a split: "Flatten to monologue" (mock
/// `SkriftDesktop/mocks/Q86-split-speakers.html`, phone step 7). The words and the user's fixes
/// stay, nothing is transcribed again, and a Mac polish that is itself turns is flattened too.
final class FlattenToMonologueTests: XCTestCase {

    @MainActor
    private func saver(_ repo: NotesRepository) -> MemoSaver {
        MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "never used"),
                  wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                      .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
                  metadataProvider: MockMetadataService())
    }

    @MainActor
    func testFlattenKeepsTheWordsAndDropsTheTurns() {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(title: "T",
                        transcript: "**Tiuri Hartog:** So the stall is Saturday.\n\n**Speaker 2:** Nine is early, i think.",
                        significance: 0.5)
        memo.pendingDiarizationTarget = 0
        repo.insert(memo)

        XCTAssertTrue(saver(repo).flattenToMonologue(id: memo.id))

        XCTAssertEqual(memo.transcript, "So the stall is Saturday.\n\nNine is early, i think.",
                       "the words stay, with the user's fix; no re-transcribe")
        XCTAssertFalse(SpeakerTranscript.isAttributed(memo.transcript))
        XCTAssertTrue(memo.transcriptUserEdited, "a deliberate edit: trusted, so the Mac never re-transcribes it")
        XCTAssertNil(memo.pendingDiarizationTarget, "no split is left waiting to be re-run at launch")
    }

    @MainActor
    func testFlattenAlsoFlattensAMacPolishThatIsTurns() throws {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(title: "T", transcript: "**A:** one\n\n**B:** two", significance: 0.5)
        repo.insert(memo)
        let enh = MemoEnhancement(memoID: memo.id, copyedit: "**A:** one\n\n**B:** two", title: "T", summary: "S")
        repo.context.insert(enh)
        try repo.context.save()

        XCTAssertTrue(saver(repo).flattenToMonologue(id: memo.id))

        XCTAssertEqual(enh.copyedit, "one\n\ntwo",
                       "otherwise the note keeps drawing the Mac's turns over the flat transcript")
        XCTAssertEqual(enh.enhancedByDeviceID, DeviceID.current(), "stamped as a phone edit so the Mac adopts it")
    }

    @MainActor
    func testFlattenOnAPlainNoteIsANoOp() {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(title: "T", transcript: "just one voice talking", significance: 0.5)
        repo.insert(memo)
        XCTAssertFalse(saver(repo).flattenToMonologue(id: memo.id))
        XCTAssertEqual(memo.transcript, "just one voice talking")
        XCTAssertFalse(memo.transcriptUserEdited)
    }

    func testTheWordsBothAppsShare() {
        XCTAssertEqual(SplitSpeakersCopy.oneVoice, "Only one voice found. Nothing was split.")
        XCTAssertEqual(SplitSpeakersCopy.mergeHint, "Wrong split? Move just this line to another speaker.")
        XCTAssertTrue(SplitSpeakersCopy.howManyMessage.contains("Auto finds the number itself"))
        XCTAssertTrue(SplitSpeakersCopy.howManyMessage.contains("Edits you made to this transcript are replaced"))
        XCTAssertEqual(SplitSpeakersCopy.flattenBodyPhone,
                       "Speaker names come off. The words stay as they are, with your fixes. Nothing is transcribed again.")
    }
}
