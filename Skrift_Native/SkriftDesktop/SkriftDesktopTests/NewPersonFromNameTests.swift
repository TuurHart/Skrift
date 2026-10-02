import XCTest

/// Q184 (note-name-06, note-body-21): one "new person from a name" flow and one note-link
/// picker rule set, read by the phone and the Mac (`NewPersonFromName`, `LinkPickerCopy`).
final class NewPersonFromNameTests: XCTestCase {

    private func person(_ canonical: String, aliases: [String]) -> Person {
        Person(canonical: canonical, aliases: aliases, short: nil,
               voiceEmbeddings: nil, lastModifiedAt: "2026-01-01T00:00:00.000Z")
    }

    private func tempStore() -> NamesStore {
        NamesStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("names_\(UUID().uuidString).json"))
    }

    // MARK: the already-known check

    func testKnownCanonicalIsRefusedIgnoringCaseAndBrackets() {
        let people = [person("[[Jack de Vries]]", aliases: ["Jack"])]
        XCTAssertEqual(NewPersonFromName.start("jack de vries", people: people),
                       .existing(canonical: "[[Jack de Vries]]"))
    }

    func testKnownAliasIsRefused() {
        let people = [person("[[Jack de Vries]]", aliases: ["Jack", "JdV"])]
        XCTAssertEqual(NewPersonFromName.start(" jdv ", people: people),
                       .existing(canonical: "[[Jack de Vries]]"))
    }

    func testUnknownNameOpensEditorPrefilledWithNameAndAlias() {
        let people = [person("[[Jack de Vries]]", aliases: ["Jack"])]
        XCTAssertEqual(NewPersonFromName.start("  Maria Costa ", people: people),
                       .prefill(name: "Maria Costa", alias: "Maria Costa"))
    }

    func testBlankSelectionDoesNothing() {
        XCTAssertEqual(NewPersonFromName.start("  \n ", people: []), .empty)
    }

    func testSomeoneElseSkipsTheCheck() {
        let people = [person("[[Jack de Vries]]", aliases: ["Jack"])]
        XCTAssertEqual(NewPersonFromName.start("Jack", people: people, someoneElse: true),
                       .prefill(name: "Jack", alias: "Jack"))
    }

    func testMessageMatchesTheMacFlash() {
        XCTAssertEqual(NewPersonFromName.alreadyKnownMessage(" Jack "), "“Jack” is already in your names")
    }

    // MARK: save through PersonEditCore

    func testCommitCreatesPersonWithTheAliasAndRenamesInPlace() throws {
        let store = tempStore()
        let canonical = try XCTUnwrap(NewPersonFromName.commit(
            fullName: "Maria Costa", aliases: ["Mari"], short: "", original: nil, in: store))
        XCTAssertEqual(canonical, "[[Maria Costa]]")
        let made = try XCTUnwrap(store.livePeople().first)
        XCTAssertEqual(made.aliases, ["Mari"])

        // A rename replaces the original (no duplicate).
        NewPersonFromName.commit(fullName: "Maria Costa-Silva", aliases: ["Mari"], short: "",
                                 original: made, in: store)
        XCTAssertEqual(store.livePeople().map(\.canonical), ["[[Maria Costa-Silva]]"])
    }

    func testCommitEmptyNameStoresNothing() {
        let store = tempStore()
        XCTAssertNil(NewPersonFromName.commit(fullName: " ", aliases: [], short: "", original: nil, in: store))
        XCTAssertTrue(store.livePeople().isEmpty)
    }

    // MARK: the note-link picker rules

    private struct Row { let title: String; let subtitle: String }

    func testPickerCopyIsTheSharedSet() {
        XCTAssertEqual(LinkPickerCopy.title, "Link a note")
        XCTAssertEqual(LinkPickerCopy.searchPlaceholder, "Search notes")
        XCTAssertEqual(LinkPickerCopy.emptyText, "No notes match")
        XCTAssertEqual(LinkPickerCopy.emptyQueryRowCap, 50)
    }

    func testEmptyQueryCapsAtFiftyAndKeepsOrder() {
        let rows = (0..<80).map { Row(title: "Note \($0)", subtitle: "") }
        let shown = LinkPickerCopy.visible(rows, query: "  ") { [$0.title, $0.subtitle] }
        XCTAssertEqual(shown.count, 50)
        XCTAssertEqual(shown.first?.title, "Note 0")
    }

    func testQuerySearchesTitleAndDateLineWithoutTheCap() {
        let rows = (0..<80).map { Row(title: "Note \($0)", subtitle: $0 == 70 ? "Tue 3 Mar" : "") }
        XCTAssertEqual(LinkPickerCopy.visible(rows, query: "note") { [$0.title, $0.subtitle] }.count, 80)
        XCTAssertEqual(LinkPickerCopy.visible(rows, query: "TUE") { [$0.title, $0.subtitle] }.map(\.title), ["Note 70"])
        XCTAssertTrue(LinkPickerCopy.visible(rows, query: "zzz") { [$0.title, $0.subtitle] }.isEmpty)
    }
}
