import Foundation
import CoreData

/// Observes CloudKit sync activity (Phase 1 sync visibility) so the UI can say
/// "Syncing with iCloud…" instead of leaving the user guessing whether a memo's
/// audio/photo is on its way or stuck.
///
/// SwiftData mirrors through `NSPersistentCloudKitContainer`, which posts
/// `eventChangedNotification` for each setup/import/export (start has `endDate ==
/// nil`, completion fills it in). We track in-flight events → `isSyncing`. When an
/// IMPORT completes we also run the materialize/merge sweeps immediately, so freshly
/// arrived blobs land on disk + names/vocab converge WITHOUT waiting for the next
/// foreground — and observing views (the image embed) re-render and show the media
/// the moment it's downloaded.
///
/// No CloudKit (in-memory store / no iCloud / tests) → no events → `isSyncing` stays
/// false and this is inert.
@MainActor
final class CloudSyncMonitor: ObservableObject {
    static let shared = CloudSyncMonitor()

    @Published private(set) var isSyncing = false

    /// REAL per-book audiobook-audio transfer progress (raw-CloudKit path): direction
    /// + a 0–1 byte-weighted fraction, published live from
    /// `CKModifyRecordsOperation`/`CKFetchRecordsOperation` progress so the library row
    /// shows a DETERMINATE "Uploading audio · 38%" / "Downloading… · 61%" bar — the
    /// thing SwiftData's auto-mirror couldn't give. Cleared when the transfer settles.
    @Published private(set) var bookTransfers: [UUID: AudiobookTransfer] = [:]

    struct AudiobookTransfer: Equatable {
        enum Direction { case up, down }
        var direction: Direction
        var fraction: Double
    }

    /// True while ANY audiobook audio is uploading/downloading — the raw transfer does
    /// NOT fire `eventChangedNotification` (that's only the SwiftData mirror), so the
    /// Library's "Syncing…" header chip checks this alongside `isSyncing`.
    var isTransferringBooks: Bool { !bookTransfers.isEmpty }

    private var inFlight: Set<UUID> = []
    private var hideTask: Task<Void, Never>?
    /// Per-book transfer epoch. CloudKit's progress callbacks fire off-main + out of
    /// order, so each is dispatched as an unstructured MainActor Task — a LATE one
    /// could otherwise re-populate `bookTransfers` after the transfer was cleared,
    /// leaving the row stuck mid-bar. Every transfer gets a token; only writes bearing
    /// the CURRENT token apply, so stale/superseded callbacks are dropped.
    private var transferEpoch: [UUID: Int] = [:]
    private var epochSeq = 0

    /// Begin a transfer; returns its epoch token. Resets the row to 0 in the given
    /// direction and supersedes any prior transfer for the book.
    func beginBookTransfer(_ bookID: UUID, direction: AudiobookTransfer.Direction) -> Int {
        epochSeq += 1
        transferEpoch[bookID] = epochSeq
        bookTransfers[bookID] = AudiobookTransfer(direction: direction, fraction: 0)
        return epochSeq
    }

    /// Live progress for an in-flight transfer — applied only if `epoch` is still the
    /// book's current token (so a late callback from a finished/superseded transfer is
    /// ignored). The transport hops here from its (possibly off-main) callbacks.
    func updateBookTransfer(_ bookID: UUID, epoch: Int, fraction: Double) {
        guard transferEpoch[bookID] == epoch, var transfer = bookTransfers[bookID] else { return }
        transfer.fraction = min(1, max(0, fraction))
        bookTransfers[bookID] = transfer
    }

    /// Transfer finished — drop the row's determinate bar (only if this epoch is still
    /// current) so it settles to its synced/resume state. Clears the token so any
    /// straggler `updateBookTransfer` for this epoch is dropped.
    func endBookTransfer(_ bookID: UUID, epoch: Int) {
        guard transferEpoch[bookID] == epoch else { return }
        transferEpoch[bookID] = nil
        bookTransfers[bookID] = nil
    }

    /// Force-cancel any in-flight transfer for a book (e.g. the user unshared it):
    /// supersede the token so late callbacks are dropped, and clear the bar.
    func cancelBookTransfer(_ bookID: UUID) {
        transferEpoch[bookID] = nil
        bookTransfers[bookID] = nil
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            // Extract Sendable primitives before hopping onto the actor.
            let id = event.identifier
            let ended = event.endDate != nil
            let importDone = ended && event.type == .import && event.succeeded
            MainActor.assumeIsolated { self?.apply(id: id, ended: ended, importDone: importDone) }
        }
    }

    private func apply(id: UUID, ended: Bool, importDone: Bool) {
        if ended { inFlight.remove(id) } else { inFlight.insert(id) }
        if inFlight.isEmpty {
            // Debounce the hide: CloudKit fires import/export events in quick bursts,
            // so a brief gap between them shouldn't flicker the indicator off. Only
            // hide after ~1s of quiet; new activity cancels the pending hide.
            hideTask?.cancel()
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.isSyncing = false
            }
        } else {
            hideTask?.cancel()
            hideTask = nil
            isSyncing = true
        }
        if importDone {
            // Blobs/rows just arrived — write them to disk + converge names/vocab now.
            AssetMaterializer.run(.shared)
            NamesCloudSync.run(.shared)
            VocabularyCloudSync.run(.shared)
            // A synced audiobook that just arrived materializes here too (hands-off
            // receive — no manual pull): the carrier's audioUploadedAt push triggers
            // this import, and reconcile fetches the audio by id. No-op when nothing's
            // synced; async (raw-CloudKit transfer) so it runs in a detached Task.
            // Then adopt a newer resume position into an already-open (paused) session
            // — fixes the cold-launch case where you opened the book before its newer
            // position finished importing.
            Task {
                await AudiobookCloudSync.reconcile()
                await MainActor.run { AudiobookSession.shared.adoptSyncedPosition() }
            }
        }
    }
}

/// Whether a memo's media file is on disk, still arriving over CloudKit, or truly
/// gone — pure so the image embed's three states are unit-testable.
enum MediaSyncState {
    case present       // file is on disk → show it
    case downloading   // file missing but a synced asset exists → it's on its way
    case missing       // no file, no asset → genuinely gone (e.g. a seeded demo memo)

    static func of(filePresent: Bool, hasAsset: Bool) -> MediaSyncState {
        if filePresent { return .present }
        return hasAsset ? .downloading : .missing
    }
}
