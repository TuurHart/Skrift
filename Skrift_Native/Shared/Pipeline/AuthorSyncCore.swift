import Foundation
import SwiftData

/// The export author (`author:` in every vault note's frontmatter) as ONE synced setting
/// (Q158, C62 / D162). The same note exported by the iPad and by the Mac must compile to the
/// same bytes — the hash and the edit guard read them — so the author cannot be two unsynced
/// stores (the iPad's `skrift.publish.author`, the Mac's `AppSettings.authorName`). It rides
/// the `VocabularyRecord` carrier on its OWN stamp (`authorModifiedAt`), exactly like the
/// destinations switch (`DestinationsSyncCore`): last-write-wins on one String.
///
/// A device that never set an author (`distantPast`) never pushes its blank, or a fresh iPad
/// would broadcast "" over the name chosen on the Mac. Like the destinations core this one MAY
/// create the carrier when none exists (an empty word list stamped `distantPast`).
enum AuthorSyncCore {
    enum Outcome: Equatable {
        /// The carrier is newer — the caller stores this name + stamp.
        case adoptRemote(name: String, modifiedAt: Date)
        /// Local was newer (or first) — the carrier now holds it.
        case pushedLocal(stamp: Date)
        case noop
    }

    static func reconcile(localName: String, localModifiedAt: Date,
                          records: [VocabularyRecord],
                          insert: (VocabularyRecord) -> Void) -> Outcome {
        // The same survivor `VocabularySyncCore` keeps when it collapses duplicates.
        guard let newest = records.max(by: { $0.modifiedAt < $1.modifiedAt }) else {
            guard localModifiedAt != .distantPast else { return .noop }
            insert(VocabularyRecord(words: [], modifiedAt: .distantPast,
                                    authorName: localName, authorModifiedAt: localModifiedAt))
            return .pushedLocal(stamp: localModifiedAt)
        }
        if newest.authorModifiedAt > localModifiedAt {
            return .adoptRemote(name: newest.authorName, modifiedAt: newest.authorModifiedAt)
        }
        if localModifiedAt > newest.authorModifiedAt {
            newest.authorName = localName
            newest.authorModifiedAt = localModifiedAt
            return .pushedLocal(stamp: localModifiedAt)
        }
        return .noop
    }
}

/// The iPhone/iPad's local author store (UserDefaults): the `skrift.publish.author` key the
/// export reads, plus its LWW stamp. The Mac keeps its author in `AppSettings` (settings.json)
/// with `authorModifiedAt` beside it; both feed `AuthorSyncCore`.
enum AuthorSettings {
    static let key = "skrift.publish.author"
    static let stampKey = "skrift.publish.authorModifiedAt"

    static func name(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: key) ?? ""
    }

    /// `.distantPast` until a real edit (or the one-time seed below).
    static func modifiedAt(defaults: UserDefaults = .standard) -> Date {
        (defaults.object(forKey: stampKey) as? Date) ?? .distantPast
    }

    /// The user typed a name here → store it and bump the stamp so it wins LWW. Writing the
    /// value already stored is ignored, so following a synced value never re-stamps it.
    static func set(_ name: String, defaults: UserDefaults = .standard, now: Date = Date()) {
        guard name != self.name(defaults: defaults) else { return }
        defaults.set(name, forKey: key)
        defaults.set(now, forKey: stampKey)
    }

    /// A name arrived from another device — keep the REMOTE stamp (never bumped to now).
    static func adoptSynced(_ name: String, modifiedAt: Date, defaults: UserDefaults = .standard) {
        defaults.set(name, forKey: key)
        defaults.set(modifiedAt, forKey: stampKey)
    }

    /// One-time migration: a device that already had an author before this synced carries no
    /// stamp. A non-blank name can only be a deliberate choice — date it now so it propagates.
    static func seedStampIfNeeded(defaults: UserDefaults = .standard, now: Date = Date()) {
        guard !name(defaults: defaults).isEmpty, defaults.object(forKey: stampKey) == nil else { return }
        defaults.set(now, forKey: stampKey)
    }
}
