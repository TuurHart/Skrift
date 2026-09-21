import XCTest
import SwiftData
@testable import SkriftMobile

/// The synthetic corpus loads into the phone's own store and every blob decodes through the
/// phone's typed accessors — the v2 rewrite's change detector is usable on this side.
final class CorpusSeedTests: XCTestCase {

    static var corpusRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/corpus", isDirectory: true)
    }

    @MainActor
    func testCorpusLoadsAndEveryBlobDecodes() throws {
        let root = Self.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated — run test-fixtures/corpus/generate.py")
        let recordings = FileManager.default.temporaryDirectory.appendingPathComponent("corpus-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: recordings) }
        let repo = NotesRepository(inMemory: true)
        let result = try CorpusSeed.seed(from: root, into: repo.context, recordingsDirectory: recordings)
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self,
                                                from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        XCTAssertEqual(result.inserted, manifest.count)

        let memos = repo.allMemosIncludingTrashed()
        XCTAssertEqual(memos.count, manifest.count)
        var captures = 0, photos = 0, trashed = 0
        for memo in memos {
            if memo.metadataData != nil {
                XCTAssertNotNil(memo.metadata, "metadata blob must decode: \(memo.id)")
            }
            if memo.sharedContentData != nil {
                XCTAssertNotNil(memo.sharedContent, "sharedContent blob must decode: \(memo.id)")
                captures += 1
            }
            for entry in memo.metadata?.imageManifest ?? [] {
                photos += 1
                if entry.filename.contains("missing") == false,
                   !(memo.transcript ?? "").contains("never made it across") {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: recordings.appendingPathComponent(entry.filename).path),
                                  "photo written under the app filename: \(entry.filename)")
                }
            }
            if memo.deletedAt != nil { trashed += 1 }
        }
        XCTAssertGreaterThan(captures, 10)
        XCTAssertGreaterThan(photos, 15)
        XCTAssertEqual(trashed, 1)
    }
}
