import XCTest
import SwiftData

/// Q433 (C5, C253): the export harness, the sibling of the body harness (`BodyDiffHarnessTests`,
/// `BodyV2HarnessTests`). v1's export of EVERY corpus note on BOTH profiles was recorded under
/// `test-fixtures/corpus/goldens/v1-export/<slug>.<vault|portfolio>.md` (+ `_paths.json`, where each
/// file landed). v1 was deleted in Q437 (tag `v1-export`), so the goldens are frozen: the C5
/// reference, never re-recorded. Every registered export engine is classed against them:
///   - identical           engine output == v1's golden;
///   - expected-different  differs AND the row carries an id in `expected-differences-export.json`;
///   - unexplained         differs with no registered id — FAILS (C5);
///   - matched-bug         a registered row an engine leaves equal to v1 — FAILS (C5).
///
/// The path is the Mac's real one: `CorpusSeed` → the reconcile sweep (ingest, polish adoption,
/// name-linking) → `VaultExporter.export` into a temp vault / temp portfolio root. A note the Mac
/// never exports (trashed, unrated, locked) is recorded as the refusal it gets. The model steps of
/// processing (copy-edit, title, summary) cannot run in this bundle, so a row exports with the
/// polish the corpus synced (`enhancement`) or none. Name-linking (the deterministic step) does
/// run — see `nameLink`.
///
/// Also here: C130 (portfolio frontmatter is flat YAML — v1's recorded violations must be EXACTLY
/// the registered rows), C57 (`typed-same-title-a/b` get distinct image files), C64 (a 23:30 note's
/// `date:` is the same day on the phone path and the Mac path), C65 (no exporter snaps the body),
/// C133/C135/C137 on the `dest-*` and `cap-image-no-words` rows.
@MainActor
final class ExportDiffHarnessTests: XCTestCase {

    // MARK: - profiles, outputs, engines

    enum Profile: String, CaseIterable {
        case vault, portfolio
        var destination: NoteDestination { self == .vault ? .personal : .portfolio }
    }

    /// One exported note: the file's text (stamp normalised) and where it landed, relative to the
    /// export root (the vault folder picked / the portfolio root). A refusal has no path.
    struct Output: Equatable {
        var markdown: String
        var path: String?
    }

    @MainActor protocol ExportEngine {
        var name: String { get }
        /// `slug.profile` → output, for every note in `manifest.json`.
        func exports(corpus root: URL, scratch: URL) throws -> [String: Output]
    }

    static let fixedZone = TimeZone(identifier: "Europe/Lisbon")!

    /// Registered engines, each classed against v1's frozen goldens.
    static let engines: [ExportEngine] = [V2Engine()]

