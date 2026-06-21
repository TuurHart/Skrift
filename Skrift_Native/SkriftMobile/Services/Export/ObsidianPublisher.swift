import Foundation
import CryptoKit

/// Persisted access to the user-picked Obsidian vault folder (security-scoped bookmark).
/// The vault picker UI (Phase 2 mock) calls `setVault`; the publisher resolves it. Mirrors
/// the security-scoped pattern in `AudiobookImporter`/`MemoSaver`.
enum ObsidianVault {
    private static let bookmarkKey = "skrift.obsidian.vaultBookmark"

    /// True once the user has chosen a vault folder.
    static var isConfigured: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    /// Persist a bookmark to the chosen folder (call from the picker with the picked URL).
    static func setVault(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    /// Resolve the saved bookmark to a (security-scoped) folder URL — the publisher
    /// starts/stops the scope around the write. nil if unset or unresolvable (stale →
    /// re-prompt in the UI).
    static func resolveVault() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: bookmarkKey) }
}

/// The result of publishing one memo.
enum PublishOutcome: Equatable {
    case written(relativePath: String)
    case skippedUnchanged
    case noVault
}

/// One-way, create-only Obsidian publish (standalone Phase 2): write a memo's markdown into a
/// dedicated `<vault>/Skrift/` subtree the app OWNS, never touching hand-authored notes.
///
/// - **Sticky path + content-hash idempotency** (via `ExportStateStore`): re-export overwrites
///   only its own file (single owner per file → no conflict copies) and skips unchanged memos.
/// - **Atomic + coordinated writes** (`NSFileCoordinator`) so Obsidian/iCloud never see a
///   half-written `.md`.
/// - **PRIVACY (hard rule): WRITE-ONLY.** Never reads or scans vault contents — idempotency
///   uses the locally-stored hash, and the only `fileExists` check is on the app's OWN file.
///
/// Dependencies are injected so the publish logic is testable against a temp directory.
struct ObsidianPublisher {
    /// Returns the vault root, or nil if unconfigured. `manageScope` says whether to wrap the
    /// write in `start/stopAccessingSecurityScopedResource` (true in prod; false for temp-dir tests).
    var vaultProvider: () -> URL?
    var manageScope: Bool
    var stateStore: ExportStateStore
    var author: String
    var peopleProvider: () -> [Person]

    /// Production publisher over the saved bookmark + live names DB.
    static func live(author: String) -> ObsidianPublisher {
        ObsidianPublisher(
            vaultProvider: { ObsidianVault.resolveVault() },
            manageScope: true,
            stateStore: .shared,
            author: author,
            peopleProvider: { NamesStore.shared.load().people }
        )
    }

    /// Publish one memo. Idempotent: an unchanged memo (same content hash + its file present)
    /// is skipped; a renamed memo still writes to its original path.
    func publish(_ memo: Memo) throws -> PublishOutcome {
        guard let vaultRoot = vaultProvider() else { return .noVault }
        let scoped = manageScope && vaultRoot.startAccessingSecurityScopedResource()
        defer { if scoped { vaultRoot.stopAccessingSecurityScopedResource() } }

        let people = peopleProvider()
        let markdown = MemoExporter.markdown(for: memo, people: people, author: author)
        let hash = Self.sha256(markdown)

        // Sticky relative path — reuse the one we first wrote (survives a rename).
        let existing = stateStore.record(for: memo.id)
        let relPath = existing?.relativePath ?? Self.relativePath(for: memo, people: people)
        let dest = vaultRoot.appendingPathComponent(relPath)

        // Idempotent skip: unchanged AND our file is still there.
        if let existing, existing.contentHash == hash, FileManager.default.fileExists(atPath: dest.path) {
            return .skippedUnchanged
        }

        try Self.writeAtomic(markdown, to: dest)
        stateStore.set(ExportRecord(relativePath: relPath, contentHash: hash, exportedAt: Date()), for: memo.id)
        return .written(relativePath: relPath)
    }

    // MARK: - Path derivation

    /// `Skrift/<subfolder>/<sanitized title>-<short id>.md`. The short id keeps two same-titled
    /// memos from colliding; the path is then frozen in `ExportStateStore` (rename-safe).
    static func relativePath(for memo: Memo, people: [Person]) -> String {
        let stem = sanitizeFilename(MemoExporter.exportTitle(for: memo, people: people))
        let shortID = String(memo.id.uuidString.prefix(8))
        return "Skrift/\(subfolder(for: memo))/\(stem)-\(shortID).md"
    }

    /// Source-keyed subfolder so the vault stays organised (and Skrift owns the whole subtree).
    static func subfolder(for memo: Memo) -> String {
        if memo.isShareCapture { return "Captures" }
        if let book = memo.metadata?.bookTitle?.trimmingCharacters(in: .whitespaces), !book.isEmpty {
            return "Audiobook Quotes"
        }
        return "Voice Memos"
    }

    /// Strip filesystem-illegal characters, collapse whitespace, cap length.
    static func sanitizeFilename(_ s: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var out = s.components(separatedBy: illegal).joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { out = "Untitled" }
        return String(out.prefix(60))
    }

    // MARK: - Write

    /// Atomic, coordinated write (creates intermediate dirs). `NSFileCoordinator` keeps
    /// Obsidian/iCloud from observing a partial file.
    static func writeAtomic(_ text: String, to dest: URL) throws {
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: dest, options: .forReplacing, error: &coordError) { url in
            do { try Data(text.utf8).write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let coordError { throw coordError }
        if let writeError { throw writeError }
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
