import Foundation
import SwiftData

/// The Mac side of photos in a note body (Q325, mock Q128-mac-note-photos, D181/D182): where a
/// photo added at the caret is stored, how a `[[img_NNN]]` marker resolves to its slot, and how
/// the owning `Memo` hears about it so the phone gets the picture.
///
/// A Mac note keeps its photos the way ingest does: the file under the working folder's
/// `images/`, an `image_manifest.json` beside it (marker N is the Nth entry, C169). When the note
/// is a synced memo, the memo's own `imageManifest` and a `MemoAsset` photo row follow, which is
/// what the phone reads. Foundation + SwiftData only, so the host-less test bundle drives it.
enum MacNotePhotos {

    struct Added: Equatable {
        /// The new marker's number (1-based into the manifest).
        let number: Int
        let filename: String
        /// The manifest length including the new photo.
        let manifestCount: Int
        let fileURL: URL
    }

    static let manifestName = "image_manifest.json"

    // MARK: reading

    /// Lenient on purpose: a manifest written by an older ingest may lack `offsetSeconds`, and
    /// `NoteBody` has always read it key by key, so a strict decode would blank old photos.
    static func manifest(in folder: URL) -> [ImageManifestEntry] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(manifestName)),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return arr.map { item in      // keeps positions: marker N is the Nth entry
            ImageManifestEntry(filename: (item["filename"] as? String) ?? "",
                               offsetSeconds: (item["offsetSeconds"] as? Double) ?? 0,
                               text: item["text"] as? String)
        }
    }

    static func imagesFolder(in folder: URL) -> URL {
        folder.appendingPathComponent("images", isDirectory: true)
    }

    /// The photo file marker `number` points at, when the file is on disk.
    static func fileURL(number: Int, folder: URL) -> URL? {
        let entries = manifest(in: folder)
        guard number >= 1, number <= entries.count, !entries[number - 1].filename.isEmpty else { return nil }
        let url = imagesFolder(in: folder).appendingPathComponent(entries[number - 1].filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// What marker `number` stands for right now. `hasAsset` asks the synced store whether a
    /// photo row exists for a filename (a row without its file = the file is on its way).
    static func slot(number: Int, folder: URL?, hasAsset: (String) -> Bool) -> NotePhoto.Slot {
        guard let folder else { return .text }
        let names = manifest(in: folder).map(\.filename)
        let images = imagesFolder(in: folder)
        return NotePhoto.slot(number: number, manifest: names,
                              fileExists: { FileManager.default.fileExists(atPath: images.appendingPathComponent($0).path) },
                              hasAsset: hasAsset)
    }

    /// Whether a synced photo row exists for `filename` (counted, so no blob is faulted in).
    static func hasAsset(filename: String, in context: ModelContext?) -> Bool {
        guard let context, !filename.isEmpty else { return false }
        var d = FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.filename == filename })
        d.fetchLimit = 1
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }

    // MARK: adding

    /// Store `imageData` as the note's next photo and tell the memo. `memo`/`context` are nil
    /// for a note that is not a synced memo (the files and manifest still land, for the export).
    /// Returns nil when the bytes are not a picture or the file cannot be written.
    @discardableResult
    static func add(imageData: Data, to pf: PipelineFile, memo: Memo?, context: ModelContext?) -> Added? {
        guard let norm = ImageNormalise.normalise(imageData) else { return nil }
        let fm = FileManager.default

        var folder = pf.workingFolder
        if folder == nil, let memo {
            // An unrated note's projection has no folder until it has media: use the same
            // cache folder its other media lives in (`MemoNoteProjection.materialiseMedia`).
            let made = MemoNoteProjection.mediaFolder(for: memo.id)
            try? fm.createDirectory(at: made, withIntermediateDirectories: true)
            pf.path = pf.sourceType == .capture ? made.path : made.appendingPathComponent("note.md").path
            folder = pf.workingFolder
        }
        guard let folder else { return nil }

        var entries = manifest(in: folder)
        let number = entries.count + 1
        let owner = memo?.id ?? UUID(uuidString: pf.id) ?? UUID()
        let filename = NotePhoto.filename(owner: owner, number: number, ext: norm.ext)
        let images = imagesFolder(in: folder)
        let dest = images.appendingPathComponent(filename)
        do {
            try fm.createDirectory(at: images, withIntermediateDirectories: true)
            try norm.data.write(to: dest, options: .atomic)
            entries.append(ImageManifestEntry(filename: filename, offsetSeconds: 0))
            let json = try JSONEncoder().encode(entries)
            try json.write(to: folder.appendingPathComponent(manifestName), options: .atomic)
        } catch {
            try? fm.removeItem(at: dest)
            return nil
        }

        if let memo, let context {
            var meta = memo.metadata ?? MemoMetadata()
            var manifest = meta.imageManifest ?? []
            manifest.append(ImageManifestEntry(filename: filename, offsetSeconds: 0))
            meta.imageManifest = manifest
            memo.metadata = meta
            if !hasAsset(filename: filename, in: context) {
                context.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.photo,
                                         filename: filename, blob: norm.data))
            }
            // Q42: a photo is not a words edit. The marker's text change rides the body write-back.
            memo.markEdited(stampWords: false)
            try? context.save()
        }
        return Added(number: number, filename: filename, manifestCount: entries.count, fileURL: dest)
    }

    // MARK: markup

    /// Quick Look's Markup rewrote the photo file: re-mirror it so the phone gets the marked-up
    /// version. The phone's asset sweep compares `byteCount` with the file, so the row is updated
    /// in place. No-op without a synced row.
    @discardableResult
    static func markupSaved(fileURL: URL, memo: Memo?, context: ModelContext?) -> Bool {
        guard let memo, let context, let data = try? Data(contentsOf: fileURL) else { return false }
        let name = fileURL.lastPathComponent
        let memoID = memo.id
        let kind = MemoAsset.Kind.photo
        var d = FetchDescriptor<MemoAsset>(predicate: #Predicate {
            $0.memoID == memoID && $0.kind == kind && $0.filename == name
        })
        d.fetchLimit = 1
        if let row = (try? context.fetch(d))?.first {
            row.blob = data
            row.byteCount = data.count
        } else {
            context.insert(MemoAsset(memoID: memoID, kind: kind, filename: name, blob: data))
        }
        memo.markEdited(stampWords: false)
        try? context.save()
        return true
    }
}
