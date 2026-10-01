import Foundation

/// The ONE composer for a bundle of voice clips + pictures that becomes one note (C68, C12,
/// C70, C238). Pure: no files, no audio, no SwiftData — the caller measures the clips and
/// writes the files; this decides ORDER and PLACE so a Mac drop and a phone share of the same
/// bundle cannot disagree.
///
/// Born from Q92 (2026-10-01): five Signal clips + one Signal picture dragged onto the Mac. The
/// clips merged; the picture was dropped on the floor, and even had it been kept, its name
/// (`signal-2026-10-01-080349.jpeg`) puts it between clip 3 (07:56) and clip 4 (08:04), which
/// only a time ordering can honour.
enum MixedBundle {

    enum Kind: Equatable, Sendable { case clip, picture }

    /// One dropped/shared file. `date` is the C70 filename-date ladder's answer (nil = the name
    /// carries none); the caller computes it so this file stays free of any app's date parser.
    struct Item: Equatable, Sendable {
        var url: URL
        var kind: Kind
        var date: Date?
    }

    /// A picture's place in the merged audio: `offsetSeconds` = how much merged speech comes
    /// BEFORE it. 0 puts it at the top of the note (a picture with no clip before it, C12).
    struct Placement: Equatable, Sendable {
        var url: URL
        var offsetSeconds: Double
    }

    struct Composition: Equatable, Sendable {
        /// Clips in the order they are stitched.
        var clips: [URL]
        /// Pictures in the order they appear in the note (ascending offset; ties keep bundle order).
        var pictures: [Placement]
    }

    /// Bundle order: by filename date when EVERY item has one (chat order — C68, C70), else the
    /// order the bundle arrived in. All-or-nothing on purpose: one undated file in the middle
    /// would otherwise be sorted against dates it cannot be compared to. Stable either way.
    static func ordered(_ items: [Item]) -> [Item] {
        guard items.count > 1, items.allSatisfy({ $0.date != nil }) else { return items }
        return items.enumerated()
            .sorted { a, b in
                let da = a.element.date!, db = b.element.date!
                return da != db ? da < db : a.offset < b.offset
            }
            .map(\.element)
    }

    /// Order the bundle, then place every picture by the clip time that precedes it.
    /// `clipDuration` answers the length in seconds of one clip (0 for an unreadable one, which
    /// the stitcher skips too, so the offsets keep matching the merged file).
    static func compose(_ items: [Item], clipDuration: (URL) -> Double) -> Composition {
        var clips: [URL] = []
        var pictures: [Placement] = []
        var elapsed = 0.0
        for item in ordered(items) {
            switch item.kind {
            case .clip:
                clips.append(item.url)
                elapsed += max(0, clipDuration(item.url))
            case .picture:
                pictures.append(Placement(url: item.url, offsetSeconds: elapsed))
            }
        }
        return Composition(clips: clips, pictures: pictures)
    }

    /// The body of a note made of pictures alone: each one its own paragraph (C12/C13).
    static func pictureOnlyBody(count: Int) -> String {
        (0..<max(0, count)).map { $0 + 1 }
            .map { "[[img_\(String(format: "%03d", $0))]]" }
            .joined(separator: "\n\n")
    }

    /// File extensions the import layer treats as pictures (C238).
    static let pictureExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"]

    static func isPictureName(_ url: URL) -> Bool { pictureExtensions.contains(url.pathExtension.lowercased()) }

    /// Extensions a viewer/vault cannot be trusted to show — converted to JPEG on the way in.
    static let convertToJPEGExtensions: Set<String> = ["heic", "heif", "tif", "tiff", "bmp"]
}
