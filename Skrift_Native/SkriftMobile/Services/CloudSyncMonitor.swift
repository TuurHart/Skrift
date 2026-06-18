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
    /// Books the user just opted into sync — shown as "Uploading…" on their row until
    /// the CloudKit export settles (cleared when `isSyncing` debounces off). Honest
    /// per-book feedback without a fake % (CloudKit exposes no upload percentage).
    @Published private(set) var uploadingBookIDs: Set<UUID> = []

    private var inFlight: Set<UUID> = []
    private var hideTask: Task<Void, Never>?

    /// Called when a book is opted into sync, so its row shows "Uploading…" while the
    /// CKAsset export is in flight.
    func markUploading(_ bookID: UUID) { uploadingBookIDs.insert(bookID) }

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
                // The export settled → those books are uploaded.
                self?.uploadingBookIDs = []
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
            // receive — no manual pull). Capture is byteCount-guarded, so this is cheap
            // on the source after its first upload; the receiver writes the audio in.
            AudiobookCloudSync.reconcile()
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
