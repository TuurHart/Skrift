import XCTest
@testable import SkriftMobile

/// Q338 / D189: a note's destination is Personal or Portfolio. idea / inspiration / project are
/// ordinary tags (one-tap presets while Portfolio is picked). Proven on real files in a temp
/// folder: the export path `<root>/_inbox/<slug>.md`, media beside it, preset tags in `tags:`,
/// the credit rule keyed on the inspiration tag, no `summary:` in the portfolio profile, and the
/// safe decode of the stored values from the four-destination era.
@MainActor
final class TwoDestinationsTests: XCTestCase {

    private var sandbox: URL!
    private var portfolioRoot: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("skrift-two-dest-\(UUID().uuidString)")
        portfolioRoot = sandbox.appendingPathComponent("portfolio")
        try FileManager.default.createDirectory(at: portfolioRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: sandbox) }

    // MARK: - The model

    func testTwoDestinationsInThePrivateThenPortfolioOrder() {
        XCTAssertEqual(NoteDestination.allCases.map(\.rawValue), ["personal", "portfolio"])
        XCTAssertEqual(NoteDestination.allCases.map(\.label), ["Personal", "Portfolio"])
        XCTAssertFalse(NoteDestination.personal.isPortfolio)
        XCTAssertTrue(NoteDestination.portfolio.isPortfolio)
        XCTAssertNil(NoteDestination.personal.portfolioFolder)
        XCTAssertEqual(NoteDestination.portfolio.portfolioFolder, "_inbox")
    }

    func testPresetsAreIdeaInspirationProject() {
        XCTAssertEqual(PortfolioTagPresets.all, ["idea", "inspiration", "project"])
    }

    // MARK: - Old stored values

    func testOldStoredValuesDecodeAsPortfolioPlusThatTag() {
        for old in ["idea", "inspiration", "project"] {
            let d = NoteDestination.decode(old)
            XCTAssertEqual(d.destination, .portfolio, old)
            XCTAssertEqual(d.legacyTag, old, old)
        }
        XCTAssertEqual(NoteDestination.decode("personal").destination, .personal)
        XCTAssertNil(NoteDestination.decode("personal").legacyTag)
        XCTAssertEqual(NoteDestination.decode("portfolio").destination, .portfolio)
        XCTAssertNil(NoteDestination.decode("portfolio").legacyTag)
    }

    func testAnUnknownValueReadsAsPersonalNeverPortfolio() {
        for junk in ["", "made", "Idea", "_ideas", "garbage"] {
            XCTAssertEqual(NoteDestination.decode(junk).destination, .personal, junk)
            XCTAssertNil(NoteDestination.decode(junk).legacyTag, junk)
        }
    }

    func testAMemoStoredAsIdeaReadsPortfolioAndAdoptsTheTagOnce() {
        let m = Memo(audioFilename: "", recordedAt: Date(), transcript: "x", significance: 0.5)
        m.destinationRaw = "inspiration"
        m.tags = ["lisbon"]
        XCTAssertEqual(m.destination, .portfolio)

        XCTAssertTrue(m.adoptLegacyDestination())
        XCTAssertEqual(m.destinationRaw, "portfolio")
        XCTAssertEqual(m.tags, ["lisbon", "inspiration"])

        XCTAssertFalse(m.adoptLegacyDestination(), "idempotent: nothing left to adopt")
        XCTAssertEqual(m.tags, ["lisbon", "inspiration"])
    }

    func testAdoptingDoesNotDuplicateATagTheNoteAlreadyHas() {
        let m = Memo(audioFilename: "", recordedAt: Date(), transcript: "x", significance: 0.5)
        m.destinationRaw = "idea"
        m.tags = ["Idea"]
        XCTAssertTrue(m.adoptLegacyDestination())
        XCTAssertEqual(m.tags, ["Idea"])
    }

    func testAPersonalMemoIsNeverTouchedByAdopt() {
        let m = Memo(audioFilename: "", recordedAt: Date(), transcript: "x", significance: 0.5)
        m.tags = ["idea"]
        XCTAssertFalse(m.adoptLegacyDestination())
        XCTAssertEqual(m.destination, .personal)
    }

    // MARK: - The export

    private func captureDate() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 11; c.hour = 9; c.minute = 5; c.second = 3
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: c)!
    }

    private func publisher(movie: URL? = nil) -> ObsidianPublisher {
        var p = ObsidianPublisher(
            vaultProvider: { self.sandbox.appendingPathComponent("vault") },
            portfolioFolderProvider: { d in
                d.portfolioFolder.map { self.portfolioRoot.appendingPathComponent($0, isDirectory: true) }
            },
            portfolioScopeRoot: { self.portfolioRoot },
            manageScope: false,
            author: "Tiuri Hartog",
            peopleProvider: { [] },
            enhancementProvider: { id in
                MemoEnhancement(memoID: id, copyedit: "A bench made of an oak slab.",
                                title: "The bench outside Café Garrett",
                                summary: "A bench worth copying.")
            },
            ledgerOverride: ExportLedger(fileURL: sandbox.appendingPathComponent("l-\(UUID().uuidString).json")))
        p.audioProvider = { _ in Data("AUDIO".utf8) }
        p.movieProvider = { _ in movie }
        return p
    }

    private func portfolioMemo(tags: [String]) -> Memo {
        let m = Memo(audioFilename: "memo.m4a", recordedAt: captureDate(),
                     transcript: "A bench made of an oak slab.", significance: 0.5)
        m.destination = .portfolio
        m.tags = tags
        return m
    }

    private func inbox(_ name: String) -> URL {
        portfolioRoot.appendingPathComponent("_inbox").appendingPathComponent(name)
    }

    func testPortfolioNoteLandsInInboxWithMediaBesideAndPresetTagsInFrontmatter() throws {
        let movie = sandbox.appendingPathComponent("clip.mov")
        try Data("MOVIE".utf8).write(to: movie)
        let memo = portfolioMemo(tags: ["idea", "inspiration", "lisbon"])

        let outcome = try publisher(movie: movie).publish(memo)
        guard case .written(let rel) = outcome else { return XCTFail("expected a write, got \(outcome)") }

        XCTAssertEqual(rel, "the-bench-outside-cafe-garrett.md")
        let note = inbox(rel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.path), note.path)
        for beside in ["the-bench-outside-cafe-garrett.m4a", "the-bench-outside-cafe-garrett.mov"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: inbox(beside).path), "\(beside) beside the note")
        }
        for gone in ["_ideas", "_inspiration", "_projects", "Skrift"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: portfolioRoot.appendingPathComponent(gone).path), gone)
        }

        let text = try String(contentsOf: note, encoding: .utf8)
        XCTAssertTrue(text.contains("tags:\n  - idea\n  - inspiration\n  - lisbon"), text)
        XCTAssertTrue(text.contains("capture: Voice-memo"), text)
        XCTAssertFalse(text.contains("author:"), text)
    }

    func testPortfolioProfileWritesNoSummaryButThePersonalProfileKeepsIt() throws {
        _ = try publisher().publish(portfolioMemo(tags: ["idea"]))
        let portfolio = try String(contentsOf: inbox("the-bench-outside-cafe-garrett.md"), encoding: .utf8)
        XCTAssertFalse(portfolio.contains("summary:"), "the archive dropped summary: (2026-08-26)")

        try FileManager.default.createDirectory(at: sandbox.appendingPathComponent("vault"), withIntermediateDirectories: true)
        let personal = portfolioMemo(tags: [])
        personal.destination = .personal
        personal.title = "A vault note"
        _ = try publisher().publish(personal)
        let vault = try String(contentsOf: sandbox.appendingPathComponent("vault/Skrift/A vault note.md"), encoding: .utf8)
        XCTAssertTrue(vault.contains("summary:"), "the vault profile is unchanged")
    }

    func testCreditIsNeededOnlyWhenTheInspirationTagIsThere() throws {
        for (tags, wants) in [(["inspiration"], true), (["Inspiration", "idea"], true),
                              (["idea"], false), (["project"], false), ([], false)] as [([String], Bool)] {
            let p = publisher()
            let memo = portfolioMemo(tags: tags)
            memo.id = UUID()
            _ = try p.publish(memo)
            let text = try String(contentsOf: inbox("the-bench-outside-cafe-garrett.md"), encoding: .utf8)
            XCTAssertEqual(text.contains("  - credit"), wants, "tags \(tags)")
            try? FileManager.default.removeItem(at: portfolioRoot.appendingPathComponent("_inbox"))
        }
    }

    func testTypingIdeaOnAPersonalNoteIsJustATag() throws {
        try FileManager.default.createDirectory(at: sandbox.appendingPathComponent("vault"), withIntermediateDirectories: true)
        let memo = portfolioMemo(tags: ["idea"])
        memo.destination = .personal
        memo.title = "Plain"
        _ = try publisher().publish(memo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: portfolioRoot.appendingPathComponent("_inbox").path),
                       "a tag never routes a note out of Personal")
        let text = try String(contentsOf: sandbox.appendingPathComponent("vault/Skrift/Plain.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("  - idea"))
    }

    func testAnOldStoredIdeaStillExportsToInboxWithItsTag() throws {
        let memo = portfolioMemo(tags: ["lisbon"])
        memo.destinationRaw = "idea"          // never opened since the four-destination era
        _ = try publisher().publish(memo)
        let text = try String(contentsOf: inbox("the-bench-outside-cafe-garrett.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("tags:\n  - lisbon\n  - idea"), text)
    }
}
