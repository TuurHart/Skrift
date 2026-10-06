import Foundation
import SwiftData

/// The OpenWeatherMap key as ONE synced setting (Q326, D182): typed once on the phone, used by
/// the Mac to tag its own recordings with weather. It rides the `VocabularyRecord` carrier on
/// its OWN stamp (`weatherKeyModifiedAt`), exactly like the export author (`AuthorSyncCore`):
/// last-write-wins on one String. The carrier lives in the user's private iCloud database.
///
/// A device that never set a key (`distantPast`) never pushes its blank, or a fresh Mac would
/// broadcast "" over the key the phone holds. Like the author core this one MAY create the
/// carrier when none exists. NEVER log the key.
enum WeatherKeySyncCore {
    enum Outcome: Equatable {
        /// The carrier is newer — the caller stores this key + stamp.
        case adoptRemote(key: String, modifiedAt: Date)
        /// Local was newer (or first) — the carrier now holds it.
        case pushedLocal(stamp: Date)
        case noop
    }

    static func reconcile(localKey: String, localModifiedAt: Date,
                          records: [VocabularyRecord],
                          insert: (VocabularyRecord) -> Void) -> Outcome {
        // The same survivor `VocabularySyncCore` keeps when it collapses duplicates.
        guard let newest = records.max(by: { $0.modifiedAt < $1.modifiedAt }) else {
            guard localModifiedAt != .distantPast else { return .noop }
            insert(VocabularyRecord(words: [], modifiedAt: .distantPast,
                                    weatherKey: localKey, weatherKeyModifiedAt: localModifiedAt))
            return .pushedLocal(stamp: localModifiedAt)
        }
        if newest.weatherKeyModifiedAt > localModifiedAt {
            return .adoptRemote(key: newest.weatherKey, modifiedAt: newest.weatherKeyModifiedAt)
        }
        if localModifiedAt > newest.weatherKeyModifiedAt {
            newest.weatherKey = localKey
            newest.weatherKeyModifiedAt = localModifiedAt
            return .pushedLocal(stamp: localModifiedAt)
        }
        return .noop
    }

    /// Masked display for the Settings row: `••••••` + the last two characters; "Not set" blank.
    static func masked(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespaces)
        return k.isEmpty ? "Not set" : "••••••" + String(k.suffix(2))
    }
}

/// The phone's local key store (UserDefaults): the `weatherAPIKey` slot Settings writes and
/// `WeatherClient` reads, plus its LWW stamp and the last value the stamp was taken for (so a
/// key that ARRIVED from another device is never re-stamped as a fresh local edit).
enum WeatherKeySettings {
    static let key = PrefKey.weatherAPIKey
    static let stampKey = "skrift.weatherAPIKeyModifiedAt"
    static let lastValueKey = "skrift.weatherAPIKeyStampedValue"

    static func value(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: key) ?? ""
    }

    /// `.distantPast` until a real edit (or the one-time seed below).
    static func modifiedAt(defaults: UserDefaults = .standard) -> Date {
        (defaults.object(forKey: stampKey) as? Date) ?? .distantPast
    }

    /// The user edited the field → bump the stamp so it wins LWW. A value equal to the one the
    /// stamp already covers (including one adopted from the carrier) is ignored.
    static func noteEdit(_ newValue: String, defaults: UserDefaults = .standard, now: Date = Date()) {
        guard newValue != (defaults.string(forKey: lastValueKey) ?? "") else { return }
        defaults.set(newValue, forKey: lastValueKey)
        defaults.set(now, forKey: stampKey)
    }

    /// A key arrived from another device — keep the REMOTE stamp (never bumped to now).
    static func adoptSynced(_ newValue: String, modifiedAt: Date, defaults: UserDefaults = .standard) {
        defaults.set(newValue, forKey: key)
        defaults.set(newValue, forKey: lastValueKey)
        defaults.set(modifiedAt, forKey: stampKey)
    }

    /// One-time migration: a phone that already had a key before this synced carries no stamp.
    /// A non-blank key can only be a deliberate choice — date it now so it reaches the Mac.
    static func seedStampIfNeeded(defaults: UserDefaults = .standard, now: Date = Date()) {
        let v = value(defaults: defaults).trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, defaults.object(forKey: stampKey) == nil else { return }
        defaults.set(value(defaults: defaults), forKey: lastValueKey)
        defaults.set(now, forKey: stampKey)
    }
}
