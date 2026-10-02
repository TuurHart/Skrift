import XCTest
import SwiftData
@testable import SkriftMobile

/// Q158 (C62, D162), the phone/iPad adapter: the export author round-trips through the
/// `VocabularyRecord` carrier (LWW by its own stamp) via `VocabularyCloudSync`, so an iPad that
/// never typed a name exports the Mac's.
@MainActor
final class AuthorSyncTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    override func setUpWithError() throws {
        suiteName = "authorsync_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// Typed here → pushed to a new carrier → a second device adopts it.
    func testRoundTripThroughTheCarrier() {
        let repo = NotesRepository(inMemory: true)
        AuthorSettings.set("Tuur", defaults: defaults, now: newer)

        VocabularyCloudSync.run(repo, defaults: defaults)

        let records = repo.allVocabularyRecords()
        XCTAssertEqual(records.count, 1, "an author-only carrier is created")
        XCTAssertEqual(records.first?.authorName, "Tuur")
        XCTAssertEqual(records.first?.authorModifiedAt, newer)

        let other = UserDefaults(suiteName: suiteName + "_b")!
        defer { other.removePersistentDomain(forName: suiteName + "_b") }
        VocabularyCloudSync.run(repo, defaults: other)
        XCTAssertEqual(AuthorSettings.name(defaults: other), "Tuur")
        XCTAssertEqual(AuthorSettings.modifiedAt(defaults: other), newer)
    }

    func testANewerRemoteNameIsAdopted() {
        let repo = NotesRepository(inMemory: true)
        AuthorSettings.set("Old", defaults: defaults, now: older)
        repo.context.insert(VocabularyRecord(words: [], modifiedAt: .distantPast,
                                             authorName: "Tuur", authorModifiedAt: newer))
        repo.save()

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(AuthorSettings.name(defaults: defaults), "Tuur")
    }

    func testANewerLocalEditWinsOverTheCarrier() {
        let repo = NotesRepository(inMemory: true)
        repo.context.insert(VocabularyRecord(words: [], modifiedAt: .distantPast,
                                             authorName: "Old", authorModifiedAt: older))
        repo.save()
        AuthorSettings.set("Tuur", defaults: defaults, now: newer)

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(repo.allVocabularyRecords().first?.authorName, "Tuur")
        XCTAssertEqual(repo.allVocabularyRecords().first?.authorModifiedAt, newer)
    }

    /// An iPad that never typed a name does not push its blank over the Mac's.
    func testABlankNeverOverwritesARealName() {
        let repo = NotesRepository(inMemory: true)
        repo.context.insert(VocabularyRecord(words: [], modifiedAt: .distantPast,
                                             authorName: "Tuur", authorModifiedAt: older))
        repo.save()

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(repo.allVocabularyRecords().first?.authorName, "Tuur")
        XCTAssertEqual(AuthorSettings.name(defaults: defaults), "Tuur")
    }

    /// The author and the destinations switch share one row but never clobber each other.
    func testAuthorAndSwitchCoexistOnOneCarrier() {
        let repo = NotesRepository(inMemory: true)
        DestinationSettings.set(true, defaults: defaults, now: newer)
        AuthorSettings.set("Tuur", defaults: defaults, now: newer)

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(repo.allVocabularyRecords().count, 1)
        XCTAssertEqual(repo.allVocabularyRecords().first?.destinationsEnabled, true)
        XCTAssertEqual(repo.allVocabularyRecords().first?.authorName, "Tuur")
    }
}
