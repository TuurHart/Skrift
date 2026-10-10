#if DEBUG
import Foundation
import SwiftData

/// Q336: the Settings glue for `TestLibrary`, ONE class for both apps. Runs the generator and the
/// removal on a background context of the app's own store (the UI never waits on it), keeps the
/// status line the two Settings rows show, and tells the app when the store changed so its lists
/// re-read. The Settings views only draw `status` and call `fill` / `remove`.
@MainActor
final class TestLibraryRunner: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var status = ""
    /// Marked notes in the store right now (refreshed by `refreshCount`, and after every run).
    @Published private(set) var markedCount = 0

    enum Copy {
        static let sectionTitle = "Test notes (Dev only)"
        static let fillTitle = "Fill with test notes"
        static let removeTitle = "Remove test notes"
        static let help = "Adds 2,000 made-up notes, with photos, audio and 150 made-up people, to this app's own store. They sync to every Skrift Dev device through the Dev iCloud, and Remove deletes exactly those everywhere. Your real notes are never touched."
        static let removeConfirm = "Delete every test note and the made-up people, on every Dev device?"
    }

    /// Fill the store behind `container`. `recordingsDirectory` is the phone's media folder (nil on
    /// the Mac). `afterChange` runs on the main actor when the store changed (re-read lists, push
    /// the names carrier).
    func fill(container: ModelContainer, recordingsDirectory: URL?, names: NamesStore = .shared,
              afterChange: @escaping @MainActor () -> Void) {
        guard !busy else { return }
        busy = true
        status = "Filling with test notes…"
        let began = Date()
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let line: String
            do {
                let s = try TestLibrary.fill(into: context, names: names, recordingsDirectory: recordingsDirectory) { phase, done, total in
                    Task { @MainActor in self.status = "Filling with test notes: \(phase) \(done) / \(total)" }
                }
                line = s.memosAdded == 0 && s.peopleAdded == 0
                    ? "Already full: the test notes are all here."
                    : "Added \(s.memosAdded) notes, \(s.assetsAdded) files, \(s.peopleAdded) people in \(Int(Date().timeIntervalSince(began))) s."
            } catch {
                line = "Fill failed: \(error)"
            }
            await MainActor.run {
                self.status = line
                self.busy = false
                self.refreshCount(container: container)
                afterChange()
            }
        }
    }

    /// Remove exactly the marked notes and the made-up people. `deleteLocalFiles` drops a note's
    /// audio / photos from the phone's media folder.
    func remove(container: ModelContainer, names: NamesStore = .shared,
                deleteLocalFiles: (@Sendable (Memo) -> Void)? = nil,
                afterChange: @escaping @MainActor () -> Void) {
        guard !busy else { return }
        busy = true
        status = "Removing test notes…"
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let line: String
            do {
                let r = try TestLibrary.remove(from: context, names: names, deleteLocalFiles: deleteLocalFiles)
                line = "Removed \(r.memos) notes, \(r.assets) files, \(r.people) people."
            } catch {
                line = "Remove failed: \(error)"
            }
            await MainActor.run {
                self.status = line
                self.busy = false
                self.refreshCount(container: container)
                afterChange()
            }
        }
    }

    func refreshCount(container: ModelContainer) {
        let context = ModelContext(container)
        markedCount = ((try? context.fetch(FetchDescriptor<Memo>())) ?? []).filter(TestLibrary.isMarked).count
    }
}
#endif
