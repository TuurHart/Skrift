import Foundation
import CloudKit

/// C155 / R47 / D217 (mock `SkriftDesktop/mocks/Q484-sync-health.html`): whether iCloud is taking
/// this device's notes, for the list banner, the "Not synced yet" pill and the note line, on both
/// apps. Pure and Codable; each app's monitor feeds it CloudKit export events and the account
/// it sees, and persists it (`SyncHealthStore`).
///
/// CloudKit gives no per-note status, so "not synced yet" is Skrift's own record: a note this
/// device changed after the start of the last export that worked (`pending`).
struct SyncHealth: Codable, Equatable {

    enum Problem: String, Codable, Equatable {
        case quotaFull, signedOut, accountSwitched
    }

    /// What the device's iCloud account looks like right now.
    enum Account: Equatable {
        /// Signed in; `recordName` is this app container's user record (one per Apple ID).
        case available(recordName: String)
        case noAccount
        /// Not asked yet, restricted, or temporarily unavailable: no evidence either way.
        case unknown
    }

    /// Notes changed on this device that no successful export has carried yet: note id → the
    /// latest local change. An export that STARTED after the change carried it.
    var pending: [UUID: Date] = [:]
    /// The last export failure the user can act on (iCloud full, not signed in); nil = the last
    /// export worked, or failed for a passing reason (network).
    var exportFailure: Problem?
    var signedOut = false
    /// The account this store syncs with. Adopted the first time an account is seen.
    var syncedAccount: String?
    /// Non-nil = the device is now on a DIFFERENT account and syncing is stopped (R47). Cleared
    /// when the old account comes back, or when the user taps Copy (D217), never on its own.
    var switchedTo: String?

    /// A healthy device uploads within seconds; a change older than this with no export is late.
    static let grace: TimeInterval = 60

    var isStopped: Bool { switchedTo != nil }

    /// The one problem the list shows, worst first.
    var problem: Problem? {
        if isStopped { return .accountSwitched }
        if signedOut || exportFailure == .signedOut { return .signedOut }
        return exportFailure
    }

    // MARK: - inputs

    mutating func noteChanged(_ ids: some Sequence<UUID>, at date: Date) {
        for id in ids { pending[id] = max(pending[id] ?? .distantPast, date) }
    }

    /// A CloudKit export finished. Success carries every change made before it started and
    /// clears the failure; a failure keeps everything pending.
    mutating func exportEnded(startedAt: Date, error: Error?) {
        guard let error else {
            pending = pending.filter { $0.value > startedAt }
            exportFailure = nil
            return
        }
        if let problem = Self.classify(error) { exportFailure = problem }
    }

    /// The account check (`CKContainer.userRecordID`, at launch and on every account change).
    /// Apple wipes a CloudKit store whose account changed (by design, DTS forum threads 764080
    /// and 811294), so a switch can only be noticed and stopped, never prevented.
    mutating func accountSeen(_ account: Account) {
        switch account {
        case .available(let name):
            signedOut = false
            if exportFailure == .signedOut { exportFailure = nil }
            if syncedAccount == nil { syncedAccount = name }
            switchedTo = (name == syncedAccount) ? nil : name
        case .noAccount:
            signedOut = true
        case .unknown:
            break
        }
    }

    /// D218: on the Mac he tapped "Copy these notes to this account". The new account becomes the
    /// one this store syncs with, and the Mac's own rows go up to it (`ReconcileV2.AccountCopy`).
    mutating func adoptCurrentAccount() {
        guard let name = switchedTo else { return }
        syncedAccount = name
        switchedTo = nil
    }

