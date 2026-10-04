import XCTest
@testable import SkriftMobile

/// The unrated-note model, phone side (locked with Tuur 2026-07-26):
/// **the rating is CONSENT — until you've judged a note, Skrift spends nothing on it
/// and shows it nowhere but back to you.** These pin the two places the phone used to
/// disagree with that.
@MainActor
final class UnratedConsentTests: XCTestCase {

    // ── the idea graph is consent-gated (round 5) ──

    /// Unrated notes must not appear as candidates in ANY other note's Related.
    /// Excluding them at INDEX time (not query time) also means their embedding is
    /// never paid for — and `EmbeddingIndex.sweep`'s orphan pass deletes the rows of
    /// a note whose rating goes back to 0.
    func testUnratedMemosAreNotIndexed() {
        let repo = NotesRepository(inMemory: true)
        let rated = Memo(title: "Rated", transcript: "The harbor at dawn.", significance: 0.5)
        let unrated = Memo(title: "Unrated", transcript: "A passing thought.", significance: 0)
        repo.context.insert(rated)
        repo.context.insert(unrated)
        repo.save()

        let ids = Set(JournalIndexService.snapshots(from: repo).map(\.id))
        XCTAssertTrue(ids.contains(rated.id))
        XCTAssertFalse(ids.contains(unrated.id),
                       "an unjudged note never joins the idea graph — in either direction")
    }

    /// …and a note that gets rated joins on the next sweep, with no other change.
    func testRatingANoteAdmitsItToTheIndex() {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(title: "Later rated", transcript: "Worth keeping after all.", significance: 0)
        repo.context.insert(memo)
        repo.save()
        XCTAssertFalse(Set(JournalIndexService.snapshots(from: repo).map(\.id)).contains(memo.id))

        memo.significance = 0.3
        repo.save()
        XCTAssertTrue(Set(JournalIndexService.snapshots(from: repo).map(\.id)).contains(memo.id))
    }

    // ── export is rated-only, everywhere ──

    /// The "All notes" option is gone from Settings, but a device that had STORED it
    /// must not keep publishing unrated notes — the gate asks `NoteConsent.isRated`
    /// unconditionally and never reads the old key. A vault folder is configured so `.live`
    /// gets past the folder gate: the refusal must be the UNRATED gate itself, and a rated
    /// control must get past it.
    func testLivePublishPolicyIsRatedOnlyRegardlessOfStoredSetting() throws {
        let bookmarkKey = "skrift.obsidian.vaultBookmark"
        let savedBookmark = UserDefaults.standard.data(forKey: bookmarkKey)
        UserDefaults.standard.set("all", forKey: "skrift.publish.policy")
        UserDefaults.standard.set(true, forKey: "skrift.publish.whenPaired")
        defer {
            UserDefaults.standard.removeObject(forKey: "skrift.publish.policy")
            UserDefaults.standard.removeObject(forKey: "skrift.publish.whenPaired")
            if let savedBookmark { UserDefaults.standard.set(savedBookmark, forKey: bookmarkKey) }
            else { UserDefaults.standard.removeObject(forKey: bookmarkKey) }
        }
        try ObsidianVault.setVault(makeTempDir())
        XCTAssertTrue(ObsidianVault.isConfigured, "the folder gate must be passed for this test to mean anything")

        let coordinator = PublishCoordinator.live(author: "T")
        let unrated = Memo(title: "T", transcript: "x", significance: 0)
        XCTAssertEqual(coordinator.gateFailure(unrated), .unrated,
                       "a stale stored 'all' must not resurrect unrated export")
        XCTAssertFalse(coordinator.shouldPublish(unrated))

        let rated = Memo(title: "T", transcript: "x", significance: 0.5)
        XCTAssertNotEqual(coordinator.gateFailure(rated), .unrated,
                          "control: a rated note passes the rated gate (it may still await processing)")
    }

    // ── the panel surface is consent-gated too (round 5: "own panel NO") ──

    /// An unrated note offers no Connections summon — the claim surface waits
    /// for the rating, exactly like membership in others' Related. Locked
    /// stays its own veto.
    func testUnratedNoteCannotSummonConnections() {
        let unrated = Memo(transcript: "A passing thought.", significance: 0)
        let rated = Memo(transcript: "The harbor at dawn.", significance: 0.5)
        XCTAssertFalse(ConnectionsPanelLogic.canSummon(unrated, isLocked: false))
        XCTAssertTrue(ConnectionsPanelLogic.canSummon(rated, isLocked: false))
        XCTAssertFalse(ConnectionsPanelLogic.canSummon(rated, isLocked: true),
                       "locked keeps its own veto")
    }

    // ── ONE predicate (2026-07-28 consolidation): every gate above asks NoteConsent ──

    /// The shared value table, pinned from the phone bundle too — the phone's
    /// dim rows, filter chips, index gate and publish gate all route through it.
    func testNoteConsentValueTable() {
        XCTAssertFalse(NoteConsent.isRated(nil))
        XCTAssertFalse(NoteConsent.isRated(0))
        XCTAssertTrue(NoteConsent.isRated(0.1))
        XCTAssertTrue(NoteConsent.isRated(1.0))
        XCTAssertFalse(NoteConsent.isRated(Memo(significance: 0)))
        XCTAssertTrue(NoteConsent.isRated(Memo(significance: 0.5)))
    }
}
