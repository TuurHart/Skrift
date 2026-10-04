import XCTest
import Foundation
@testable import SkriftMobile

/// Q293 (C25 amended by D176), phone half: `MemoSaver.importAudio` keeps a REAL file name in the
/// memo's metadata and drops a generic one, and the list/header title shows the name until the
/// note has words. Same rule as the Mac's `ImportFileNameTitleTests` (one `NoteTitle`).
@MainActor
final class ImportFileNameTitlePhoneTests: XCTestCase {

    private var dir: URL!
    private var imported: [URL] = []

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("q293-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        for url in imported { try? FileManager.default.removeItem(at: url) }
        imported = []
        super.tearDown()
    }

    private func saver(_ repo: NotesRepository) -> MemoSaver {
        MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "unused"),
                  wordTimings: WordTimingsStore(directory: dir.appendingPathComponent("wt", isDirectory: true)),
                  metadataProvider: MockMetadataService())
    }

    private func file(_ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: url)
        return url
    }

    func testMemoAdapterShowsNameUntilWords() {
        let m = Memo.make(audioFilename: "memo_x.m4a", metadata: MemoMetadata(importFileName: "Interview with Jan"))
        XCTAssertEqual(m.ladderTitle(), "Interview with Jan")
        XCTAssertEqual(m.displayTitle(enhancedTitle: nil), "Interview with Jan")
        XCTAssertNil(m.ladderGhost(), "a file name is not a derived title: the header keeps 'Add a title'")
        m.transcript = "So we met at noon"
        XCTAssertEqual(m.ladderTitle(), "So we met at noon")
        XCTAssertEqual(m.ladderTitle(suggestedTitle: "Polished"), "Polished")
    }

    func testGenericNameFallsBackToVoiceNote() {
        let m = Memo.make(audioFilename: "memo_x.m4a", metadata: MemoMetadata(importFileName: "New Recording 22"))
        XCTAssertEqual(m.ladderTitle(), "Voice note")
        XCTAssertEqual(Memo.make(audioFilename: "memo_x.m4a").ladderTitle(), "Voice note")
    }

    func testImportAudioStoresARealNameAndDropsAGenericOne() throws {
        let repo = NotesRepository(inMemory: true)
        let real = try XCTUnwrap(saver(repo).importAudio(from: try file("Interview with Jan.wav")))
        let generic = try XCTUnwrap(saver(repo).importAudio(from: try file("New Recording 22.wav")))
        for id in [real, generic] {
            if let m = repo.memo(id: id) {
                imported.append(AppPaths.recordingsDirectory.appendingPathComponent(m.audioFilename))
            }
        }
        XCTAssertEqual(repo.memo(id: real)?.metadata?.importFileName, "Interview with Jan")
        XCTAssertEqual(repo.memo(id: real)?.ladderTitle(), "Interview with Jan")
        XCTAssertNil(repo.memo(id: generic)?.metadata?.importFileName)
        XCTAssertEqual(repo.memo(id: generic)?.ladderTitle(), "Voice note")
    }
}
