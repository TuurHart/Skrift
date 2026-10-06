import Foundation

/// One security-scoped-bookmark store for a user-picked folder, keyed by a `UserDefaults` key.
/// `ObsidianVault` (the vault) and `PortfolioVault` (the portfolio root) are the same store
/// under different keys; they keep their own extras and forward here.
struct ScopedFolderBookmark {
    let key: String

    /// True once the user has chosen a folder.
    var isConfigured: Bool { UserDefaults.standard.data(forKey: key) != nil }

    /// Persist a bookmark to the chosen folder (call from the picker with the picked URL).
    func set(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: key)
    }

    /// The saved bookmark as a (security-scoped) folder URL; the caller starts/stops the scope
    /// around any write. nil if unset or unresolvable (stale → re-prompt in the UI).
    func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// The picked folder's display name for Settings ("Skrift", not a whole path).
    var displayName: String? { resolve()?.lastPathComponent }
}

/// Where a note's destination writes: the folder the user picked, the root the bookmark's
/// security scope belongs to, and the layout profile. Derived once for the publisher and for
/// the coordinator's ledger lookup, so the two cannot disagree about it.
///
/// A portfolio destination writes into its folder inside the portfolio root, flat (see
/// `ExportProfile`), and the scope belongs to the portfolio ROOT, not that subfolder.
/// `.personal` is the Obsidian vault: picked root and scope root are the same folder.
struct ExportDestinationRoot {
    let picked: URL
    let scopeRoot: URL
    let profile: ExportProfile

    /// nil when no folder is configured for this destination.
    static func resolve(for destination: NoteDestination,
                        vault: () -> URL?,
                        portfolioFolder: (NoteDestination) -> URL?,
                        portfolioScopeRoot: () -> URL?) -> ExportDestinationRoot? {
        let profile = ExportProfile.of(destination)
        guard let picked = destination.isPortfolio ? portfolioFolder(destination) : vault() else { return nil }
        let scopeRoot = destination.isPortfolio ? (portfolioScopeRoot() ?? picked) : picked
        return ExportDestinationRoot(picked: picked, scopeRoot: scopeRoot, profile: profile)
    }

    /// Start the scope (unless `manage` is false — temp-dir tests); `close()` the token with `defer`.
    func openScope(manage: Bool = true) -> Scope {
        Scope(root: scopeRoot, started: manage && scopeRoot.startAccessingSecurityScopedResource())
    }

    struct Scope {
        let root: URL
        let started: Bool
        func close() { if started { root.stopAccessingSecurityScopedResource() } }
    }
}
