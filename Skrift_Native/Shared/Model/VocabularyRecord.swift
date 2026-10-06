import Foundation
import SwiftData

/// CloudKit-synced carrier for the custom-vocabulary word list (Phase 1f), so the
/// words you add on one device boost transcription on your others.
///
/// The local source of truth stays `CustomVocabularyStore` (UserDefaults) — the
/// booster reads it synchronously off the main actor during transcription, which a
/// SwiftData `@Model` can't serve. This carrier just mirrors the list for sync;
/// `VocabularyCloudSync` reconciles the two LWW by `modifiedAt` (so a delete on one
/// device propagates — unlike a union, which would resurrect removed words).
///
/// One row by convention (collapsed in `VocabularyCloudSync`). CloudKit shape rules:
/// every attribute defaulted, no `@Attribute(.unique)`.
/// Since 2026-07-26 it also carries the TRANSCRIPTION LANGUAGE MODE
/// (`ASRLanguageMode`) — same singleton row, but with its OWN stamp
/// (`languageModifiedAt`) so the two settings reconcile INDEPENDENTLY. Sharing one
/// stamp would mean editing your word list on the Mac and the language on the phone
/// makes one of them lose. The type name stays `VocabularyRecord` on purpose: renaming
/// a `@Model` renames the CloudKit record type, which would orphan every existing row.
@Model
final class VocabularyRecord {
    var words: [String] = []
    var modifiedAt: Date = Date()

    /// Transcription language mode, stored as the same Bool both apps keep locally
    /// (`false` = English). Additive + defaulted → lightweight migration, and CloudKit
    /// requires every attribute to have a default.
    var multilingual: Bool = false
    /// LWW stamp for `multilingual` ALONE. `.distantPast` = never set on any device, so
    /// a real edit anywhere wins over a default nobody chose.
    /// (Written out as `Date.distantPast`, not `.distantPast` — the `@Model` macro
    /// can't infer a shorthand default and fails to expand.)
    var languageModifiedAt: Date = Date.distantPast

    /// The "Separate destinations" switch (`DestinationSettings`, Q98 / D162) — a third
    /// setting on this same singleton row with its OWN stamp, for the same reason as the
    /// language mode. `.distantPast` = no device ever flipped it. The portfolio FOLDER is
    /// deliberately not here: a folder bookmark is per device.
    var destinationsEnabled: Bool = false
    var destinationsModifiedAt: Date = Date.distantPast

    /// The export author (`author:` frontmatter, `AuthorSyncCore`, Q158) — a fourth setting on
    /// this row with its OWN stamp. `.distantPast` = no device ever set it.
    var authorName: String = ""
    var authorModifiedAt: Date = Date.distantPast

    /// The OpenWeatherMap key (`WeatherKeySyncCore`, Q326 / D182) — a fifth setting on this row
    /// with its OWN stamp, so the Mac records weather with the key typed once on the phone.
    /// Travels through the user's own private iCloud database only; never logged or exported.
    /// `.distantPast` = no device ever set it.
    var weatherKey: String = ""
    var weatherKeyModifiedAt: Date = Date.distantPast

    init(words: [String], modifiedAt: Date = Date(),
         multilingual: Bool = false, languageModifiedAt: Date = Date.distantPast,
         destinationsEnabled: Bool = false, destinationsModifiedAt: Date = Date.distantPast,
         authorName: String = "", authorModifiedAt: Date = Date.distantPast,
         weatherKey: String = "", weatherKeyModifiedAt: Date = Date.distantPast) {
        self.words = words
        self.modifiedAt = modifiedAt
        self.multilingual = multilingual
        self.languageModifiedAt = languageModifiedAt
        self.destinationsEnabled = destinationsEnabled
        self.destinationsModifiedAt = destinationsModifiedAt
        self.authorName = authorName
        self.authorModifiedAt = authorModifiedAt
        self.weatherKey = weatherKey
        self.weatherKeyModifiedAt = weatherKeyModifiedAt
    }
}
