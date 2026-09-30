import Foundation

/// The portfolio ROOT on this device — the folder the three portfolio destinations live inside
/// (`_projects` / `_ideas` / `_inspiration`). Same security-scoped-bookmark shape as
/// `ObsidianVault`, which stays exactly as it is and keeps owning `.personal`.
///
/// **Per-device, like the vault bookmark.** A destination is a folder this device can see,
/// so "is the portfolio set up here" is a local fact, not a synced one. Tuur's portfolio repo
/// lives in `Documents` on his Mac today, so the Mac writes it; move it into iCloud Drive
/// or a Working Copy checkout and the iPad writes it with no code change.
///
/// **PRIVACY (hard rule, inherited from `ObsidianPublisher`): WRITE-ONLY.** Skrift never
/// scans what is already in the portfolio. The only read is of its own candidate path, to
/// judge whether a file there is Skrift's and untouched — which is what makes never
/// overwriting your edits possible.
enum PortfolioVault {

    /// True once a portfolio root has been chosen on this device.
    static var isConfigured: Bool {
        UserDefaults.standard.data(forKey: DestinationSettings.portfolioRootKey) != nil
    }

    static func setRoot(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: DestinationSettings.portfolioRootKey)
    }

    /// The portfolio root, or nil when unset / the bookmark no longer resolves (re-prompt).
    /// The caller owns `start`/`stopAccessingSecurityScopedResource` around any write.
    static func resolveRoot() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: DestinationSettings.portfolioRootKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// The folder a given destination writes into — the root plus its subfolder. nil for
    /// `.personal` (that is the Obsidian vault, not the portfolio) and nil when no root is set.
    static func folder(for destination: NoteDestination) -> URL? {
        guard let sub = destination.portfolioFolder, let root = resolveRoot() else { return nil }
        return root.appendingPathComponent(sub, isDirectory: true)
    }

    /// The root's display name for Settings ("portfolio", not a whole path).
    static var displayName: String? { resolveRoot()?.lastPathComponent }

    static func clear() { UserDefaults.standard.removeObject(forKey: DestinationSettings.portfolioRootKey) }

    /// `-seedPortfolioFolder` — the screenshot/UI rig. Makes a real folder in the app's own
    /// container and bookmarks it, so a run can show the CONFIGURED Destinations settings
    /// without driving the system document picker. Never runs without the flag.
    static func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seedPortfolioFolder") else { return }
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/portfolio", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? setRoot(root)
    }
}
