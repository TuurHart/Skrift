import Foundation
import LocalAuthentication
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Session gate for locked notes (feature-wave chunk 8), SHARED phone↔Mac — the
/// two apps carried byte-identical copies (phone `Services/LockGate`, Mac
/// `Features/Shell/LockGate`) that could silently drift. `Memo.locked` is the
/// SYNCED flag (mirrored onto the Mac's `PipelineFile.locked`); this gate is the
/// per-device unlock state, keyed on the memo UUID **string** (the unified key —
/// the phone used to key on `UUID`, the Mac on `String`). Unlocks are per-session:
/// resigning active re-locks everything (the Apple Notes idiom). v1 is an
/// auth-gated UI, not per-note encryption — the pipeline keeps processing and the
/// exporter refuses locked notes regardless of the gate. Each app adds a
/// model-typed `isLocked` convenience (Mac `PipelineFile`, phone `Memo`).
@MainActor
final class LockGate: ObservableObject {
    static let shared = LockGate()

    /// Note ids (memo UUID strings) the user has authenticated for THIS session.
    @Published private(set) var unlockedIDs: Set<String> = []

    /// Injectable authenticator (tests replace it): device-owner auth —
    /// Face ID / Touch ID with passcode fallback (Mac: Touch ID / password).
    var authenticate: (String) async -> Bool = { reason in
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: reason)) ?? false
    }

    private var resignObserver: NSObjectProtocol?

    private init() {
        #if canImport(UIKit)
        let resignName = UIApplication.willResignActiveNotification
        #else
        let resignName = NSApplication.willResignActiveNotification
        #endif
        resignObserver = NotificationCenter.default.addObserver(
            forName: resignName, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { LockGate.shared.relockAll() }
        }
    }

    /// Whether this note id has been unlocked for the session.
    func isUnlocked(_ id: String) -> Bool { unlockedIDs.contains(id) }

    /// Device-owner auth → unlock for this session. Returns whether the content may show.
    func unlock(_ id: String) async -> Bool {
        guard await authenticate("Unlock this note") else { return false }
        unlockedIDs.insert(id)
        return true
    }

    /// Removing the LOCK itself also requires auth (Apple Notes idiom).
    func authorizeRemoveLock() async -> Bool {
        await authenticate("Remove the lock from this note")
    }

    /// Whether this device can authenticate at all (no passcode set → it can't;
    /// locking would brick the note on this device).
    func canAuthenticate() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func relockAll() {
        if !unlockedIDs.isEmpty { unlockedIDs = [] }
    }
}
