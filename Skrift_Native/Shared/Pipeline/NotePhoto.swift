import Foundation
import CoreGraphics

/// Whether a memo's media file is on disk, still arriving over CloudKit, or truly
/// gone — pure so the image embed's three states are unit-testable. (Moved here from the
/// phone's `CloudSyncMonitor` so the Mac's note body draws the same three states, Q325.)
enum MediaSyncState {
    case present       // file is on disk → show it
    case downloading   // file missing but a synced asset exists → it's on its way
    case missing       // no file, no asset → genuinely gone (e.g. a seeded demo memo)

    static func of(filePresent: Bool, hasAsset: Bool) -> MediaSyncState {
        if filePresent { return .present }
        return hasAsset ? .downloading : .missing
    }
}

/// Photos inside a note body, the rules both apps share (Q325, mock Q128-mac-note-photos,
/// D181/D182). Foundation + CoreGraphics only, so the host-less Mac test bundle drives it.
enum NotePhoto {

    // MARK: A marker whose file has not arrived — the phone's `ImageEmbed` card

    /// The card's words while the file is still coming over iCloud.
    static let downloadingCopy = "Downloading from iCloud…"
    /// The card is a fixed height, so the text below moves down when a tall photo lands.
    static let cardHeight: CGFloat = 160
    static let cardCornerRadius: CGFloat = 14
    /// The card's dark gradient, top-leading to bottom-trailing (phone: 0x2b3350 → 0x161a29).
    static let cardGradientHex: (UInt32, UInt32) = (0x2b3350, 0x161a29)
    /// Spinner, words and glyph on the card.
    static let cardInkHex: UInt32 = 0xa3a3aa

    /// What a `[[img_NNN]]` marker stands for right now.
    enum Slot: Equatable {
        /// Not a picture: no manifest entry carries this number, so the marker stays the
        /// author's text (C169).
        case text
        /// The photo file is here — draw it.
        case present
        /// The marker and manifest arrived, the file is still coming: spinner card.
        case downloading
        /// No file and none on its way: the plain photo card.
        case missing
    }

    /// `manifest` is the ordered filenames (marker N is the Nth, 1-based, C169).
    static func slot(number: Int, manifest: [String],
                     fileExists: (String) -> Bool, hasAsset: (String) -> Bool) -> Slot {
        guard number >= 1, number <= manifest.count else { return .text }
        let name = manifest[number - 1]
        switch MediaSyncState.of(filePresent: fileExists(name), hasAsset: hasAsset(name)) {
        case .present: return .present
        case .downloading: return .downloading
        case .missing: return .missing
        }
    }

    // MARK: Adding a photo at the caret

    /// `photo_<owner>_<NNN>.<ext>`: the manifest filename convention the phone writes
    /// (`NoteBodyView.insertPhoto`), so a photo added on the Mac is named like one added there.
    static func filename(owner: UUID, number: Int, ext: String) -> String {
        "photo_\(owner.uuidString)_\(String(format: "%03d", number)).\(ext.isEmpty ? "jpg" : ext)"
    }

    /// The model text with picture `number` put at UTF-16 offset `caret`, stored the v2 way: its
    /// own paragraph, after the sentence the caret is in (C10). The phone's save step does the
    /// same, so both devices end up with the picture in the same place. `manifestCount` already
    /// includes the new picture. Also returns where the marker starts in the stored text.
    static func inserting(number: Int, into text: String, atOffset caret: Int,
                          manifestCount: Int) -> (text: String, markerOffset: Int) {
        let ns = text as NSString
        let at = max(0, min(caret, ns.length))
        let marker = BodyV2Marker.literal(number)
        let raw = ns.replacingCharacters(in: NSRange(location: at, length: 0), with: "\n\n" + marker + "\n\n")
        let entries = Array(repeating: ImageManifestEntry(filename: "", offsetSeconds: 0),
                            count: max(manifestCount, number))
        let stored = BodyV2.committed(BodyV2.Input(text: raw, manifest: entries, source: .typed, userEdited: true))
        let found = (stored as NSString).range(of: marker)
        return (stored, found.location == NSNotFound ? at : found.location)
    }

    /// File extensions the note takes as a picture (a dropped file, the Insert Photo… panel).
    static let acceptedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp"]
}
