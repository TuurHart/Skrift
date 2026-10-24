import Foundation

/// C163 (Q490): a note exported to one destination and then re-filed to the other (Personal ⇄
/// Portfolio) must not leave its old file behind — a Personal note never stays in the
/// portfolio, the privacy boundary D189 draws. Before the note is written to its new home,
/// the file this device wrote into the OLD home is judged by the same rules as every vault
/// write (C54): ours and untouched → removed, then the new one is written; edited in place or
/// moved elsewhere → the move is refused, naming that file, and nothing is written anywhere.
/// Shared by the Mac's `VaultExporter` and the phone/iPad `ObsidianPublisher`.
enum DestinationMove {
    enum Verdict: Equatable {
        /// This device never wrote the note into the old home, or that file is gone for good.
        case nothingThere
        /// Ours and untouched: remove it, then write the new one.
        case remove(relativePath: String)
        /// Edited in place (`backedOffUserEdited`) or filed elsewhere (`movedAway`): the move is
        /// refused and this outcome names the file.
        case refuse(VaultWriteOutcome)
    }

    /// Judge what note `id` left in `oldHome` (the folder Skrift owns for the destination the
    /// note is NOT in now), through that home's ledger.
    static func verdict(id: UUID, oldHome: URL, ledger: ExportLedger,
                        fileManager fm: FileManager = .default) -> Verdict {
        guard let known = ledger.entry(for: id) else { return .nothingThere }
        let dest = oldHome.appendingPathComponent(known.relativePath)
        guard fm.fileExists(atPath: dest.path) else {
            // Filed somewhere else under that home → his to keep, so the move waits. Nowhere →
            // deleted, which frees the move (the same moved-vs-deleted line `assess` draws).
            return VaultStamp.locate(id: id, under: oldHome, fileManager: fm) != nil
                ? .refuse(.movedAway(relativePath: known.relativePath)) : .nothingThere
        }
        switch VaultStamp.standing(of: VaultWriter.readCoordinated(dest)) {
        case .untouched(let marks) where marks.id == id:
            return .remove(relativePath: known.relativePath)
        case .userEdited(let marks) where marks.id == id:
            return .refuse(.backedOffUserEdited(relativePath: known.relativePath))
        default:
            // Not our note at that path any more (someone else's file took the name): there is
            // nothing of ours to remove, and theirs is never touched.
            return .nothingThere
        }
    }

    /// Carry out a `.remove`: delete the old file (coordinated, the vault lives in iCloud) and
    /// forget it in that home's ledger. True when the file is gone.
    @discardableResult
    static func removeOld(relativePath: String, id: UUID, oldHome: URL, ledger: ExportLedger,
                          fileManager fm: FileManager = .default) -> Bool {
        let url = oldHome.appendingPathComponent(relativePath)
        var coordError: NSError?
        var removed = false
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { u in
            removed = (try? fm.removeItem(at: u)) != nil
        }
        if removed || !fm.fileExists(atPath: url.path) { ledger.remove(for: id); return true }
        return false
    }
}
