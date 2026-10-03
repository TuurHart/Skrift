import XCTest
@testable import SkriftMobile

/// The PORTFOLIO export profile, proven END TO END on real files in a temp folder — the shape
/// of an entry is derived data, and derived data that is only reasoned about is derived data
/// nobody has checked (the ePub-alignment lesson, 2026-07-23).
///
/// What a portfolio entry must be, from the portfolio brief:
///
///     _ideas/2026-08/
///       2026-08-26-142312.md      frontmatter + body
///       2026-08-26-142312.jpg     BESIDE the note, same basename
///       2026-08-26-142312.m4a
///
/// Flat, timestamp-named, media beside the note, and no `![[wiki embed]]` anywhere — a
/// vault-relative embed is precisely what stops a note being readable outside its vault.
@MainActor
final class PortfolioExportTests: XCTestCase {

    private var sandbox: URL!
    private var portfolioRoot: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("skrift-portfolio-\(UUID().uuidString)")
        portfolioRoot = sandbox.appendingPathComponent("portfolio")
        try FileManager.default.createDirectory(at: portfolioRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: sandbox) }

    /// 26 Aug 2026, 14:23:12 local — the brief's own example timestamp.
    private func captureDate() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 26; c.hour = 14; c.minute = 23; c.second = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: c)!
    }

    private func publisher(ledger: ExportLedger) -> ObsidianPublisher {
        ObsidianPublisher(
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
            ledgerOverride: ledger)
    }

    private func ideaMemo() -> Memo {
        let m = Memo(audioFilename: "memo.m4a", recordedAt: captureDate(),
                     transcript: "A bench made of an oak slab.", significance: 0.5)
        m.destination = .idea
        return m
    }

    // MARK: - The shape of an entry

    func testPortfolioEntryIsFlatAndTimestampNamed() throws {
        let ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("l.json"))
        let memo = ideaMemo()

        let outcome = try publisher(ledger: ledger).publish(memo)
        guard case .written(let rel) = outcome else {
            return XCTFail("expected a write, got \(outcome)")
        }

        XCTAssertEqual(rel, "the-bench-outside-cafe-garrett.md",
                       "named, not dated, and FLAT — his 148 items are `Lamps/<name>/item.md`")
        let file = portfolioRoot.appendingPathComponent("_ideas").appendingPathComponent(rel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path)

        // The Obsidian house — Skrift/, Images/, Recordings/ — must NOT appear in the portfolio.
        for unwanted in ["Skrift", "_ideas/Skrift", "_ideas/Images", "_ideas/Recordings"] {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: portfolioRoot.appendingPathComponent(unwanted).path),
                "the portfolio is not a vault — found \(unwanted)")
        }
    }

    func testPortfolioNoteCarriesNoWikiEmbedAndNoSensorFrontmatter() throws {
        let ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("l.json"))
        let memo = ideaMemo()
        _ = try publisher(ledger: ledger).publish(memo)

        let file = portfolioRoot.appendingPathComponent("_ideas/the-bench-outside-cafe-garrett.md")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(text.contains("![["), "a vault-relative embed does not travel")
        for key in ["weather:", "pressure:", "dayPeriod:", "daylight:", "steps:", "significance:"] {
            XCTAssertFalse(text.contains(key), "\(key) is personal-notes furniture")
        }
        // …and the keys a portfolio entry DOES need, including the stamp that stops a filed
        // note from being written again.
        for key in ["title:", "date:", "summary:", "tags:", VaultStamp.idKey] {
            XCTAssertTrue(text.contains(key), "missing \(key)")
        }

        // The portfolio OWNS these two keys with other meanings — Skrift must not squat on them.
        // `type:` is that repo's category (`type: lamps`, on 100+ items, from his own folder
        // names) and `source:` is an item's provenance path. Verified against the real repo
        // 2026-08-27; `type: idea` shipped for a day and was pulled.
        XCTAssertFalse(text.contains("type:"), "type: belongs to the portfolio's categories")
        XCTAssertFalse(text.contains("source:"), "source: belongs to the portfolio's provenance")
        XCTAssertTrue(text.contains("capture: Voice-memo"), "…Skrift says capture: instead")

        // `author:` is dropped: everything in the portfolio is his by that portfolio's rule, so the
        // key could only ever hold one value. `voice:` carries what varies — and it is the
        // portfolio's own key with the portfolio's own three values.
        XCTAssertFalse(text.contains("author:"))
        XCTAssertTrue(text.contains("voice: cleaned"), "the copy-edit is what was exported")
    }

    /// `needs:` is the portfolio's punch list. An INSPIRATION is someone else's work by
    /// definition, so one with no maker is always incomplete. Project and Idea are HIS — raising
    /// credit on them would be a false need, and a punch list of false needs is not one.
    func testOnlyInspirationAsksForCredit() throws {
        for (destination, folder, wantsCredit) in [
            (NoteDestination.inspiration, "_inspiration", true),
            (NoteDestination.idea, "_ideas", false),
            (NoteDestination.project, "_projects", false),
        ] {
            let ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("\(folder).json"))
            let memo = ideaMemo()
            memo.destination = destination
            _ = try publisher(ledger: ledger).publish(memo)

            let text = try String(
                contentsOf: portfolioRoot.appendingPathComponent(
                    "\(folder)/the-bench-outside-cafe-garrett.md"), encoding: .utf8)
            XCTAssertEqual(text.contains("- credit"), wantsCredit,
                           "\(destination.label) credit need should be \(wantsCredit)")
        }
    }

    /// The case Tuur says happens most: someone else's object gives HIM an idea. It is filed
    /// Idea because the intent is his, and it still owes a credit because the object is not —
    /// so the `#inspiration` TAG has to raise the need the folder would have.
    func testAnIdeaTaggedInspirationStillAsksForCredit() throws {
        let ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("tagged.json"))
        let memo = ideaMemo()               // destination .idea
        memo.tags = ["lisbon", "inspiration"]
        _ = try publisher(ledger: ledger).publish(memo)

        let text = try String(
            contentsOf: portfolioRoot.appendingPathComponent("_ideas/the-bench-outside-cafe-garrett.md"),
            encoding: .utf8)
        XCTAssertTrue(text.contains("- credit"),
                      "the object is someone else's even though the idea is his")
        XCTAssertTrue(text.contains("  - inspiration"), "…and the tag itself is kept")
    }

    /// `voice:` says how the words got there. A typed note was never spoken.
    func testVoiceIsWrittenForATypedNote() throws {
        let ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("typed.json"))
        let memo = ideaMemo()
        memo.audioFilename = ""          // typed — no recording behind it
        _ = try publisher(ledger: ledger).publish(memo)

        let text = try String(
            contentsOf: portfolioRoot.appendingPathComponent("_ideas/the-bench-outside-cafe-garrett.md"),
            encoding: .utf8)
        XCTAssertTrue(text.contains("voice: written"), text)
    }

    /// …and a vault note gets no `type:`. `personal` is the default and thousands of existing
    /// notes do not need a key repeating it.
    func testPersonalNoteHasNoTypeKey() throws {
        let vault = sandbox.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("l3.json"))
        let memo = ideaMemo()
        memo.destination = .personal
        memo.title = "A vault note"
        _ = try publisher(ledger: ledger).publish(memo)

        let text = try String(contentsOf: vault.appendingPathComponent("Skrift/A vault note.md"),
                              encoding: .utf8)
        XCTAssertFalse(text.contains("type:"))
        XCTAssertFalse(text.contains("voice:"), "voice: is the portfolio's key, not the vault's")
        XCTAssertTrue(text.contains("author:"), "the vault keeps its author")
        XCTAssertTrue(text.contains("source: Voice-memo"), "…and its source:")
        XCTAssertTrue(text.contains("location:"), "location stays in BOTH profiles")
    }

    /// The vault profile must be untouched by all of this: same home folder, same title-based
    /// name, same subfolders. Destinations changed nothing for a Personal note.
    func testPersonalNoteStillWritesTheObsidianLayout() throws {
        let vault = sandbox.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("l2.json"))

        let memo = ideaMemo()
        memo.destination = .personal
        // The vault name comes from the NOTE's own title (`MemoExporter.exportTitle` —
        // phone-set title, else the transcript's first line), not from the model's suggested
        // one. Set it explicitly so this asserts the naming RULE rather than that fallback.
        memo.title = "The bench outside Café Garrett"

        let outcome = try publisher(ledger: ledger).publish(memo)
        guard case .written(let rel) = outcome else {
            return XCTFail("expected a write, got \(outcome)")
        }
        XCTAssertEqual(rel, "The bench outside Café Garrett.md",
                       "named by title, at the root of the Skrift home — unchanged")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: vault.appendingPathComponent("Skrift").appendingPathComponent(rel).path))
    }

    // MARK: - The name

    /// Tuur, 2026-08-28: "I don't think we need timeframes, just the name is fine — that's how
    /// the rest of my portfolio works, and all the dates are just in the metadata." His 148
    /// items are named `voronoi-decimation-lamp`, `engagement-ring`. So: no date in the name.
    func testTheNameIsTheNameNotTheDate() {
        let d = captureDate()
        XCTAssertEqual(ExportProfile.entryStem(for: d, title: "The bench outside Café Garrett"),
                       "the-bench-outside-cafe-garrett",
                       "accents fold, so the filename survives being copied anywhere")
    }

    /// The one case with no name: a thing he photographed and said nothing about. Something has
    /// to identify that file, and WHEN it arrived is the only fact there is — so the timestamp
    /// survives as the fallback and only as the fallback.
    func testAWordlessCaptureFallsBackToTheTimestamp() {
        let d = captureDate()
        XCTAssertEqual(ExportProfile.entryStem(for: d, title: nil), "2026-08-26-142312")
        XCTAssertEqual(ExportProfile.entryStem(for: d, title: "   "), "2026-08-26-142312")
        XCTAssertEqual(ExportProfile.entryStem(for: d, title: "…!?"), "2026-08-26-142312")
    }

    /// Two entries called the same thing in one folder — now a real case, since the date no
    /// longer separates them. The suffix is deterministic (same note → same suffix, forever)
    /// and slug-shaped, because these filenames ARE slugs now.
    func testASecondEntryWithTheSameNameGetsASlugSuffix() {
        let id = UUID(uuidString: "9E24A49F-2460-4E14-9D5A-40E6384B4EDE")!
        XCTAssertEqual(VaultName.disambiguated("a-bench", id: id, profile: .portfolio),
                       "a-bench-9e24a49f")
        XCTAssertEqual(VaultName.disambiguated("A bench", id: id, profile: .obsidian),
                       "A bench 9E24A49F", "the vault's own shape is unchanged")
    }

    /// The WHOLE name. A 42-character cap shipped for an hour and cut a real title down to
    /// `testing-the-functionality-of-the` — Tuur: "full name is cut off". The cap is 120 now,
    /// the same rule the vault uses, chosen so it never bites a title he'd actually write.
    func testARealTitleIsNeverCut() {
        XCTAssertEqual(ExportProfile.slug("Testing the functionality of the recording device."),
                       "testing-the-functionality-of-the-recording-device")
        XCTAssertEqual(ExportProfile.slug("Testing idea and inspiration tagging for credit lines."),
                       "testing-idea-and-inspiration-tagging-for-credit-lines")
    }

    /// The cap still exists so a pasted monster can't become a 500-character filename, and it
    /// cuts at a word boundary when it does fire.
    func testAPastedMonsterIsCutAtAWordBoundary() {
        let long = String(repeating: "seventeen letters ", count: 20)
        let slug = ExportProfile.slug(long)!
        XCTAssertLessThanOrEqual(slug.count, 120)
        XCTAssertFalse(slug.hasSuffix("-"), "no trailing hyphen")
        XCTAssertTrue(slug.hasSuffix("seventeen") || slug.hasSuffix("letters"),
                      "cut between words, not mid-word — got \(slug)")
    }

    /// No month folder either: an entry sits directly in its destination folder.
    func testEntriesAreFlatInTheirDestinationFolder() throws {
        let ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("flat.json"))
        _ = try publisher(ledger: ledger).publish(ideaMemo())
        let byMonth = portfolioRoot.appendingPathComponent("_ideas/2026-08")
        XCTAssertFalse(FileManager.default.fileExists(atPath: byMonth.path),
                       "no date folders — Tuur, 2026-08-28: we dont need the month either")
    }

    // MARK: - Body links

    func testPortfolioKeepsPeopleLinksAndPlainifiesEverythingElse() {
        let jack = Person(canonical: "[[Jack]]", aliases: [], short: nil,
                          lastModifiedAt: "2026-01-01T00:00:00Z")
        let body = "Saw [[Jack]] at [[Hotel Du Vin]] and it gave me an idea."

        let kept = Compiler.plainifyNonPeopleLinks(in: body, knownPeople: [jack])
        XCTAssertEqual(kept, "Saw [[Jack]] at Hotel Du Vin and it gave me an idea.",
                       "credit the person, drop the place — Tuur's call, 2026-08-26")
    }

    func testPlainifyLeavesImageEmbedsAlone() {
        let body = "![[shot.jpg]] and [[Somewhere]]"
        XCTAssertEqual(Compiler.plainifyNonPeopleLinks(in: body, knownPeople: []),
                       "![[shot.jpg]] and Somewhere",
                       "an embed is not a link")
    }

    func testPlainifyKeepsTheSpokenFormOfAnAliasLink() {
        XCTAssertEqual(
            Compiler.plainifyNonPeopleLinks(in: "at [[Hotel Du Vin|the hotel]] again", knownPeople: []),
            "at the hotel again",
            "the reader saw the spoken form — that is the text that stays")
    }
}