    /// The CloudKit errors the user can act on. A partial failure counts when one of its items
    /// failed that way; anything else (network, throttling) passes on its own.
    static func classify(_ error: Error) -> Problem? {
        let ns = error as NSError
        if ns.domain == CKError.errorDomain, let code = CKError.Code(rawValue: ns.code) {
            switch code {
            case .quotaExceeded: return .quotaFull
            case .notAuthenticated: return .signedOut
            case .partialFailure:
                let parts = (ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error]) ?? [:]
                // The mirror posts a full iCloud as a partial failure with NO per-item errors
                // (Apple bug FB13773922, developer.apple.com/forums/thread/840348). Unverified
                // on Skrift's own devices; read as full until an export works.
                if parts.isEmpty { return .quotaFull }
                let problems = parts.values.compactMap(classify)
                if problems.contains(.signedOut) { return .signedOut }
                return problems.first
            default: break
            }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return classify(underlying) }
        return nil
    }

    // MARK: - what the user sees

    /// The notes to mark "Not synced yet". With a problem, every pending note; while healthy,
    /// only a change older than `grace` (one still uploading is not news).
    func unsynced(now: Date = Date()) -> Set<UUID> {
        if problem != nil { return Set(pending.keys) }
        return Set(pending.filter { now.timeIntervalSince($0.value) >= Self.grace }.keys)
    }

    struct Banner: Equatable {
        var title: String
        var line: String
        /// true = "What now" (the account-switch sheet); false = "Show" (filter to the waiting notes).
        var opensSheet: Bool
    }

    /// The list banner, or nil (healthy: a waiting note only gets its pill and note line).
    func banner(unsyncedCount n: Int, device: String) -> Banner? {
        let notes = n == 1 ? "1 note hasn't synced." : "\(n) notes haven't synced."
        switch problem {
        case .accountSwitched?:
            return Banner(title: "A different iCloud account",
                          line: "Syncing stopped so your notes don't go into that account.",
                          opensSheet: true)
        case .signedOut?:
            return Banner(title: "Not signed in to iCloud",
                          line: n == 0 ? "New notes stay on \(device) until you sign in to iCloud in Settings."
                                       : "\(notes) They stay on \(device) until you sign in to iCloud in Settings.",
                          opensSheet: false)
        case .quotaFull?:
            return Banner(title: "iCloud is full",
                          line: n == 0 ? "New notes stay on \(device) and go up once iCloud has room."
                                       : "\(notes) They're safe on \(device) and go up once iCloud has room.",
                          opensSheet: false)
        case nil:
            return nil
        }
    }

    /// The reason after "Not synced yet · " on the note.
    var noteReason: String {
        switch problem {
        case .quotaFull?: return "iCloud is full"
        case .signedOut?: return "not signed in to iCloud"
        case .accountSwitched?: return "syncing is stopped"
        case nil: return "waiting for iCloud"
        }
    }

    /// The "What now" sheet after an account switch (mock Q484, D217). `notesHere` is the count
    /// this device still holds: Apple wipes a CloudKit store when its account changes, so on the
    /// phone it is usually 0 and the notes live in the old account; the Mac keeps its own rows.
    struct WhatNow: Equatable {
        var title = "Syncing is stopped"
        var lead: String
        var facts: [String]
    }

    func whatNow(device: String, deviceKind: String, notesHere: Int, settingsPath: String) -> WhatNow {
        let waiting = pending.count
        let signIn = "\(settingsPath) › your name"
        var facts: [String] = []
        if notesHere > 0 {
            facts.append("Your \(notesHere == 1 ? "1 note is" : "\(notesHere) notes are") still on \(device).")
            if waiting > 0 {
                facts.append(waiting == 1 ? "1 note made here hasn't synced." : "\(waiting) notes made here haven't synced.")
            }
            facts.append("To sync again, sign back into the iCloud account you used before, in \(signIn).")
        } else {
            // D218: the phone after a switch. Apple removed this device's copy; the notes are safe
            // in the old account, and only ones that never went up may be gone.
            facts.append("Your notes are in the iCloud account you used before. Sign back into it, in \(signIn), to get them back on \(device).")
            if waiting > 0 {
                facts.append(waiting == 1 ? "1 note made here hadn't synced yet, so it may be gone."
                                          : "\(waiting) notes made here hadn't synced yet, so they may be gone.")
            }
        }
        return WhatNow(lead: "This \(deviceKind) was syncing with a different iCloud account. Skrift stopped so notes from that account don't go into this one.",
                       facts: facts)
    }

    static let pillText = "Not synced yet"
    static let showVerb = "Show"
    static let hideVerb = "Hide"
    static let whatNowVerb = "What now"
    /// D218, the Mac only.
    static let copyVerb = "Copy these notes to this account"
    static let copyFootnote = "This Mac's notes go up to the account it's signed into now. Your notes in the old account stay there."
}
