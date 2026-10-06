import Foundation
import UserNotifications

/// The slice of `UNUserNotificationCenter` the reminder cleanup needs (a fake in tests).
protocol ReminderCleanupCenter {
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
    func removePending(_ ids: [String])
    func removeDelivered(_ ids: [String])
}

/// D185: note reminders were removed (phone, iPad, Mac). The synced `Memo.remindAt` stays in
/// the model, unused. This is the one-time cleanup of what the old `ReminderScheduler` left in
/// the system notification centre: pending requests and delivered banners whose identifier
/// carries the reminder prefix. Every other notification (the wall-queue notice, FeedbackKit's)
/// is left alone.
enum ReminderCleanup {
    /// The identifier scheme the removed `ReminderScheduler` used: `memo-reminder-<memo UUID>`.
    static let idPrefix = "memo-reminder-"
    static let doneKey = "d185.remindersCleanedUp"

    /// The reminder identifiers among `ids`, nothing else.
    static func reminderIDs(in ids: [String]) -> [String] {
        ids.filter { $0.hasPrefix(idPrefix) }
    }

    struct SystemCenter: ReminderCleanupCenter {
        func pendingIdentifiers() async -> [String] {
            await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
        }
        func deliveredIdentifiers() async -> [String] {
            await UNUserNotificationCenter.current().deliveredNotifications().map(\.request.identifier)
        }
        func removePending(_ ids: [String]) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
        func removeDelivered(_ ids: [String]) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    /// Remove every pending + delivered reminder notification. Returns how many were removed.
    @discardableResult
    static func purge(from center: ReminderCleanupCenter) async -> Int {
        let pending = reminderIDs(in: await center.pendingIdentifiers())
        let delivered = reminderIDs(in: await center.deliveredIdentifiers())
        if !pending.isEmpty { center.removePending(pending) }
        if !delivered.isEmpty { center.removeDelivered(delivered) }
        return pending.count + delivered.count
    }

    /// First launch after the update: purge once, then never again.
    static func runOnce(center: ReminderCleanupCenter = SystemCenter(), defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        Task {
            let n = await purge(from: center)
            if n > 0 { DevLog.log("D185: removed \(n) reminder notification(s)") }
        }
    }
}

/// Keeps notifications visible while the app is open (the wall-queue notice relied on the
/// delegate the removed `ReminderScheduler` installed). No tap routing: nothing opens a note
/// from a notification any more.
final class ForegroundBanner: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundBanner()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
