import Foundation

/// The ONE composer for a bundle of voice clips + pictures + text (+ video) that becomes one
/// note (C68, C12, C70, C238). Pure: no files, no audio, no SwiftData — the caller measures the
/// clips and writes the files; this decides WHAT a bundle accepts, ORDER and PLACE, so a Mac
/// drop and a phone share of the same bundle cannot disagree.
///
/// Born from Q92 (2026-10-01): five Signal clips + one Signal picture dragged onto the Mac. The
/// clips merged; the picture was dropped on the floor, and even had it been kept, its name
/// (`signal-2026-10-01-080349.jpeg`) puts it between clip 3 (07:56) and clip 4 (08:04), which
/// only a time ordering can honour.
enum MixedBundle {

    /// A positioned bundle member. A `video` is speech AND a picture (C68): its audio is
    /// stitched in its place like a clip, its frame is a picture paragraph where its speech
    /// starts.
    enum Kind: Equatable, Sendable { case clip, picture, video }

    // MARK: - The accept set (Q186)

    /// What one file is to a bundle. `text` has no place in time: every text in the bundle
    /// becomes the note's annotation (C68: "text as the annotation"). A document or a book is
    /// never bundled (nil): it keeps its own door.
    enum Member: Equatable, Sendable { case clip, picture, video, text }

    /// Movie containers that can carry audio alone; one with no video track is a clip.
    static let audioOnlyContainerExtensions: Set<String> = ["mp4", "mov"]

    /// THE accept set, phone and Mac. `hasVideoTrack` is the caller's probe of a movie
    /// container (file I/O, so it stays out of this pure file); it is asked only for a
    /// `.video` extension.
    static func member(of url: URL, hasVideoTrack: (URL) -> Bool) -> Member? {
        let ext = url.pathExtension.lowercased()
        switch ImportKinds.kind(forExtension: ext) {
        case .audio: return .clip
        case .video:
            if hasVideoTrack(url) { return .video }
            return audioOnlyContainerExtensions.contains(ext) ? .clip : nil
        case .image: return .picture
        case .text: return .text
        case .document, .book, .none: return nil
        }
    }

    /// The annotation a bundle's texts make: each trimmed text in bundle order, empty ones
    /// dropped, one paragraph each. nil when there is nothing to say.
    static func annotation(fromTexts texts: [String]) -> String? {
        let kept = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return kept.isEmpty ? nil : kept.joined(separator: "\n\n")
    }

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
        /// True when `url` is a VIDEO and this placement is its frame (the caller grabs it).
        var isVideoFrame: Bool = false
    }

    struct Composition: Equatable, Sendable {
        /// Clips in the order they are stitched. A video's own URL stands for its audio track.
        var clips: [URL]
        /// Pictures in the order they appear in the note (ascending offset; ties keep bundle order).
        var pictures: [Placement]
    }

    /// Bundle order: by date when EVERY item has one (chat order — C68, C70), else the order the
    /// bundle arrived in. All-or-nothing on purpose: one undated file in the middle would
    /// otherwise be sorted against dates it cannot be compared to. Dates all within 2 s are one
    /// moment and keep the arrival order too (Q134, the phone's old clip rule). Stable either way.
    static func ordered(_ items: [Item]) -> [Item] {
        FilenameDate.chronologicalOrder(items.map(\.date)).map { items[$0] }
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
            case .video:
                // C68: its frame where its speech starts, then the speech in its place.
                pictures.append(Placement(url: item.url, offsetSeconds: elapsed, isVideoFrame: true))
                clips.append(item.url)
                elapsed += max(0, clipDuration(item.url))
            }
        }
        return Composition(clips: clips, pictures: pictures)
    }

    /// One clip's place in a merged note (C124, D35). The type lives in `MemoMetadata.swift`
    /// (the share extension compiles that file but not this one).
    typealias ClipEntry = ClipManifestEntry

    /// The manifest of `clips` stitched in this order. `clipDuration` as in `compose`; `dates`
    /// gives each clip's message time.
    static func clipManifest(clips: [URL], dates: (URL) -> Date?, clipDuration: (URL) -> Double) -> [ClipEntry] {
        var elapsed = 0.0
        var out: [ClipEntry] = []
        for url in clips {
            let d = max(0, clipDuration(url))
            guard d > 0 else { continue }          // the stitcher skips an unreadable clip too
            out.append(ClipEntry(filename: url.lastPathComponent, startSeconds: elapsed,
                                 recordedAt: dates(url).map { ISO8601.string(from: $0) }))
            elapsed += d
        }
        return out
    }

    /// The moments (seconds) at which a clip OTHER THAN THE FIRST begins: the forced paragraph
    /// breaks of a merged note (C124).
    static func breakStarts(_ manifest: [ClipEntry]) -> [Double] {
        manifest.dropFirst().map(\.startSeconds).filter { $0 > 0 }
    }

    /// The body of a note made of pictures alone: each one its own paragraph (C12/C13).
    static func pictureOnlyBody(count: Int) -> String {
        BodyV2Marker.block(Array(stride(from: 1, through: max(0, count), by: 1)))
    }

    /// File extensions the import layer treats as pictures (C238).
    static let pictureExtensions: Set<String> = ImportKinds.imageExtensions

    static func isPictureName(_ url: URL) -> Bool { pictureExtensions.contains(url.pathExtension.lowercased()) }

    /// Extensions a viewer/vault cannot be trusted to show — converted to JPEG on the way in.
    static let convertToJPEGExtensions: Set<String> = ["heic", "heif", "tif", "tiff", "bmp"]
}
