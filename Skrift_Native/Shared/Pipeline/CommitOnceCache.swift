import Foundation

/// A single-slot memo keyed by whatever identifies "the same commit" (a memo-set
/// version counter, a transcript string, …) — recomputes only when the key differs
/// from the last call. Used to collapse the typing-path costs the perf sweep found
/// running once per CALL SITE into one run per key (C277/C282: nothing heavy runs
/// per keystroke) — `NotesRepository.allTags()` (per memo-set version) and the
/// editor's `recomputeSpans()` double-fire (per transcript text) both route through
/// this same shape. Thread-confined to whatever actor calls it (both current uses
/// are MainActor); not itself synchronized.
final class CommitOnceCache<Key: Equatable, Value> {
    private var lastKey: Key?
    private var lastValue: Value?
    /// How many times `compute` actually ran — read by tests to prove the
    /// "at most once per commit" contract; harmless to read in production.
    private(set) var computeCount = 0

    init() {}

    /// Returns the cached value when `key` matches the last call; otherwise runs
    /// `compute`, caches, and returns the fresh value.
    func value(for key: Key, compute: () -> Value) -> Value {
        if let lastKey, lastKey == key, let lastValue {
            return lastValue
        }
        computeCount += 1
        let value = compute()
        lastKey = key
        lastValue = value
        return value
    }

    /// Forces the next `value(for:compute:)` call to recompute regardless of key.
    func invalidate() {
        lastKey = nil
        lastValue = nil
    }
}
