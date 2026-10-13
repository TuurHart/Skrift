import Foundation

// Q363 (plan/perf2/f-mac-ui.md M4, M6, M6b): the two decisions that keep Mac typing cheap,
// Foundation-only so the host-less `SkriftDesktopTests` bundle compiles them directly
// (`MacTypingWorkTests`). `MacCloudEditSync` and `BodyTextView` are the only callers.

/// One pending action per key, rescheduled by every call: a burst of keystrokes fires
/// ONCE, `delay` after the last one. `MacCloudEditSync` routes both the body and the
/// title push through one of these, so a typing pause costs one CloudKit save and one
/// sidebar notification, not one per key (M4).
@MainActor
final class MacTypingDebounce {
    let delay: Duration
    private var pending: [String: Task<Void, Never>] = [:]

    init(delay: Duration) { self.delay = delay }

    /// (Re)schedule `fire` for `key`; an earlier pending action for the same key is dropped.
    func schedule(_ key: String, _ fire: @escaping @MainActor () -> Void) {
        pending[key]?.cancel()
        pending[key] = Task { [weak self] in
            guard let delay = self?.delay else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.pending[key] = nil
            fire()
        }
    }

    func isPending(_ key: String) -> Bool { pending[key] != nil }
}

/// What one SwiftUI `updateNSView` of the note body must do (M6, M6b).
///
/// - Re-render only for an EXTERNAL text change, and never while a debounced model commit
///   is pending: the binding lags the typing by up to 1 s then, so "model differs from the
///   view" means "he is typing", and re-rendering would put the older model text back (M6b).
/// - The O(document) model-string rebuild runs only when the binding moved since the last
///   text this gate accounted for, not on every update (C277).
/// - Full restyle only when a styling input changed or playback just ended, never for an
///   update that only moved geometry or re-created closures (M6).
struct BodyUpdateGate<StyleKey: Equatable> {
    struct Plan: Equatable {
        var render: Bool
        var restyle: Bool
    }

    /// The binding text the view is known to show (rendered, or committed by us).
    private(set) var lastModel: String?
    private var lastStyle: StyleKey?
    private var wasPlaying = false

    /// - Parameters:
    ///   - model: the binding's text now.
    ///   - commitPending: a debounced model commit is in flight.
    ///   - style: everything the full restyle reads besides the text.
    ///   - playing: karaoke is on (it recolors in place; no restyle).
    ///   - storageModel: rebuilds the model string from the text view (O(document)).
    ///   - shown: the read-only legacy form of a pre-v2 body (Q13; identity for v2).
    mutating func plan(model: String, commitPending: Bool, style: StyleKey, playing: Bool,
                       storageModel: () -> String, shown: (String) -> String) -> Plan {
        var render = false
        if !commitPending, model != lastModel {
            let ms = storageModel()
            render = ms != model && ms != shown(model)
            lastModel = model
        }
        var restyle = false
        if !playing {
            restyle = !render && (wasPlaying || lastStyle != style)
            lastStyle = style
        }
        wasPlaying = playing
        return Plan(render: render, restyle: restyle)
    }

    /// The view now shows `model` (a render, or our own debounced commit wrote it).
    mutating func accounted(_ model: String) { lastModel = model }
}
