import XCTest
import SwiftData
@testable import SkriftMobile

/// Phase 1f: the custom-vocabulary list syncs across devices via a CloudKit
/// `VocabularyRecord` carrier, LWW by `modifiedAt` (so a delete propagates). The
/// store stays UserDefaults-backed for the booster's synchronous reads; tests inject
/// an isolated suite. SwiftData is in-memory (CloudKit `.none`).
@MainActor
final class VocabularyCloudSyncTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "vocabtest_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFirstSyncPushesLocalListToCarrier() {
        let repo = NotesRepository(inMemory: true)
        CustomVocabularyStore.save(["Skrift", "Parakeet"], defaults: defaults)

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(repo.allVocabularyRecords().count, 1)
        XCTAssertEqual(repo.allVocabularyRecords().first?.words, ["Skrift", "Parakeet"])
    }

    func testNewerCarrierAdoptedLocally() {
        let repo = NotesRepository(inMemory: true)
        CustomVocabularyStore.save(["old"], defaults: defaults)            // local ts ≈ now
        repo.context.insert(VocabularyRecord(words: ["alpha", "beta"],
                                             modifiedAt: Date().addingTimeInterval(100)))   // remote newer
        repo.save()

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(CustomVocabularyStore.words(defaults: defaults), ["alpha", "beta"])
    }

    func testNewerLocalPushedToCarrier() {
        let repo = NotesRepository(inMemory: true)
        repo.context.insert(VocabularyRecord(words: ["stale"], modifiedAt: .distantPast))   // remote older
        repo.save()
        CustomVocabularyStore.save(["x", "y"], defaults: defaults)         // local ts ≈ now (newer)

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(repo.allVocabularyRecords().count, 1)
        XCTAssertEqual(repo.allVocabularyRecords().first?.words, ["x", "y"])
    }

    func testDuplicateCarriersCollapseToNewest() {
        let repo = NotesRepository(inMemory: true)
        CustomVocabularyStore.save(["local"], defaults: defaults)
        repo.context.insert(VocabularyRecord(words: ["older"], modifiedAt: Date().addingTimeInterval(50)))
        repo.context.insert(VocabularyRecord(words: ["newest"], modifiedAt: Date().addingTimeInterval(500)))
        repo.save()

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(repo.allVocabularyRecords().count, 1, "duplicate carriers collapse")
        XCTAssertEqual(CustomVocabularyStore.words(defaults: defaults), ["newest"], "newest carrier wins")
    }

    // MARK: - Empty-carrier clobber guard (regression)

    /// A fresh device (no words, never edited) must NOT create an empty carrier — an
    /// empty-@-now would LWW-clobber another device's real words once it syncs.
    func testFreshDeviceDoesNotCreateEmptyCarrier() {
        let repo = NotesRepository(inMemory: true)   // no words saved, no carrier
        VocabularyCloudSync.run(repo, defaults: defaults)
        XCTAssertTrue(repo.allVocabularyRecords().isEmpty, "fresh device must wait to receive, not push empty")
    }

    /// The fresh device then RECEIVES another device's words and adopts them without
    /// wiping the incoming carrier — the scenario that was losing the phone's words.
    func testFreshDeviceAdoptsIncomingWordsWithoutClobber() {
        let repo = NotesRepository(inMemory: true)   // local: empty + distantPast
        repo.context.insert(VocabularyRecord(words: ["Skrift", "Parakeet"], modifiedAt: Date()))
        repo.save()

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(CustomVocabularyStore.words(defaults: defaults), ["Skrift", "Parakeet"])
        XCTAssertEqual(repo.allVocabularyRecords().count, 1)
        XCTAssertEqual(repo.allVocabularyRecords().first?.words, ["Skrift", "Parakeet"], "incoming words not clobbered")
    }

    /// But a genuine "I deleted all my words" (empty list that WAS edited) still
    /// propagates the deletion up.
    func testDeletedAllWordsStillPropagates() {
        let repo = NotesRepository(inMemory: true)
        CustomVocabularyStore.save([], defaults: defaults)   // edited → empty, ts = now

        VocabularyCloudSync.run(repo, defaults: defaults)

        XCTAssertEqual(repo.allVocabularyRecords().count, 1, "a deliberate empty list still syncs the deletion")
        XCTAssertEqual(repo.allVocabularyRecords().first?.words, [])
    }
}
