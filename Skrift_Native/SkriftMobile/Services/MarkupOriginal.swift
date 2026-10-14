import Foundation
import SwiftData

/// C273 / R86: Markup in Quick Look runs in `.updateContents` and writes INTO the photo file,
/// so the un-annotated original is kept aside first and stays recoverable ("Revert to Original").
///
/// - `begin` runs BEFORE Quick Look is presented: it clones the untouched photo to
///   `<stem>.original.<ext>` next to it, unless an original is already kept.
/// - `Session.end(edited: true)` turns that copy into a synced `MemoAsset` (kind `photoOriginal`,
///   additive, C96), so every device can revert. A look without an edit drops the copy again.
/// - Only the FIRST markup keeps an original; later markups leave it as it is.
/// - `revert` writes the kept bytes back over the photo and refreshes the photo's own asset.
///
/// A copy left on disk without an asset (the app died mid-markup) is still the untouched
/// original, so `begin` keeps it rather than cloning the already-marked-up file.
@MainActor
enum MarkupOriginal {

    /// `photo_<uuid>_001.jpg` → `photo_<uuid>_001.original.jpg`: keeps the memo UUID (globally
    /// unique filenames, the `MemoAsset` invariant) and the extension (still a viewable image).
    nonisolated static func originalFilename(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension
        let stem = (filename as NSString).deletingPathExtension
        return ext.isEmpty ? stem + ".original" : stem + ".original." + ext
    }

    private static func fileURL(_ filename: String) -> URL {
        AppPaths.recordingsDirectory.appendingPathComponent(filename)
    }

    /// The kept-original asset row for a photo, or nil.
    static func originalAsset(for filename: String, memoID: UUID, repository: NotesRepository) -> MemoAsset? {
        let name = originalFilename(for: filename)
        return repository.assets(forMemo: memoID)
            .first { $0.kind == MemoAsset.Kind.photoOriginal && $0.filename == name }
    }

    /// True when the photo has an original to revert to (drives the menu item).
    static func hasOriginal(for filename: String, memoID: UUID, repository: NotesRepository) -> Bool {
        originalAsset(for: filename, memoID: memoID, repository: repository) != nil
    }

    /// One markup session's keep-the-original bookkeeping. `end` is idempotent.
    @MainActor
    final class Session {
        let memoID: UUID
        let filename: String
        let repository: NotesRepository
        /// True when this session made the on-disk copy (and so owns dropping it on a clean look).
        private let madeCopy: Bool
        private var ended = false

        fileprivate init(memoID: UUID, filename: String, repository: NotesRepository, madeCopy: Bool) {
            self.memoID = memoID
            self.filename = filename
            self.repository = repository
            self.madeCopy = madeCopy
        }

        func end(edited: Bool) {
            guard !ended else { return }
            ended = true
            if MarkupOriginal.hasOriginal(for: filename, memoID: memoID, repository: repository) { return }
            let copy = MarkupOriginal.fileURL(MarkupOriginal.originalFilename(for: filename))
            if edited {
                guard let data = try? Data(contentsOf: copy) else {
                    DevLog.log("markup: original copy missing for \(filename)")
                    return
                }
                repository.context.insert(MemoAsset(memoID: memoID, kind: MemoAsset.Kind.photoOriginal,
                                                    filename: copy.lastPathComponent, blob: data))
                repository.save()
                DevLog.log("markup: kept original \(copy.lastPathComponent) (\(data.count)B)")
            } else if madeCopy {
                try? FileManager.default.removeItem(at: copy)
            }
        }
    }

    /// Call BEFORE presenting Markup on `filename` (a photo in the recordings dir). nil when the
    /// photo isn't on disk (nothing Markup could overwrite).
    static func begin(memoID: UUID, filename: String, repository: NotesRepository) -> Session? {
        let photo = fileURL(filename)
        guard FileManager.default.fileExists(atPath: photo.path) else { return nil }
        if hasOriginal(for: filename, memoID: memoID, repository: repository) {
            return Session(memoID: memoID, filename: filename, repository: repository, madeCopy: false)
        }
        let copy = fileURL(originalFilename(for: filename))
        if FileManager.default.fileExists(atPath: copy.path) {
            return Session(memoID: memoID, filename: filename, repository: repository, madeCopy: false)
        }
        do {
            try FileManager.default.copyItem(at: photo, to: copy)   // an APFS clone: no bytes copied
        } catch {
            DevLog.log("markup: could not keep original of \(filename): \(error)")
            return nil
        }
        return Session(memoID: memoID, filename: filename, repository: repository, madeCopy: true)
    }

    /// Write the kept original back over the photo and refresh the photo's synced asset (set
    /// directly: the capture sweep only notices a size change). The original stays kept.
    @discardableResult
    static func revert(memoID: UUID, filename: String, repository: NotesRepository) -> Bool {
        guard let original = originalAsset(for: filename, memoID: memoID, repository: repository) else { return false }
        let data = original.blob.isEmpty
            ? ((try? Data(contentsOf: fileURL(original.filename))) ?? Data())
            : original.blob
        guard !data.isEmpty else { return false }
        do {
            try data.write(to: fileURL(filename), options: .atomic)
        } catch {
            DevLog.log("markup: revert FAILED \(filename): \(error)")
            return false
        }
        if let photo = repository.assets(forMemo: memoID)
            .first(where: { $0.kind == MemoAsset.Kind.photo && $0.filename == filename }) {
            photo.blob = data
            photo.byteCount = data.count
        }
        repository.save()
        DevLog.log("markup: reverted \(filename) to its original (\(data.count)B)")
        return true
    }
}
