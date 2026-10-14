import Foundation

// Q421 (C258): a roster change that arrives by sync while a note is open re-derives that note's
// name spans at once, not on the next open. Before, only the Settings names list observed
// `.namesDidChangeFromSync`; the open note kept the links it was derived with until it was
// reopened or the user edited a name.

/// The open note's side of a synced roster change. The review screen points it at the note on
/// show (`open`), and it re-links + recompiles that note (no LLM, the same operation as
/// `ProcessingCoordinator.resanitiseForNames`) each time `.namesDidChangeFromSync` is posted.
/// Host-less on purpose (no coordinator, no view) so `OpenNoteRosterRefreshTests` can drive it
/// with a private `NotificationCenter`.
@MainActor
final class OpenNoteRosterRefresh {
    private(set) var file: PipelineFile?
    /// How many times a synced roster change re-derived the open note.
    private(set) var refreshCount = 0

    private let people: () -> [Person]
    private let author: () -> String
    private let afterRefresh: (PipelineFile) -> Void
    private var token: NSObjectProtocol?
    private let center: NotificationCenter

    /// `afterRefresh` is where the app saves the model context; the test leaves it empty.
    init(center: NotificationCenter = .default,
         people: @escaping () -> [Person] = { NamesStore.shared.livePeople() },
         author: @escaping () -> String = { SettingsStore.shared.load().authorName },
         afterRefresh: @escaping (PipelineFile) -> Void = { _ in }) {
        self.center = center
        self.people = people
        self.author = author
        self.afterRefresh = afterRefresh
        token = center.addObserver(forName: .namesDidChangeFromSync, object: nil, queue: nil) { [weak self] _ in
            // The reconcile posts from whichever thread ran the sync; the note model is main-actor.
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.refresh() }
            } else {
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    deinit { if let token { center.removeObserver(token) } }

    /// The note now on screen (nil when none is).
    func open(_ file: PipelineFile?) { self.file = file }

    /// Re-derive the open note over the CURRENT roster. A note that was never name-linked
    /// (no `sanitised` yet) is left to its first processing run.
    func refresh() {
        guard let file, file.sanitised != nil else { return }
        MemoCloudUpdate.resanitiseAndCompile(file, people: people(), author: author())
        refreshCount += 1
        afterRefresh(file)
    }
}
