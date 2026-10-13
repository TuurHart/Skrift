import Foundation

/// The phone side of videos and files in a note body (D199, D202): copies a picked movie or file
/// into the recordings folder under its `NoteAttachment.filename` and appends it to the memo's
/// `attachmentManifest`. The asset sweep (`AssetMaterializer.captureFiles`) turns it into a
/// synced `MemoAsset`. Every rule lives in `NoteAttachment` (Shared); this only moves bytes.
enum NoteAttachmentStore {

    struct Added: Equatable {
        let entry: NoteAttachmentEntry
        let number: Int
    }

    static func fileURL(_ entry: NoteAttachmentEntry) -> URL {
        AppPaths.recordingsDirectory.appendingPathComponent(entry.filename)
    }

    static func fileExists(_ entry: NoteAttachmentEntry) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(entry).path)
    }

    /// Copy `source` (read with security scope when it needs one) into the note. `originalName`
    /// defaults to the source's name; `uti` to its extension's type. Returns nil on a read/write
    /// failure, leaving the memo untouched.
    @discardableResult
    static func add(fileURL source: URL, originalName: String? = nil, uti: String? = nil, to memo: Memo) -> Added? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: source) else { return nil }
        var meta = memo.metadata ?? MemoMetadata()
        var entries = meta.attachmentManifest ?? []
        let number = entries.count + 1
        let entry = NoteAttachment.makeEntry(owner: memo.id, number: number, source: source,
                                             originalName: originalName ?? source.lastPathComponent, uti: uti,
                                             byteCount: data.count)
        do {
            try FileManager.default.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
            try data.write(to: fileURL(entry), options: .atomic)
        } catch {
            DevLog.log("attachment: write failed \(error)")
            return nil
        }
        entries.append(entry)
        meta.attachmentManifest = entries
        memo.metadata = meta
        return Added(entry: entry, number: number)
    }

    /// Switch one attachment, or every one (`filename` nil = Set All): the shared rule over the
    /// note's own blocks.
    static func setSize(_ size: NoteAttachment.Size, filename: String?, memo: Memo) {
        NoteAttachment.setSize(size, filename: filename, all: NoteAttachment.allFilenames(of: memo), on: memo)
    }
}
