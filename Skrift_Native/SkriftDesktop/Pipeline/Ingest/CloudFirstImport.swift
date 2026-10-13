import Foundation

/// Q397 (D203, `plan/release/ICLOUD_MERGE.md` A1): has the Mac's cloud store finished its first
/// CloudKit import since that store file was created? Until it has, the reconcile's backfill
/// authors nothing (`MacMemoAuthor.mayBackfill`): a Memo that exists in CloudKit but has not
/// downloaded yet looks missing, and authoring it again would upload a same-id twin.
///
/// Persisted as a small stamp file (`AppPaths.memoCloudFirstImportStamp`) that names the store
/// file it vouches for by inode + creation date. `user_settings.json` stays put when the old
/// store is moved out (ICLOUD_MERGE step 6), so a plain boolean there would carry over to the
/// fresh store; this stamp reads "not done" for any store file other than the one it was
/// written for. Every failure (no store, no stamp, corrupt stamp, a store file rewritten in
/// place) reads "not done": the backfill then waits for the next import, which re-stamps.
///
/// Pure + host-less: callers pass both URLs, so tests use temp files. The app sets it from the
/// mirroring delegate's import event (`MemoCloudReconciler.start`).
enum CloudFirstImport {

    struct Stamp: Codable, Equatable {
        var storeFileNumber: UInt64
        var storeCreatedAt: TimeInterval   // seconds since 1970, compared with a 1 ms tolerance
        var doneAt: TimeInterval
    }

    /// True only when the stamp exists, decodes, and names the store file now at `storeURL`.
    static func isDone(storeURL: URL, stampURL: URL) -> Bool {
        guard let identity = identity(of: storeURL),
              let data = try? Data(contentsOf: stampURL),
              let stamp = try? JSONDecoder().decode(Stamp.self, from: data) else { return false }
        return stamp.storeFileNumber == identity.fileNumber
            && abs(stamp.storeCreatedAt - identity.createdAt) < 0.001
    }

    /// Record that the store at `storeURL` has finished an import. Idempotent (an existing
    /// matching stamp is left alone); a no-op when the store file does not exist.
    static func markDone(storeURL: URL, stampURL: URL, now: Date = Date()) {
        guard !isDone(storeURL: storeURL, stampURL: stampURL),
              let identity = identity(of: storeURL) else { return }
        let stamp = Stamp(storeFileNumber: identity.fileNumber, storeCreatedAt: identity.createdAt,
                          doneAt: now.timeIntervalSince1970)
        guard let data = try? JSONEncoder().encode(stamp) else { return }
        try? data.write(to: stampURL, options: .atomic)
    }

    private static func identity(of url: URL) -> (fileNumber: UInt64, createdAt: TimeInterval)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value,
              let created = attrs[.creationDate] as? Date else { return nil }
        return (number, created.timeIntervalSince1970)
    }
}
