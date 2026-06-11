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
enum AudiobookImporter {
    enum ImportError: LocalizedError {
        case copyFailed
        case unreadable

        var errorDescription: String? {
            switch self {
            case .copyFailed: return "The file couldn’t be copied into Skrift."
            case .unreadable: return "That file doesn’t look like a playable audiobook."
            }
        }
    }

    /// Copy `source` into the library folder and read its tags. Returns the
    /// pending import — the caller adds it to the store directly when the tags
    /// were complete, or shows the editable confirm sheet first.
    static func importBook(from source: URL, libraryDirectory: URL) async throws -> PendingAudiobookImport {
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
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: source, to: dest)
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw ImportError.copyFailed
            }

            let tags = await readTags(at: dest)
            guard tags.duration > 0 else {
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

    // MARK: - Tag reading (AVAsset metadata)

    struct ParsedTags: Sendable {
        var title: String?
        var author: String?
        var artworkData: Data?
        var chapters: [AudiobookChapter]
        var duration: TimeInterval
    }

    /// Read title / author / artwork / chapters from the file's metadata.
    /// Missing pieces come back nil/empty — `AudiobookMetadataDefaults` decides
    /// the fallbacks.
    static func readTags(at url: URL) async -> ParsedTags {
        let asset = AVURLAsset(url: url)
        let duration = ((try? await asset.load(.duration)).map { CMTimeGetSeconds($0) }) ?? 0
        let common = (try? await asset.load(.commonMetadata)) ?? []

        let title = await stringValue(in: common, identifier: .commonIdentifierTitle)
        var author = await stringValue(in: common, identifier: .commonIdentifierArtist)
        if author == nil {
            // m4b files often carry the author in the iTunes keyspace instead.
            let all = (try? await asset.load(.metadata)) ?? []
            author = await stringValue(in: all, identifier: .iTunesMetadataArtist)
                ?? (await stringValue(in: all, identifier: .iTunesMetadataAlbumArtist))
        }

        var artwork: Data?
        if let item = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork).first {
            artwork = (try? await item.load(.dataValue)) ?? nil
        }

        return ParsedTags(
            title: title,
            author: author,
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
