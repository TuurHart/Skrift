import XCTest
import Foundation

/// Q18 (C50/C265/C218): a locally-cached JSON file that fails to decode is
/// never adopted as empty and never written back over — it's quarantined
/// (`SafeJSONStore`) and recovery is surfaced. Mac coverage: names.json +
/// settings.json. (Phone coverage — library.json/bookmarks.json — lives in
/// `SkriftMobileTests/CorruptStoreTests.swift`.)
final class CorruptStoreTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString).json")
    }

    private func writeGarbage(to url: URL) {
        try? Data("{not valid json at all".utf8).write(to: url)
    }

    // MARK: - corrupt-settings-json (R78)

    func testCorruptSettingsJSONIsQuarantinedNotAdoptedEmpty() {
        let url = tempURL("settings")
        writeGarbage(to: url)
        CorruptFileRegistry.shared.reset()

        let store = SettingsStore(fileURL: url)
        let loaded = store.load()

        // Falls back to freshDefault for this session (no other source exists
        // for settings) — but the ORIGINAL file must be gone from `url` (moved
        // aside), never left in place to be silently overwritten empty.
        XCTAssertEqual(loaded.noteFolder, SettingsStore.freshDefault.noteFolder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                        "the corrupt file must be moved aside, not left/overwritten in place")

        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
        XCTAssertTrue(siblings.contains { $0.hasPrefix(url.lastPathComponent + ".corrupt-") },
                      "a <name>.corrupt-<timestamp> sibling must exist")
        XCTAssertTrue(CorruptFileRegistry.shared.found.contains { $0.url == url },
                      "recovery must be surfaced via CorruptFileRegistry")
    }

    func testSettingsSaveNeverOverwritesAQuarantinedFile() {
        let url = tempURL("settings2")
        writeGarbage(to: url)
        let store = SettingsStore(fileURL: url)
        _ = store.load()   // triggers quarantine

        var next = AppSettings.default
        next.authorName = "Tuur"
        store.save(next)

        // The corrupt sibling from the FIRST load is still there, untouched —
        // save() only ever writes the (now-empty) original slot going forward.
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
        XCTAssertTrue(siblings.contains { $0.hasPrefix(url.lastPathComponent + ".corrupt-") })

        let reloaded = try? JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url))
        XCTAssertEqual(reloaded?.authorName, "Tuur")
    }

    // MARK: - corrupt names.json (C50, D1: "torn file → previous roster")

    func testCorruptNamesJSONFallsBackToLastGoodRosterNotEmpty() {
        let url = tempURL("names")
        let store = NamesStore(fileURL: url)

        store.upsert(canonical: "Nick", aliases: ["Nicky"], short: "Nick")
        XCTAssertEqual(store.livePeople().count, 1)

        // Torn write: truncate the real file mid-write.
        writeGarbage(to: url)

        let afterTear = store.load()
        XCTAssertEqual(afterTear.people.filter { !$0.isDeleted }.count, 1,
                        "a torn read must return the last-known-good roster, never an empty one")
        XCTAssertEqual(afterTear.people.first?.canonical, "[[Nick]]")
    }

    func testCorruptNamesJSONIsQuarantinedAndRecoverySurfaced() {
        let url = tempURL("names2")
        writeGarbage(to: url)
        CorruptFileRegistry.shared.reset()

        let store = NamesStore(fileURL: url)
        // No prior in-process lastGood (fresh NamesStore instance) — a first-ever
        // read of a corrupt file has nothing else to fall back to, but the file
        // itself must still be preserved (never silently treated as "brand new").
        _ = store.load()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
        XCTAssertTrue(siblings.contains { $0.hasPrefix(url.lastPathComponent + ".corrupt-") })
        XCTAssertTrue(CorruptFileRegistry.shared.found.contains { $0.url == url })
    }

    func testNamesUpsertAfterTearNeverShrinksTheRoster() {
        let url = tempURL("names3")
        let store = NamesStore(fileURL: url)
        store.upsert(canonical: "Nick", aliases: [], short: nil)
        store.upsert(canonical: "Jane", aliases: [], short: nil)
        XCTAssertEqual(store.livePeople().count, 2)

        writeGarbage(to: url)   // torn on disk; in-memory lastGood still holds 2

        // A subsequent write (e.g. a third add) must merge onto the last-good
        // roster, not silently reset to whatever the torn read produced.
        store.upsert(canonical: "Alex", aliases: [], short: nil)
        XCTAssertEqual(store.livePeople().count, 3, "merge never shrinks (R8)")
    }
}
