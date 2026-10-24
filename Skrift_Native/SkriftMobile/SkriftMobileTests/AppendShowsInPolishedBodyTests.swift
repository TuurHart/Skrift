import XCTest
import SwiftData
@testable import SkriftMobile

/// Q481 (C152, C223), the phone half: Add recording on a POLISHED note used to write only the raw
/// transcript while every screen shows the polish, so the new words were invisible. They now land
/// in the polished body he sees too, remembered as the block the next pass polishes. Fixture:
/// corpus `voice-en-append-after-polish` (the Mac half is `AppendAfterPolishTests`).
@MainActor
final class AppendShowsInPolishedBodyTests: XCTestCase {

    private struct Expect: Decodable {
        let append: String, appendRaw: String, rawAfterAppend: String, bodyAfterAppend: String
    }
    private struct Wrapper: Decodable { let expect: Expect }

    private let fm = FileManager.default
    private var cleanup: [URL] = []
    private var repo: NotesRepository!   // kept alive: a SwiftData model traps once its context is gone

    override func tearDown() {
        cleanup.forEach { try? fm.removeItem(at: $0) }
        cleanup = []
        repo = nil
        super.tearDown()
    }

    private var dir: URL {
        CorpusSeed.fixtureRoot(file: #filePath).appendingPathComponent("notes/voice-en-append-after-polish")
    }

    /// The corpus note + its Mac polish, its audio at the app's own filename.
    private func seeded() throws -> (Memo, MemoEnhancement, Expect) {
        let data = try Data(contentsOf: dir.appendingPathComponent("note.json"))
        let note = try JSONDecoder().decode(CorpusSeed.Note.self, from: data)
        let expect = try JSONDecoder().decode(Wrapper.self, from: data).expect
        let id = try XCTUnwrap(UUID(uuidString: note.id))
        repo = NotesRepository(inMemory: true)
        let memo = CorpusSeed.makeMemo(note, id: id)
        repo.context.insert(memo)
        let e = try XCTUnwrap(note.enhancement)
        let enh = MemoEnhancement(memoID: id, copyedit: e.copyedit, title: e.title, summary: e.summary,
                                  enhancedByDeviceID: e.enhancedByDeviceID ?? "corpus",
                                  enhancedAt: CorpusSeed.date(e.enhancedAt) ?? Date())
        repo.context.insert(enh)
        try repo.context.save()
        let audio = try XCTUnwrap(memo.audioURL)
        try fm.createDirectory(at: audio.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: audio)
        try fm.copyItem(at: dir.appendingPathComponent("audio.m4a"), to: audio)
        cleanup.append(audio)
        return (memo, enh, expect)
    }

    private func append(_ expect: Expect, to id: UUID) async throws {
        let clip = fm.temporaryDirectory.appendingPathComponent("clip_\(UUID().uuidString).m4a")
        try fm.copyItem(at: dir.appendingPathComponent(expect.append), to: clip)
        cleanup.append(clip)
        let saver = MemoSaver(repository: repo, transcriber: SeededTranscriber(text: expect.appendRaw),
                              wordTimings: WordTimingsStore(directory: fm.temporaryDirectory
                                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
                              metadataProvider: MockMetadataService(), appendRetryDelays: [0])
        await saver.appendRecordingAsync(to: id, tempURL: clip)
    }

    func testAppendedWordsShowInThePolishedBody() async throws {
        let (memo, _, expect) = try seeded()
        try await append(expect, to: memo.id)

        let after = try XCTUnwrap(repo.memo(id: memo.id))
        let enh = try XCTUnwrap(repo.enhancement(forMemo: memo.id))
        XCTAssertEqual(after.transcript, expect.rawAfterAppend, "C223: the raw gains the words after a blank line")
        XCTAssertTrue(after.transcriptUserEdited)
        XCTAssertEqual(enh.copyedit, expect.bodyAfterAppend, "C152: the body he sees gains them too")
        XCTAssertEqual(enh.pendingBlock, expect.appendRaw, "…as the one block the next pass polishes")
        XCTAssertEqual(enh.enhancedByDeviceID, DeviceID.current(), "stamped as this phone's edit, so it syncs")
        // The shown body is the shared working-body rule over the two layers.
        let shown = CompilerInput.workingBody(raw: after.transcript, copyedit: enh.copyedit).text
        XCTAssertTrue(shown.hasSuffix(expect.appendRaw), "the new words are visible:\n\(shown)")
    }

    func testATitleOnlyPolishIsLeftAloneBecauseTheRawShows() async throws {
        let (memo, enh, expect) = try seeded()
        enh.copyedit = ""
        try repo.context.save()
        try await append(expect, to: memo.id)
        XCTAssertEqual(repo.enhancement(forMemo: memo.id)?.copyedit, "")
        XCTAssertEqual(repo.enhancement(forMemo: memo.id)?.pendingBlock, "")
        let shown = CompilerInput.workingBody(raw: repo.memo(id: memo.id)?.transcript, copyedit: "").text
        XCTAssertTrue(shown.hasSuffix(expect.appendRaw))
    }

    func testAConversationsPolishIsNotTouched() async throws {
        let (memo, enh, expect) = try seeded()
        memo.transcript = "**Speaker 1:** So the pricing.\n\n**Speaker 2:** Forty-five euros."
        let before = enh.copyedit
        try repo.context.save()
        try await append(expect, to: memo.id)
        XCTAssertEqual(repo.enhancement(forMemo: memo.id)?.copyedit, before, "conversations show turns, not the polish")
        XCTAssertEqual(repo.enhancement(forMemo: memo.id)?.pendingBlock, "")
    }
}
