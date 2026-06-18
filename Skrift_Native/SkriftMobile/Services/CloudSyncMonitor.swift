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

    private var inFlight: Set<UUID> = []

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
        isSyncing = !inFlight.isEmpty
        if importDone {
            // Blobs/rows just arrived — write them to disk + converge names/vocab now.
            AssetMaterializer.run(.shared)
            NamesCloudSync.run(.shared)
            VocabularyCloudSync.run(.shared)
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
