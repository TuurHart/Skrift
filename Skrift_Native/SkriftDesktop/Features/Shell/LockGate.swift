import AppKit
import Foundation
import LocalAuthentication

/// Session gate for locked notes — the Mac side of the phone's `LockGate`
/// (feature wave chunk 8): `Memo.locked` syncs and mirrors onto
/// `PipelineFile.locked`; this gate is the per-device unlock state. Unlocks are
/// per-session — deactivating the app re-locks everything (the Apple Notes
/// behaviour, same as the phone). v1 is an auth-gated UI, not per-note
/// encryption: the pipeline keeps processing; export is refused by
/// `VaultExporter` regardless of the gate.
@MainActor
final class LockGate: ObservableObject {
    static let shared = LockGate()

    /// Row ids (memo UUIDs) the user has authenticated for THIS session.
    @Published private(set) var unlockedIDs: Set<String> = []

    /// Injectable authenticator (tests replace it): device-owner auth =
    /// Touch ID / password on the Mac.
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
            forName: NSApplication.willResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { LockGate.shared.relockAll() }
        }
    }

    /// Whether this row's CONTENT is currently gated.
    func isLocked(_ pf: PipelineFile) -> Bool {
        pf.locked && !unlockedIDs.contains(pf.id)
    }

    /// Touch ID / password → unlock for this session. Returns whether the content may show.
    func unlock(_ id: String) async -> Bool {
        guard await authenticate("Unlock this note") else { return false }
        unlockedIDs.insert(id)
        return true
    }

    func relockAll() {
        if !unlockedIDs.isEmpty { unlockedIDs = [] }
    }
}
