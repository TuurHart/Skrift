import Foundation
import UserNotifications

/// Note reminders (note feature wave, chunk 7 — design signed off 2026-07-06):
/// the reminder is DATA (`Memo.remindAt`, a shared-model field that syncs over
/// CloudKit like everything else); the ALARM is derived, per device — each
/// device reconciles its local `UNUserNotificationCenter` requests from the
/// synced field, so setting a reminder on the Mac rings the phone and clearing
/// it anywhere silences every device. No server, fully offline; macOS uses the
/// SAME framework (its reconciler is the owed half).
enum ReminderPlan {
    static let idPrefix = "memo-reminder-"

    struct Entry: Equatable {
        let memoID: UUID
        let fireAt: Date
    }

    /// What SHOULD be scheduled: live memos with a FUTURE remindAt. Past dates
    /// are inert data (never scheduled — no fire-immediately storms), trashed
    /// memos ring nowhere.
    static func desired(memos: [(id: UUID, remindAt: Date?, deleted: Bool)], now: Date) -> [Entry] {
        memos.compactMap { memo in
            guard !memo.deleted, let at = memo.remindAt, at > now else { return nil }
            return Entry(memoID: memo.id, fireAt: at)
        }
    }

    /// Reconcile desired vs pending: `add` (new or date changed — re-add replaces),
    /// `remove` (no longer desired, or rescheduled).
    static func diff(desired: [Entry],
                     pending: [(id: String, fireAt: Date?)]) -> (add: [Entry], remove: [String]) {
        let desiredByID = Dictionary(desired.map { (idPrefix + $0.memoID.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        var add: [Entry] = []
        var remove: [String] = []
        var seen = Set<String>()
        for p in pending where p.id.hasPrefix(idPrefix) {
            seen.insert(p.id)
            guard let want = desiredByID[p.id] else { remove.append(p.id); continue }
            // Same memo, different time → replace.
            if let at = p.fireAt, abs(at.timeIntervalSince(want.fireAt)) > 1 {
                remove.append(p.id)
                add.append(want)
            }
        }
        add.append(contentsOf: desired.filter { !seen.contains(idPrefix + $0.memoID.uuidString) })
        return (add, remove)
    }
}

@MainActor
enum ReminderScheduler {
    /// Ask once, when the user first SETS a reminder (never at launch).
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Idempotent reconcile — call on launch, foreground, sync-settle, and
    /// after set/clear (the same cadence as the other sweeps).
    static func run(_ repository: NotesRepository) {
        let memos = repository.allMemosIncludingTrashed().map {
            (id: $0.id, remindAt: $0.remindAt, deleted: $0.deletedAt != nil)
        }
        let titles: [UUID: String] = Dictionary(
            repository.allMemos().map { ($0.id, $0.title ?? $0.firstTranscriptLine ?? "A note") },
            uniquingKeysWith: { a, _ in a })
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests().map { req in
                (id: req.identifier,
                 fireAt: (req.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
            }
            let (add, remove) = ReminderPlan.diff(
                desired: ReminderPlan.desired(memos: memos, now: Date()),
                pending: pending)
            if !remove.isEmpty { center.removePendingNotificationRequests(withIdentifiers: remove) }
            for entry in add {
                let content = UNMutableNotificationContent()
                content.title = String((titles[entry.memoID] ?? "A note").prefix(60))
                content.body = "You asked Skrift to remind you about this note."
                content.sound = .default
                content.userInfo = ["memoID": entry.memoID.uuidString]
                let comps = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: entry.fireAt)
                let request = UNNotificationRequest(
                    identifier: ReminderPlan.idPrefix + entry.memoID.uuidString,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                try? await center.add(request)
            }
            if !add.isEmpty || !remove.isEmpty {
                DevLog.log("reminders: reconciled +\(add.count) −\(remove.count)")
            }
        }
    }

    // MARK: - Tap routing + foreground presentation

    /// Install once at launch (AppDelegate): a tapped reminder opens its memo
    /// via `MemoOpenBridge`; a reminder firing while the app is OPEN still
    /// shows a banner.
    static let delegate = Delegate()

    /// @MainActor: the async delegate variants otherwise RESUME UIKit's internal
    /// completion on the cooperative pool — UIKit then runs its state-restoration
    /// snapshot off-main and trips the main-thread assert in
    /// `_performBlockAfterCATransactionCommitSynchronizes` (device crash
    /// 2026-07-07 18:00, build 39: reminder tapped as the app was snapshotting).
    /// Isolating the class makes the thunk hop to main before the body AND the
    /// completion resume.
    @MainActor
    final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        nonisolated override init() { super.init() }

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse) async {
            guard let raw = response.notification.request.content.userInfo["memoID"] as? String,
                  let id = UUID(uuidString: raw) else { return }
            MemoOpenBridge.shared.open(id)
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification)
            async -> UNNotificationPresentationOptions {
            [.banner, .sound, .list]
        }
    }
}
