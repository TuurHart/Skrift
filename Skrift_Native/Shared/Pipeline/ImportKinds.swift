import Foundation
import UniformTypeIdentifiers

/// The ONE accepted-types list (C238, C199, D19). Extension → kind, for Open-in, the share
/// extension, the in-app Files picker and the Mac drop / +Upload. A file name resolves to the
/// same kind on every surface; each surface then decides what it can DO with that kind, but
/// none keeps its own list of extensions.
///
/// Pure (Foundation + UniformTypeIdentifiers only), so the share extension and the host-less
/// Mac test bundle compile it directly.
enum ImportKinds {
    enum Kind: String, CaseIterable, Sendable {
        /// A voice note / recording. Imported, transcribed.
        case audio
        /// A movie container: audio is stripped and transcribed, a frame is the thumbnail.
        case video
        /// A picture. Becomes an image note (or rides along with a clip).
        case image
        /// A text or markdown file: its text is the note body.
        case text
        /// A document (PDF): kept as a file capture.
        case document
        /// An audiobook or ePub or a shared `.skriftbook`: goes to the Books library, never a note.
        case book
    }

    static let audioExtensions: Set<String> =
        ["m4a", "mp3", "wav", "aac", "caf", "aiff", "aif", "opus", "ogg", "oga", "flac"]

    /// `mp4` / `mov` are containers: they resolve to `.video`, and a surface that finds no video
    /// track in one treats it as audio (D-B26).
    static let videoExtensions: Set<String> =
        ["mov", "mp4", "m4v", "qt", "avi", "mpg", "mpeg", "3gp", "3g2", "webm", "mkv"]

    static let imageExtensions: Set<String> =
        ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"]

    static let textExtensions: Set<String> = ["md", "markdown", "txt"]

    static let documentExtensions: Set<String> = ["pdf"]

    static let bookExtensions: Set<String> = ["epub", "m4b", "skriftbook"]

    static func extensions(of kind: Kind) -> Set<String> {
        switch kind {
        case .audio: return audioExtensions
        case .video: return videoExtensions
        case .image: return imageExtensions
        case .text: return textExtensions
        case .document: return documentExtensions
        case .book: return bookExtensions
        }
    }

    /// The kind of a file extension (any case, no dot); nil when Skrift takes no such file.
    static func kind(forExtension ext: String) -> Kind? {
        let e = ext.lowercased()
        return Kind.allCases.first { extensions(of: $0).contains(e) }
    }

    static func kind(of url: URL) -> Kind? { kind(forExtension: url.pathExtension) }

    /// What the note doors take: everything but books (a book has its own door in the library).
    static let noteKinds: [Kind] = [.audio, .video, .image, .text, .document]

    /// The `allowedContentTypes` of a picker, derived from the extensions above: each kind's
    /// parent type (so the picker greys out nothing the kind covers) plus one type per extension
    /// the system knows (so `.opus`, `.md`, `.mkv` stay pickable). De-duplicated, stable order.
    static func allowedContentTypes(for kinds: [Kind] = noteKinds) -> [UTType] {
        var out: [UTType] = []
        func add(_ t: UTType?) { if let t, !out.contains(t) { out.append(t) } }
        for kind in kinds {
            switch kind {
            case .audio: add(.audio)
            case .video: add(.movie)
            case .image: add(.image)
            case .text: add(.plainText)
            case .document: add(.pdf)
            case .book: break
            }
            for ext in extensions(of: kind).sorted() { add(UTType(filenameExtension: ext)) }
        }
        return out
    }
}
