import AVFoundation
import Foundation

/// Pure fallback logic for missing file tags (host-less unit-tested): the
/// confirm sheet only appears when a tag is missing, pre-filled from these.
enum AudiobookMetadataDefaults {
    /// Resolve possibly-missing embedded tags against the source filename.
    /// `needsConfirmation` is true whenever either tag was absent — that's the
    /// one-time editable confirm sheet trigger (spec: capture asks NOTHING;
    /// import only confirms when tags are missing).
    static func resolve(title: String?, author: String?, filename: String)
        -> (title: String, author: String, needsConfirmation: Bool) {
        let cleanTitle = normalized(title)
        let cleanAuthor = normalized(author)
        return (
            title: cleanTitle ?? filenameTitle(filename),
            author: cleanAuthor ?? "",
            needsConfirmation: cleanTitle == nil || cleanAuthor == nil
        )
    }

    /// "The_Beginning_of_Infinity.m4b" → "The Beginning of Infinity".
    static func filenameTitle(_ filename: String) -> String {
        var name = (filename as NSString).deletingPathExtension
        name = name.replacingOccurrences(of: "_", with: " ")
        let collapsed = name
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? "Untitled audiobook" : collapsed
    }

    private static func normalized(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

/// A finished import waiting (at most) for the user to confirm missing tags.
struct PendingAudiobookImport: Identifiable {
    var book: Audiobook
    var needsConfirmation: Bool
    var id: UUID { book.id }
}

/// Imports an audiobook picked in Files/iCloud: COPY into
/// `Documents/audiobooks/<id>/`, read the embedded tags (title / author /
/// cover art / chapter list via AVAsset metadata), and build the `Audiobook`
/// record. The copy + tag read run off the main actor (book files are big).
///
/// MULTI-SELECT (Bound-style): picking several files at once imports them as
/// ONE book — sorted by filename (Finder-style numeric order), each file
/// becoming a chapter. Book-level tags come from the first file's ALBUM tag
/// (the title tag on file-per-chapter rips is usually the chapter's name).
enum AudiobookImporter {
    enum ImportError: LocalizedError {
        case copyFailed
        case unreadable
        case emptySelection

        var errorDescription: String? {
            switch self {
            case .copyFailed: return "The file couldn’t be copied into Skrift."
            case .unreadable: return "That file doesn’t look like a playable audiobook."
            case .emptySelection: return "No files were selected."
            }
        }
    }

    /// One or more picked files → ONE pending audiobook. A single file keeps
    /// the original behavior (embedded m4b chapter track honored); multiple
    /// files become an ordered file-per-chapter book.
    static func importBook(from sources: [URL], libraryDirectory: URL) async throws -> PendingAudiobookImport {
        guard let first = sources.first else { throw ImportError.emptySelection }
        if sources.count == 1 {
            return try await importSingleFile(from: first, libraryDirectory: libraryDirectory)
        }
        return try await importParts(from: sources, libraryDirectory: libraryDirectory)
    }

    /// Copy `source` into the library folder and read its tags. Returns the
    /// pending import — the caller adds it to the store directly when the tags
    /// were complete, or shows the editable confirm sheet first.
    static func importBook(from source: URL, libraryDirectory: URL) async throws -> PendingAudiobookImport {
        try await importBook(from: [source], libraryDirectory: libraryDirectory)
    }

    private static func importSingleFile(from source: URL, libraryDirectory: URL) async throws -> PendingAudiobookImport {
        let id = UUID()
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let filename = "book.\(ext)"
        let folder = libraryDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let dest = folder.appendingPathComponent(filename)
        let coverDest = folder.appendingPathComponent("cover.jpg")
        let originalName = source.lastPathComponent

        // Copy + parse off the main actor — an m4b can be hundreds of MB.
        let parsed: ParsedTags = try await Task.detached(priority: .userInitiated) {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try materializingCopy(from: source, to: dest)
            } catch {
                DevLog.log("audiobook import COPY FAILED \(originalName): \(error)")
                try? FileManager.default.removeItem(at: folder)
                throw ImportError.copyFailed
            }

            let tags = await readTags(at: dest)
            guard tags.duration > 0 else {
                DevLog.log("audiobook import REJECTED (unreadable) \(originalName) — copiedBytes=\(copiedByteString(dest)) duration=\(tags.duration)")
                try? FileManager.default.removeItem(at: folder)
                throw ImportError.unreadable
            }
            if let art = tags.artworkData {
                try? art.write(to: coverDest)
            }
            return tags
        }.value

        let resolved = AudiobookMetadataDefaults.resolve(
            title: parsed.title, author: parsed.author, filename: originalName
        )
        let book = Audiobook(
            id: id,
            audioFilename: filename,
            title: resolved.title,
            author: resolved.author,
            duration: parsed.duration,
            chapters: parsed.chapters,
            hasCover: parsed.artworkData != nil && FileManager.default.fileExists(atPath: coverDest.path)
        )
        return PendingAudiobookImport(book: book, needsConfirmation: resolved.needsConfirmation)
    }

    // MARK: - Multi-file import (file-per-chapter books)

    private struct ParsedParts: Sendable {
        var filenames: [String]
        var durations: [TimeInterval]
        var title: String?
        var author: String?
        var hasCover: Bool
    }

    /// Several picked files → one book: sort by filename, copy each part into
    /// the book folder (an index prefix pins playback order), read per-file
    /// durations, and synthesize one chapter per file.
    private static func importParts(from sources: [URL], libraryDirectory: URL) async throws -> PendingAudiobookImport {
        let id = UUID()
        let folder = libraryDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let coverDest = folder.appendingPathComponent("cover.jpg")
        let ordered = sortedByFilename(sources)
        // The folder the parts came from usually IS the book ("Steal Like an
        // Artist/01.mp3") — a far better tag fallback than "01.mp3".
        let fallbackName = folderFallbackName(for: ordered[0])

        let parsed: ParsedParts = try await Task.detached(priority: .userInitiated) {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                throw ImportError.copyFailed
            }

            var filenames: [String] = []
            for (index, source) in ordered.enumerated() {
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                let name = String(format: "%03d_%@", index + 1, source.lastPathComponent)
                do {
                    try materializingCopy(from: source, to: folder.appendingPathComponent(name))
                } catch {
                    DevLog.log("audiobook part COPY FAILED \(source.lastPathComponent): \(error)")
                    try? FileManager.default.removeItem(at: folder)
                    throw ImportError.copyFailed
                }
                filenames.append(name)
            }

            var durations: [TimeInterval] = []
            for name in filenames {
                let partURL = folder.appendingPathComponent(name)
                let asset = makeAsset(url: partURL)
                let seconds = ((try? await asset.load(.duration)).map { CMTimeGetSeconds($0) }) ?? 0
                guard seconds.isFinite, seconds > 0 else {
                    DevLog.log("audiobook part REJECTED (unreadable) \(name) — copiedBytes=\(copiedByteString(partURL)) duration=\(seconds)")
                    try? FileManager.default.removeItem(at: folder)
                    throw ImportError.unreadable
                }
                durations.append(seconds)
            }

            // Book-level tags from the FIRST part. Prefer the ALBUM tag for
            // the title — on file-per-chapter rips the title tag is the
            // chapter's name, the album is the book.
            let tags = await readTags(at: folder.appendingPathComponent(filenames[0]))
            if let art = tags.artworkData {
                try? art.write(to: coverDest)
            }
            return ParsedParts(
                filenames: filenames,
                durations: durations,
                title: tags.albumTitle ?? tags.title,
                author: tags.author,
                hasCover: tags.artworkData != nil
            )
        }.value

        let resolved = AudiobookMetadataDefaults.resolve(
            title: parsed.title, author: parsed.author, filename: fallbackName
        )

        // One chapter per part, named from the original filename — the whole
        // chapter UI (lines, menu, scoped scrubber, ch. N attribution) then
        // works unchanged for multi-file books.
        var chapters: [AudiobookChapter] = []
        var total: TimeInterval = 0
        for (i, source) in ordered.enumerated() {
            chapters.append(AudiobookChapter(
                title: AudiobookMetadataDefaults.filenameTitle(source.lastPathComponent),
                start: total,
                duration: parsed.durations[i]
            ))
            total += parsed.durations[i]
        }

        let book = Audiobook(
            id: id,
            files: parsed.filenames,
            fileDurations: parsed.durations,
            title: resolved.title,
            author: resolved.author,
            duration: total,
            chapters: chapters,
            hasCover: parsed.hasCover && FileManager.default.fileExists(atPath: coverDest.path)
        )
        return PendingAudiobookImport(book: book, needsConfirmation: resolved.needsConfirmation)
    }

