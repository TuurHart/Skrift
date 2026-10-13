import Foundation
import AVFoundation

/// The attachment rules that need the `Memo` or a movie file, one copy for the phone, iPad and
/// Mac (Q390: these were twins in `NoteAttachmentStore` and `MacNoteAttachments`). The apps
/// keep only where the bytes live and how a change is saved.
extension NoteAttachment {

    /// A movie's length read from the file; nil when unreadable. Only the add paths call it,
    /// never note open.
    static func videoDuration(of url: URL) -> Double? {
        let seconds = CMTimeGetSeconds(AVURLAsset(url: url).duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    /// A new entry for `source` copied into the note under `originalName`: a video carries the
    /// length read from the file.
    static func makeEntry(owner: UUID, number: Int, source: URL, originalName: String, uti: String?,
                          byteCount: Int) -> NoteAttachmentEntry {
        let isVideo = kind(forFilename: originalName, uti: uti) == Kind.video
        return makeEntry(owner: owner, number: number, originalName: originalName, uti: uti,
                         byteCount: byteCount, durationSeconds: isVideo ? videoDuration(of: source) : nil)
    }

    /// The captured (shared) file's name, which a PDF block's size is stored under. nil = the
    /// note holds no captured file.
    static func capturedFilename(of memo: Memo) -> String? {
        guard let sc = memo.sharedContent, sc.type == .file, let rel = sc.filePath, !rel.isEmpty else { return nil }
        return rel
    }

    /// Every filename the ⋯ menu's Set All switches: videos, files, photos and the captured PDF.
    static func allFilenames(of memo: Memo) -> [String] {
        allFilenames(attachments: memo.metadata?.attachmentManifest, photos: memo.metadata?.imageManifest,
                     pdf: capturedFilename(of: memo)).filter { !$0.isEmpty }
    }

    /// Switch one block (`filename`) or every one in `all` (`filename` nil = Set All). Synced memo
    /// state, not a words edit; the caller saves.
    static func setSize(_ size: Size, filename: String?, all: [String], on memo: Memo) {
        var meta = memo.metadata ?? MemoMetadata()
        meta.largeAttachments = filename.map { setting($0, to: size, in: meta.largeAttachments) }
            ?? settingAll(size, filenames: all)
        memo.metadata = meta
        memo.markEdited(stampWords: false)
    }
}
