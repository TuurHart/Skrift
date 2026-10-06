import Foundation

/// WHERE Skrift's stuff goes inside the folder you picked — one answer for every app.
///
/// Before this (2026-08-14) the Mac carried two free-text settings (`audioFolder`,
/// `attachmentsFolder`, defaulting to Tuur's `1 Recordings` / `0 Images`) while iOS had no
/// such settings at all and silently used different names. Same vault, two layouts, and it
/// only became visible when the iPad gained the ability to export at all. So the names stop
/// being configuration: Skrift owns its own house inside the folder you point at.
///
/// Signed off from `mocks/vault-folder-model.html` (Tuur, 2026-08-14: *"do it like u did in
/// the mockup"*), which also cut video — there is no `video` asset kind to export.
enum VaultLayout {

    /// The folder Skrift creates and owns when you point it at a plain folder.
    static let homeFolderName = "Skrift"

    /// Subfolders inside the home folder. Notes sit at its root — the folder is an INBOX
    /// you file OUT of, so notes stay reachable and attachments stay out of the way.
    static let audio = "Recordings"
    static let images = "Images"
    /// PDFs and other shared documents (`MemoAsset.Kind.document`). Reached the Mac since
    /// the 3b capture work but was never written to the vault until now.
    static let documents = "Documents"

    /// Resolve the folder the user picked into the folder we actually write into.
    ///
    /// Deliberately forgiving, because both of Tuur's habits have to work and neither
    /// should nest (*"if i pick a folder that already has a skrift folder then it just uses
    /// that. make it smart"*):
    ///
    /// 1. the pick **already holds our notes** → use it as-is (pointing at `0 Inbox/Skrift`
    ///    keeps working and moves nothing);
    /// 2. the pick **contains** a `Skrift/` folder → use that (point at `0 Inbox`);
    /// 3. otherwise → `<pick>/Skrift`, created on first write.
    ///
    /// Case 1 asks the FILES, not the folder name: a folder is ours when something in it
    /// carries a `skriftID` stamp. The stamp is already the public contract for "is this
    /// ours" (`VaultStamp`), so a folder someone renamed is still recognised — and a folder
    /// simply NAMED `Skrift` counts too, which is what saves the pre-stamp case.
    ///
    /// `.portfolio` returns the pick UNCHANGED: the portfolio already has a home and its
    /// folders are named by the portfolio, not by Skrift. Only the Obsidian profile creates
    /// and adopts a `Skrift/` folder.
    static func home(forPicked picked: URL, profile: ExportProfile = .obsidian,
                     fileManager fm: FileManager = .default) -> URL {
        guard profile.ownsHomeFolder else { return picked }
        // Named for us, or holding our notes — either is enough. The NAME check is not
        // cosmetic: the `skriftID` stamp only arrived 2026-07-26, so a folder full of
        // older exports carries no stamp at all, and without this a long-standing
        // `0 Inbox/Skrift` would fail to be recognised and get `Skrift/` created INSIDE
        // it — the `Skrift/Skrift/` nesting the doctrine exists to prevent.
        if picked.lastPathComponent == homeFolderName { return picked }
        if holdsSkriftNotes(picked, fileManager: fm) { return picked }

        // An existing `Skrift/` is adopted; otherwise name it, don't create it — the writer
        // makes directories as it needs them, so merely LOOKING at a folder never leaves a
        // mark in the vault.
        return picked.appendingPathComponent(homeFolderName, isDirectory: true)
    }

    /// True when this folder already contains at least one Skrift-stamped markdown file.
    ///
    /// Shallow and cheap: top level only, stops at the first hit, and reads just the head of
    /// each file — enough to see frontmatter without pulling a long note into memory.
    static func holdsSkriftNotes(_ folder: URL, fileManager fm: FileManager = .default) -> Bool {
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return false }
        for name in names where name.hasSuffix(".md") {
            let url = folder.appendingPathComponent(name)
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            if let text = VaultStamp.head(of: handle), text.contains(VaultStamp.idKey) {
                return true
            }
        }
        return false
    }
}
