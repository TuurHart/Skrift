import Foundation
import SwiftData

/// The "Separate destinations" switch reconciling across devices (Q98 / D162) — ONE algorithm
/// for phone, iPad and Mac, riding the `VocabularyRecord` carrier on its OWN stamp
/// (`destinationsModifiedAt`), exactly like `LanguageSyncCore`. Last-write-wins on one Bool.
///
/// A device that never flipped the switch (`distantPast`) never pushes its default, or a fresh
/// phone would broadcast "off" over the "on" chosen on the Mac. Unlike the language mode, this
/// core MAY create the carrier when none exists yet (an empty word list stamped `distantPast`,
/// which the vocab reconcile treats as "nothing to say"), because most people never edit custom
/// words and the switch would otherwise have no row to ride on.
enum DestinationsSyncCore {
    enum Outcome: Equatable {
        /// The carrier is newer — the caller stores this value + stamp.
        case adoptRemote(enabled: Bool, modifiedAt: Date)
        /// Local was newer (or first) — the carrier now holds it.
        case pushedLocal(stamp: Date)
        case noop
    }

    static func reconcile(localEnabled: Bool, localModifiedAt: Date,
                          records: [VocabularyRecord],
                          insert: (VocabularyRecord) -> Void) -> Outcome {
        // The same survivor `VocabularySyncCore` keeps when it collapses duplicates.
        guard let newest = records.max(by: { $0.modifiedAt < $1.modifiedAt }) else {
            guard localModifiedAt != .distantPast else { return .noop }
            insert(VocabularyRecord(words: [], modifiedAt: .distantPast,
                                    destinationsEnabled: localEnabled,
                                    destinationsModifiedAt: localModifiedAt))
            return .pushedLocal(stamp: localModifiedAt)
        }
        if newest.destinationsModifiedAt > localModifiedAt {
            return .adoptRemote(enabled: newest.destinationsEnabled,
                                modifiedAt: newest.destinationsModifiedAt)
        }
        if localModifiedAt > newest.destinationsModifiedAt {
            newest.destinationsEnabled = localEnabled
            newest.destinationsModifiedAt = localModifiedAt
            return .pushedLocal(stamp: localModifiedAt)
        }
        return .noop
    }
}
