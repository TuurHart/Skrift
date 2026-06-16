import XCTest
import Foundation

/// Chunk 2 — seeding the portable names roster from the vault's `People/` note titles
/// (NAMING_MODEL.md decision 5). Privacy: the scanner reads FILENAMES only, never note
/// contents; seeding never clobbers an existing person.
final class RosterSeedingTests: XCTestCase {

    // MARK: PeopleFolderScanner — titles only, no contents

    private func makeVault(people: [String: String], extras: [(String, String)] = []) -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vault_\(UUID().uuidString)")
        let peopleDir = root.appendingPathComponent("People")
        try? FileManager.default.createDirectory(at: peopleDir, withIntermediateDirectories: true)
        for (name, body) in people {
            try? body.write(to: peopleDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        for (relPath, body) in extras {
            let url = root.appendingPathComponent(relPath)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    func testScanReturnsMarkdownTitlesSortedAndDeduped() {
        let root = makeVault(people: [
            "Jack Hutton.md": "secret contents that must never be read",
            "Hendri van Niekerk.md": "x",
            "notes.txt": "not markdown",        // wrong extension → excluded
            "README.markdown": "wrong ext too", // only .md counts → excluded
        ])
        let titles = PeopleFolderScanner.titles(vaultRoot: root)
        XCTAssertEqual(titles, ["Hendri van Niekerk", "Jack Hutton"], "md stems, sorted; non-md excluded")
    }

    func testScanEmptyWhenNoPeopleFolder() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("novault_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertTrue(PeopleFolderScanner.titles(vaultRoot: root).isEmpty)
    }

    func testScanIgnoresNestedAndHiddenFiles() {
        let root = makeVault(
            people: ["Bruno Aragorn.md": "x", ".hidden.md": "x"],
            extras: [("People/sub/Nested Person.md", "x")])   // nested → not a top-level person note
        XCTAssertEqual(PeopleFolderScanner.titles(vaultRoot: root), ["Bruno Aragorn"])
    }

    // MARK: NamesStore.seedRoster — derive aliases, idempotent, non-clobbering

    private func tempStore() -> NamesStore {
        NamesStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("names_\(UUID().uuidString).json"))
    }

    func testSeedCreatesPeopleWithCanonicalAndDerivedAliases() {
        let store = tempStore()
        let added = store.seedRoster(titles: ["Hendri van Niekerk", "Madonna"])
        XCTAssertEqual(added, 2)
        let people = store.livePeople()
        let hendri = people.first { $0.canonical == "[[Hendri van Niekerk]]" }
        XCTAssertNotNil(hendri)
        // Full title + first-name token are both aliases (so opt-out can link "Hendri").
        XCTAssertEqual(hendri?.aliases, ["Hendri van Niekerk", "Hendri"])
        // A single-word title yields just the one alias (no duplicate).
        let madonna = people.first { $0.canonical == "[[Madonna]]" }
        XCTAssertEqual(madonna?.aliases, ["Madonna"])
    }

    func testSeedIsIdempotent() {
        let store = tempStore()
        XCTAssertEqual(store.seedRoster(titles: ["Jack Hutton"]), 1)
        XCTAssertEqual(store.seedRoster(titles: ["Jack Hutton", "jack hutton", "JACK HUTTON"]), 0,
                       "existing canonical (case-insensitive) → never re-added")
        XCTAssertEqual(store.livePeople().filter { $0.canonical == "[[Jack Hutton]]" }.count, 1, "no duplicate")
    }

    func testSeedDoesNotClobberExistingPerson() {
        let store = tempStore()
        // An existing person with hand-curated aliases + a voiceprint.
        store.upsert(Person(canonical: "[[Jack Hutton]]", aliases: ["Jack", "Jacky"], short: "Jack",
                            voiceEmbeddings: [VoiceEmbedding(vector: [0.1, 0.2])], lastModifiedAt: "x"),
                     replacing: nil)
        let added = store.seedRoster(titles: ["Jack Hutton", "Bruno Aragorn"])
        XCTAssertEqual(added, 1, "only the genuinely-new title is added")
        let jack = store.livePeople().first { $0.canonical == "[[Jack Hutton]]" }
        XCTAssertEqual(jack?.aliases, ["Jack", "Jacky"], "existing aliases untouched (not overwritten by the title)")
        XCTAssertEqual(jack?.voiceEmbeddings?.count, 1, "voiceprint preserved")
    }

    func testSeededDistinctiveNameAutoLinksOptOut() {
        // End-to-end with chunk 1: a seeded distinctive person auto-links in the Sanitiser.
        let store = tempStore()
        store.seedRoster(titles: ["Hendri van Niekerk"])
        let r = Sanitiser.process(text: "I met Hendri at the studio.", people: store.livePeople())
        XCTAssertEqual(r.sanitised, "I met [[Hendri van Niekerk]] at the studio.")
    }
}
