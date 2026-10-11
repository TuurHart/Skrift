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

    /// The whole fill, run OFF the main actor on its own context of `container` (Q340). The seeder
    /// saves in batches of `PerfLibrarySeeder.saveBatch` and never touches `NotesRepository`, so
    /// `memoSetVersion` / `memoStructureVersion` do not move until the caller's `afterChange`.
    /// `progress` is called on the worker thread.
    nonisolated static func fillWork(container: ModelContainer, recordingsDirectory: URL?, names: NamesStore,
                                     now: Date = Date(), plan: PerfLibrarySeeder.Plan = PerfLibrarySeeder.Plan(),
                                     progress: (@Sendable (String, Int, Int) -> Void)? = nil) async throws -> TestLibrary.FillSummary {
        try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            return try TestLibrary.fill(into: context, names: names, recordingsDirectory: recordingsDirectory,
                                        now: now, plan: plan, progress: progress)
        }.value
    }

    /// Marked notes in the store, counted off the main actor (decoding 2,000 metadata blobs is
    /// not main-thread work).
    nonisolated static func markedCount(in container: ModelContainer) async -> Int {
        await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            return ((try? context.fetch(FetchDescriptor<Memo>())) ?? []).filter(TestLibrary.isMarked).count
        }.value
    }

    /// Fill the store behind `container`. `recordingsDirectory` is the phone's media folder (nil on
    /// the Mac). `afterChange` runs on the main actor when the store changed (re-read lists, push
    /// the names carrier). The status line follows the real phases: building, saving (with counts),
    /// "refreshing the list" while `afterChange` runs on main, then the final line once it returned.
    func fill(container: ModelContainer, recordingsDirectory: URL?, names: NamesStore = .shared,
              afterChange: @escaping @MainActor () -> Void) {
        guard !busy else { return }
        busy = true
        status = "Filling with test notes…"
        let began = Date()
        Task {
            var line: String
            var changed = false
            do {
                let s = try await Self.fillWork(container: container, recordingsDirectory: recordingsDirectory,
                                                names: names) { phase, done, total in
                    Task { @MainActor in self.status = "Filling with test notes: \(phase) \(done) / \(total)" }
                }
                changed = s.memosAdded > 0 || s.peopleAdded > 0
                line = !changed
                    ? "Already full: the test notes are all here."
                    : "Added \(s.memosAdded) notes, \(s.assetsAdded) files, \(s.peopleAdded) people in \(Int(Date().timeIntervalSince(began))) s. They sync to your other devices in the background."
            } catch {
                line = "Fill failed: \(error)"
                changed = true   // earlier batches may have saved: re-read the lists anyway
            }
            if changed {
                // `afterChange` rebuilds the lists on this actor and can hold it for a moment:
                // say so first and let the line draw before it starts.
                status = "Saved. Refreshing the list (the screen may pause for a second)…"
                try? await Task.sleep(nanoseconds: 150_000_000)
                afterChange()
            }
            markedCount = await Self.markedCount(in: container)
            status = line
            busy = false
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
            let count = await Self.markedCount(in: container)
            await MainActor.run {
                self.status = line
                self.busy = false
                self.markedCount = count
                afterChange()
            }
        }
    }

    /// Re-count the marked notes without blocking the main actor.
    func refreshCount(container: ModelContainer) {
        Task { markedCount = await Self.markedCount(in: container) }
    }
}
#endif
