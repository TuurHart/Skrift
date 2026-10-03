import XCTest
import SwiftData

/// Q153 (C25, C64, C165): one note exports to ONE file name and ONE `date:` whichever device
/// writes it. The corpus note `045-voice-en-with-mac-polish` (Mac polish title "Saturday
/// workshop debrief"), re-timed to 23:30 local in a zone where that is already tomorrow in
/// UTC, goes through the iPad's input (`ExportNaming.title(for: Memo, …)`, what
/// `MemoExporter` / `ObsidianPublisher` call) and through the Mac's bridge (phone memo →
/// `MemoCloudIngest` row → `VaultExporter` / `Compiler.compile(file:)`). Before the fix the
/// iPad named it from the transcript's first line and the Mac's `date:` was the UTC day.
/// The phone target's twin class asserts the same two literals through `MemoExporter`.
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

    /// 2026-08-19 23:30 in Los Angeles = 2026-08-20 06:30 UTC.
    private static var lateEvening: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 23, minute: 30))!
    }

    private func seededNote() throws -> (ModelContext, Memo, MemoEnhancement?) {
        let root = CorpusSeedTests.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated — run test-fixtures/corpus/generate.py")
        let cloud = ModelContext(try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
        try CorpusSeed.seed(from: root, into: cloud, recordingsDirectory: makeTempDir())
        let id = Self.noteID
        let memo = try XCTUnwrap(try cloud.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })).first,
                                 "corpus note 045 must exist")
        memo.recordedAt = Self.lateEvening
        let enh = try cloud.fetch(FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == id })).first
        return (cloud, memo, enh)
    }

    func testLocalDayIsTheRecordingsDayNotTheUTCDay() {
        XCTAssertEqual(ExportNaming.deviceZone.identifier, Self.zone.identifier, "precondition: the test zone is active")
        XCTAssertEqual(ExportNaming.localDay(Self.lateEvening), Self.expectedDay)
        XCTAssertEqual(ExportNaming.localDay(iso: ISO8601.string(from: Self.lateEvening)), Self.expectedDay,
                       "the Mac's stored UTC text reads back as the local day")
        XCTAssertEqual(ExportNaming.localDay(iso: "2026-08-20T06:30:00Z"), Self.expectedDay,
                       "no fractional seconds parses too")
        XCTAssertNil(ExportNaming.localDay(iso: "not a date"))
    }

    func testOneNoteGetsOneStemAndOneDateThroughBothBridges() throws {
        let (cloud, memo, enh) = try seededNote()
        XCTAssertEqual(enh?.title, "Saturday workshop debrief", "the corpus note carries a Mac polish title")

        // The iPad's side: the same shared input `MemoExporter.exportTitle` / `dateString` use.
        let ipadTitle = ExportNaming.title(for: memo, enhancement: enh)
        let ipadStem = ExportNaming.stem(title: ipadTitle, filename: memo.audioFilename)
        let ipadDay = ExportNaming.localDay(memo.recordedAt)

        // The Mac's side: the synced memo becomes a row exactly as the reconcile sweep does it.
        let pipeline = ModelContext(try ModelContainer(for: PipelineFile.self,
                                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let id = memo.id
        let assets = try cloud.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id }))
        let row = try XCTUnwrap(try MemoCloudIngest.ingest(memo: memo, assets: assets,
                                                           upload: UploadService(outputDir: makeTempDir()),
                                                           into: pipeline))
        MemoCloudUpdate.apply(memo: memo, enhancement: enh, to: row, people: [], author: "",
                              thisDeviceID: "q153-mac", isFreshRow: true)

        let vault = makeTempDir()
        var settings = AppSettings.default
        settings.noteFolder = vault.path
        let written = try VaultExporter.export(row, settings: settings)
        let macStem = (written.markdownURL.lastPathComponent as NSString).deletingPathExtension
        let macMarkdown = try String(contentsOf: written.markdownURL, encoding: .utf8)

        XCTAssertEqual(ipadStem, Self.expectedStem)
        XCTAssertEqual(macStem, Self.expectedStem, "the Mac writes the file the iPad would")
        XCTAssertEqual(VaultExporter.noteStem(row), ipadStem, "memo-link stems follow the same rule")
        XCTAssertEqual(ipadDay, Self.expectedDay)
        XCTAssertTrue(macMarkdown.contains("\ndate: \(Self.expectedDay)\n"),
                      "the Mac's date: is the recording's local day, not the UTC day:\n\(macMarkdown)")
        XCTAssertTrue(macMarkdown.contains("title: \"\(Self.expectedStem)\""), macMarkdown)
    }

    func testTitleLadderRungs() {
        // C25: user title → suggested → first body line (markers stripped) → share → fallback.
        XCTAssertEqual(ExportNaming.title(userTitle: "Mine", suggestedTitle: "Polished", body: "Body",
                                          shared: nil, isVoice: true), "Mine")
        XCTAssertEqual(ExportNaming.title(userTitle: "  ", suggestedTitle: "Polished", body: "Body",
                                          shared: nil, isVoice: true), "Polished")
        XCTAssertEqual(ExportNaming.title(userTitle: nil, suggestedTitle: "", body: "\n[[img_001]]\n[[Nick Jansen|Nick]] said hi\nmore",
                                          shared: nil, isVoice: true), "Nick said hi")
        XCTAssertEqual(ExportNaming.title(userTitle: nil, suggestedTitle: nil, body: nil,
                                          shared: nil, isVoice: true), "Voice note")
        XCTAssertEqual(ExportNaming.title(userTitle: nil, suggestedTitle: nil, body: "",
                                          shared: nil, isVoice: false), "Note")
        let sc = SharedContent(type: .url, url: "https://x.y", urlTitle: "A page")
        XCTAssertEqual(ExportNaming.title(userTitle: nil, suggestedTitle: nil, body: "",
                                          shared: sc, isVoice: false), "A page")
        // A derived title clips at 120 on a word boundary (C25/C165), no ellipsis.
        let long = Array(repeating: "word", count: 40).joined(separator: " ")
        let cut = ExportNaming.firstLine(long)!
        XCTAssertLessThanOrEqual(cut.count, 120)
        XCTAssertTrue(cut.hasSuffix("word"))
    }
}
