import Foundation

extension LockGate {
    /// The real session + auth wired into the shared policy. Read `authenticate` at
    /// call time so a test-replaced authenticator still applies.
    var policy: LockPolicy {
        LockPolicy(isUnlocked: { [self] in isUnlocked($0) },
                   unlock: { [self] in await unlock($0) },
                   canAuthenticate: { [self] in canAuthenticate() },
                   authorizeRemoveLock: { [self] in await authorizeRemoveLock() })
    }
}
