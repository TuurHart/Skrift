import Foundation
import SwiftData

/// The Mac side of videos and files in a note body (D199, D202): where an attachment added by
/// drop / paste / Insert is stored, how its synced bytes land on disk, and how the owning `Memo`
/// hears about it. Every rule (markers, filenames, sizes, labels, export names) is
/// `NoteAttachment` in Shared; this file only moves bytes, the way `MacNotePhotos` does for photos.
///
/// On disk: the files under the working folder's `attachments/`, an `attachment_manifest.json`
/// beside it (marker N is the Nth entry). A synced memo carries the same list in
/// `MemoMetadata.attachmentManifest` plus one `MemoAsset` row per file.
enum MacNoteAttachments {

    struct Added: Equatable {
        let entry: NoteAttachmentEntry
        /// The new marker's number (1-based into the manifest).
        let number: Int
        let fileURL: URL
    }

    static let manifestName = "attachment_manifest.json"

    static func folder(in working: URL) -> URL {
        working.appendingPathComponent("attachments", isDirectory: true)
    }

    static func manifest(in working: URL) -> [NoteAttachmentEntry] {
        guard let data = try? Data(contentsOf: working.appendingPathComponent(manifestName)) else { return [] }
        return (try? JSONDecoder().decode([NoteAttachmentEntry].self, from: data)) ?? []
    }

    /// The note's attachment list: the memo's synced manifest when it has one, else the folder's.
    static func manifest(memo: Memo?, working: URL?) -> [NoteAttachmentEntry] {
        if let m = memo?.metadata?.attachmentManifest, !m.isEmpty { return m }
        return working.map { manifest(in: $0) } ?? []
    }

    /// The file an entry points at, when it is on disk.
    static func fileURL(_ entry: NoteAttachmentEntry, working: URL?) -> URL? {
        guard let working else { return nil }
        let url = folder(in: working).appendingPathComponent(entry.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether a file the person dropped / pasted / picked becomes an attachment rather than a photo.
    static func isAttachment(_ url: URL) -> Bool {
        !NotePhoto.acceptedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: adding

    /// Copy `source` into the note as its next attachment and tell the memo. `memo` / `context`
    /// are nil for a note that is not a synced memo (the file and manifest still land, for the
    /// export). Returns nil when the file cannot be read or written.
    @discardableResult
    static func add(fileURL source: URL, to pf: PipelineFile, memo: Memo?, context: ModelContext?) -> Added? {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: source) else { return nil }
        var working = pf.workingFolder
        if working == nil, let memo {
            let made = MemoNoteProjection.mediaFolder(for: memo.id)
            try? fm.createDirectory(at: made, withIntermediateDirectories: true)
            pf.path = pf.sourceType == .capture ? made.path : made.appendingPathComponent("note.md").path
            working = pf.workingFolder
        }
        guard let working else { return nil }

        var entries = manifest(memo: memo, working: working)
        let number = entries.count + 1
        let owner = memo?.id ?? UUID(uuidString: pf.id) ?? UUID()
        let entry = NoteAttachment.makeEntry(owner: owner, number: number, source: source,
                                             originalName: source.lastPathComponent, uti: nil, byteCount: data.count)
        let dir = folder(in: working)
        let dest = dir.appendingPathComponent(entry.filename)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dest, options: .atomic)
            entries.append(entry)
            try JSONEncoder().encode(entries).write(to: working.appendingPathComponent(manifestName), options: .atomic)
        } catch {
            try? fm.removeItem(at: dest)
            return nil
        }

        if let memo, let context {
            var meta = memo.metadata ?? MemoMetadata()
            meta.attachmentManifest = entries
            memo.metadata = meta
            context.insert(MemoAsset(memoID: memo.id, kind: entry.kind, filename: entry.filename, blob: data))
            // An attachment is not a words edit. The marker's text change rides the body write-back.
            memo.markEdited(stampWords: false)
            try? context.save()
        }
        return Added(entry: entry, number: number, fileURL: dest)
    }

    // MARK: small / large (D202)

    /// The filenames drawn large: the memo's synced list, else none (a Mac-only note draws small).
    static func large(memo: Memo?) -> [String]? { memo?.metadata?.largeAttachments }

    /// Whether the note's ⋯ menu offers Set All (it holds a photo, video, file or captured PDF).
    static func hasBlocks(memo: Memo?) -> Bool {
        guard let memo else { return false }
        return !NoteAttachment.allFilenames(of: memo).isEmpty
    }

    /// Switch one attachment, or every one (`filename` nil = the ⋯ menu's Set All): the shared
    /// rule, then the save and the redraw notice.
    static func setSize(_ size: NoteAttachment.Size, filename: String?, memo: Memo, allFilenames: [String],
                        context: ModelContext?) {
        NoteAttachment.setSize(size, filename: filename, all: allFilenames, on: memo)
        try? context?.save()
        NotificationCenter.default.post(name: sizesChanged, object: nil)
    }

    /// Posted after a size switch, so an open body redraws its blocks (the ⋯ menu is another view).
    static let sizesChanged = Notification.Name("SkriftNoteBlockSizesChanged")

    // MARK: sync heal

    /// Write any of `memo`'s attachment assets missing from `pf`'s `attachments/` folder and bring
    /// `attachment_manifest.json` in line. Assets are fetched only while a file is missing, so the
    /// steady-state sweep touches no blobs. Returns true when it wrote something.
    @discardableResult
    static func materializeMissing(memo: Memo, pf: PipelineFile, fetchAssets: () -> [MemoAsset]) -> Bool {
        let entries = memo.metadata?.attachmentManifest ?? []
        guard !entries.isEmpty, let working = pf.workingFolder else { return false }
        let fm = FileManager.default
        let dir = folder(in: working)
        var wrote = false
        let missing = Set(entries.map(\.filename).filter { !$0.isEmpty && !fm.fileExists(atPath: dir.appendingPathComponent($0).path) })
        if !missing.isEmpty {
            for asset in fetchAssets() where missing.contains(asset.filename)
                && (asset.kind == MemoAsset.Kind.file || asset.kind == MemoAsset.Kind.video) && !asset.blob.isEmpty {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                if (try? asset.blob.write(to: dir.appendingPathComponent(asset.filename))) != nil { wrote = true }
            }
        }
        if manifest(in: working) != entries, let data = try? JSONEncoder().encode(entries) {
            try? fm.createDirectory(at: working, withIntermediateDirectories: true)
            if (try? data.write(to: working.appendingPathComponent(manifestName), options: .atomic)) != nil { wrote = true }
        }
        return wrote
    }

    // MARK: export

    /// Replace `[[vid_NNN]]` / `[[file_NNN]]` with embeds of the files copied beside the note
    /// (`NoteAttachment.convertMarkers`), through the same placer photos use (C58 ownership copy,
    /// the Q365 dry run). Returns the markdown and the copy count.
    static func convertMarkers(_ markdown: String, working: URL?, safe: String, into attDir: URL,
                               profile: ExportProfile, place: VaultExporter.Placer) -> (String, Int) {
        guard markdown.contains("[[vid_") || markdown.contains("[[file_") else { return (markdown, 0) }
        let entries = working.map { manifest(in: $0) } ?? []
        let dir = working.map { folder(in: $0) }
        let r = ExportBody.convertAttachmentMarkers(markdown, manifest: entries, stem: safe, profile: profile) { source, preferred in
            guard let dir else { return nil }
            let file = dir.appendingPathComponent(source)
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return place(file, preferred, attDir)?.lastPathComponent
        }
        return (r.markdown, r.placed)
    }
}
