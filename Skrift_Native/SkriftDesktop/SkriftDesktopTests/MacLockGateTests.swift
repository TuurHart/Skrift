import XCTest
import Foundation

/// Q100 — the Mac list honours the lock (C91/C161/C213, R88): a locked note renders the
/// "Locked note" placeholder, stays IN the list when never rated, and deleting / unlocking
/// it asks the shared `LockPolicy` (the same one the phone's `deleteMemo` / `toggleLock`
/// now call). Host-less: the policy is closure-injected, so no LocalAuthentication here.
/// Synthetic notes only.
@MainActor
final class MacLockGateTests: XCTestCase {

    private let now = Date()

    private func memo(significance: Double, locked: Bool, title: String? = nil,
                      transcript: String? = "a private thought about the thing") -> Memo {
        let id = UUID()
        let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: now.addingTimeInterval(-86_400),
                     title: title, transcript: transcript, transcriptStatus: .done,
                     significance: significance)
        m.locked = locked
        return m
    }

    /// A policy with scripted answers; counts how often auth was asked.
    private final class Probe {
        var unlocked: Set<String> = []
        var canAuth = true
        var authOK = true
        var authAsks = 0
        func policy() -> LockPolicy {
            LockPolicy(
                isUnlocked: { [unowned self] in unlocked.contains($0) },
                unlock: { [unowned self] id in
                    authAsks += 1
                    guard authOK else { return false }
                    unlocked.insert(id)
                    return true
                },
                canAuthenticate: { [unowned self] in canAuth },
                authorizeRemoveLock: { [unowned self] in authAsks += 1; return authOK })
        }
    }

    // MARK: - list membership (list-sidebar-73)

    func testLockedUnratedNoteStaysInTheListAsALockedRow() {
        let m = memo(significance: 0, locked: true)
        XCTAssertTrue(WayOutRules.unpipelined(memos: [m], files: []).isEmpty,
                      "a resolved locked note still doesn't nag the band / counts")
        XCTAssertEqual(WayOutRules.lockedQuiet(memos: [m], files: []).map(\.id), [m.id],
                       "but it must stay in the list — locking must not make the row vanish")
    }

    func testLockedQuietExcludesRatedUnlockedAndDeleted() {
        let rated = memo(significance: 0.4, locked: true)
        let plain = memo(significance: 0, locked: false)
        let trashed = memo(significance: 0, locked: true)
        trashed.deletedAt = now
        XCTAssertTrue(WayOutRules.lockedQuiet(memos: [rated, plain, trashed], files: []).isEmpty)
    }

    func testSearchNeverRevealsALockedNotesWords() {
        let m = memo(significance: 0, locked: true, title: "Groceries")
        XCTAssertTrue(WayOutRules.matchesSearch(m, query: "grocer"), "its title still matches")
        XCTAssertFalse(WayOutRules.matchesSearch(m, query: "private thought"), "its words must not")
        let untitled = memo(significance: 0, locked: true)
        XCTAssertFalse(WayOutRules.matchesSearch(untitled, query: "private"),
                       "the first-line title fallback is its words too")
    }

    // MARK: - the row (list-sidebar-72)

    func testLockedRowShowsTitleAndLockOnly_unrated() {
        let m = memo(significance: 0, locked: true)
        let card = LockedRow.card(stamp: "Today", title: LockedRow.title(for: m), selected: false, quiet: true)
        XCTAssertTrue(card.locked)
        XCTAssertEqual(card.title, "Locked note", "never the first line of the transcript")
        XCTAssertNil(card.balls)
        XCTAssertNil(card.snippet)
        XCTAssertTrue(card.chips.isEmpty)
        XCTAssertNil(card.quote)
    }

    func testLockedRowShowsTitleAndLockOnly_rated() {
        let pf = PipelineFile(id: UUID().uuidString, filename: "x.m4a", sourceType: .audio, uploadedAt: now)
        pf.locked = true
        pf.significance = 0.7
        pf.transcript = "a private thought about the thing"
        XCTAssertEqual(LockedRow.title(for: pf), "Locked note")
        pf.enhancedTitle = "  Groceries  "
        XCTAssertEqual(LockedRow.title(for: pf), "Groceries", "an explicit title is allowed (the phone's rule)")
        let card = LockedRow.card(stamp: "Today", title: LockedRow.title(for: pf), selected: true, quiet: false)
        XCTAssertTrue(card.locked)
        XCTAssertNil(card.balls, "a rated locked note shows no balls")
        XCTAssertNil(card.snippet)
        XCTAssertTrue(card.chips.isEmpty)
        XCTAssertTrue(card.selected)
    }

    // MARK: - delete asks the gate (list-sidebar-87)

    func testDeletingALockedNoteAsksForAuthAndRefusedAuthKeepsIt() async {
        let m = memo(significance: 0, locked: true)
        let probe = Probe()
        probe.authOK = false
        let allowed = await probe.policy().authorizeDelete(id: m.id.uuidString, locked: m.locked)
        XCTAssertFalse(allowed)
        XCTAssertEqual(probe.authAsks, 1)
    }

    func testDeletingALockedNoteProceedsAfterAuthAndNotAskedTwice() async {
        let m = memo(significance: 0.5, locked: true)
        let probe = Probe()
        let first = await probe.policy().authorizeDelete(id: m.id.uuidString, locked: true)
        let second = await probe.policy().authorizeDelete(id: m.id.uuidString, locked: true)
        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(probe.authAsks, 1, "unlocked for the session — no second prompt")
    }

    func testDeletingAnUnlockedNoteNeverAsks() async {
        let probe = Probe()
        let ok = await probe.policy().authorizeDelete(id: UUID().uuidString, locked: false)
        XCTAssertTrue(ok)
        XCTAssertEqual(probe.authAsks, 0)
    }

    // MARK: - toggleLock (list-sidebar-88, setexp-96)

    func testUnlockNeedsAuthAndKeepsLockWhenRefused() async {
        let m = memo(significance: 0, locked: true)
        let probe = Probe()
        probe.authOK = false
        let removed = await probe.policy().removeLock(m)
        XCTAssertFalse(removed)
        XCTAssertTrue(m.locked, "refused auth leaves the note locked")
        XCTAssertEqual(probe.authAsks, 1)
    }

    func testUnlockAfterAuthClearsLockAndMarksEdited() async {
        let m = memo(significance: 0, locked: true)
        let before = m.editedAt
        let probe = Probe()
        let removed = await probe.policy().removeLock(m)
        XCTAssertTrue(removed)
        XCTAssertFalse(m.locked)
        XCTAssertNotEqual(m.editedAt, before, "markEdited so the unlock syncs (LWW)")
    }

    func testLockNeedsADeviceThatCanAuthenticate() {
        let m = memo(significance: 0, locked: false)
        let probe = Probe()
        probe.canAuth = false
        XCTAssertFalse(probe.policy().lock(m))
        XCTAssertFalse(m.locked, "no passcode ⇒ locking would brick the note here")
        probe.canAuth = true
        XCTAssertTrue(probe.policy().lock(m))
        XCTAssertTrue(m.locked)
        XCTAssertEqual(probe.authAsks, 0, "locking itself is instant, no auth")
    }

    func testLockMarksEditedWithoutStampingWords() {
        let m = memo(significance: 0, locked: false)
        m.editedAt = .distantPast
        _ = Probe().policy().lock(m)
        XCTAssertGreaterThan(m.editedAt ?? .distantPast, Date.distantPast.addingTimeInterval(1))
    }

    // MARK: - vault notice (list-sidebar-88)

    func testNoVaultMeansNoAlreadyInYourVaultNotice() {
        var s = AppSettings()
        s.noteFolder = ""
        XCTAssertFalse(LockVaultNotice.hasPublished(UUID(), settings: s))
    }
}
