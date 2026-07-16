import XCTest
@testable import SkriftMobile

/// One rulebook for the person editor (Shared/Naming/PersonEditCore) — same test
/// file in both suites (deliberate twin, desktop compiles Shared/Naming directly).
final class PersonEditCoreTests: XCTestCase {

    private func person(_ canonical: String, aliases: [String] = [], short: String? = nil,
                        voices: [VoiceEmbedding]? = nil) -> Person {
        Person(canonical: canonical, aliases: aliases, short: short,
               voiceEmbeddings: voices, lastModifiedAt: "2026-01-01T00:00:00.000Z")
    }

    // MARK: displayShort

    func testDisplayShortPrefersExplicitShort() {
        XCTAssertEqual(PersonEditCore.displayShort(fullName: "Jack de Vries", short: " JdV "), "JdV")
    }

    func testDisplayShortFallsBackToFirstWord() {
        XCTAssertEqual(PersonEditCore.displayShort(fullName: "Jack de Vries", short: ""), "Jack")
        XCTAssertEqual(PersonEditCore.displayShort(fullName: "  ", short: ""), "")
    }

    // MARK: alias demo

    func testAliasDemoBoldsHowTheMentionReads() {
        let d = PersonEditCore.aliasDemo(firstAlias: "Jackie", fullName: "Jack de Vries", short: "")
        XCTAssertEqual(d?.prefix, "saying “Jackie” → recognised as ")
        XCTAssertEqual(d?.bold, "Jack", "bold = the short display, not the full canonical")
    }

    func testAliasDemoNilOnEmptyAlias() {
        XCTAssertNil(PersonEditCore.aliasDemo(firstAlias: "  ", fullName: "Jack", short: ""))
    }

    // MARK: materialise

    func testMaterialiseNormalisesAndDefaultsAlias() throws {
        let r = try XCTUnwrap(PersonEditCore.materialise(
            fullName: " Nick Jansen ", aliases: [], short: "  ", original: nil))
        XCTAssertEqual(r.person.canonical, NamesMerge.normaliseCanonical("Nick Jansen"))
        XCTAssertEqual(r.person.aliases, ["Nick Jansen"], "no alias = never links → default to the name")
        XCTAssertNil(r.person.short)
        XCTAssertNil(r.renamedFrom)
    }

    func testMaterialiseCleansAndDedupesAliases() throws {
        let r = try XCTUnwrap(PersonEditCore.materialise(
            fullName: "Nick Jansen", aliases: [" Nick ", "nick", "", "Nico"], short: "",
            original: nil))
        XCTAssertEqual(r.person.aliases, ["Nick", "Nico"])
    }

    func testMaterialiseRejectsEmptyName() {
        XCTAssertNil(PersonEditCore.materialise(fullName: "   ", aliases: ["x"], short: "", original: nil))
    }

    func testRenameDetectedAndVoiceprintsCarry() throws {
        let voices = [VoiceEmbedding(vector: [0.1, 0.2])]
        let old = person(NamesMerge.normaliseCanonical("Jack Timmons"), aliases: ["Jack"], voices: voices)
        let r = try XCTUnwrap(PersonEditCore.materialise(
            fullName: "Jack Timmermans", aliases: ["Jack"], short: "", original: old))
        XCTAssertEqual(r.renamedFrom, old.canonical)
        XCTAssertEqual(r.person.voiceEmbeddings?.count, 1,
                       "a rename must not drop the voice enrollment (the old phone bug)")
    }

    func testNoRenameOnSameCanonical() throws {
        let old = person(NamesMerge.normaliseCanonical("Jack Timmons"), aliases: ["Jack"])
        let r = try XCTUnwrap(PersonEditCore.materialise(
            fullName: "Jack Timmons", aliases: ["Jack", "Jackie"], short: "J", original: old))
        XCTAssertNil(r.renamedFrom)
        XCTAssertEqual(r.person.short, "J")
    }
}
