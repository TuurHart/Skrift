import Foundation

/// The legacy Bonjour/HTTP phone↔Mac LAN path is being retired in favor of CloudKit — names +
/// memos now sync over the user's private CloudKit database, reaching a paired Mac (and iPad)
/// without pairing or the local network. This flag keeps the old path available only as an
/// explicit opt-in fallback (e.g. a setup with no iCloud). **OFF by default.**
///
/// Phase 3 of retiring Bonjour: the transports coexist but CloudKit is the default and the LAN
/// path stays dark unless re-enabled. The Bonjour code is removed entirely once CloudKit is
/// prod-verified (Phase 5).
enum BonjourFallback {
    private static let key = "bonjourFallbackEnabled"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: key) }   // default false
    static func set(_ on: Bool) { UserDefaults.standard.set(on, forKey: key) }
}
