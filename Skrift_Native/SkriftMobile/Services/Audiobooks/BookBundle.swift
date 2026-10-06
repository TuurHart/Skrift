import Foundation
import ZIPFoundation

/// Reads and writes `.skriftbook` — one file holding one shared book.
///
/// A thin shell over `BookBundleRules`: every decision about what a bundle
/// carries lives there and is unit-tested; this type only moves bytes. The
/// archive is a plain ZIP (conforming to `public.zip-archive`, so renaming it to
/// `.zip` gives someone without Skrift something they can open), streamed
/// entry-by-entry so a 797 MB book never has to fit in memory. Audio is stored
/// uncompressed — it already is — and the JSON is deflated.
enum BookBundle {

    enum BundleError: LocalizedError {
        case unreadableArchive
        case missingManifest
        case unsupportedBundle
        case missingAudio(String)

        var errorDescription: String? {
            switch self {
            case .unreadableArchive:  return "This file isn't a Skrift book."
            case .missingManifest:    return "This book file is missing its details."
            case .unsupportedBundle:  return "This book was shared from a newer version of Skrift."
            case .missingAudio(let n): return "The audio file \(n) is missing from this book."
            }
        }
    }

    /// This build's file extension and type identifier, read from the Info.plist
    /// keys `project.yml` fills per config.
    ///
    /// **They differ between Dev and prod on purpose.** Both builds are installed
    /// on the same phone by design, and two apps claiming one document type makes
    /// routing between them undefined — "Open in Skrift" could hand a test bundle
    /// to the production app. Distinct extensions (`.skriftbookdev` vs
    /// `.skriftbook`) mean the OS can never make that mistake, since extension is
    /// what it falls back to. Defaults keep a unit test working without a bundle.
    static var fileExtension: String {
        Bundle.main.object(forInfoDictionaryKey: "SkriftBookExtension") as? String ?? "skriftbook"
    }

    /// True when `url` is a book bundle this build owns — the test
    /// `AppURLHandler` runs before it decides an incoming file is ours.
    static func isBookBundle(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == fileExtension.lowercased()
    }

