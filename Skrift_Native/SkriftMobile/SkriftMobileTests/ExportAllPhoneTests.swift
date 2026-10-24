import XCTest
import SwiftUI
import SwiftData
@testable import SkriftMobile

/// Q516 (D218, D219) on the phone: "Export all notes…" over the synthetic corpus through the
/// phone's own items (`ObsidianPublisher.exportAllItems`) and the shared engine. Every live note
/// is in the archive once (locked and unrated too) with its audio and the pictures its note
/// embeds; trashed notes are not. Plus the Settings row, rendered in each state.
@MainActor
final class ExportAllPhoneTests: XCTestCase {

    /// Collects what the engine writes (the zip writer is covered on the Mac, ExportAllZipTests).
    final class Collect: ExportAll.Sink {
        var files: [String: VaultAsset.Source] = [:]
        func add(_ path: String, _ source: VaultAsset.Source) async throws {
            XCTAssertNil(files[path], "\(path) written twice")
            files[path] = source
        }
        func text(_ path: String) -> String? {
            guard case .data(let d)? = files[path] else { return nil }
            return String(decoding: d, as: UTF8.self)
        }
    }

    func testEveryLiveCorpusNoteGoesInOnceWithItsAssets() async throws {
        let root = CorpusSeedTests.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated")
        let recordings = FileManager.default.temporaryDirectory.appendingPathComponent("q516-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: recordings) }
        let repo = NotesRepository(inMemory: true)
        try CorpusSeed.seed(from: root, into: repo.context, recordingsDirectory: recordings)
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self,
                                                from: Data(contentsOf: root.appendingPathComponent("manifest.json")))

        let publisher = ObsidianPublisher(
            vaultProvider: { nil }, manageScope: false, author: "Tiuri", peopleProvider: { [] },
            memoProvider: { repo.memo(id: $0) },
            enhancementProvider: { repo.enhancement(forMemo: $0) },
            photosProvider: { id in
                Dictionary(repo.assets(forMemo: id).filter { $0.kind == MemoAsset.Kind.photo }.map { ($0.filename, $0.blob) },
                           uniquingKeysWith: { a, _ in a })
            },
            audioProvider: { id in repo.assets(forMemo: id).first { $0.kind == MemoAsset.Kind.audio }?.blob },
            documentProvider: { memo in
                repo.assets(forMemo: memo.id).first { $0.kind == MemoAsset.Kind.document && !$0.blob.isEmpty }?.blob
            })
        let items = publisher.exportAllItems(repo.canonicalMemos())
        let sink = Collect()
        let written = try await ExportAll.write(items, to: sink, root: "r")
        XCTAssertEqual(written, items.count)

        var byID: [String: [String]] = [:]
        for path in sink.files.keys where path.hasSuffix(".md") {
            let line = sink.text(path)?.components(separatedBy: "\n").first { $0.hasPrefix(VaultStamp.idKey + ":") } ?? ""
            byID[line.dropFirst(VaultStamp.idKey.count + 1).trimmingCharacters(in: .whitespaces).uppercased(), default: []].append(path)
        }
        let embed = try NSRegularExpression(pattern: #"!\[\[([^\]|#]+)\]\]|!\[\]\(([^)]+)\)"#)
        var live = 0, audio = 0, pictures = 0
        for entry in manifest.notes {
            let memo = try XCTUnwrap(repo.allMemosIncludingTrashed().first { $0.id.uuidString == entry.id.uppercased() }, entry.slug)
            let paths = byID[entry.id.uppercased()] ?? []
            guard memo.deletedAt == nil else { XCTAssertEqual(paths, [], "\(entry.slug) is trashed"); continue }
            live += 1
            XCTAssertEqual(paths.count, 1, "\(entry.slug) is in once: \(paths)")
            guard let path = paths.first else { continue }
            let folder = (path as NSString).deletingLastPathComponent
            let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            let portfolio = memo.destination.isPortfolio
            func asset(_ sub: String, _ name: String) -> String { portfolio ? "\(folder)/\(name)" : "\(folder)/\(sub)/\(name)" }
            if !memo.audioFilename.isEmpty, repo.assets(forMemo: memo.id).contains(where: { $0.kind == MemoAsset.Kind.audio }) {
                let ext = (memo.audioFilename as NSString).pathExtension
                XCTAssertNotNil(sink.files[asset(VaultLayout.audio, stem + "." + (ext.isEmpty ? "m4a" : ext))], "\(entry.slug) brings its audio")
                audio += 1
            }
            let md = sink.text(path) ?? ""
            let sharedImage = memo.sharedContent?.type == .image ? memo.sharedContent?.fileName : nil
            for m in embed.matches(in: md, range: NSRange(md.startIndex..., in: md)) {
                let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
                let name = String(md[Range(r, in: md)!])
                if name == sharedImage { continue }   // export v2 names a marker-less image capture by the shared file
                XCTAssertTrue(sink.files[asset(VaultLayout.images, name)] != nil || sink.files[asset(VaultLayout.documents, name)] != nil,
                              "\(entry.slug) embeds \(name), and it is in the archive")
                pictures += 1
            }
        }
        XCTAssertEqual(items.count, live, "only the live notes")
        XCTAssertGreaterThan(audio, 30)
        XCTAssertGreaterThan(pictures, 10)
        for slug in ["typed-locked", "voice-en-unrated-old"] {
            let id = try XCTUnwrap(manifest.notes.first { $0.slug == slug }).id.uppercased()
            XCTAssertEqual(byID[id]?.count, 1, "\(slug) goes in (D219: locked notes too)")
        }
    }

    /// The row in each state, for the eyes (mock Q515). `TEST_RUNNER_SKRIFT_RENDER_DIR` keeps the PNGs.
    func testRenderTheRowStates() throws {
        let states: [(String, ExportAllRun.State)] = [("ready", .ready), ("building", .building(done: 128, total: 312)),
                                                       ("failed", .failed("Couldn't build the zip: The disk is full."))]
        let dir = ProcessInfo.processInfo.environment["SKRIFT_RENDER_DIR"] ?? NSTemporaryDirectory()
        for scheme in [ColorScheme.light, .dark] {
            for (name, state) in states {
                let view = ExportAllSettingsRow(run: ExportAllRun(state: state), countOverride: 312)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .frame(width: 358, alignment: .leading)
                    .background(Color.skSurface, in: RoundedRectangle(cornerRadius: 12))
                    .padding(16)
                    .background(Color.skBg)
                    .environment(\.colorScheme, scheme)
                    .tint(.skAccent)   // the app's root tint (AppTabView)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertGreaterThan(image.size.height, 60, "\(name) collapsed")
                try XCTUnwrap(image.pngData()).write(
                    to: URL(fileURLWithPath: dir).appendingPathComponent("export-all-\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}
