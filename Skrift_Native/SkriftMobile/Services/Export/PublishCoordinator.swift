import Foundation

/// Fans the memo store out to the Obsidian sink (standalone Phase 2) — the peer to
/// `SyncCoordinator` (which owns the Mac transport sink). Decides WHICH memos publish and
/// defers to the Mac when paired; the actual write is `ObsidianPublisher`.
///
/// Routing rules:
/// - **Opt-in:** nothing publishes until a vault is configured + Obsidian is enabled.
/// - **Policy:** `.all` or `.importantOnly` (significance > 0 — mirrors the Mac flag-to-send).
/// - **Paired mode:** when a Mac is paired it owns Obsidian export (it has the *enhanced* text),
///   so the phone's publish is off by default — overridable. Per-memo file ownership +
///   content-hash idempotency (in `ObsidianPublisher`) make a stray double-write harmless anyway.
@MainActor
struct PublishCoordinator {
    enum Policy: String { case all, importantOnly }

    var memosProvider: () -> [Memo]
    var publisher: ObsidianPublisher
    var isMacPaired: () -> Bool
    var obsidianEnabled: () -> Bool
    var publishWhenPaired: () -> Bool
    var policy: () -> Policy

    struct Summary: Equatable {
        var written = 0
        var skipped = 0
        var failed = 0
        var ineligible = 0
    }

    /// Production coordinator over the live store, settings, and pairing state.
    static func live(author: String) -> PublishCoordinator {
        PublishCoordinator(
            memosProvider: { NotesRepository.shared.allMemos() },
            publisher: .live(author: author),
            isMacPaired: { MacConnection.load() != nil },
            obsidianEnabled: { ObsidianVault.isConfigured && UserDefaults.standard.bool(forKey: "skrift.publish.obsidianEnabled") },
            publishWhenPaired: { UserDefaults.standard.bool(forKey: "skrift.publish.whenPaired") },
            policy: { Policy(rawValue: UserDefaults.standard.string(forKey: "skrift.publish.policy") ?? "") ?? .importantOnly }
        )
    }

    /// Whether this memo should publish to Obsidian right now.
    func shouldPublish(_ memo: Memo) -> Bool {
        guard obsidianEnabled() else { return false }
        guard memo.deletedAt == nil else { return false }
        if isMacPaired() && !publishWhenPaired() { return false }   // Mac owns export when paired
        if policy() == .importantOnly && memo.significance <= 0 { return false }
        // Needs some content to be worth a file.
        let hasBody = !(memo.transcript ?? "").isEmpty || !(memo.annotationText ?? "").isEmpty
        return hasBody || (memo.title?.isEmpty == false)
    }

    /// Publish one memo if eligible; nil when the gate excludes it.
    @discardableResult
    func publishIfEligible(_ memo: Memo) throws -> PublishOutcome? {
        guard shouldPublish(memo) else { return nil }
        return try publisher.publish(memo)
    }

    /// Publish every eligible memo, tallying the outcomes.
    @discardableResult
    func publishAll() -> Summary {
        var s = Summary()
        for memo in memosProvider() {
            guard shouldPublish(memo) else { s.ineligible += 1; continue }
            do {
                switch try publisher.publish(memo) {
                case .written:          s.written += 1
                case .skippedUnchanged: s.skipped += 1
                case .noVault:          s.failed += 1   // enabled but the bookmark didn't resolve
                }
            } catch {
                s.failed += 1
            }
        }
        return s
    }
}
