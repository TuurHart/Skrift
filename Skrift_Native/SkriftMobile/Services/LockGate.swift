import Foundation
import LocalAuthentication
import UIKit

/// Session gate for locked notes (feature wave chunk 8): `Memo.locked` is the
/// SYNCED flag; this gate is the per-device unlock state. Unlocks are
/// per-session — backgrounding the app re-locks everything (the Apple Notes
/// behaviour). v1 is an auth-gated UI, not per-note encryption.
@MainActor
final class LockGate: ObservableObject {
    static let shared = LockGate()

    /// Memos the user has authenticated for THIS session.
    @Published private(set) var unlockedMemoIDs: Set<UUID> = []

    /// Injectable authenticator (tests replace it): device-owner auth =
    /// Face ID / Touch ID with passcode fallback.
    var authenticate: (String) async -> Bool = { reason in
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: reason)) ?? false
    }

    private var resignObserver: NSObjectProtocol?

    private init() {
        resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { LockGate.shared.relockAll() }
        }
    }

    /// Whether this memo's CONTENT is currently gated.
    func isLocked(_ memo: Memo) -> Bool {
        memo.locked && !unlockedMemoIDs.contains(memo.id)
    }

    /// Face ID → unlock for this session. Returns whether the content may show.
    func unlock(_ id: UUID) async -> Bool {
        guard await authenticate("Unlock this note") else { return false }
        unlockedMemoIDs.insert(id)
        return true
    }

    /// Removing the LOCK itself also requires auth (Apple Notes idiom).
    func authorizeRemoveLock() async -> Bool {
        await authenticate("Remove the lock from this note")
    }

    /// Whether this device can authenticate at all (no passcode set → it
    /// can't; locking would brick the note on this device).
    func canAuthenticate() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func relockAll() {
        if !unlockedMemoIDs.isEmpty { unlockedMemoIDs = [] }
    }
}
