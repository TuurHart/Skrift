import XCTest
import Foundation

/// Q420 (C257/R66): naming a speaker with a name that is not on the roster never mints an
/// alias-less person. Both naming doors (phone assign sheet, Mac gutter popover) call
/// `PersonEditCore.createIfNeeded`; the voice-enrolment path (`NamesStore.addVoiceEmbedding`,
/// reached by `VoiceEnroller.enroll` and the Mac's `learnVoice`) seeds from the same
/// `PersonEditCore.defaultAliases`. Fixture: test-fixtures/corpus/rosters/edge-speaker-assign-new-name.json.
final class SpeakerAssignNewNameTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Expect: Decodable {
            let canonical: String
            let minAliases: Int
            let aliasesContain: [String]
            let voiceprints: Int
        }
        let existing: NamesData
        let displayed: String
        let typed: String
        let typedFirstWordOnly: String
        let voiceprint: VoiceEmbedding
        let expect: Expect
    }

    private func fixture() throws -> Fixture {
        let url = CorpusSeed.fixtureRoot(file: #filePath)
            .appendingPathComponent("rosters/edge-speaker-assign-new-name.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func seededStore(_ f: Fixture) -> NamesStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("names_q420_\(UUID().uuidString).json")
        let store = NamesStore(fileURL: url)
        _ = store.save(f.existing)
        return store
    }

    private func assertSeeded(_ person: Person?, _ f: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(person, "the person exists", file: file, line: line)
        XCTAssertEqual(person?.canonical, f.expect.canonical, file: file, line: line)
        XCTAssertGreaterThanOrEqual(person?.aliases.count ?? 0, f.expect.minAliases,
                                    "an alias-less person never links (C257)", file: file, line: line)
        for a in f.expect.aliasesContain {
            XCTAssertTrue(person?.aliases.contains(a) ?? false, "alias \(a) seeded", file: file, line: line)
        }
    }

    /// The shared naming door (phone assign sheet AND Mac gutter popover): a typed name not on
    /// the roster is born with the typed name as an alias.
    func testNamingUnknownSpeakerSeedsAlias() throws {
        let f = try fixture()
        let store = seededStore(f)
        XCTAssertNil(store.livePeople().first { NamesMerge.matchKey($0.canonical) == NamesMerge.matchKey(f.typed) })

        let person = PersonEditCore.createIfNeeded(fullName: f.typed, announceMerge: false, in: store)
        assertSeeded(person, f)
        XCTAssertEqual(store.livePeople().count, f.existing.people.count + 1, "exactly one person added")
        XCTAssertEqual(store.livePeople().first { $0.canonical == "[[Lotte Vos]]" }?.aliases, ["Lotte"], "roster untouched")
    }

    /// A one-word typed name still gets exactly one alias, not an empty list or a duplicate.
    func testSingleWordNameSeedsOneAlias() throws {
        let f = try fixture()
        let store = seededStore(f)
        let person = PersonEditCore.createIfNeeded(fullName: f.typedFirstWordOnly, announceMerge: false, in: store)
        XCTAssertEqual(person?.aliases, [f.typedFirstWordOnly])
    }

    /// R66's actual path: the voiceprint is enrolled for a name that is not on the roster
    /// (`VoiceEnroller.enroll` / the Mac's `learnVoice` → `addVoiceEmbedding`). The person it
    /// creates carries the voiceprint AND an alias.
    func testVoiceEnrolmentOfUnknownNameSeedsAlias() throws {
        let f = try fixture()
        let store = seededStore(f)
        store.addVoiceEmbedding(canonical: f.typed, embedding: f.voiceprint)
        let person = store.livePeople().first { NamesMerge.matchKey($0.canonical) == NamesMerge.matchKey(f.typed) }
        assertSeeded(person, f)
        XCTAssertEqual(person?.voiceEmbeddings?.count, f.expect.voiceprints)
    }

    /// Naming first (door), then enrolling: the door's aliases survive the enrolment.
    func testDoorThenEnrolmentKeepsAliasesAndAddsVoiceprint() throws {
        let f = try fixture()
        let store = seededStore(f)
        PersonEditCore.createIfNeeded(fullName: f.typed, announceMerge: false, in: store)
        store.addVoiceEmbedding(canonical: f.typed, embedding: f.voiceprint)
        let person = store.livePeople().first { NamesMerge.matchKey($0.canonical) == NamesMerge.matchKey(f.typed) }
        assertSeeded(person, f)
        XCTAssertEqual(person?.voiceEmbeddings?.count, f.expect.voiceprints)
    }

    /// Enrolling a voice for a person who IS on the roster must not touch their aliases.
    func testEnrolmentOfKnownNameLeavesAliasesAlone() throws {
        let f = try fixture()
        let store = seededStore(f)
        store.addVoiceEmbedding(canonical: "Lotte Vos", embedding: f.voiceprint)
        let lotte = store.livePeople().first { $0.canonical == "[[Lotte Vos]]" }
        XCTAssertEqual(lotte?.aliases, ["Lotte"])
        XCTAssertEqual(lotte?.voiceEmbeddings?.count, 1)
    }
}
