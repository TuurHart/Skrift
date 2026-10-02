import XCTest
@testable import SkriftMobile

/// R12 / C83 / C80: every door that makes a person on the phone (speaker naming, Add Person
/// sheet) goes through `PersonEditCore.createIfNeeded` — the person exists with aliases
/// `[full, first]` before any voice enrolment is attempted, and an existing person is never
/// overwritten.
final class PersonCreationRulesTests: XCTestCase {
    private func tempStore() -> NamesStore {
        NamesStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("names_\(UUID().uuidString).json"))
    }
    private func clip(_ n: Int) -> [Float] { (0..<n).map { Float(sin(Double($0) * 0.01)) } }

    func testNewPersonGetsFullAndFirstAliasAndShort() throws {
        let store = tempStore()
        let p = try XCTUnwrap(PersonEditCore.createIfNeeded(fullName: "Jack de Vries", in: store))
        XCTAssertEqual(p.aliases, ["Jack de Vries", "Jack"])
        XCTAssertEqual(p.short, "Jack")
        XCTAssertEqual(store.livePeople().count, 1)
    }

    func testSingleWordNameGetsOneAlias() throws {
        let store = tempStore()
        let p = try XCTUnwrap(PersonEditCore.createIfNeeded(fullName: "Tiuri", in: store))
        XCTAssertEqual(p.aliases, ["Tiuri"])
    }

    func testTypedShortWins() throws {
        let store = tempStore()
        let p = try XCTUnwrap(PersonEditCore.createIfNeeded(fullName: "Jack de Vries", short: "JdV", in: store))
        XCTAssertEqual(p.short, "JdV")
        XCTAssertEqual(p.aliases, ["Jack de Vries", "Jack"])
    }

    func testEmptyNameCreatesNobody() {
        let store = tempStore()
        XCTAssertNil(PersonEditCore.createIfNeeded(fullName: "   ", in: store))
        XCTAssertTrue(store.livePeople().isEmpty)
    }

    /// Speaker naming with a clip too short to embed: the person must still exist (the
    /// old order created them only inside a successful `VoiceEnroller.enroll`).
    func testPersonExistsEvenWhenEnrolmentFails() async throws {
        let store = tempStore()
        PersonEditCore.createIfNeeded(fullName: "Jack de Vries", in: store)
        let ok = await VoiceEnroller.enroll(name: "Jack de Vries", clip: clip(1_000), using: SeededEmbedder(), into: store)
        XCTAssertFalse(ok)
        let p = try XCTUnwrap(store.livePeople().first)
        XCTAssertEqual(p.aliases, ["Jack de Vries", "Jack"])
    }

    /// Enrolment after creation appends the voiceprint and keeps the default aliases.
    func testEnrolmentAfterCreationKeepsAliases() async throws {
        let store = tempStore()
        PersonEditCore.createIfNeeded(fullName: "Jack de Vries", in: store)
        let ok = await VoiceEnroller.enroll(name: "Jack de Vries", clip: clip(40_000), using: SeededEmbedder(), into: store)
        XCTAssertTrue(ok)
        let p = try XCTUnwrap(store.livePeople().first)
        XCTAssertEqual(p.aliases, ["Jack de Vries", "Jack"])
        XCTAssertEqual(p.voiceEmbeddings?.count, 1)
    }

    /// setexp-107: Add Person on an existing canonical must not wipe its aliases.
    func testAddingExistingPersonKeepsTheirAliases() throws {
        let store = tempStore()
        _ = store.save(NamesData(lastModifiedAt: "2026-06-01T00:00:00.000Z", people: [
            Person(canonical: "[[Tiuri Hartog]]", aliases: ["Tuur", "Tiuri Hartog"], short: "Tuur",
                   lastModifiedAt: "2026-06-01T00:00:00.000Z")
        ]))
        let p = try XCTUnwrap(PersonEditCore.createIfNeeded(fullName: "Tiuri Hartog", in: store))
        XCTAssertEqual(p.aliases, ["Tuur", "Tiuri Hartog"])
        XCTAssertEqual(p.short, "Tuur")
        XCTAssertEqual(store.livePeople().count, 1)
    }

    /// An Add with a typed short merges: aliases are unioned, never replaced.
    func testAddingExistingPersonWithShortUnionsAliases() throws {
        let store = tempStore()
        _ = store.save(NamesData(lastModifiedAt: "2026-06-01T00:00:00.000Z", people: [
            Person(canonical: "[[Tiuri Hartog]]", aliases: ["Tuur"], short: nil,
                   lastModifiedAt: "2026-06-01T00:00:00.000Z")
        ]))
        let p = try XCTUnwrap(PersonEditCore.createIfNeeded(fullName: "Tiuri Hartog", short: "Tiuri", in: store))
        XCTAssertTrue(p.aliases.contains("Tuur"))
        XCTAssertEqual(p.short, "Tiuri")
        XCTAssertEqual(store.livePeople().count, 1)
    }

    /// The low-level `upsert(canonical:aliases:short:)` no longer overwrites a live person.
    func testUpsertCanonicalDoesNotOverwriteLivePerson() throws {
        let store = tempStore()
        store.upsert(canonical: "Nick", aliases: ["Nicky"], short: "Nick")
        store.upsert(canonical: "Nick", aliases: [], short: nil)
        let p = try XCTUnwrap(store.livePeople().first)
        XCTAssertEqual(p.aliases, ["Nicky"])
        XCTAssertEqual(p.short, "Nick")
    }
}
