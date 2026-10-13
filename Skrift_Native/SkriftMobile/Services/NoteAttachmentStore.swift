import Foundation
import AVFoundation

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

    /// A movie's length (nil when unreadable).
    static func duration(of url: URL) -> Double? {
        let s = CMTimeGetSeconds(AVURLAsset(url: url).duration)
        return s.isFinite && s > 0 ? s : nil
    }

    /// A movie's display size (rotation applied), for the block's height.
    static func naturalSize(of url: URL) -> CGSize? {
        guard let track = AVURLAsset(url: url).tracks(withMediaType: .video).first else { return nil }
        let r = track.naturalSize.applying(track.preferredTransform)
        let size = CGSize(width: abs(r.width), height: abs(r.height))
        return size.width > 0 && size.height > 0 ? size : nil
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
        let name = originalName ?? source.lastPathComponent
        let kind = NoteAttachment.kind(forFilename: name, uti: uti)
        let entry = NoteAttachment.makeEntry(owner: memo.id, number: number, originalName: name, uti: uti,
                                             byteCount: data.count,
                                             durationSeconds: kind == NoteAttachment.Kind.video ? duration(of: source) : nil)
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

    /// Every attachment filename the note holds, for the ⋯ menu's Set All: its videos and files,
    /// photos and a shared PDF (the photo and PDF blocks get the switch too, D202).
    static func allFilenames(of memo: Memo) -> [String] {
        NoteAttachment.allFilenames(attachments: memo.metadata?.attachmentManifest, photos: memo.metadata?.imageManifest,
                                    pdf: pdfFilename(of: memo)).filter { !$0.isEmpty }
    }

    /// The captured file's name the PDF block's size is stored under (nil = no captured file).
    static func pdfFilename(of memo: Memo) -> String? {
        guard let sc = memo.sharedContent, sc.type == .file, let rel = sc.filePath, !rel.isEmpty else { return nil }
        return rel
    }

    /// Switch one attachment, or every one (`filename` nil = Set All). Not a words edit.
    static func setSize(_ size: NoteAttachment.Size, filename: String?, memo: Memo) {
        var meta = memo.metadata ?? MemoMetadata()
        meta.largeAttachments = filename.map { NoteAttachment.setting($0, to: size, in: meta.largeAttachments) }
            ?? NoteAttachment.settingAll(size, filenames: allFilenames(of: memo))
        memo.metadata = meta
        memo.markEdited(stampWords: false)
    }
}
