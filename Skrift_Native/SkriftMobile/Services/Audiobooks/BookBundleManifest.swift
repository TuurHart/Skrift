import Foundation

/// The manifest at the root of a `.skriftbook` — the single file a shared book
/// travels as. It is written by the packager and is the only part of a bundle
/// the importer parses before unpacking anything.
///
/// **The rule Tuur signed off 2026-08-11: send the BOOK, never your relationship
/// to it.** Every book-side part rides along if the sender has it — audio, cover,
/// attached texts, transcript and alignment sidecars — with no picker and nothing
/// optional ("Share what I have"). What stays home is everything describing how
/// *you* have been reading: playback position ("don't share my location, it's a
/// new book for them"), bookmarks, playback rate, and the notes and captures you
/// made about the book. Those are your memos, not the book.
///
/// Audio is the one part that is always present — an audiobook has it by
/// definition. That is why sharing needs no options at all, and why a bundle's
/// transcript can never be attached to a different rip: it always arrives with
/// the audio it was measured against.
struct BookBundleManifest: Codable, Equatable, Sendable {
    /// Bumped only when the layout changes in a way an older importer cannot
    /// read. We own this format forever, so the version is explicit.
    static let currentSchema = 1

    /// Directory names inside the archive. Flat and boring on purpose — a
    /// `.skriftbook` conforms to `public.zip-archive`, so renaming it to `.zip`
    /// has to give someone without Skrift something legible.
    enum Dir {
        static let audio = "audio"
        static let text = "text"
        static let derived = "derived"
        static let manifest = "manifest.json"
        static let cover = "cover.jpg"
    }

    var schema: Int
    /// The book record with the reading state already stripped —
    /// `Audiobook.sanitizedForSharing()`.
    var book: Audiobook
    /// Ordered audio filenames living under `audio/`, original names preserved.
    /// Never empty in a valid bundle.
    var audioFilenames: [String]
    /// `cover.jpg` when the sender had cover art, else nil.
    var coverFilename: String?
    /// Attached ePub / plain-text filenames under `text/`. Empty when the sender
    /// has no ePub — "If I have the ePUB also share the EPUB. If I don't, don't."
    var textFilenames: [String]
    /// `transcript_f<i>.json` sidecars under `derived/`. Empty when the book was
    /// never transcribed — same rule, present-if-present.
    var transcriptFilenames: [String]
    /// `alignment_f<i>.json` sidecars under `derived/`, pairing texts to audio.
    var alignmentFilenames: [String]

    init(schema: Int = BookBundleManifest.currentSchema,
         book: Audiobook,
         audioFilenames: [String],
         coverFilename: String? = nil,
         textFilenames: [String] = [],
         transcriptFilenames: [String] = [],
         alignmentFilenames: [String] = []) {
        self.schema = schema
        self.book = book
        self.audioFilenames = audioFilenames
        self.coverFilename = coverFilename
        self.textFilenames = textFilenames
        self.transcriptFilenames = transcriptFilenames
        self.alignmentFilenames = alignmentFilenames
    }

    /// Every entry path the archive should contain, manifest first. The packager
    /// writes these and the importer expects them; keeping the mapping in one
    /// place stops the two halves drifting apart.
    var entryPaths: [String] {
        var paths = [Dir.manifest]
        paths += audioFilenames.map { "\(Dir.audio)/\($0)" }
        if let cover = coverFilename { paths.append(cover) }
        paths += textFilenames.map { "\(Dir.text)/\($0)" }
        paths += (transcriptFilenames + alignmentFilenames).map { "\(Dir.derived)/\($0)" }
        return paths
    }

    /// A bundle we can act on: a schema we understand and at least one audio
    /// file. A manifest that fails this is refused before anything is unpacked,
    /// so a truncated or foreign archive can never half-import a book.
    var isReadable: Bool {
        schema <= Self.currentSchema && schema > 0 && !audioFilenames.isEmpty
            && audioFilenames.count == book.files.count
    }
}

extension Audiobook {
    /// The share-side strip: the book without the sender's reading state.
    ///
    /// Builds on `sanitizedForSync()`, which already removes the local-only
    /// derived fields (`epubFilename(s)`, `epubChapters`, `detectedChapters`) —
    /// the receiver gets the FILES those derive from and re-derives its own, so
    /// shipping the sender's copies would only be a second source to drift.
    /// On top of that this zeroes what "my location" means: where you are in the
    /// book, how fast you play it, and when you last opened it.
    ///
    /// The `id` deliberately survives. It is what makes re-importing the same
    /// bundle land on "Already in your books" instead of a duplicate.
    func sanitizedForSharing() -> Audiobook {
        var copy = sanitizedForSync()
        copy.position = 0
        copy.playbackRate = 1.0
        copy.lastPlayedAt = nil
        return copy
    }
}

/// The pure decisions a share or an import makes, kept out of the zip shell so
/// they can be asserted without touching the filesystem.
enum BookBundleRules {

    /// What a bundle for this book would carry, given what is actually on disk.
    /// The caller supplies the facts (does a cover exist, which sidecars are
    /// there) and this decides — so "share what I have" is one rule in one
    /// place rather than a scatter of `if let`s in the packager.
    static func manifest(for book: Audiobook,
                         hasCover: Bool,
                         textFilenames: [String],
                         transcriptFilenames: [String],
                         alignmentFilenames: [String]) -> BookBundleManifest {
        BookBundleManifest(
            book: book.sanitizedForSharing(),
            audioFilenames: book.files,
            coverFilename: hasCover ? BookBundleManifest.Dir.cover : nil,
            textFilenames: textFilenames,
            transcriptFilenames: transcriptFilenames,
            alignmentFilenames: alignmentFilenames)
    }

    /// The already-have-it check. Keyed on the book id the bundle carries, which
    /// is why the id survives `sanitizedForSharing()`: importing the same file
    /// twice is a no-op, not a duplicate library entry.
    static func alreadyImported(_ manifest: BookBundleManifest, existing: [UUID]) -> Bool {
        existing.contains(manifest.book.id)
    }

    /// The `Audiobook` to persist on the receiving device: the bundle's record,
    /// stamped with THIS device's import time and its attached-text filenames
    /// re-pointed at the files that just landed. Chapter lists stay nil — the
    /// receiver re-derives them from the sidecars it now owns.
    static func imported(_ manifest: BookBundleManifest, at now: Date) -> Audiobook {
        var book = manifest.book
        book.importedAt = now
        book.modifiedAt = now
        book.setAttachedTexts(manifest.textFilenames)
        return book
    }
}
