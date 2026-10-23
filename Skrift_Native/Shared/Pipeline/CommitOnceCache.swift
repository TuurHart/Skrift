import Foundation

/// A single-slot memo keyed by whatever identifies "the same commit" (a memo-set
/// version counter, a transcript string, …) — recomputes only when the key differs
/// from the last call. Used to collapse the typing-path costs the perf sweep found
/// running once per CALL SITE into one run per key (C277/C282: nothing heavy runs
/// per keystroke) — `NotesRepository.allTags()` (per memo-set version) and the
/// editor's `recomputeSpans()` double-fire (per transcript text) both route through
/// this same shape. Synchronized: `SpeakerTranscript.parse` keeps one static instance and
/// is called from the Mac's pass off the main actor while the main actor reads it too —
/// unsynchronized, two writers corrupted the heap (Q483: a SwiftData dealloc crash inside
/// the copy-edit corpus harnesses). `compute` runs OUTSIDE the lock, so it may re-enter.
final class CommitOnceCache<Key: Equatable, Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var lastKey: Key?
    private var lastValue: Value?
    /// How many times `compute` actually ran — read by tests to prove the
    /// "at most once per commit" contract; harmless to read in production.
    private(set) var computeCount = 0

    init() {}

    /// Returns the cached value when `key` matches the last call; otherwise runs
    /// `compute`, caches, and returns the fresh value.
    func value(for key: Key, compute: () -> Value) -> Value {
        if let hit = peek(for: key) { return hit }
        let value = compute()
        lock.lock()
        computeCount += 1
        lastKey = key
        lastValue = value
        lock.unlock()
        return value
    }

    /// The cached value for `key` without computing (nil on a different key or no value).
    func peek(for key: Key) -> Value? {
        lock.lock(); defer { lock.unlock() }
        if let lastKey, lastKey == key { return lastValue }
        return nil
    }
}
