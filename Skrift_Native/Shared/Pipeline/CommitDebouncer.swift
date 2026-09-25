import Foundation

/// Coalesces rapid-fire calls (typing) into ONE action per settle window — the
/// same "type, pause, then commit" shape as the real note editor's
/// `NoteBodyView.Coordinator.textViewDidChange`/`commitDraft` (1 s). Used by
/// Quick Note's title/body `onChange` so its `context.save()` stops running on
/// every keystroke (C277/C282). MainActor-bound: every caller today drives it
/// from SwiftUI `onChange`, same as the editor's own debounce.
@MainActor
final class CommitDebouncer {
    private var task: Task<Void, Never>?
    private let interval: Duration

    init(interval: Duration = .seconds(1)) {
        self.interval = interval
    }

    /// Cancel any pending fire and schedule a new one `interval` out.
    func schedule(_ action: @escaping () -> Void) {
        task?.cancel()
        task = Task { [interval] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    /// Cancel any pending fire and run `action` immediately — used to flush
    /// before something reads the debounced state (e.g. leaving the screen,
    /// where the empty/non-empty check must see the LATEST typed text).
    func flush(_ action: () -> Void) {
        task?.cancel()
        task = nil
        action()
    }

    /// Cancel any pending fire without running it (e.g. an explicit discard
    /// that must not resurrect the draft via a stale scheduled save).
    func cancel() {
        task?.cancel()
        task = nil
    }
}
