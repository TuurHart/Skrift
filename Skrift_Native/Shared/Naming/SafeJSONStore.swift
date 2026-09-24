import Foundation
import os

/// ONE doctrine for every locally-cached JSON file (Q18, C50/C265/C218): atomic
/// write, and a file present-but-undecodable is NEVER treated as "fresh install
/// empty". Decode failure moves the original bytes aside to
/// `<name>.corrupt-<yyyyMMdd-HHmmss>` (never deleted, never silently adopted as
/// `[]`/defaults and written back over), logs it, and records it in
/// `CorruptFileRegistry` so the app can surface recovery.
///
/// Lives in Shared/Naming (not its own folder) so both apps' host-less test
/// bundles pick it up for free — they already compile this directory directly
/// (see project.yml comments beside `NamesStore.swift`); a new top-level Shared
/// folder would need four separate project.yml edits for zero behavioural gain.
///
/// Covers: `names.json` (`NamesStore`), Mac `settings.json` (`SettingsStore`),
/// phone `library.json` (`AudiobookLibraryStore`) + `bookmarks.json`
/// (`BookmarkStore`). The audiobook-bookmark CloudKit blob (R42) isn't a file —
/// its decode-never-adopts-empty guard lives directly in
/// `AudiobookBookmarkSyncCore`.
enum SafeJSONStore {

    /// Outcome of a load attempt. `value` is nil for both a genuinely missing
    /// file (fresh install — the normal, non-corrupt case) and a corrupt one
    /// (`wasCorrupt` tells them apart); callers that must never present an
    /// empty result on corruption (names.json, C50) fall back to their own
    /// last-known-good cache when `wasCorrupt` is true.
    struct LoadOutcome<T> {
        let value: T?
        let wasCorrupt: Bool
        let quarantinedTo: URL?

        static func missing() -> LoadOutcome<T> { LoadOutcome(value: nil, wasCorrupt: false, quarantinedTo: nil) }
        static func ok(_ v: T) -> LoadOutcome<T> { LoadOutcome(value: v, wasCorrupt: false, quarantinedTo: nil) }
    }

    private static let log = Logger(subsystem: "com.skrift.shared", category: "SafeJSONStore")

    /// Decode `url` as `T`. Never throws, never overwrites: a decode failure
    /// quarantines the original file (best-effort rename) and returns
    /// `wasCorrupt: true` with `value: nil` — the caller decides the fallback.
    static func load<T: Decodable>(_ type: T.Type, from url: URL,
                                    decoder: JSONDecoder = JSONDecoder()) -> LoadOutcome<T> {
        guard let data = try? Data(contentsOf: url) else { return .missing() }
        if let decoded = try? decoder.decode(T.self, from: data) {
            return .ok(decoded)
        }
        let quarantined = quarantine(url)
        CorruptFileRegistry.shared.record(url: url, quarantinedTo: quarantined)
        log.error("corrupt store: \(url.lastPathComponent, privacy: .public) failed to decode as \(String(describing: T.self), privacy: .public) — quarantined to \(quarantined?.lastPathComponent ?? "n/a", privacy: .public)")
        return LoadOutcome(value: nil, wasCorrupt: true, quarantinedTo: quarantined)
    }

    /// Atomic write. The ONE way any doctrine-covered file is ever written.
    static func write<T: Encodable>(_ value: T, to url: URL, encoder: JSONEncoder = JSONEncoder()) {
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Move (never copy — the original slot must end up genuinely empty so the
    /// caller's normal "no file yet" path runs, rather than re-reading the same
    /// corrupt bytes forever) the bad file aside to a timestamped sibling.
    /// Returns nil if the move itself fails (permissions, etc.) — the caller
    /// still reports `wasCorrupt: true` even then, it just can't point at a
    /// quarantine location.
    @discardableResult
    private static func quarantine(_ url: URL) -> URL? {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        df.timeZone = TimeZone(identifier: "UTC")
        let stamp = df.string(from: Date())
        var dest = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
        var suffix = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)-\(suffix)")
            suffix += 1
        }
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }
}

/// Recovery surfaced (minimum for this item): a Release-safe `os_log` line
/// (above) plus this in-memory flag the app can read. No new UI screen here —
/// a settings/debug banner reading `CorruptFileRegistry.shared.found` is the
/// natural next step (e.g. a row in the Mac's Settings or the phone's About
/// screen: "N cached file(s) needed repair — tap for details").
final class CorruptFileRegistry: @unchecked Sendable {
    static let shared = CorruptFileRegistry()

    struct Entry: Sendable {
        let url: URL
        let quarantinedTo: URL?
        let at: Date
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    var found: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    func record(url: URL, quarantinedTo: URL?) {
        lock.lock()
        entries.append(Entry(url: url, quarantinedTo: quarantinedTo, at: Date()))
        lock.unlock()
    }

    /// Test-only reset (avoid cross-test bleed).
    func reset() {
        lock.lock()
        entries = []
        lock.unlock()
    }
}
