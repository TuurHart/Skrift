import XCTest

/// C159 / C283 / D32 (Q489): adding, aliasing or renaming a person re-links every processed note
/// on the Mac once, and the untouched vault files we own are re-exported; a rename rewrites
/// `[[Old]]` → `[[New]]` and `people:` there; an edited file is never touched. Fixtures: corpus
/// `voice-en-bruno-before-roster-1…3` + `rosters/bruno-roster-change.json`; rename golden under
/// `goldens/q489-roster/` (record with SKRIFT_RECORD_ROSTER_GOLDENS=1).
@MainActor
final class RosterReexportTests: XCTestCase {

    private struct Note: Decodable {
        struct Enhancement: Decodable { let copyedit: String }
        let id: String, slug: String, title: String, transcript: String, recordedAt: String
        let enhancement: Enhancement?
    }
    private struct Rosters: Decodable { let before: [Person], added: [Person], renamed: [Person] }

    private static let slugs = (1...3).map { "voice-en-bruno-before-roster-\($0)" }
    private var work: URL!
    private var defaults: UserDefaults!
    private var rosters: Rosters!

    private var corpus: URL { CorpusSeed.fixtureRoot(file: #filePath) }
    private var goldenDir: URL { corpus.appendingPathComponent("goldens/q489-roster") }

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("q489-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "q489-\(UUID().uuidString)")
        rosters = try JSONDecoder().decode(Rosters.self, from: Data(
            contentsOf: corpus.appendingPathComponent("rosters/bruno-roster-change.json")))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    private func settings() -> AppSettings {
        var s = AppSettings.default
        s.noteFolder = work.appendingPathComponent("vault").path
        s.authorName = "Tuur"
        return s
    }

    /// One export against `people` (the app's run reads the live roster the same way).
    private func export(_ pf: PipelineFile, people: [Person]) throws -> VaultExporter.Result {
        let session = ExportSession(people: people)
        defer { session.finish() }
        return try VaultExporter.export(pf, settings: settings(), session: session)
    }

    /// The three notes as processed and exported under the `before` roster.
    private func exportedRows() throws -> [PipelineFile] {
        try Self.slugs.map { slug in
            let note = try JSONDecoder().decode(Note.self, from: Data(
                contentsOf: corpus.appendingPathComponent("notes/\(slug)/note.json")))
            let pf = PipelineFile(id: note.id, filename: "memo_\(note.id).m4a", sourceType: .audio)
            pf.transcript = note.transcript
            pf.transcribeStatus = .done
            pf.enhancedCopyedit = note.enhancement?.copyedit
            pf.enhancedTitle = note.title
            pf.enhanceStatus = .done
            pf.uploadedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: note.recordedAt))
            MemoCloudUpdate.resanitiseAndCompile(pf, people: rosters.before, author: settings().authorName)
            let r = try export(pf, people: rosters.before)
            XCTAssertTrue(r.outcome.isWrittenOrCurrent, slug)
            pf.exportStatus = .done
            pf.exported = r.markdownURL.path
            return pf
        }
    }

    /// What the reconcile wiring does with the changed ids: re-export the rows already in the vault.
    @discardableResult
    private func reexport(_ ids: [String], _ rows: [PipelineFile], people: [Person]) throws -> [String: VaultWriteOutcome] {
        var out: [String: VaultWriteOutcome] = [:]
        for pf in rows where ids.contains(pf.id) && pf.exportStatus == .done {
            out[pf.id] = try export(pf, people: people).outcome
        }
        return out
    }

    private func vaultText(_ pf: PipelineFile) throws -> String {
        try String(contentsOfFile: try XCTUnwrap(pf.exported), encoding: .utf8)
    }

    /// The `people:` frontmatter line's names (`people: [[A]], [[B]]`).
    private func people(_ md: String) -> [String] {
        guard let line = md.components(separatedBy: "\n").first(where: { $0.hasPrefix("people:") }) else { return [] }
        return line.dropFirst("people:".count).components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: - add

    func testAddingAPersonRelinksEveryProcessedNoteOnceAndReexportsThem() throws {
        let rows = try exportedRows()
        XCTAssertTrue(RosterRelink.runIfChanged(rows, people: rosters.before, author: "Tuur", defaults: defaults).isEmpty,
                      "the first run on a Mac only records the roster")
        for pf in rows { XCTAssertFalse(try vaultText(pf).contains("Bruno Costa"), "Bruno is plain before he exists") }

        let changed = RosterRelink.runIfChanged(rows, people: rosters.added, author: "Tuur", defaults: defaults)

        XCTAssertEqual(Set(changed), Set(rows.map(\.id)), "every processed note mentioning him")
        let outcomes = try reexport(changed, rows, people: rosters.added)
        for pf in rows {
            XCTAssertEqual(outcomes[pf.id], .updated(relativePath: try XCTUnwrap(outcomes[pf.id]).relativePath))
            let md = try vaultText(pf)
            XCTAssertTrue(md.contains("[[Bruno Costa"), "linked in the vault: \(md)")
            XCTAssertTrue(people(md).contains { $0.contains("Bruno Costa") }, "people: carries him: \(md)")
        }
        XCTAssertTrue(RosterRelink.runIfChanged(rows, people: rosters.added, author: "Tuur", defaults: defaults).isEmpty,
                      "once: the same roster never re-links again")
    }

    func testAnUnprocessedOrTrashedRowIsLeftAlone() throws {
        let rows = try exportedRows()
        rows[0].deletedAt = Date()
        let raw = PipelineFile(id: UUID().uuidString, filename: "raw.m4a", sourceType: .audio)
        raw.transcript = "Bruno called."
        RosterRelink.runIfChanged(rows + [raw], people: rosters.before, author: "Tuur", defaults: defaults)

        let changed = RosterRelink.runIfChanged(rows + [raw], people: rosters.added, author: "Tuur", defaults: defaults)

        XCTAssertFalse(changed.contains(rows[0].id), "a trashed row is not re-derived")
        XCTAssertFalse(changed.contains(raw.id), "a row never name-linked waits for its first run")
        XCTAssertNil(raw.sanitised)
    }

    // MARK: - rename

    func testARenameRewritesTheLinkAndPeopleAndMatchesTheGolden() throws {
        let rows = try exportedRows()
        RosterRelink.runIfChanged(rows, people: rosters.before, author: "Tuur", defaults: defaults)
        try reexport(RosterRelink.runIfChanged(rows, people: rosters.added, author: "Tuur", defaults: defaults), rows,
                     people: rosters.added)

        let changed = RosterRelink.runIfChanged(rows, people: rosters.renamed, author: "Tuur", defaults: defaults)
        try reexport(changed, rows, people: rosters.renamed)

        XCTAssertEqual(Set(changed), Set(rows.map(\.id)))
        for (slug, pf) in zip(Self.slugs, rows) {
            let md = try vaultText(pf)
            XCTAssertFalse(md.contains("Bruno Costa"), "\(slug): the old name is gone: \(md)")
            XCTAssertTrue(md.contains("[[Bruno Almeida"), "\(slug): \(md)")
            XCTAssertTrue(people(md).contains { $0.contains("Bruno Almeida") }, "\(slug): \(md)")
            try assertGolden(Self.stable(md), slug: slug)
        }
    }

    func testAFileEditedInTheVaultIsNeverTouched() throws {
        let rows = try exportedRows()
        RosterRelink.runIfChanged(rows, people: rosters.before, author: "Tuur", defaults: defaults)
        let edited = rows[1]
        let mine = try vaultText(edited) + "\nHis own line.\n"
        try mine.write(toFile: try XCTUnwrap(edited.exported), atomically: true, encoding: .utf8)

        let outcomes = try reexport(RosterRelink.runIfChanged(rows, people: rosters.added, author: "Tuur",
                                                              defaults: defaults), rows, people: rosters.added)

        XCTAssertEqual(outcomes[edited.id], .backedOffUserEdited(relativePath: try XCTUnwrap(outcomes[edited.id]).relativePath))
        XCTAssertEqual(try vaultText(edited), mine, "his edit stands; the link waits for the return path")
        XCTAssertTrue(try vaultText(rows[0]).contains("[[Bruno Costa"), "the untouched ones still update")
    }

    func testTheFingerprintIgnoresOrderVoiceprintsAndStamps() {
        var shuffled = rosters.added.reversed().map { $0 }
        shuffled[0].lastModifiedAt = "2030-01-01T00:00:00Z"
        XCTAssertEqual(RosterRelink.fingerprint(rosters.added), RosterRelink.fingerprint(shuffled))
        XCTAssertNotEqual(RosterRelink.fingerprint(rosters.added), RosterRelink.fingerprint(rosters.renamed))
        var aliased = rosters.added
        aliased[1].aliases.append("Brunão")
        XCTAssertNotEqual(RosterRelink.fingerprint(rosters.added), RosterRelink.fingerprint(aliased), "an alias is a change")
    }

    // MARK: - golden

    /// The vault file without the stamp's volatile lines (hash, last write time).
    private static func stable(_ md: String) -> String {
        md.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("skriftHash:") && !$0.hasPrefix("lastTouched:") }
            .joined(separator: "\n")
    }

    private func assertGolden(_ text: String, slug: String) throws {
        let url = goldenDir.appendingPathComponent("\(slug).renamed.md")
        if ProcessInfo.processInfo.environment["SKRIFT_RECORD_ROSTER_GOLDENS"] == "1" {
            try FileManager.default.createDirectory(at: goldenDir, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        XCTAssertEqual(text, try String(contentsOf: url, encoding: .utf8), "\(slug): rename golden")
    }
}
