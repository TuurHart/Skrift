import Foundation
import SwiftData

/// Trash retention, mirroring the phone's `TrashPolicy` (Apple Voice Memos' ~2 weeks).
enum DesktopTrashPolicy {
    static let retentionDays = 14
    static var retention: TimeInterval { TimeInterval(retentionDays) * 86_400 }
}

/// Soft-delete / restore / purge for desktop `PipelineFile`s — the "Recently
/// Deleted" backend mirroring the phone. Soft-delete KEEPS the working folder on
/// disk (lossless Restore); only a permanent removal (purge or Delete Now) trashes
/// the folder to the macOS Trash. All operations run on the model context's actor.
@MainActor
enum DesktopTrash {

    /// Soft-delete: hide from the sidebar/queue/sync, keep everything on disk.
    static func softDelete(_ files: [PipelineFile], at date: Date = Date(), in ctx: ModelContext) {
        for f in files where f.deletedAt == nil { f.deletedAt = date }
        try? ctx.save()
    }

    /// Restore: clear the trash flag — the file reappears exactly where it was.
    static func restore(_ files: [PipelineFile], in ctx: ModelContext) {
        for f in files { f.deletedAt = nil }
        try? ctx.save()
    }

    /// Permanent removal (Delete Now / purge): drop the record AND trash the
    /// on-disk working folder so the disk is freed too.
    static func deleteForever(_ files: [PipelineFile], in ctx: ModelContext) {
        for f in files {
            trashWorkingFolder(of: f)
            ctx.delete(f)
        }
        try? ctx.save()
    }

    /// Launch purge: permanently remove every file trashed at least
    /// `retention` ago. Returns the count purged.
    @discardableResult
    static func purgeExpired(now: Date = Date(), in ctx: ModelContext) -> Int {
        let all = (try? ctx.fetch(FetchDescriptor<PipelineFile>())) ?? []
        let expired = all.filter {
            guard let d = $0.deletedAt else { return false }
            return now.timeIntervalSince(d) >= DesktopTrashPolicy.retention
        }
        guard !expired.isEmpty else { return 0 }
        deleteForever(expired, in: ctx)
        return expired.count
    }

    /// Move a file's per-file working folder to the macOS Trash (recoverable).
    /// Safety: only ever trashes a per-file folder INSIDE the output dir — the
    /// same guard the old hard-delete used.
    static func trashWorkingFolder(of f: PipelineFile) {
        guard let folder = f.workingFolder else { return }   // capture: path IS the folder; audio/note: its parent
        let outRoot = AppPaths.audioOutputDirectory.standardizedFileURL.path
        let name = folder.lastPathComponent
        guard folder.standardizedFileURL.path.hasPrefix(outRoot),
              name.contains("_") || name.hasPrefix("capture_") else { return }
        try? FileManager.default.trashItem(at: folder, resultingItemURL: nil)
    }
}