    /// The deterministic tail of the Mac's processing (`BatchRunner` step 4, the only part that
    /// needs no model): name-link the working body — the copy-edit when the sweep adopted one,
    /// else the transcript — with the same conversation routing. A row that already carries a
    /// `sanitised` body keeps it. Without this every exported note would read unlinked, which
    /// no processed note on the Mac ever does.
    static func nameLink(_ rows: [PipelineFile], people: [Person]) {
        for pf in rows where pf.sanitised == nil {
            let copyedit = (pf.enhancedCopyedit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let working = copyedit.isEmpty ? (pf.transcript ?? "") : (pf.enhancedCopyedit ?? "")
            guard !working.isEmpty else { continue }
            pf.relinkNames(working: working,
                           isConversation: SpeakerTranscript.isConversation(pf.transcript, source: pf.noteSource),
                           people: people)
        }
    }

    // MARK: - corpus + goldens

    static var corpusRoot: URL { CorpusSeed.fixtureRoot(file: #filePath) }
    static var goldenDir: URL { corpusRoot.appendingPathComponent("goldens/v1-export", isDirectory: true) }
    static var pathsURL: URL { goldenDir.appendingPathComponent("_paths.json") }

    static func manifest(_ root: URL) throws -> CorpusSeed.Manifest {
        try JSONDecoder().decode(CorpusSeed.Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
    }

    static func note(_ root: URL, folder: String) throws -> CorpusSeed.Note {
        try JSONDecoder().decode(CorpusSeed.Note.self, from: Data(contentsOf:
            root.appendingPathComponent("notes").appendingPathComponent(folder).appendingPathComponent("note.json")))
    }

    static func roster(_ root: URL) throws -> [Person] {
        try JSONDecoder().decode([Person].self, from: Data(contentsOf: root.appendingPathComponent("names.json")))
    }

    /// The stamp's two volatile lines (`lastTouched` is the write time, `skriftHash` covers it).
    static func normalised(_ md: String) -> String {
        md.components(separatedBy: "\n").map { line in
            if line.hasPrefix("\(VaultStamp.touchedKey):") { return "\(VaultStamp.touchedKey): <stamp>" }
            if line.hasPrefix("\(VaultStamp.hashKey):") { return "\(VaultStamp.hashKey): <stamp>" }
            return line
        }.joined(separator: "\n")
    }

    /// `slug.profile` → [R or C id]. Keys starting with `_` are documentation.
    static func loadExpectedDifferences() throws -> [String: [String]] {
        let url = corpusRoot.appendingPathComponent("expected-differences-export.json")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        var out: [String: [String]] = [:]
        for (key, value) in obj where !key.hasPrefix("_") { out[key] = (value as? [String]) ?? [] }
        return out
    }

    func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Q433-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private var savedZone: TimeZone?
    override func setUp() {
        super.setUp()
        savedZone = NSTimeZone.default
        NSTimeZone.default = Self.fixedZone   // `date:` (C64) reads the device zone
    }
    override func tearDown() {
        if let savedZone { NSTimeZone.default = savedZone }
        super.tearDown()
    }

    /// v1's recorded outputs: the frozen goldens and where each file landed.
    func v1Goldens() throws -> [String: Output] {
        let root = Self.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated — run test-fixtures/corpus/generate.py")
        let paths = (try? JSONSerialization.jsonObject(with: Data(contentsOf: Self.pathsURL))) as? [String: Any] ?? [:]
        var out: [String: Output] = [:]
        for entry in try Self.manifest(root).notes {
            for profile in Profile.allCases {
                let key = "\(entry.slug).\(profile.rawValue)"
                guard let md = try? String(contentsOf: Self.goldenDir.appendingPathComponent("\(key).md"), encoding: .utf8)
                else { continue }
                out[key] = Output(markdown: md, path: paths[key] as? String)
            }
        }
        return out
    }

    /// The shipping exporter's outputs over the corpus (the sweep + 2 × 116 exports take a few seconds).
    func v2Outputs() throws -> [String: Output] {
        let root = Self.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated — run test-fixtures/corpus/generate.py")
        return try V2Engine().exports(corpus: root, scratch: try scratch())
    }

    // MARK: - C5: classification against v1's golden

    func testEngineClassificationAgainstV1Golden() throws {
        let root = Self.corpusRoot
        let goldens = try v1Goldens()
        let expected = try Self.loadExpectedDifferences()

        var missing: [String] = [], unexplained: [String] = [], matchedBug: [String] = []
        var identical = 0, expectedDifferent = 0
        let keys = try Self.manifest(root).notes.flatMap { e in Profile.allCases.map { "\(e.slug).\($0.rawValue)" } }
        for engine in Self.engines {
            let outputs = try engine.exports(corpus: root, scratch: try scratch())
            for key in keys {
                guard let g = goldens[key] else { missing.append(key); continue }
                let o = outputs[key]
                let ids = expected[key] ?? []
                if o == g {
                    identical += 1
                    if !ids.isEmpty { matchedBug.append("\(key) (\(engine.name)): still equals v1 on registered \(ids)") }
                } else if ids.isEmpty {
                    unexplained.append("\(key) (\(engine.name)): differs from v1 with no registered id")
                } else {
                    expectedDifferent += 1
                }
            }
        }
        print("Export harness: \(keys.count) rows, identical \(identical), expected-different \(expectedDifferent), unexplained \(unexplained.count)")
        XCTAssertTrue(missing.isEmpty, "no golden recorded:\n" + missing.joined(separator: "\n"))
        XCTAssertTrue(unexplained.isEmpty, "unexplained (C5):\n" + unexplained.joined(separator: "\n"))
        XCTAssertTrue(matchedBug.isEmpty, "unfixed pre-registered bugs (C5):\n" + matchedBug.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(keys.count, 200, "every corpus note on both profiles")
    }

    // MARK: - C130: portfolio frontmatter is flat YAML

    static let c130Allowed: Set<String> = ["title", "date", "capture", "voice", "tags", "people", "location",
                                           "credit", "needs", "lastTouched", "skriftID", "skriftHash"]
    static let c130Forbidden: Set<String> = ["type", "source", "author", "summary", "confidence", "status",
                                             "layer", "shortlist", "added", "destination"]

    static func frontmatter(_ md: String) -> [String]? {
        let lines = md.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        return Array(lines[1..<end])
    }

    /// Every C130 breach in one portfolio file, each tagged with the SPEC id it falls under:
    /// R51 for `people:` written inline (`[[A]], [[B]]` — the portfolio parser garbles it),
    /// C130 for the rest. `heGaveTitle` = the note carries his own title.
    static func c130Violations(_ md: String, heGaveTitle: Bool) -> [(id: String, what: String)] {
        guard let fm = frontmatter(md) else { return [("C130", "no frontmatter")] }
        var out: [(String, String)] = []
        var listOpen = false
        for line in fm {
            if line.hasPrefix("  - ") {
                if !listOpen { out.append(("C130", "list item under a key with a value: \(line)")) }
                continue
            }
            if line.hasPrefix(" ") || line.hasPrefix("\t") { out.append(("C130", "nested line: \(line)")); continue }
            guard let colon = line.firstIndex(of: ":") else { out.append(("C130", "not key: value: \(line)")); continue }
            let key = String(line[..<colon])
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            listOpen = value.isEmpty
            if c130Forbidden.contains(key) { out.append(("C130", "forbidden key \(key)")) }
            else if !c130Allowed.contains(key) { out.append(("C130", "unlisted key \(key)")) }
            if key == "title", !heGaveTitle { out.append(("C130", "title written though he gave none")) }
            if value.hasPrefix("[") {
                out.append((key == "people" ? "R51" : "C130", "inline list on \(key): \(value)"))
            } else if !value.hasPrefix("\""), value.contains(": ") {
                out.append(("C130", "`: ` inside a plain value on \(key)"))
            }
        }
        return out
    }

    /// v1's C130 breaches must be EXACTLY the registered rows: an unregistered breach is
    /// unexplained, a registered row v1 already satisfies is a stale registration.
    func testV1PortfolioFrontmatterBreachesAreExactlyTheRegisteredRows() throws {
        let root = Self.corpusRoot
        let v1 = try v1Goldens()
        let expected = try Self.loadExpectedDifferences()
        var unregistered: [String] = [], stale: [String] = []
        var found: [String: Set<String>] = [:]
        for entry in try Self.manifest(root).notes {
            let key = "\(entry.slug).portfolio"
            guard let o = v1[key], o.path != nil else { continue }
            let note = try Self.note(root, folder: entry.folder)
            let gave = !(note.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            let breaches = Self.c130Violations(o.markdown, heGaveTitle: gave)
            let ids = Set(breaches.map(\.id))
            if !ids.isEmpty { found[key] = ids }
            let registered = Set(expected[key] ?? [])
            for b in breaches where !registered.contains(b.id) {
                unregistered.append("\(key): \(b.id) \(b.what)")
            }
            // R51 also covers the body's `![[…]]` (C129), so only a C130 registration can go stale here.
            if registered.contains("C130"), !ids.contains("C130") {
                stale.append("\(key): registered C130 but v1's frontmatter does not breach it")
            }
        }
        if !unregistered.isEmpty {
            // The exact registration lines, for a reviewer (never auto-applied).
            print("C130 v1 breaches: " + found.keys.sorted().map { "\"\($0)\": \(found[$0]!.sorted())" }.joined(separator: ", "))
        }
        XCTAssertTrue(unregistered.isEmpty, "unregistered C130 breaches:\n" + unregistered.joined(separator: "\n"))
        XCTAssertTrue(stale.isEmpty, stale.joined(separator: "\n"))
    }

    // MARK: - dest-* on the two destinations (C129, C133, C135, C137)

    func testPortfolioNotesLandFlatInInbox() throws {
        let v2 = try v2Outputs()
        for slug in ["dest-project", "dest-idea", "dest-inspiration-credit", "cap-image-no-words"] {
            let o = try XCTUnwrap(v2["\(slug).portfolio"], slug)
            let path = try XCTUnwrap(o.path, "\(slug) did not export to the portfolio: \(o.markdown)")
            let parts = path.split(separator: "/")
            XCTAssertEqual(parts.count, 2, "\(slug): flat, no folder per entry — got \(path)")
            XCTAssertEqual(parts.first, "_inbox", "\(slug): every Portfolio note lands in _inbox/ (C133)")
            XCTAssertTrue(path.hasSuffix(".md"), path)
            XCTAssertFalse(o.markdown.contains("![["), "\(slug): portfolio embeds are ![](file), never ![[…]] (C129, R51)")
        }
        // Personal never reaches the portfolio: its vault file is under Skrift/, its own destination.
        let personal = try XCTUnwrap(v2["dest-personal.vault"]?.path)
        XCTAssertTrue(personal.hasPrefix("Skrift/"), personal)
        // The inspiration tag carries the credit need (D189).
        XCTAssertTrue(try XCTUnwrap(v2["dest-inspiration-credit.portfolio"]).markdown.contains("needs:\n  - credit"))
    }

    /// C137: `people:`, a `[[name]]` in the body and `location:` stay in the `dest-idea` export.
    func testDestIdeaKeepsPeopleNamesAndLocation() throws {
        let md = try XCTUnwrap(try v2Outputs()["dest-idea.portfolio"]).markdown
        let fm = try XCTUnwrap(Self.frontmatter(md))
        // R51: `people:` is a block list, so Lotte is on the line after the key.
        let people = try XCTUnwrap(fm.firstIndex { $0.hasPrefix("people:") }, "people: stays\n\(md)")
        XCTAssertTrue(fm[people...].dropFirst().prefix { $0.hasPrefix("  - ") }.contains { $0.contains("Lotte") },
                      "people: carries Lotte\n\(md)")
        XCTAssertTrue(fm.contains { $0.hasPrefix("location:") }, "location: stays\n\(md)")
        let body = md.components(separatedBy: "\n---\n").dropFirst().joined(separator: "\n---\n")
        XCTAssertTrue(body.contains("[[Lotte"), "the body keeps the [[name]]\n\(md)")
    }

    /// C135: a bare picture on the portfolio exports with no invented sentence.
    func testBarePictureExportsWithoutInventedWords() throws {
        let md = try XCTUnwrap(try v2Outputs()["cap-image-no-words.portfolio"]).markdown
        let body = md.components(separatedBy: "\n---\n").dropFirst().joined(separator: "\n---\n")
        // Either embed form counts as the picture (which form is R51's business, not C135's).
        let words = body.replacingOccurrences(of: #"!\[\]\([^)]*\)|!\[\[[^\]]*\]\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(words, "", "only the picture, no words\n\(md)")
    }

    // MARK: - C57: same-titled notes get distinct image files

    /// R6: `typed-same-title-a/b` (both titled "Glaze test", one photo each) exported into ONE
    /// vault / ONE portfolio must embed two different image files, both present on disk.
    ///
    /// A typed note's manifest-only photo has no `[[img_001]]` marker in its text (v1's recorded
    /// goldens show both notes exporting without a picture), so this test gives each body its
    /// marker first: C57 is about how the picture is NAMED, and that is what runs here.
    func testSameTitleNotesGetDistinctImageFiles() throws {
        let root = Self.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path))
        let work = try scratch()
        let cloud = ModelContext(try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
        let pipeline = ModelContext(try ModelContainer(
            for: PipelineFile.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CorpusSeed.seed(from: root, into: cloud, recordingsDirectory: work.appendingPathComponent("phone"))
        V2.sweep(cloud, into: pipeline, outputDir: work.appendingPathComponent("mac"))
        let rows = try pipeline.fetch(FetchDescriptor<PipelineFile>())
        let ids = try Self.manifest(root).notes.filter { $0.slug.hasPrefix("typed-same-title-") }.map(\.id)
        let pair = ids.compactMap { id in rows.first { $0.id == id } }
        XCTAssertEqual(pair.count, 2, "both same-title notes ingest")
        for pf in pair {
            pf.transcript = (pf.transcript ?? "") + "\n\n[[img_001]]"
            pf.sanitised = nil
        }
        for profile in Profile.allCases {
            let exportRoot = work.appendingPathComponent("c57-\(profile.rawValue)", isDirectory: true)
            var settings = AppSettings.default
            settings.noteFolder = profile == .vault ? exportRoot.path : ""
            settings.portfolioRoot = profile == .portfolio ? exportRoot.path : ""
            let session = ExportSession(people: [])
            var embeds: [[String]] = []
            for pf in pair {
                pf.destination = profile.destination
                let r = try VaultExporter.export(pf, settings: settings, session: session)
                let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
                let pattern = profile == .vault ? #"!\[\[([^\]]+)\]\]"# : #"!\[\]\(([^)]+)\)"#
                let re = try NSRegularExpression(pattern: pattern)
                embeds.append(re.matches(in: md, range: NSRange(md.startIndex..., in: md)).map {
                    (md as NSString).substring(with: $0.range(at: 1))
                })
            }
            XCTAssertEqual(embeds.map(\.count), [1, 1], "\(profile): each note embeds its one picture — \(embeds)")
            XCTAssertTrue(Set(embeds[0]).isDisjoint(with: Set(embeds[1])),
                          "\(profile): R6 — same title, shared image file \(embeds)")
            let onDisk = Set((FileManager.default.enumerator(atPath: exportRoot.path)?.allObjects as? [String] ?? [])
                .map { ($0 as NSString).lastPathComponent })
            for name in embeds.joined() {
                XCTAssertTrue(onDisk.contains(name), "\(profile): \(name) was written")
            }
        }
    }

    // MARK: - C64: one `date:` rule on the phone path and the Mac path

    /// A note recorded at 23:30 local. The PHONE path is `ObsidianPublisher.v2Note` (`date:` =
    /// `ExportNaming.localDay(memo.recordedAt)`); the phone test `ExportDateC64Tests` pins the same
    /// literals on the real phone code. The MAC path is the real one: sweep → `PipelineFile`
    /// (recordedAt stored as UTC text) → export v2's compile.
    func testLateNightNoteHasOneDateOnPhoneAndMac() throws {
        let root = Self.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path))
        let cases: [(zone: String, recorded: String, day: String)] = [
            ("Europe/Lisbon", "2026-09-14T23:30:00+01:00", "2026-09-14"),
            ("Asia/Tokyo", "2026-09-14T23:30:00+09:00", "2026-09-14"),
            ("America/Los_Angeles", "2026-09-14T23:30:00-07:00", "2026-09-14"),
        ]
        let entry = try XCTUnwrap(try Self.manifest(root).notes.first { $0.slug == "typed-two-liner" })
        let note = try Self.note(root, folder: entry.folder)
        for c in cases {
            NSTimeZone.default = TimeZone(identifier: c.zone)!
            let recorded = try XCTUnwrap(CorpusSeed.date(c.recorded))
            let cloud = ModelContext(try ModelContainer(
                for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
            let pipeline = ModelContext(try ModelContainer(
                for: PipelineFile.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
            let memo = CorpusSeed.makeMemo(note, id: UUID())
            memo.recordedAt = recorded
            memo.createdAt = recorded
            cloud.insert(memo)
            try cloud.save()
            V2.sweep(cloud, into: pipeline, outputDir: try scratch())
            let pf = try XCTUnwrap(try pipeline.fetch(FetchDescriptor<PipelineFile>()).first, "\(c.zone): not ingested")

            let phoneDay = ExportNaming.localDay(memo.recordedAt)
            let mac = ExportV2Test.markdown(pf, author: "")
            let macDay = mac.components(separatedBy: "\n").first { $0.hasPrefix("date: ") }.map { String($0.dropFirst(6)) }
            XCTAssertEqual(phoneDay, c.day, "\(c.zone): phone date")
            XCTAssertEqual(macDay, c.day, "\(c.zone): Mac date (R15)")
        }
    }

    // MARK: - C65: no exporter snaps the body

    func testNoExporterSnapsTheBody() throws {
        let native = Self.corpusRoot.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Skrift_Native", isDirectory: true)
        let dirs = ["Shared/Export", "SkriftDesktop/Pipeline/Export", "SkriftMobile/Services/Export"]
        var scanned = 0
        for dir in dirs {
            let url = native.appendingPathComponent(dir, isDirectory: true)
            let files = try FileManager.default.contentsOfDirectory(atPath: url.path).filter { $0.hasSuffix(".swift") }
            for f in files {
                let src = try String(contentsOf: url.appendingPathComponent(f), encoding: .utf8)
                scanned += 1
                for needle in ["snappedImageBody", "snapImage", ".snapped("] {
                    XCTAssertFalse(src.contains(needle), "\(dir)/\(f) calls \(needle) — export must not transform the body (C65)")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(scanned, 15, "the exporter sources were found")
    }
}
