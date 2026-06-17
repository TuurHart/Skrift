import Foundation
import SwiftData

/// CloudKit-synced carrier for the names/people database (standalone Phase 1e), so
/// people + enrolled voices sync across the user's own devices.
///
/// **Why a blob carrier, not a `Person` `@Model`:** `names.json` is a byte-compatible
/// part of the phone↔Mac contract (`NamesData`/`Person`/`VoiceEmbedding` in
/// `Shared/Naming/`), and the merge that matters — per-canonical last-write-wins with
/// **union** of voiceEmbeddings — already lives in `NamesMerge`. Re-modelling people as
/// SwiftData rows would (a) fork the contract type and (b) lose the union merge to
/// CloudKit's blunt row-level LWW. Instead this holds the serialized `NamesData`, and
/// `NamesCloudSync` reconciles it with the local `names.json` through the SAME
/// `NamesMerge` — so device↔device sync and the existing Mac sync use identical
/// semantics, and `NamesStore` / the contract are untouched.
///
/// One row by convention (collapsed in `NamesCloudSync`; CloudKit forbids
/// `@Attribute(.unique)`, and two devices can briefly each create one before they
/// sync). CloudKit shape rules: every attribute defaulted, no unique constraint.
@Model
final class NamesRecord {
    /// Serialized `NamesData` (the same JSON shape as `names.json`).
    var blob: Data = Data()
    var updatedAt: Date = Date()

    init(blob: Data, updatedAt: Date = Date()) {
        self.blob = blob
        self.updatedAt = updatedAt
    }
}