    /// Where a packaged bundle waits for the share sheet. A file name, not a
    /// temp-random one, because the receiver sees it — and the book's own title
    /// is the only sensible thing to call it.
    static func stagedURL(for book: Audiobook) -> URL {
        let safe = book.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = safe.isEmpty ? "Book" : safe
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).\(fileExtension)")
    }

    // MARK: - Writing

    /// Pack `book` into a `.skriftbook` at `destination`.
    ///
    /// `progress` reports bytes written against the total it will write, so the
    /// share sheet can show a real bar rather than a spinner — a 797 MB book
    /// takes long enough that an honest number matters.
    @discardableResult
    static func write(book: Audiobook,
                      folder: URL,
                      to destination: URL,
                      progress: ((Double) -> Void)? = nil) throws -> BookBundleManifest {
        let fm = FileManager.default
        let derived = derivedSidecars(folder: folder, fileCount: book.files.count)
        let coverURL = folder.appendingPathComponent(BookBundleManifest.Dir.cover)
        let hasCover = fm.fileExists(atPath: coverURL.path)

        let manifest = BookBundleRules.manifest(
            for: book,
            hasCover: hasCover,
            textFilenames: attachedTexts(book: book, folder: folder),
            transcriptFilenames: derived.transcripts,
            alignmentFilenames: derived.alignments)

        try? fm.removeItem(at: destination)
        let archive = try Archive(url: destination, accessMode: .create)

        let manifestData = try JSONEncoder().encode(manifest)
        try archive.addEntry(with: BookBundleManifest.Dir.manifest,
                             type: .file,
                             uncompressedSize: Int64(manifestData.count),
                             compressionMethod: .deflate) { position, size in
            manifestData.subdata(in: Int(position)..<Int(position) + size)
        }

        // Everything after the manifest is a file already on disk, added in the
        // order `entryPaths` declares so the two halves stay in step.
        let payload = manifest.entryPaths.dropFirst()
        let total = payload.reduce(Int64(0)) { sum, path in
            sum + (fileSize(at: folder.appendingPathComponent(sourceName(for: path))) ?? 0)
        }
        var written: Int64 = 0
        progress?(0)

        for path in payload {
            let source = folder.appendingPathComponent(sourceName(for: path))
            guard fm.fileExists(atPath: source.path) else {
                // A sidecar can vanish between the listing and the write; the book
                // is still shareable without it. Missing AUDIO is fatal, though —
                // a bundle without its audio is not a book.
                if path.hasPrefix("\(BookBundleManifest.Dir.audio)/") {
                    throw BundleError.missingAudio(sourceName(for: path))
                }
                continue
            }
            // Audio is already compressed; deflating it costs minutes and saves
            // nothing. The JSON and the ePub do compress, so they get deflate.
            let isAudio = path.hasPrefix("\(BookBundleManifest.Dir.audio)/")
            try archive.addEntry(with: path,
                                 fileURL: source,
                                 compressionMethod: isAudio ? .none : .deflate)
            written += fileSize(at: source) ?? 0
            progress?(total > 0 ? min(1, Double(written) / Double(total)) : 1)
        }

        progress?(1)
        return manifest
    }

    /// The bytes a bundle for this book would weigh — what the share sheet shows
    /// before you commit to packaging ("Audio + book text · 797 MB").
    static func estimatedSize(book: Audiobook, folder: URL) -> Int64 {
        let derived = derivedSidecars(folder: folder, fileCount: book.files.count)
        let names = book.files
            + attachedTexts(book: book, folder: folder)
            + derived.transcripts + derived.alignments
            + [BookBundleManifest.Dir.cover]
        return names.reduce(0) { $0 + (fileSize(at: folder.appendingPathComponent($1)) ?? 0) }
    }

    // MARK: - Reading

    /// Read just the manifest, without unpacking. This is what decides whether to
    /// show "Add this book?" or "Already in your books", so it has to be cheap
    /// and it has to run before a single byte lands in the library.
    static func readManifest(at url: URL) throws -> BookBundleManifest {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        guard let archive = try? Archive(url: url, accessMode: .read) else {
            throw BundleError.unreadableArchive
        }
        guard let entry = archive[BookBundleManifest.Dir.manifest] else {
            throw BundleError.missingManifest
        }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }

        guard let manifest = try? JSONDecoder().decode(BookBundleManifest.self, from: data) else {
            throw BundleError.missingManifest
        }
        guard manifest.isReadable else { throw BundleError.unsupportedBundle }
        return manifest
    }

    /// Pull just the cover out of a bundle, so the "Add this book?" sheet can show
    /// the real book before anything is unpacked. One small entry out of an archive
    /// that may be 797 MB. nil when the sender had no cover art.
    static func coverImageData(at url: URL, manifest: BookBundleManifest) -> Data? {
        guard let name = manifest.coverFilename else { return nil }
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        guard let archive = try? Archive(url: url, accessMode: .read),
              let entry = archive[name] else { return nil }
        var data = Data()
        guard (try? archive.extract(entry, consumer: { data.append($0) })) != nil else { return nil }
        return data
    }

    /// Unpack a bundle into `folder` (the receiving device's book folder) and
    /// return the record to persist.
    ///
    /// The re-stamp at the end is not optional: sidecar staleness is keyed on the
    /// LOCAL audio's `"<size>:<mtime>"`, and mtime changes the moment this device
    /// writes the file — so without it a fully transcribed book would arrive
    /// looking untranscribed.
    @discardableResult
    static func unpack(at url: URL,
                       manifest: BookBundleManifest,
                       into folder: URL,
                       library: AudiobookLibraryStore,
                       now: Date = Date(),
                       progress: ((Double) -> Void)? = nil) throws -> Audiobook {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        guard let archive = try? Archive(url: url, accessMode: .read) else {
            throw BundleError.unreadableArchive
        }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let payload = Array(manifest.entryPaths.dropFirst())
        let total = payload.reduce(Int64(0)) { $0 + Int64(archive[$1]?.uncompressedSize ?? 0) }
        var written: Int64 = 0
        progress?(0)

        for path in payload {
            guard let entry = archive[path] else {
                if path.hasPrefix("\(BookBundleManifest.Dir.audio)/") {
                    throw BundleError.missingAudio(sourceName(for: path))
                }
                continue
            }
            // Flatten back out: the archive's directories are for legibility when
            // someone renames the file to .zip; on disk a book folder is flat.
            let target = folder.appendingPathComponent(sourceName(for: path))
            try? fm.removeItem(at: target)
            _ = try archive.extract(entry, to: target)
            written += Int64(entry.uncompressedSize)
            progress?(total > 0 ? min(1, Double(written) / Double(total)) : 1)
        }

        let book = BookBundleRules.imported(manifest, at: now)
        BookTranscriptStore(directory: library.directory)
            .restampTranscripts(for: book, in: folder)
        progress?(1)
        return book
    }

    // MARK: - Helpers

    /// Archive path → the flat filename it has inside a book folder.
    private static func sourceName(for entryPath: String) -> String {
        (entryPath as NSString).lastPathComponent
    }

    private static func fileSize(at url: URL) -> Int64? {
        AudiobookPaths.fileSize(at: url)
    }

    /// The attached texts actually sitting in the folder. The disk is the durable
    /// truth for what's attached (the record's fields are local-only and stripped
    /// on the way out), so a bundle can't promise a text file that isn't there.
    private static func attachedTexts(book: Audiobook, folder: URL) -> [String] {
        let onDisk = Set(BookAlignmentRunner.orphanedAttachedTexts(
            inFolder: folder, audioFiles: book.files))
        let declared = book.attachedTextFilenames.filter { onDisk.contains($0) }
        return declared + onDisk.subtracting(declared).sorted()
    }

    private static func derivedSidecars(folder: URL, fileCount: Int)
        -> (transcripts: [String], alignments: [String]) {
        let fm = FileManager.default
        var transcripts: [String] = []
        var alignments: [String] = []
        for i in 0..<fileCount {
            let t = "transcript_f\(i).json"
            let a = "alignment_f\(i).json"
            if fm.fileExists(atPath: folder.appendingPathComponent(t).path) { transcripts.append(t) }
            if fm.fileExists(atPath: folder.appendingPathComponent(a).path) { alignments.append(a) }
        }
        return (transcripts, alignments)
    }
}
