import Foundation

/// What the Mac knows about the user's iCloud account, boiled down from `CKAccountStatus`
/// (kept out of this file so the rule below stays Foundation-only and testable).
/// `unknown` = not asked yet, could not be determined, or temporarily unavailable: none of
/// those is evidence of trouble, so none of them alarms.
enum MacSyncAccount: Equatable {
    case available, noAccount, restricted, unknown
}

/// The Mac's iCloud sync state (Q327, mock `mocks/Q162-mac-icloud-state.html`, D182): ONE value
/// that the Settings row, the Sync card and the notes-list capsule all read.
enum MacSyncState: Equatable, CaseIterable {
    case syncing, upToDate, off, signedOut, failed

    /// The rule. Order matters: a switched-off Mac is "Off" whatever the account says (it never
    /// touches CloudKit); a signed-out account explains more than a container that did not open.
    static func resolve(switchOn: Bool, containerOpened: Bool,
                        account: MacSyncAccount, inFlight: Bool) -> MacSyncState {
        guard switchOn else { return .off }
        if account == .noAccount { return .signedOut }
        if account == .restricted || !containerOpened { return .failed }
        return inFlight ? .syncing : .upToDate
    }

    /// The right-hand text of the Settings "iCloud" row.
    var rowText: String {
        switch self {
        case .syncing:   return "Syncing…"
        case .upToDate:  return "Up to date"
        case .off:       return "Off"
        case .signedOut: return SharedCopy.syncSignedOutRow
        case .failed:    return "Couldn't start"
        }
    }

    /// Amber in the row (the mock's `.warn`): only the two states the user has to act on.
    var rowIsWarning: Bool { self == .signedOut || self == .failed }

    /// The notes-list capsule's words, or nil = no capsule. D182: only when sync is broken, off
    /// or signed out; never while it is syncing normally or up to date.
    var capsuleText: String? {
        switch self {
        case .syncing, .upToDate: return nil
        case .off:                return "iCloud sync is off"
        case .signedOut:          return SharedCopy.syncSignedOutCapsule
        case .failed:             return "iCloud sync couldn’t start"
        }
    }

    var showsCapsule: Bool { capsuleText != nil }

    /// Amber capsule (signed out, couldn't start) vs grey (switched off).
    var capsuleIsWarning: Bool { self == .signedOut || self == .failed }

    /// The alert card under the row (signed out / couldn't start), or nil.
    var alertText: String? {
        switch self {
        case .signedOut:
            return "This Mac isn't signed in to iCloud. Your phone's notes can't reach it and your phone won't get this Mac's polish. Notes you make here stay on this Mac until you sign in."
        case .failed:
            return "Skrift couldn't open its iCloud store on this Mac, so nothing syncs. Your notes on this Mac are safe. Skrift tries again when it reopens."
        default:
            return nil
        }
    }

    /// The small mono line under the "couldn't start" alert.
    static func failureDetail(account: MacSyncAccount) -> String {
        account == .restricted
            ? "iCloud is restricted on this Mac (CKAccountStatus.restricted)"
            : "memo_cloud.store · ModelContainer init failed"
    }

    /// The line under the switch when it is off.
    static let offText = "Off. This Mac works on its own notes and sends nothing to your phone."

    /// What the one switch gates, in the mock's words: direction arrow + line.
    enum Direction: Equatable { case incoming, outgoing, both }
    static let gates: [(Direction, String)] = [
        (.incoming, "Notes from your phone and iPad come in"),
        (.outgoing, "Title, summary and copy-edit go back to your phone"),
        (.outgoing, "Notes you record or type on this Mac go to your phone"),
        (.both, "Edits, ratings and deletes, both ways"),
        (.both, "Names and voices"),
        (.both, "Custom words, language, the destinations switch"),
        (.both, "Polish prompts"),
    ]

    static let accountHelp = "Needs this Mac signed in to the same iCloud account as your phone."
}
