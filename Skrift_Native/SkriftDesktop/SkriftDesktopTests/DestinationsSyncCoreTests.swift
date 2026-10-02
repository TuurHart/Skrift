import XCTest
import SwiftData

/// Q98 / D162 — the "Separate destinations" switch syncs through the `VocabularyRecord`
/// carrier on its OWN stamp, last-write-wins. The portfolio folder is NOT part of it.
final class DestinationsSyncCoreTests: XCTestCase {

    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    private func carrier(enabled: Bool = false, at: Date = Date.distantPast,
                         wordsAt: Date = Date(timeIntervalSince1970: 1_000)) -> VocabularyRecord {
        VocabularyRecord(words: ["Skrift"], modifiedAt: wordsAt,
                         destinationsEnabled: enabled, destinationsModifiedAt: at)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "destsync_\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    // ── LWW ──

    func testRemoteNewerIsAdopted() {
        let r = carrier(enabled: true, at: newer)
        XCTAssertEqual(DestinationsSyncCore.reconcile(localEnabled: false, localModifiedAt: older,
                                                      records: [r], insert: { _ in XCTFail("no insert") }),
                       .adoptRemote(enabled: true, modifiedAt: newer))
    }

    func testRemoteOffNewerTurnsALocalOnOff() {
        let r = carrier(enabled: false, at: newer)
        XCTAssertEqual(DestinationsSyncCore.reconcile(localEnabled: true, localModifiedAt: older,
                                                      records: [r], insert: { _ in }),
                       .adoptRemote(enabled: false, modifiedAt: newer))
    }

    func testLocalNewerIsPushedOntoTheCarrier() {
        let r = carrier(enabled: false, at: older)
        XCTAssertEqual(DestinationsSyncCore.reconcile(localEnabled: true, localModifiedAt: newer,
                                                      records: [r], insert: { _ in }),
                       .pushedLocal(stamp: newer))
        XCTAssertTrue(r.destinationsEnabled)
        XCTAssertEqual(r.destinationsModifiedAt, newer)
    }

    func testEqualStampsDoNothing() {
        let r = carrier(enabled: true, at: newer)
        XCTAssertEqual(DestinationsSyncCore.reconcile(localEnabled: true, localModifiedAt: newer,
                                                      records: [r], insert: { _ in }), .noop)
    }

    /// A device that never touched the switch must not broadcast its default "off".
    func testADeviceThatNeverChoseAdoptsInsteadOfPushing() {
        let r = carrier(enabled: true, at: newer)
        XCTAssertEqual(DestinationsSyncCore.reconcile(localEnabled: false, localModifiedAt: .distantPast,
                                                      records: [r], insert: { _ in }),
                       .adoptRemote(enabled: true, modifiedAt: newer))
        XCTAssertTrue(r.destinationsEnabled, "the carrier is left alone")
    }

    func testNoOpinionAnywhereIsNoop() {
        XCTAssertEqual(DestinationsSyncCore.reconcile(localEnabled: false, localModifiedAt: .distantPast,
                                                      records: [carrier()], insert: { _ in }), .noop)
        XCTAssertEqual(DestinationsSyncCore.reconcile(localEnabled: false, localModifiedAt: .distantPast,
                                                      records: [], insert: { _ in XCTFail("no insert") }), .noop)
    }

    // ── no carrier yet ──

    /// Most people never edit custom words, so the switch must be able to create the row — with
    /// an EMPTY word list stamped `distantPast`, which can never beat anyone's real words.
    func testNoCarrierCreatesOneForARealLocalChoice() {
        var inserted: [VocabularyRecord] = []
        let out = DestinationsSyncCore.reconcile(localEnabled: true, localModifiedAt: newer,
                                                 records: [], insert: { inserted.append($0) })
        XCTAssertEqual(out, .pushedLocal(stamp: newer))
        XCTAssertEqual(inserted.count, 1)
        XCTAssertTrue(inserted[0].destinationsEnabled)
        XCTAssertEqual(inserted[0].destinationsModifiedAt, newer)
        XCTAssertTrue(inserted[0].words.isEmpty)
        XCTAssertEqual(inserted[0].modifiedAt, .distantPast, "never outranks a real word list")
    }

    /// The vocab reconcile must treat that switch-only row as "nothing to say" on a fresh device
    /// and as older than any real list.
    func testSwitchOnlyCarrierDoesNotClobberRealWords() {
        let switchOnly = VocabularyRecord(words: [], modifiedAt: .distantPast,
                                          destinationsEnabled: true, destinationsModifiedAt: newer)
        var inserted = 0
        let out = VocabularySyncCore.reconcile(localWords: ["alpha"], localModifiedAt: older,
                                               records: [switchOnly], insert: { _ in inserted += 1 },
                                               delete: { _ in })
        XCTAssertEqual(out, .pushedLocal(stamp: older, seededLocalStamp: false))
        XCTAssertEqual(switchOnly.words, ["alpha"])
        XCTAssertTrue(switchOnly.destinationsEnabled, "and the switch survives the words push")
        XCTAssertEqual(inserted, 0)
    }

    // ── independence from the other two settings ──

    func testWordsAndLanguageStampsDoNotMoveTheSwitch() {
        let r = VocabularyRecord(words: ["x"], modifiedAt: newer, multilingual: true,
                                 languageModifiedAt: newer, destinationsEnabled: false,
                                 destinationsModifiedAt: older)
        XCTAssertEqual(DestinationsSyncCore.reconcile(localEnabled: true, localModifiedAt: newer,
                                                      records: [r], insert: { _ in }),
                       .pushedLocal(stamp: newer))
        XCTAssertEqual(r.modifiedAt, newer)
        XCTAssertEqual(r.languageModifiedAt, newer)
        XCTAssertTrue(r.multilingual)
    }

    // ── the local store ──

    func testFlippingTheSwitchStampsIt() {
        let d = isolatedDefaults()
        XCTAssertFalse(DestinationSettings.storedEnabled(defaults: d))
        XCTAssertEqual(DestinationSettings.modifiedAt(defaults: d), .distantPast)
        DestinationSettings.set(true, defaults: d, now: newer)
        XCTAssertTrue(DestinationSettings.storedEnabled(defaults: d))
        XCTAssertEqual(DestinationSettings.modifiedAt(defaults: d), newer)
    }

    /// Re-applying the value already stored (what a synced value arriving does to a Settings
    /// binding) must not count as a fresh edit.
    func testSettingTheSameValueDoesNotRestamp() {
        let d = isolatedDefaults()
        DestinationSettings.adoptSynced(true, modifiedAt: older, defaults: d)
        DestinationSettings.set(true, defaults: d, now: newer)
        XCTAssertEqual(DestinationSettings.modifiedAt(defaults: d), older)
    }

    func testAdoptKeepsTheRemoteStamp() {
        let d = isolatedDefaults()
        DestinationSettings.adoptSynced(true, modifiedAt: older, defaults: d)
        XCTAssertTrue(DestinationSettings.storedEnabled(defaults: d))
        XCTAssertEqual(DestinationSettings.modifiedAt(defaults: d), older)
    }

    /// A device that had the switch ON before it synced has no stamp; it gets one so the choice
    /// propagates. An OFF device (the default) stays unstamped and never pushes.
    func testSeedStampOnlyForAnUnstampedOn() {
        let on = isolatedDefaults()
        on.set(true, forKey: "skrift.destinations.enabled")
        DestinationSettings.seedStampIfNeeded(defaults: on, now: newer)
        XCTAssertEqual(DestinationSettings.modifiedAt(defaults: on), newer)

        let off = isolatedDefaults()
        DestinationSettings.seedStampIfNeeded(defaults: off, now: newer)
        XCTAssertEqual(DestinationSettings.modifiedAt(defaults: off), .distantPast)
    }

    /// Two devices end to end through the core: A turns it on, B (off, never chose) adopts;
    /// then B turns it off LATER and A follows.
    func testTwoDevicesConverge() {
        let a = isolatedDefaults(), b = isolatedDefaults()
        var store: [VocabularyRecord] = []
        func run(_ d: UserDefaults) {
            switch DestinationsSyncCore.reconcile(
                localEnabled: DestinationSettings.storedEnabled(defaults: d),
                localModifiedAt: DestinationSettings.modifiedAt(defaults: d),
                records: store, insert: { store.append($0) }) {
            case .adoptRemote(let on, let ts): DestinationSettings.adoptSynced(on, modifiedAt: ts, defaults: d)
            case .pushedLocal, .noop: break
            }
        }
        DestinationSettings.set(true, defaults: a, now: older)
        run(a); run(b)
        XCTAssertTrue(DestinationSettings.storedEnabled(defaults: b))
        DestinationSettings.set(false, defaults: b, now: newer)
        run(b); run(a)
        XCTAssertFalse(DestinationSettings.storedEnabled(defaults: a))
        XCTAssertEqual(store.count, 1)
    }
}
