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
@Model
final class VocabularyRecord {
    var words: [String] = []
    var modifiedAt: Date = Date()

    init(words: [String], modifiedAt: Date = Date()) {
        self.words = words
        self.modifiedAt = modifiedAt
    }
}
