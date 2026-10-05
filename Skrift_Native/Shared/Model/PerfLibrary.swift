#if DEBUG
import Foundation
import SwiftData

/// Q313: the perf library. `-perfLibrary` (DEBUG only, both apps) points the app at a SEPARATE
/// on-disk SwiftData store (`perf.store`, CloudKit OFF) seeded once with ~2,000 deterministic
/// notes (`PerfLibrarySeeder`), plus its own names file, recordings folder and vocabulary key,
/// so a speed sweep runs on a realistic library without ever touching, or syncing into, the real
/// Dev data. Without the flag nothing here is consulted; Release compiles none of it.
///
/// "Inert under the flag" is enforced twice: the store has `cloudKitDatabase: .none`, and every
/// launch-time CloudKit side channel (names/vocab/prompts/audiobook sync, the sync monitor,
/// reminders, remote-notification registration, the share-inbox drain) returns early when
/// `isActive` is true. Each gate is a `guard !PerfLibrary.isActive` inside `#if DEBUG`.
enum PerfLibrary {
    static let flag = "-perfLibrary"

    /// True when this process was launched with `-perfLibrary`.
    static var isActive: Bool { LaunchArgs.has(flag) }

    static let storeFileName = "perf.store"
    /// Written once seeding has finished; a perf store without it is a half-seeded leftover.
    static let seededMarkerName = "perf.store.seeded"
    static let alreadySeededLine = "perf library already seeded, opening it as is"

    /// Folder the perf store lives in: next to the app's normal store (iOS Application Support;
    /// the Mac's per-build "Skrift Dev" folder).
    static var directory: URL {
        #if os(iOS)
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #else
        return AppPaths.appSupportDirectory
        #endif
    }

    static var storeURL: URL { directory.appendingPathComponent(storeFileName) }
    static var seededMarkerURL: URL { directory.appendingPathComponent(seededMarkerName) }

    /// SwiftData's default store location (what `ModelConfiguration(schema:)` opens) — the file
    /// the perf store must never be.
    static var defaultStoreURL: URL { directory.appendingPathComponent("default.store") }

    /// The perf store's configuration: an on-disk file of its own and NO CloudKit database,
    /// so it can never upload. One definition for both apps and the unit test.
    static func storeConfiguration(schema: Schema, url: URL = PerfLibrary.storeURL) -> ModelConfiguration {
        ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    }

    private static var didReset = false

    static var isSeeded: Bool { FileManager.default.fileExists(atPath: seededMarkerURL.path) }

    /// A launch with the flag but no seeded marker: remove any half-written perf store (and its
    /// -wal/-shm, and the perf media folder) so the seeder starts from nothing. Touches only
    /// the perf files; the normal store is never named here. Returns true when seeding is due.
    @discardableResult
    static func resetIfUnseeded() -> Bool {
        guard isActive, !isSeeded, !didReset else { return false }
        didReset = true   // once per process: never delete a store this process may already have open
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: directory.appendingPathComponent(storeFileName + suffix))
            #if os(macOS)
            try? fm.removeItem(at: AppPaths.storeFile.deletingLastPathComponent()
                .appendingPathComponent(AppPaths.storeFile.lastPathComponent + suffix))   // perf_skrift.store (the pipeline rows)
            #endif
        }
        #if os(macOS)
        try? fm.removeItem(at: AppPaths.audioOutputDirectory)   // the " Perf" working folders, perf-only under the flag
        #endif
        try? fm.removeItem(at: AppPaths.recordingsDirectory)   // already the perf folder under the flag
        try? fm.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
        return true
    }

    static func markSeeded() {
        try? Data("seeded\n".utf8).write(to: seededMarkerURL)
    }

    /// Append-only progress line (also readable by whoever launched the app headlessly).
    static func logProgress(_ line: String) {
        let url = directory.appendingPathComponent("perf-progress.txt")
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(stamped.utf8)); try? h.close()
        } else {
            try? Data(stamped.utf8).write(to: url)
        }
        print("[perf] \(line)")
    }

    /// Write the generated roster to the perf names file (`AppPaths.namesFile`, perf-suffixed
    /// under the flag) — never the real `names.json`.
    static func writeNames(_ people: [Person], to store: NamesStore = NamesStore()) {
        _ = store.save(NamesData(lastModifiedAt: ISO8601.now(), people: people))
    }
}
#endif
