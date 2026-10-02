import Foundation

/// The Mac twin of the phone's `PublishCoordinator.hasPublished` (Q100, C161): locking a note
/// that this machine already exported must say the plaintext file still exists — Skrift
/// never deletes vault files. Reads only Skrift's OWN export ledger for the personal
/// destination, never the vault's contents.
enum LockVaultNotice {
    static let message = "This note was published to Obsidian before you locked it. Skrift never deletes vault files — remove it there if you want it gone. New publishes will skip it."

    static func hasPublished(_ memoID: UUID, settings: AppSettings) -> Bool {
        let picked = settings.noteFolder.trimmingCharacters(in: .whitespaces)
        guard !picked.isEmpty else { return false }
        let home = VaultLayout.home(forPicked: URL(fileURLWithPath: picked))
        return ExportLedger.default(for: home).relativePath(for: memoID) != nil
    }
}
