import Foundation
import SwiftData
import os

/// Puts a PLACE on a note the Mac recorded — the parity Tuur asked for on 2026-08-27:
/// *"I think Mac should also have location, same as the phone and iPad."*
///
/// Why it was missing: `MetadataService` (place, weather, steps, daylight) is an iOS file,
/// and `MacMemoAuthor` never wrote any `MemoMetadata` at all. So a Mac recording exported
/// with an empty `location:` while the same words recorded on the phone carried a place.
/// The one-shot fix itself now lives in `Shared/Metadata/LocationOneShot.swift`; this is the
/// Mac's caller.
///
/// Two deliberate limits:
///
/// - **RECORDINGS ONLY, never imports.** Where the Mac is standing right now is the truth
///   about a memo it is recording; it says nothing about a file dragged in from disk, whose
///   real place was wherever it was captured, possibly years ago. Stamping an import would
///   be inventing metadata, which is worse than having none.
/// - **Never overwrites.** If the note already carries metadata (a synced phone memo whose
///   place came from the phone), this leaves it alone. The phone's fix is the better one:
///   it was taken at the moment of recording, on the device that was actually there.
///
/// Fire-and-forget: the memo is created and shown immediately and the place lands a moment
/// later, because a location fix + reverse-geocode is a network-ish round trip and no
/// recording should wait on it. Failure is silent and normal — permission declined, no fix
/// indoors, Location Services off. An empty `location:` is exactly what it was before.
@MainActor
enum MacLocationStamp {
    private static let log = Logger(subsystem: "com.skrift.desktop", category: "location")

    /// Stamp this note with where the Mac is, unless it already has metadata.
    ///
    /// Writes BOTH models, and that is the whole bug fix (2026-08-28). The first version wrote
    /// only `Memo.metadata`, so the place synced to the phone and never reached the Mac's own
    /// export — which compiles from `PipelineFile.audioMetadataJSON`. Tuur recorded on the Mac,
    /// granted the permission, and still got an empty `location:`. It is exactly the
    /// PipelineFile⇄Memo seam `MirroredNoteFields` exists for: a value written to one side is
    /// invisible on the other until someone says so.
    static func stamp(memo: Memo, file pf: PipelineFile, in ctx: ModelContext) {
        let memoID = memo.id
        Task { @MainActor in
            // One instance PER CALL: a shared one has a single continuation slot, so a second
            // `current()` before the first fix returned would strand the first caller forever.
            let oneShot = LocationOneShot()
            guard let place = await oneShot.current() else {
                log.debug("no location fix — leaving the note without one")
                return
            }
            guard memo.metadata == nil else { return }
            memo.metadata = MemoMetadata(location: place)
            try? ctx.save()
            // The Mac's editing model, which is what its exporter actually reads.
            pf.audioMetadataJSON = MemoCloudIngest.metadataJSON(for: memo)
            try? pf.modelContext?.save()
            log.debug("stamped \(memoID, privacy: .public) with a place, both models")
        }
    }
}