    /// Finder-style ordering ("2.mp3" before "10.mp3") — the order the parts
    /// play in and the chapter numbering.
    static func sortedByFilename(_ urls: [URL]) -> [URL] {
        urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// Tag fallback for a multi-file pick: the containing folder's name (the
    /// book), unless it's a bare root — then the first filename.
    static func folderFallbackName(for url: URL) -> String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        let trimmed = parent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" || trimmed == "." || trimmed == ".." {
            return url.lastPathComponent
        }
        return trimmed
    }

    // MARK: - Cloud-safe copy

    /// Copy a picked file into the library, MATERIALIZING it first if it lives in
    /// iCloud / a third-party File Provider and hasn't been downloaded to the
    /// device. A plain `copyItem` grabs the on-disk PLACEHOLDER for an un-downloaded
    /// cloud item — a 0-byte / undecodable copy → `readTags` sees `duration == 0` →
    /// the import rejects a perfectly good book ("doesn't look like a playable
    /// audiobook"). A COORDINATED read forces the provider to download the real
    /// bytes first (same pattern as `ObsidianPublisher`); `startDownloadingUbiquitousItem`
    /// nudges iCloud along (throws + is ignored for non-iCloud sources). Must be
    /// called inside the source's security scope. Throws on a genuine copy failure.
    static func materializingCopy(from source: URL, to dest: URL) throws {
        try? FileManager.default.startDownloadingUbiquitousItem(at: source)
        var coordError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordError) { readURL in
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: readURL, to: dest)
            } catch {
                copyError = error
            }
        }
        if let copyError { throw copyError }
        if let coordError { throw coordError }
    }

    /// Byte size of a just-copied file, as a string for the devlog. A tiny value
    /// on an `.unreadable` reject means the source was an un-downloaded cloud
    /// placeholder; a real size means a codec AVFoundation couldn't decode.
    static func copiedByteString(_ url: URL) -> String {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int).map(String.init) ?? "?"
    }

    // MARK: - Asset construction

    /// Build the asset with PRECISE duration + timing. Without this option
    /// AVFoundation estimates duration lazily from the first frame's bitrate,
    /// which for many MP3s (VBR rips, big ID3 tags) comes back 0 / indefinite —
    /// the import then fails the `duration > 0` guard and rejects a perfectly
    /// playable book ("doesn't look like a playable audiobook"). m4b/m4a are
    /// unaffected; turning it on everywhere is the safe default for imports.
    static func makeAsset(url: URL) -> AVURLAsset {
        AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    }

    // MARK: - Tag reading (AVAsset metadata)

    struct ParsedTags: Sendable {
        var title: String?
        var author: String?
        /// The album tag — on file-per-chapter rips this is the BOOK title
        /// (the title tag is the chapter's). nil for most single-file m4bs.
        var albumTitle: String?
        var artworkData: Data?
        var chapters: [AudiobookChapter]
        var duration: TimeInterval
    }

    /// Read title / album / author / artwork / chapters from the file's
    /// metadata. Missing pieces come back nil/empty —
    /// `AudiobookMetadataDefaults` decides the fallbacks.
    static func readTags(at url: URL) async -> ParsedTags {
        let asset = makeAsset(url: url)
        let duration = ((try? await asset.load(.duration)).map { CMTimeGetSeconds($0) }) ?? 0
        let common = (try? await asset.load(.commonMetadata)) ?? []

        let title = await stringValue(in: common, identifier: .commonIdentifierTitle)
        var album = await stringValue(in: common, identifier: .commonIdentifierAlbumName)
        var author = await stringValue(in: common, identifier: .commonIdentifierArtist)
        if author == nil || album == nil {
            // m4b/mp3 files often carry these in the iTunes keyspace instead.
            let all = (try? await asset.load(.metadata)) ?? []
            // Separate statements: `??`'s right side is an autoclosure, which can't await.
            if author == nil {
                author = await stringValue(in: all, identifier: .iTunesMetadataArtist)
            }
            if author == nil {
                author = await stringValue(in: all, identifier: .iTunesMetadataAlbumArtist)
            }
            if album == nil {
                album = await stringValue(in: all, identifier: .iTunesMetadataAlbum)
            }
        }

        var artwork: Data?
        if let item = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork).first {
            artwork = (try? await item.load(.dataValue)) ?? nil
        }

        return ParsedTags(
            title: title,
            author: author,
            albumTitle: album,
            artworkData: artwork,
            chapters: await readChapters(of: asset, duration: duration),
            duration: duration
        )
    }

    /// The embedded chapter track (m4b). Empty when absent.
    static func readChapters(of asset: AVAsset, duration: TimeInterval) async -> [AudiobookChapter] {
        guard let locales = try? await asset.load(.availableChapterLocales),
              let locale = locales.first,
              let groups = try? await asset.loadChapterMetadataGroups(
                  withTitleLocale: locale, containingItemsWithCommonKeys: []
              ),
              !groups.isEmpty else { return [] }

        var chapters: [AudiobookChapter] = []
        for (index, group) in groups.enumerated() {
            let titleItem = AVMetadataItem.metadataItems(
                from: group.items, filteredByIdentifier: .commonIdentifierTitle
            ).first
            let title = ((try? await titleItem?.load(.stringValue)) ?? nil) ?? "Chapter \(index + 1)"
            let start = CMTimeGetSeconds(group.timeRange.start)
            let groupDuration = CMTimeGetSeconds(group.timeRange.duration)
            chapters.append(AudiobookChapter(
                title: title,
                start: max(0, start),
                duration: groupDuration.isFinite && groupDuration > 0
                    ? groupDuration
                    : max(0, duration - start)
            ))
        }
        return chapters.sorted { $0.start < $1.start }
    }

    private static func stringValue(in items: [AVMetadataItem], identifier: AVMetadataIdentifier) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first else {
            return nil
        }
        return (try? await item.load(.stringValue)) ?? nil
    }
}
