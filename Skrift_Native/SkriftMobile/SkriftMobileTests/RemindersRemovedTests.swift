import XCTest
import UserNotifications
@testable import SkriftMobile

/// D185 — note reminders are gone. `Memo.remindAt` stays in the model (CloudKit + older
/// builds) but nothing schedules a notification for it, the launch cleanup removes the old
/// reminder notifications and only those, and a note carrying a `remindAt` fades like any other.
@MainActor
final class RemindersRemovedTests: XCTestCase {

    // MARK: fake notification centre

    private final class FakeCenter: ReminderCleanupCenter {
        var pending: [String]
        var delivered: [String]
        var removedPending: [String] = []
        var removedDelivered: [String] = []
        init(pending: [String], delivered: [String]) { self.pending = pending; self.delivered = delivered }
        func pendingIdentifiers() async -> [String] { pending }
        func deliveredIdentifiers() async -> [String] { delivered }
        func removePending(_ ids: [String]) {
            removedPending += ids; pending.removeAll { ids.contains($0) }
        }
        func removeDelivered(_ ids: [String]) {
            removedDelivered += ids; delivered.removeAll { ids.contains($0) }
        }
    }

    private let reminderA = "memo-reminder-" + UUID().uuidString
    private let reminderB = "memo-reminder-" + UUID().uuidString

    // MARK: the launch cleanup

    func testCleanupRemovesOnlyReminderIdentifiers() async {
        let center = FakeCenter(
            pending: [reminderA, "wall-queue", "feedback-reply", reminderB],
            delivered: [reminderB, "wall-queue", "some-other-banner"])
        let removed = await ReminderCleanup.purge(from: center)
        XCTAssertEqual(removed, 3)
        XCTAssertEqual(Set(center.removedPending), [reminderA, reminderB])
        XCTAssertEqual(center.removedDelivered, [reminderB])
        XCTAssertEqual(Set(center.pending), ["wall-queue", "feedback-reply"], "other pending kept")
        XCTAssertEqual(Set(center.delivered), ["wall-queue", "some-other-banner"], "other delivered kept")
    }

    func testCleanupWithNothingToRemoveTouchesNothing() async {
        let center = FakeCenter(pending: ["wall-queue"], delivered: ["feedback-reply"])
        let removed = await ReminderCleanup.purge(from: center)
        XCTAssertEqual(removed, 0)
        XCTAssertTrue(center.removedPending.isEmpty)
        XCTAssertTrue(center.removedDelivered.isEmpty)
    }

    func testReminderIDsMatchTheOldSchemeExactly() {
        XCTAssertEqual(
            ReminderCleanup.reminderIDs(in: [reminderA, "wall-queue", "memo-reminders", "x-memo-reminder-1"]),
            [reminderA])
    }

    func testRunOncePurgesOnFirstLaunchOnly() async throws {
        let suite = "d185.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

        let first = FakeCenter(pending: [reminderA], delivered: [])
        ReminderCleanup.runOnce(center: first, defaults: defaults)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(first.removedPending, [reminderA], "first launch after the update purges")

        let second = FakeCenter(pending: [reminderB], delivered: [])
        ReminderCleanup.runOnce(center: second, defaults: defaults)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(second.removedPending.isEmpty, "later launches never purge again")
    }

    // MARK: nothing schedules a reminder any more

    func testNoSweepSchedulesANotificationForRemindAt() async throws {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(audioFilename: "", transcript: "call the plumber", transcriptStatus: .done)
        memo.remindAt = Date().addingTimeInterval(3600)
        repo.insert(memo)

        let cp = AssetCaptureCheckpoint(defaults: UserDefaults(suiteName: "d185.\(UUID().uuidString)")!, key: "cp")
        await LaunchSweeps.launch(repo, checkpoint: cp).value
        await LaunchSweeps.foreground(repo, checkpoint: cp).task.value
        await LaunchSweeps.importBurst(repo, checkpoint: cp).value
        CloudSyncMonitor.runMemoSweeps(repo)
        try await Task.sleep(nanoseconds: 500_000_000)   // the old scheduler hopped to a Task

        let pending = await center.pendingNotificationRequests().map(\.identifier)
        XCTAssertTrue(ReminderCleanup.reminderIDs(in: pending).isEmpty,
                      "no reminder notification may be scheduled for remindAt — got \(pending)")
    }

    // MARK: lifecycle

    func testNoteWithRemindAtFadesLikeAnyOther() {
        let now = Date()
        let old = now.addingTimeInterval(-90 * 86_400)
        let plain = Memo(audioFilename: "m.m4a", recordedAt: old, transcript: "words", transcriptStatus: .done)
        let reminded = Memo(audioFilename: "m.m4a", recordedAt: old, transcript: "words", transcriptStatus: .done)
        reminded.remindAt = now.addingTimeInterval(86_400)   // even a FUTURE reminder
        XCTAssertTrue(MemoLifecycle.isFading(plain, backlinked: [], now: now))
        XCTAssertTrue(MemoLifecycle.isFading(reminded, backlinked: [], now: now),
                      "remindAt no longer holds a note off the fade clock")
        XCTAssertNil(MemoSpine.holdReason(of: reminded, backlinked: []))
    }
}
