import Foundation
import CloudKit

/// Raw-CloudKit implementation of `AudiobookAudioTransport`. Audiobook audio is large
/// and the whole point of this layer is a REAL transfer %, which SwiftData's
/// auto-mirror can't give — so the audio lives as plain `CKRecord`s (type
/// `AudiobookAudio`) carrying a `CKAsset(fileURL:)`, written to the **private DB's
/// default zone**.
///
/// Coexistence (verified): `NSPersistentCloudKitContainer` confines its mirror to its
/// own zone (`com.apple.coredata.cloudkit.zone`, `CD_`-prefixed types), so these raw
/// default-zone records never collide with the synced `Memo`/carrier store, and the
/// existing iCloud entitlement already authorises `CKContainer(identifier:)`. We do
/// NOT register a `CKDatabaseSubscription` (it would also fire for Core Data's zone,
/// and doesn't fire for the default zone anyway): the receiver is nudged to pull by
/// the SwiftData carrier's own push (`AudiobookSyncRecord.audioUploadedAt`), then
/// fetches these records by **exact id** — which needs no queryable index.
final class CloudKitAudiobookTransport: AudiobookAudioTransport {
    static let recordType = "AudiobookAudio"
    private let database: CKDatabase

    init(containerID: String) {
        database = CKContainer(identifier: containerID).privateCloudDatabase
    }

    /// Wi-Fi-only by default (no silent multi-hundred-MB push over cellular); `.utility`
    /// QoS keeps these big transfers out of the way of interactive work.
    private func configuration() -> CKOperation.Configuration {
        let config = CKOperation.Configuration()
        config.allowsCellularAccess = false
        config.qualityOfService = .utility
        return config
    }

    // MARK: - Upload

    func upload(_ parts: [AudiobookAudioPart], progress: @Sendable @escaping (Double) -> Void) async throws {
        guard !parts.isEmpty else { progress(1); return }

        // Byte-weight the per-record fractions into one honest book-level %.
        let sizeByName: [String: Int] = Dictionary(uniqueKeysWithValues: parts.map {
            ($0.recordName, fileSize($0.fileURL))
        })
        let total = max(1, sizeByName.values.reduce(0, +))

        let records: [CKRecord] = parts.map { part in
            let record = CKRecord(recordType: Self.recordType,
                                  recordID: CKRecord.ID(recordName: part.recordName))
            record["filename"] = part.filename as CKRecordValue
            record["asset"] = CKAsset(fileURL: part.fileURL)
            return record
        }

        let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        op.configuration = configuration()
        op.savePolicy = .allKeys      // a re-upload overwrites cleanly
        op.isAtomic = false
        // Surface a per-record failure (e.g. a silently-dropped cover) instead of it
        // vanishing into a non-atomic batch that still reports overall success.
        op.perRecordSaveBlock = { recordID, result in
            if case .failure(let error) = result {
                DevLog.log("audiobook upload record \(recordID.recordName) failed: \(error)")
            }
        }

        // perRecordProgressBlock isn't guaranteed serial across records → guard the
        // shared fraction map with a lock (the "SwiftData off a socket queue" hazard).
        let lock = NSLock()
        var per: [String: Double] = [:]
        op.perRecordProgressBlock = { record, fraction in
            lock.lock()
            per[record.recordID.recordName] = fraction
            let weighted = per.reduce(0.0) { acc, kv in
                acc + kv.value * Double(sizeByName[kv.key] ?? 0)
            } / Double(total)
            lock.unlock()
            progress(min(1, weighted))
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            database.add(op)
        }
        progress(1)
    }

    // MARK: - Download

    func download(_ refs: [AudiobookAudioRef], into destFolder: URL,
                  progress: @Sendable @escaping (Double) -> Void) async throws {
        guard !refs.isEmpty else { progress(1); return }
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)

        let ids = refs.map { CKRecord.ID(recordName: $0.recordName) }
        let filenameByName = Dictionary(uniqueKeysWithValues: refs.map { ($0.recordName, $0.filename) })

        // Equal-weight the fetch fraction (sizes are unknown until bytes arrive).
        let lock = NSLock()
        var per: [String: Double] = [:]
        let denom = Double(ids.count)

        let op = CKFetchRecordsOperation(recordIDs: ids)
        op.configuration = configuration()
        op.perRecordProgressBlock = { recordID, fraction in
            lock.lock()
            per[recordID.recordName] = fraction
            let agg = per.values.reduce(0, +) / denom
            lock.unlock()
            progress(min(1, agg))
        }
        // Copy each asset into place AS SOON AS it lands — CloudKit reclaims the
        // staging area, so a deferred copy can lose the file. This runs off-main and
        // can race main-actor folder ops (removeDownload / a fileExists probe), so
        // stage to a temp sibling then put it in place ATOMICALLY (rename / replace) —
        // a concurrent reader sees either the old file or the complete new one, never
        // a half-written one.
        op.perRecordResultBlock = { recordID, result in
            switch result {
            case .failure(let error):
                DevLog.log("audiobook download record \(recordID.recordName) failed: \(error)")
            case .success(let record):
                guard let asset = record["asset"] as? CKAsset, let staged = asset.fileURL else { return }
                let filename = filenameByName[recordID.recordName] ?? recordID.recordName
                let dest = destFolder.appendingPathComponent(filename)
                let tmp = destFolder.appendingPathComponent(".\(UUID().uuidString).part")
                do {
                    try FileManager.default.copyItem(at: staged, to: tmp)
                    if FileManager.default.fileExists(atPath: dest.path) {
                        _ = try FileManager.default.replaceItemAt(dest, withItemAt: tmp)
                    } else {
                        try FileManager.default.moveItem(at: tmp, to: dest)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: tmp)
                    DevLog.log("audiobook asset copy failed \(filename): \(error)")
                }
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            op.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    cont.resume()
                case .failure(let error):
                    // Records that DID arrive were already copied per-record above. If
                    // the only failures are absent records (a part the source never
                    // uploaded / unshared), treat it as done rather than throwing away
                    // the successful copies + retrying forever.
                    if Self.isOnlyUnknownItem(error) { cont.resume() }
                    else { cont.resume(throwing: error) }
                }
            }
            database.add(op)
        }
        progress(1)
    }

    // MARK: - Delete (unshare)

    func delete(recordNames: [String]) async throws {
        guard !recordNames.isEmpty else { return }
        let ids = recordNames.map { CKRecord.ID(recordName: $0) }
        let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
        op.configuration = configuration()
        op.isAtomic = false   // deleting an already-absent record shouldn't fail the batch

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    cont.resume()
                case .failure(let error):
                    // Treat "the record was already gone" as success (idempotent unshare).
                    if Self.isOnlyUnknownItem(error) { cont.resume() }
                    else { cont.resume(throwing: error) }
                }
            }
            database.add(op)
        }
    }

    /// A partial failure whose only sub-errors are `.unknownItem` means every target
    /// was already absent — a no-op delete, which we treat as success.
    private static func isOnlyUnknownItem(_ error: Error) -> Bool {
        guard let ckError = error as? CKError, ckError.code == .partialFailure,
              let partials = ckError.partialErrorsByItemID, !partials.isEmpty else {
            return (error as? CKError)?.code == .unknownItem
        }
        return partials.values.allSatisfy { ($0 as? CKError)?.code == .unknownItem }
    }

    private func fileSize(_ url: URL) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int) ?? 0
    }
}
