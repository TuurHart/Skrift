import XCTest
import SwiftData

/// Q158 (C62, D162): the export author is ONE synced setting. It rides the `VocabularyRecord`
/// carrier on its OWN stamp, last-write-wins (`AuthorSyncCore`), so the iPad and the Mac write
/// the same `author:` line and the same note compiles to the same bytes on both. The phone
/// target's twin class runs the same round trip through the phone's `VocabularyCloudSync`.
final class AuthorSyncTests: XCTestCase {

    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    private func carrier(name: String = "", at: Date = Date.distantPast) -> VocabularyRecord {
        VocabularyRecord(words: ["Skrift"], modifiedAt: Date(timeIntervalSince1970: 500),
                         authorName: name, authorModifiedAt: at)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "authorsync_\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    // ── round trip ──

    /// Mac sets the name → the carrier holds it → a blank iPad adopts it → both compile the
    /// same `author:` line.
    func testRoundTripMacToIPadGivesOneAuthorLine() {
        var records: [VocabularyRecord] = []
        let pushed = AuthorSyncCore.reconcile(localName: "Tuur", localModifiedAt: newer,
                                              records: records, insert: { records.append($0) })
        XCTAssertEqual(pushed, .pushedLocal(stamp: newer))
        XCTAssertEqual(records.first?.authorName, "Tuur")
        XCTAssertEqual(records.first?.authorModifiedAt, newer)
        XCTAssertTrue(records.first?.words.isEmpty ?? false, "an author-only carrier has no words")

        let ipad = isolatedDefaults()
        switch AuthorSyncCore.reconcile(localName: AuthorSettings.name(defaults: ipad),
                                        localModifiedAt: AuthorSettings.modifiedAt(defaults: ipad),
                                        records: records, insert: { _ in XCTFail("no second carrier") }) {
        case .adoptRemote(let name, let ts): AuthorSettings.adoptSynced(name, modifiedAt: ts, defaults: ipad)
        default: XCTFail("the blank iPad must adopt")
        }
        XCTAssertEqual(AuthorSettings.name(defaults: ipad), "Tuur")
        XCTAssertEqual(AuthorSettings.modifiedAt(defaults: ipad), newer, "the remote stamp is kept")

        let input = CompilerInput(filename: "n.md", transcript: "Words.")
        let mac = Compiler.compile(input, author: "Tuur", date: "2026-10-03")
        let pad = Compiler.compile(input, author: AuthorSettings.name(defaults: ipad), date: "2026-10-03")
        XCTAssertEqual(mac, pad)
        XCTAssertTrue(pad.contains("\nauthor: Tuur\n"), pad)
    }

    // ── LWW ──

    func testRemoteNewerIsAdopted() {
        XCTAssertEqual(AuthorSyncCore.reconcile(localName: "Old", localModifiedAt: older,
                                                records: [carrier(name: "New", at: newer)],
                                                insert: { _ in XCTFail("no insert") }),
                       .adoptRemote(name: "New", modifiedAt: newer))
    }

    func testLocalNewerIsPushedOntoTheCarrier() {
        let r = carrier(name: "Old", at: older)
        XCTAssertEqual(AuthorSyncCore.reconcile(localName: "New", localModifiedAt: newer,
                                                records: [r], insert: { _ in XCTFail("no insert") }),
                       .pushedLocal(stamp: newer))
        XCTAssertEqual(r.authorName, "New")
        XCTAssertEqual(r.authorModifiedAt, newer)
        XCTAssertEqual(r.words, ["Skrift"], "the word list on the same row is untouched")
    }

    /// A blank cleared on purpose is a real edit and wins like any other.
    func testANewerDeliberateBlankWins() {
        XCTAssertEqual(AuthorSyncCore.reconcile(localName: "Tuur", localModifiedAt: older,
                                                records: [carrier(name: "", at: newer)],
                                                insert: { _ in }),
                       .adoptRemote(name: "", modifiedAt: newer))
    }

    /// A device that never set an author does not push its blank over a real name.
    func testUnstampedBlankNeverPushes() {
        let r = carrier(name: "Tuur", at: newer)
        XCTAssertEqual(AuthorSyncCore.reconcile(localName: "", localModifiedAt: .distantPast,
                                                records: [], insert: { _ in XCTFail("no insert") }), .noop)
        XCTAssertEqual(AuthorSyncCore.reconcile(localName: "", localModifiedAt: .distantPast,
                                                records: [r], insert: { _ in }),
                       .adoptRemote(name: "Tuur", modifiedAt: newer))
    }

    func testEqualStampsAreANoop() {
        XCTAssertEqual(AuthorSyncCore.reconcile(localName: "Tuur", localModifiedAt: newer,
                                                records: [carrier(name: "Tuur", at: newer)],
                                                insert: { _ in }), .noop)
    }

    // ── the local store ──

    func testSetStampsOnlyARealEditAndSeedDatesAnOldName() {
        let d = isolatedDefaults()
        AuthorSettings.set("Tuur", defaults: d, now: older)
        XCTAssertEqual(AuthorSettings.modifiedAt(defaults: d), older)
        AuthorSettings.set("Tuur", defaults: d, now: newer)
        XCTAssertEqual(AuthorSettings.modifiedAt(defaults: d), older, "same value: no new stamp")

        let legacy = isolatedDefaults()
        legacy.set("Tuur", forKey: AuthorSettings.key)
        AuthorSettings.seedStampIfNeeded(defaults: legacy, now: newer)
        XCTAssertEqual(AuthorSettings.modifiedAt(defaults: legacy), newer)

        let blank = isolatedDefaults()
        AuthorSettings.seedStampIfNeeded(defaults: blank, now: newer)
        XCTAssertEqual(AuthorSettings.modifiedAt(defaults: blank), .distantPast, "a blank is never seeded")
    }

    /// The Mac's settings.json written before the stamp existed still decodes.
    func testLegacyMacSettingsWithoutTheStampDecode() throws {
        let json = #"{"noteFolder":"/tmp/v","audioFolder":"","attachmentsFolder":"","authorName":"Tuur","#
            + #""enhancementModelRepo":"x","prompts":{"copyEdit":"a","summary":"b","title":"c"},"highpassFreqHz":80}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.authorName, "Tuur")
        XCTAssertNil(s.authorModifiedAt)
    }
}
