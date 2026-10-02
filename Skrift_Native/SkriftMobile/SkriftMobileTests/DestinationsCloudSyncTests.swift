import XCTest
import SwiftData
@testable import SkriftMobile

/// Q98 / D162 — the phone adapter: the "Separate destinations" switch round-trips through the
/// `VocabularyRecord` carrier (LWW by its own stamp), without touching the portfolio folder.
@MainActor
final class DestinationsCloudSyncTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    override func setUpWithError() throws {
        suiteName = "destsync_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testTurningItOnPushesToANewCarrier() {
        let repo = NotesRepository(inMemory: true)
        DestinationSettings.set(true, defaults: defaults, now: newer)

        VocabularyCloudSync.run(repo, defaults: defaults)

        let records = repo.allVocabularyRecords()
        XCTAssertEqual(records.count, 1, "a switch-only carrier is created")
        XCTAssertEqual(records.first?.destinationsEnabled, true)
        XCTAssertEqual(records.first?.destinationsModifiedAt, newer)
        XCTAssertTrue(records.first?.words.isEmpty ?? false)
    }

    func testANewerRemoteOnIsAdopted() {
        let repo = NotesRepository(inMemory: true)
        repo.context.insert(VocabularyRecord(words: [], modifiedAt: .distantPast,
                                             destinationsEnabled: true, destinationsModifiedAt: newer))
        repo.save()

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertTrue(DestinationSettings.storedEnabled(defaults: defaults))
        XCTAssertEqual(DestinationSettings.modifiedAt(defaults: defaults), newer)
    }

    func testANewerRemoteOffTurnsTheLocalOnOff() {
        let repo = NotesRepository(inMemory: true)
        DestinationSettings.set(true, defaults: defaults, now: older)
        repo.context.insert(VocabularyRecord(words: [], modifiedAt: .distantPast,
                                             destinationsEnabled: false, destinationsModifiedAt: newer))
        repo.save()

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertFalse(DestinationSettings.storedEnabled(defaults: defaults))
    }

    func testANewerLocalFlipWinsOverTheCarrier() {
        let repo = NotesRepository(inMemory: true)
        repo.context.insert(VocabularyRecord(words: [], modifiedAt: .distantPast,
                                             destinationsEnabled: true, destinationsModifiedAt: older))
        repo.save()
        DestinationSettings.adoptSynced(true, modifiedAt: older, defaults: defaults)
        DestinationSettings.set(false, defaults: defaults, now: newer)

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(repo.allVocabularyRecords().first?.destinationsEnabled, false)
        XCTAssertEqual(repo.allVocabularyRecords().first?.destinationsModifiedAt, newer)
    }

    /// A device that already had the switch on before this synced (no stamp) pushes it.
    func testAnUnstampedOnFromBeforeSyncPropagates() {
        let repo = NotesRepository(inMemory: true)
        defaults.set(true, forKey: "skrift.destinations.enabled")

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(repo.allVocabularyRecords().first?.destinationsEnabled, true)
    }

    /// The switch and the word list share one row but never clobber each other.
    func testSwitchAndWordsCoexistOnOneCarrier() {
        let repo = NotesRepository(inMemory: true)
        CustomVocabularyStore.save(["Skrift"], defaults: defaults)
        DestinationSettings.set(true, defaults: defaults, now: newer)

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(repo.allVocabularyRecords().count, 1)
        XCTAssertEqual(repo.allVocabularyRecords().first?.words, ["Skrift"])
        XCTAssertEqual(repo.allVocabularyRecords().first?.destinationsEnabled, true)
    }

    /// The folder bookmark is per device: syncing the switch never writes or clears it.
    func testTheSwitchNeverTouchesThePortfolioFolderKey() {
        let repo = NotesRepository(inMemory: true)
        defaults.set(Data([1, 2, 3]), forKey: DestinationSettings.portfolioRootKey)
        repo.context.insert(VocabularyRecord(words: [], modifiedAt: .distantPast,
                                             destinationsEnabled: true, destinationsModifiedAt: newer))
        repo.save()

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(defaults.data(forKey: DestinationSettings.portfolioRootKey), Data([1, 2, 3]))
    }
}
