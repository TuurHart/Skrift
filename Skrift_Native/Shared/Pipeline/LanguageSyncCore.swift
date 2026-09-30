import Foundation
import SwiftData

/// The transcription-language reconcile — ONE algorithm for every device, riding the
/// existing `VocabularyRecord` carrier but on its OWN stamp (`languageModifiedAt`), so
/// language and word-list edits never clobber each other.
///
/// Last-write-wins on a single Bool. The subtlety is the same one `VocabularySyncCore`
/// documents: a device that has NEVER touched the setting must not push its default up,
/// or a fresh Mac would broadcast "English" and silently undo the Multilingual you chose
/// on your phone. Only a real edit (a non-`distantPast` local stamp) pushes.
enum LanguageSyncCore {
    enum Outcome: Equatable {
        /// The carrier is newer — the caller adopts this value + stamp, and must drop
        /// its loaded ASR model so the next transcription rebuilds with the right config.
        case adoptRemote(multilingual: Bool, modifiedAt: Date)
        /// Local was newer — the carrier now holds it.
        case pushedLocal(stamp: Date)
        /// Nothing to do: stamps equal, or this device has no opinion to push.
        case noop
    }

    /// `records` is the same fetch the vocab reconcile uses (callers run both together);
    /// duplicate-carrier collapsing is left to `VocabularySyncCore` so this never
    /// deletes a row out from under it.
    static func reconcile(localMultilingual: Bool,
                          localModifiedAt: Date,
                          records: [VocabularyRecord]) -> Outcome {
        guard let newest = records.max(by: { $0.modifiedAt < $1.modifiedAt }) else {
            // No carrier at all. Creating one is the vocab reconcile's job (it owns the
            // row's lifecycle); if this device has a real choice it lands on the next run.
            return .noop
        }
        // Never broadcast a default nobody picked.
        guard localModifiedAt != .distantPast else {
            return newest.languageModifiedAt == .distantPast
                ? .noop
                : .adoptRemote(multilingual: newest.multilingual, modifiedAt: newest.languageModifiedAt)
        }
        if newest.languageModifiedAt > localModifiedAt {
            return .adoptRemote(multilingual: newest.multilingual, modifiedAt: newest.languageModifiedAt)
        }
        if localModifiedAt > newest.languageModifiedAt {
            newest.multilingual = localMultilingual
            newest.languageModifiedAt = localModifiedAt
            return .pushedLocal(stamp: localModifiedAt)
        }
        return .noop
    }
}
