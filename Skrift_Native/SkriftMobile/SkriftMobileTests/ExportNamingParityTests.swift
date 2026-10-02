import XCTest
import SwiftData
@testable import SkriftMobile

/// Q153 (C25, C64, C165), the iPad's half: corpus note `045-voice-en-with-mac-polish`
/// re-timed to 23:30 in Los Angeles (already tomorrow in UTC) publishes through
/// `ObsidianPublisher` / `MemoExporter` as `Saturday workshop debrief.md` with
/// `date: 2026-08-19` — the same two literals the Mac's `ExportNamingParityTests` asserts
/// through `VaultExporter`. Before the fix the iPad named it from the transcript's first line.
final class ExportNamingParityTests: XCTestCase {

    private static let noteID = UUID(uuidString: "3B6912FA-AAD7-5203-96C4-D7D2B1050AAA")!
    private static let expectedStem = "Saturday workshop debrief"
    private static let expectedDay = "2026-08-19"
    private static let zone = TimeZone(identifier: "America/Los_Angeles")!

    private var savedZone: TimeZone!

    override func setUp() {
        super.setUp()
        savedZone = NSTimeZone.default
        NSTimeZone.default = Self.zone
    }

    override func tearDown() {
        NSTimeZone.default = savedZone
        super.tearDown()
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("q153-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private static var lateEvening: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 23, minute: 30))!
    }

    @MainActor
    func testOneNoteGetsTheMacsStemAndLocalDay() throws {
        let root = CorpusSeedTests.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated — run test-fixtures/corpus/generate.py")
        let repo = NotesRepository(inMemory: true)
        try CorpusSeed.seed(from: root, into: repo.context, recordingsDirectory: try tempDir())
        let id = Self.noteID
        let memo = try XCTUnwrap(try repo.context.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })).first)
        memo.recordedAt = Self.lateEvening
        let enh = try repo.context.fetch(FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == id })).first
        XCTAssertEqual(enh?.title, "Saturday workshop debrief")

        // MemoExporter: frontmatter title + date:
        let md = MemoExporter.markdown(for: memo, people: [], enhancement: enh)
        XCTAssertTrue(md.contains("\ndate: \(Self.expectedDay)\n"), md)
        XCTAssertTrue(md.contains("title: \"\(Self.expectedStem)\""), md)
        XCTAssertEqual(MemoExporter.exportTitle(for: memo, people: [], enhancement: enh), Self.expectedStem)

        // ObsidianPublisher: the file it writes.
        let vault = try tempDir()
        let publisher = ObsidianPublisher(
            vaultProvider: { vault },
            manageScope: false,
            author: "",
            peopleProvider: { [] },
            enhancementProvider: { $0 == id ? enh : nil },
            ledgerOverride: ExportLedger(fileURL: vault.appendingPathComponent("ledger.json")))
        let outcome = try publisher.publish(memo)
        guard case .written(let rel) = outcome else { return XCTFail("expected a write, got \(outcome)") }
        XCTAssertEqual(((rel as NSString).lastPathComponent as NSString).deletingPathExtension, Self.expectedStem,
                       "the iPad writes the file the Mac would")
    }
}
