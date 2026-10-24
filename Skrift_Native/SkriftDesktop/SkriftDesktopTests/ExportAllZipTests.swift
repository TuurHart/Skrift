import XCTest
import SwiftData
import ZIPFoundation

/// Q516 (D218, D219): "Export all notes…" over the synthetic corpus, through the Mac's real path:
/// `CorpusSeed` → the reconcile sweep → `VaultExporter.exportAllItems` → `ExportAll.write` →
/// `ExportAllZip`, then the zip is read back. Every live corpus note is in it once (unrated and
/// locked ones too), with the files its note embeds; trashed notes are not.
@MainActor
final class ExportAllZipTests: XCTestCase {

    private var scratch: URL!
    private let now = Date(timeIntervalSince1970: 1_792_828_800)   // 2026-10-24 12:00 UTC
    private let lisbon = TimeZone(identifier: "Europe/Lisbon")!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("q516-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: scratch) }

    private struct Built {
        let archive: Archive
        let root: String
        let entries: [String: Entry]
        let items: Int
        let manifest: CorpusSeed.Manifest
    }

    private func buildCorpusZip() async throws -> Built {
        let root = ExportDiffHarnessTests.corpusRoot
        let cloud = ModelContext(try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
        let local = ModelContext(try ModelContainer(
            for: PipelineFile.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CorpusSeed.seed(from: root, into: cloud, recordingsDirectory: scratch.appendingPathComponent("phone-recordings"))
        let roster = try ExportDiffHarnessTests.roster(root)
        V2.sweep(cloud, into: local, people: roster, author: "Tiuri", device: "corpus-mac-0001",
                 outputDir: scratch.appendingPathComponent("mac-work"))
        let rows = try local.fetch(FetchDescriptor<PipelineFile>())
        ExportDiffHarnessTests.nameLink(rows, people: roster)
        let memos = try cloud.fetch(FetchDescriptor<Memo>())
        let assets = try cloud.fetch(FetchDescriptor<MemoAsset>())
        let items = VaultExporter.exportAllItems(rows: rows, memos: memos,
                                                 assets: { id in assets.filter { $0.memoID == id } },
                                                 people: roster, author: "Tiuri")
        XCTAssertEqual(items.count, VaultExporter.exportAllCount(rows: rows, memos: memos),
                       "the row's count is the number of notes that go in")

        let top = ExportAll.rootName(on: now, timeZone: lisbon)
        let url = scratch.appendingPathComponent(top + ".zip")
        var ticks: [Int] = []
        let written = try await ExportAll.write(items, to: try ExportAllZip(creating: url), root: top, now: now,
                                                progress: { done, _ in ticks.append(done) })
        XCTAssertEqual(written, items.count, "no note was skipped")
        XCTAssertEqual(ticks.first, 0)
        XCTAssertEqual(ticks.last, items.count, "progress ends at the total")

        let archive = try Archive(url: url, accessMode: .read)
        var entries: [String: Entry] = [:]
        for entry in archive {
            XCTAssertNil(entries[entry.path], "\(entry.path) is in the zip twice")
            entries[entry.path] = entry
        }
        return Built(archive: archive, root: top, entries: entries, items: items.count,
                     manifest: try ExportDiffHarnessTests.manifest(root))
    }

    /// The note file whose stamp carries `id`, one per note.
    private func notes(in built: Built) throws -> [String: [String]] {
        var byID: [String: [String]] = [:]
        for path in built.entries.keys where path.hasSuffix(".md") {
            let md = String(decoding: try VerifiedZip.data(built.entries[path]!, in: built.archive), as: UTF8.self)
            let line = md.components(separatedBy: "\n").first { $0.hasPrefix(VaultStamp.idKey + ":") } ?? ""
            let id = line.dropFirst(VaultStamp.idKey.count + 1).trimmingCharacters(in: .whitespaces).uppercased()
            byID[id, default: []].append(path)
        }
        return byID
    }

    func testEveryLiveCorpusNoteIsInTheZipOnceAndTrashedOnesAreNot() async throws {
        let built = try await buildCorpusZip()
        let byID = try notes(in: built)
        var live = 0
        for entry in built.manifest.notes {
            let note = try ExportDiffHarnessTests.note(ExportDiffHarnessTests.corpusRoot, folder: entry.folder)
            let paths = byID[entry.id.uppercased()] ?? []
            if note.deletedAt != nil {
                XCTAssertEqual(paths, [], "\(entry.slug) is in the trash and stays out")
            } else {
                live += 1
                XCTAssertEqual(paths.count, 1, "\(entry.slug) is in the zip once: \(paths)")
                let folder = note.destination == "personal" ? "Personal/" : "Portfolio/_inbox/"
                XCTAssertTrue(paths.first?.hasPrefix(built.root + "/" + folder) ?? false,
                              "\(entry.slug) sits in its destination's folder: \(paths)")
            }
        }
        XCTAssertEqual(built.items, live, "nothing but the corpus's live notes went in")
        XCTAssertGreaterThan(live, 100)
    }

    func testUnratedAndLockedNotesGoIn() async throws {
        let built = try await buildCorpusZip()
        let byID = try notes(in: built)
        for slug in ["typed-locked", "applenote-dutch", "typed-dutch-boodschappen", "voice-en-unrated-old", "typed-empty-body"] {
            let entry = try XCTUnwrap(built.manifest.notes.first { $0.slug == slug }, slug)
            XCTAssertEqual(byID[entry.id.uppercased()]?.count, 1, "\(slug) is in the zip")
        }
    }

    /// Each note's media is beside it in the zip: its audio, every picture or file its note
    /// embeds, a shared document.
    func testEachNoteBringsItsAssets() async throws {
        let built = try await buildCorpusZip()
        let byID = try notes(in: built)
        let embed = try NSRegularExpression(pattern: #"!\[\[([^\]|#]+)\]\]|!\[\]\(([^)]+)\)"#)
        var audioNotes = 0, embeds = 0, documents = 0
        for entry in built.manifest.notes {
            let note = try ExportDiffHarnessTests.note(ExportDiffHarnessTests.corpusRoot, folder: entry.folder)
            guard note.deletedAt == nil, let path = byID[entry.id.uppercased()]?.first else { continue }
            let portfolio = note.destination != "personal"
            let folder = (path as NSString).deletingLastPathComponent
            let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            func asset(_ sub: String, _ name: String) -> String { portfolio ? "\(folder)/\(name)" : "\(folder)/\(sub)/\(name)" }

            if note.audio != nil {
                XCTAssertNotNil(built.entries[asset(VaultLayout.audio, stem + ".m4a")], "\(entry.slug) brings its audio")
                audioNotes += 1
            }
            let md = String(decoding: try VerifiedZip.data(built.entries[path]!, in: built.archive), as: UTF8.self)
            let sharedImage = note.kind == "capture" && !note.photos.isEmpty && !(note.transcript ?? "").contains("[[img_")
            for m in embed.matches(in: md, range: NSRange(md.startIndex..., in: md)) {
                let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
                let name = String(md[Range(r, in: md)!])
                if sharedImage, name == ((note.sharedContent?.foundation as? [String: Any])?["fileName"] as? String) {
                    // Export v2 (as v1) embeds a marker-less image capture under the shared file's
                    // name while its picture keeps its stored name; the vault gets the same. The
                    // picture itself is in the zip, under the name its memo id is in.
                    XCTAssertTrue(built.entries.keys.contains { $0.hasPrefix(asset(VaultLayout.images, ""))
                                      && $0.contains(entry.id.uppercased()) }, "\(entry.slug) brings its picture")
                    continue
                }
                let found = built.entries[asset(VaultLayout.images, name)] ?? built.entries[asset(VaultLayout.documents, name)]
                XCTAssertNotNil(found, "\(entry.slug) embeds \(name), and it is in the zip")
                embeds += 1
            }
            if note.sharedFile != nil {
                XCTAssertTrue(built.entries.keys.contains { $0.hasPrefix(asset(VaultLayout.documents, stem)) },
                              "\(entry.slug) brings its shared document")
                documents += 1
            }
        }
        XCTAssertGreaterThan(audioNotes, 30)
        XCTAssertGreaterThan(embeds, 10)
        XCTAssertEqual(documents, 2)
    }

    func testTheZipIsNamedForTheDay() {
        XCTAssertEqual(ExportAll.rootName(on: now, timeZone: lisbon), "Skrift notes 2026-10-24")
        XCTAssertEqual(ExportAll.noteFolder(.personal), "Personal")
        XCTAssertEqual(ExportAll.noteFolder(.portfolio), "Portfolio/_inbox")
    }

    /// Cancel stops before the next note; the caller deletes the half-written zip.
    func testCancelStops() async throws {
        let id = UUID()
        let item = ExportAll.Item(id: id, destination: .personal, title: "One", filenameFallback: "one.m4a",
                                  recordedAt: nil) { _ in ExportAll.Compiled(markdown: "---\n---\nOne\n") }
        let url = scratch.appendingPathComponent("cancel.zip")
        var calls = 0
        do {
            _ = try await ExportAll.write([item, item], to: try ExportAllZip(creating: url), root: "r",
                                          isCancelled: { calls += 1; return calls > 1 })
            XCTFail("a cancelled run throws")
        } catch is ExportAll.Cancelled {}
    }

    /// Two notes with one title get two files, the second suffixed with its id (the vault's rule).
    func testSameTitleNotesGetTwoFiles() async throws {
        let a = UUID(), b = UUID()
        func item(_ id: UUID) -> ExportAll.Item {
            ExportAll.Item(id: id, destination: .personal, title: "Kiln", filenameFallback: "k.m4a", recordedAt: nil) { stem in
                ExportAll.Compiled(markdown: "---\n---\n\(stem)\n",
                                   audio: VaultAsset(name: stem + ".m4a", source: .data(Data("A".utf8))))
            }
        }
        let url = scratch.appendingPathComponent("same.zip")
        _ = try await ExportAll.write([item(a), item(b)], to: try ExportAllZip(creating: url), root: "r")
        let paths = Set(try Archive(url: url, accessMode: .read).map(\.path))
        let second = "Kiln \(b.uuidString.prefix(8))"
        XCTAssertEqual(paths, ["r/Personal/Kiln.md", "r/Personal/Recordings/Kiln.m4a",
                               "r/Personal/\(second).md", "r/Personal/Recordings/\(second).m4a"])
    }
}
