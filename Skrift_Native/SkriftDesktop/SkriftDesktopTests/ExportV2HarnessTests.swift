import XCTest
import SwiftData

extension ExportDiffHarnessTests {
    /// Q434: export v2 over the seeded corpus — the same sweep and rows as `V1Engine`, written by
    /// `VaultExporter.exportV2` (the same writer, compiled by `Shared/ExportV2`). `created:` and
    /// "he gave a title" ride the row, mirrored from the synced memo (Q511).
    struct V2Engine: ExportEngine {
        let name = "v2"

        func exports(corpus root: URL, scratch: URL) throws -> [String: Output] {
            let cloud = ModelContext(try ModelContainer(
                for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
            let pipeline = ModelContext(try ModelContainer(
                for: PipelineFile.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
            try CorpusSeed.seed(from: root, into: cloud, recordingsDirectory: scratch.appendingPathComponent("v2-phone"))
            let roster = try ExportDiffHarnessTests.roster(root)
            MemoCloudReconciler.sweep(from: cloud, into: pipeline, people: roster, author: "Tiuri",
                                      thisDeviceID: "corpus-mac-0001",
                                      upload: UploadService(outputDir: scratch.appendingPathComponent("v2-mac-work")))
            let rows = try pipeline.fetch(FetchDescriptor<PipelineFile>())
            ExportDiffHarnessTests.nameLink(rows, people: roster)
            let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let memos = Dictionary(try cloud.fetch(FetchDescriptor<Memo>()).map { ($0.id.uuidString, $0) },
                                   uniquingKeysWith: { a, _ in a })

            var out: [String: Output] = [:]
            for profile in Profile.allCases {
                let exportRoot = scratch.appendingPathComponent("v2-export-\(profile.rawValue)", isDirectory: true)
                try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
                var settings = AppSettings.default
                settings.authorName = "Tiuri"
                settings.noteFolder = profile == .vault ? exportRoot.path : ""
                settings.portfolioRoot = profile == .portfolio ? exportRoot.path : ""
                let session = ExportSession(people: roster)
                for entry in try ExportDiffHarnessTests.manifest(root).notes {
                    let key = "\(entry.slug).\(profile.rawValue)"
                    let memo = memos[entry.id]
                    guard let pf = byID[entry.id] else {
                        let why = memo?.deletedAt != nil ? "trashed" : (memo.map(NoteConsent.isRated) == false ? "unrated" : "not ingested")
                        out[key] = Output(markdown: "<not exported: \(why) — the Mac never ingests it>\n", path: nil)
                        continue
                    }
                    let kept = pf.destinationRaw
                    pf.destination = profile.destination
                    defer { pf.destinationRaw = kept }
                    do {
                        let r = try VaultExporter.exportV2(pf, settings: settings, session: session)
                        let md = (try? String(contentsOf: r.markdownURL, encoding: .utf8)) ?? ""
                        let rel = String(r.markdownURL.standardizedFileURL.path
                            .dropFirst(exportRoot.standardizedFileURL.path.count + 1))
                        switch r.outcome {
                        case .created, .updated, .unchanged:
                            out[key] = Output(markdown: ExportDiffHarnessTests.normalised(md), path: rel)
                        default:
                            out[key] = Output(markdown: "<not exported: \(r.outcome)>\n", path: nil)
                        }
                    } catch {
                        out[key] = Output(markdown: "<not exported: \(error)>\n", path: nil)
                    }
                }
            }
            return out
        }
    }
}

/// Q434: export v2's own clause checks over the corpus (the C5 classification against v1's
/// golden runs in `ExportDiffHarnessTests` with v2 registered there) and on hand-made notes.
@MainActor
final class ExportV2HarnessTests: XCTestCase {
    typealias H = ExportDiffHarnessTests

    private static var cached: [String: H.Output]?

    private func v2() throws -> [String: H.Output] {
        if let done = Self.cached { return done }
        try XCTSkipUnless(FileManager.default.fileExists(atPath: H.corpusRoot.appendingPathComponent("manifest.json").path))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Q434-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = NSTimeZone.default
        NSTimeZone.default = H.fixedZone
        defer { NSTimeZone.default = saved }
        let out = try H.V2Engine().exports(corpus: H.corpusRoot, scratch: dir)
        Self.cached = out
        return out
    }

    // MARK: - the corpus

    /// C130 / R51: every portfolio file v2 writes is flat YAML with only the allowed keys,
    /// `people:` a block list, and no `![[…]]` anywhere (C129).
    func testEveryPortfolioExportIsFlatAndPortable() throws {
        var bad: [String] = []
        for entry in try H.manifest(H.corpusRoot).notes {
            guard let o = try v2()["\(entry.slug).portfolio"], o.path != nil else { continue }
            let note = try H.note(H.corpusRoot, folder: entry.folder)
            let gave = !(note.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            bad += H.c130Violations(o.markdown, heGaveTitle: gave).map { "\(entry.slug): \($0.id) \($0.what)" }
            if o.markdown.contains("![[") { bad.append("\(entry.slug): a ![[…]] embed on the portfolio (C129)") }
        }
        XCTAssertEqual(bad, [], bad.joined(separator: "\n"))
    }

    func testDestinationsLandWhereD189Says() throws {
        let out = try v2()
        for slug in ["dest-project", "dest-idea", "dest-inspiration-credit", "cap-image-no-words"] {
            let path = try XCTUnwrap(out["\(slug).portfolio"]?.path, slug)
            XCTAssertEqual(path.split(separator: "/").first, "_inbox", "\(slug): \(path)")
            XCTAssertEqual(path.split(separator: "/").count, 2, "\(slug): flat")
        }
        XCTAssertTrue(try XCTUnwrap(out["dest-personal.vault"]?.path).hasPrefix("Skrift/"))
        XCTAssertTrue(try XCTUnwrap(out["dest-inspiration-credit.portfolio"]).markdown.contains("needs:\n  - credit"))
        let idea = try XCTUnwrap(out["dest-idea.portfolio"]).markdown
        XCTAssertTrue(idea.contains("people:\n  - Lotte"), "people: as a block list of plain names (R51)\n\(idea)")
        XCTAssertTrue(idea.contains("location:"), idea)
    }

    /// D12 / R38: every vault export carries `created:` and `duration:`; a recording's duration is
    /// its seconds; a `.file` capture brings its document.
    func testVaultCarriesCreatedDurationAndTheDocument() throws {
        let out = try v2()
        let voice = try XCTUnwrap(out["pic-ocr-text.vault"]).markdown
        XCTAssertTrue(voice.contains("\ncreated: 2026-08-09T20:00:00\n"), voice)
        XCTAssertTrue(voice.contains("\nduration: 5\n"), voice)
        let typed = try XCTUnwrap(out["typed-user-wikilink.vault"]).markdown
        XCTAssertTrue(typed.contains("\nduration:\n"), "a typed note has no recording\n\(typed)")
        let pdf = try XCTUnwrap(out["cap-file-pdf.vault"]).markdown
        XCTAssertTrue(pdf.contains("![[") && pdf.contains(".pdf]]"), "the shared document is embedded (R38)\n\(pdf)")
    }

    func testTagsAreValidYAML_R50() throws {
        let md = try XCTUnwrap(try v2()["typed-tags-with-spaces.vault"]).markdown
        XCTAssertTrue(md.contains("\n  - studio\n"), "no `#` (a YAML comment)\n\(md)")
        XCTAssertTrue(md.contains("\n  - blue glaze\n"), md)
    }

    // MARK: - hand-made notes

    private func note(_ body: String, kind: SourceKind? = nil, sourceType: NoteSourceType = .audio) -> ExportV2.Note {
        var input = CompilerInput(filename: "memo.m4a")
        input.transcript = body
        input.sourceType = sourceType
        input.kind = kind
        input.rawRecordedAt = "2026-09-14T22:30:00Z"
        var n = ExportV2.Note(input: input, title: "Glaze: blue at cone five")
        n.people = [Person(canonical: "[[Lotte Vos]]", aliases: ["Lotte"], short: "Lotte", lastModifiedAt: "2026-01-01T00:00:00.000Z")]
        n.author = "Tiuri"
        return n
    }

    func testAHandTypedLinkToNothingIsEscapedInTheVault_R49() {
        let n = note("Ask [[Lotte Vos]] about [[the kiln]] and [[memo:00000000-0000-0000-0000-000000000001|Glaze log]].")
        let md = ExportV2.compile(n, profile: .obsidian, stem: "s").markdown
        XCTAssertTrue(md.contains("[[Lotte Vos]]"), md)
        XCTAssertTrue(md.contains("\\[\\[the kiln\\]\\]"), "escaped, never a link to nothing\n\(md)")
        XCTAssertTrue(md.contains("[[Glaze log]]"), "a memo-link still exports (C59)\n\(md)")
        let p = ExportV2.compile(n, profile: .portfolio, stem: "s").markdown
        XCTAssertTrue(p.contains("about the kiln and Glaze log."), "the portfolio keeps only people links\n\(p)")
    }

    func testTitleIsQuotedAndThePortfolioWritesItOnlyWhenHeGaveOne() {
        var n = note("Words.")
        XCTAssertTrue(ExportV2.compile(n, profile: .obsidian, stem: "s").markdown.contains("title: \"Glaze: blue at cone five\""))
        XCTAssertFalse(ExportV2.compile(n, profile: .portfolio, stem: "s").markdown.contains("title:"))
        n.heGaveTitle = true
        XCTAssertTrue(ExportV2.compile(n, profile: .portfolio, stem: "s").markdown.contains("title: \"Glaze: blue at cone five\""))
    }

    func testPicturesNamedByStemWithTheirOCRInTheVaultOnly() {
        var n = note("Price board. [[img_001]] Went up. [[img_009]]")
        n.pictureManifest = ["photo_001.jpg"]
        n.pictureText = [1: "GREY BODY €18"]
        let v = ExportV2.compile(n, profile: .obsidian, stem: "Price board")
        XCTAssertTrue(v.markdown.contains("![[Price board_001.jpg]]\n%% GREY BODY €18 %%"), v.markdown)
        XCTAssertFalse(v.markdown.contains("img_009"), "a dangling marker is dropped (C196)")
        XCTAssertEqual(v.pictures, [PlacedPicture(source: "photo_001.jpg", embedName: "Price board_001.jpg")])
        let p = ExportV2.compile(n, profile: .portfolio, stem: "price-board")
        XCTAssertTrue(p.markdown.contains("![](price-board_001.jpg)"), p.markdown)
        XCTAssertFalse(p.markdown.contains("GREY BODY"), "below the fence is his words only (C131)")
    }

    func testAPictureOnlyCaptureUsesThePortfolioEmbed_R51() {
        var n = note("", sourceType: .capture)
        n.input.sharedContent = SharedContent(type: .image, fileName: "IMG_0042.jpg")
        let p = ExportV2.compile(n, profile: .portfolio, stem: "s").markdown
        XCTAssertTrue(p.contains("![](IMG_0042.jpg)"), p)
        XCTAssertFalse(p.contains("![["), p)
    }
}
