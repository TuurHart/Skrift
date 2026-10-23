import Foundation

/// Canonical on-disk locations for app data — ONE type for both apps (SharedKit
/// wave 2; previously the name `AppPaths` was declared per-app with different
/// members, the highest-risk twin class). Platform sections live side-by-side so
/// the layout contract — e.g. `names.json` byte-compatible across apps — is one
/// file, not a convention.
enum AppPaths {
    /// The names DB filename — the phone⇄Mac contract (NamesMerge LWW). Same name
    /// in both containers; only the base directory differs per platform.
    static let namesFileName = "names.json"

    // MARK: - Create once (C280)

    private static let createLock = NSLock()
    nonisolated(unsafe) private static var createdPaths: Set<String> = []
    nonisolated(unsafe) private static var createCalls = 0

    /// R93/C280: the ONE place a directory accessor creates its folder — at most once per
    /// path per process launch, however often the accessor is read (99+ call sites read
    /// `recordingsDirectory`). Returns `dir` so an accessor is one expression.
    @discardableResult
    static func ensureDirectory(_ dir: URL) -> URL {
        let key = dir.standardizedFileURL.path
        createLock.lock(); defer { createLock.unlock() }
        guard createdPaths.insert(key).inserted else { return dir }
        createCalls += 1
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// How many times `ensureDirectory` actually called `createDirectory` this launch.
    static var createDirectoryCallCount: Int {
        createLock.lock(); defer { createLock.unlock() }
        return createCalls
    }

    #if os(iOS)
    // iOS: bundle-id namespaced containers give dev ("com.skrift.mobile.dev") and
    // prod their own sandboxes for free — no path suffixing needed. Audio, photos,
    // and word-timing sidecars live in `Documents/recordings` (the RN-era layout).
    static var documentsDirectory: URL { URL.documentsDirectory }

    /// R93/C280: `static let`, not a computed `var` — the directory only needs
    /// creating ONCE per process. 99 call sites across the repo read this; a
    /// computed `var` ran `createDirectory` (mkdir+stat) on every single one.
    static let recordingsDirectory: URL = {
        #if DEBUG
        // Q313: `-perfLibrary` keeps its generated photos/audio out of the real library's folder.
        let folder = PerfLibrary.isActive ? "recordings_perf" : "recordings"
        #else
        let folder = "recordings"
        #endif
        return ensureDirectory(documentsDirectory.appendingPathComponent(folder, isDirectory: true))
    }()

    static var namesFile: URL {
        #if DEBUG
        if PerfLibrary.isActive { return documentsDirectory.appendingPathComponent("names.perf.json") }   // Q313: fake people never reach the real roster
        #endif
        return documentsDirectory.appendingPathComponent(namesFileName)
    }
    #endif

    #if os(macOS)
    // macOS: a non-sandboxed app's locations are NOT bundle-id namespaced, so the
    // Debug ("Skrift Dev") build suffixes every on-disk location to keep dev
    // iteration away from the production names DB / settings / audio output.
    // Release keeps the original paths (inheriting the Electron-era names DB).
    #if DEBUG
    private static let dataSuffix = " Dev"
    #else
    private static let dataSuffix = ""
    #endif

    /// C280: `static let` — created once per launch, never on each of its many reads.
    static let appSupportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return ensureDirectory(base.appendingPathComponent("Skrift\(dataSuffix)", isDirectory: true))
    }()

    static var namesFile: URL {
        #if DEBUG
        // Headless snapshots use a synthetic roster (`-snapshot-split`), never the dev data.
        if let o = ProcessInfo.processInfo.environment["SKRIFT_NAMES_FILE"], !o.isEmpty { return URL(fileURLWithPath: o) }
        if PerfLibrary.isActive { return appSupportDirectory.appendingPathComponent("names.perf.json") }   // Q313
        #endif
        return appSupportDirectory.appendingPathComponent(namesFileName)
    }
    static var settingsFile: URL { appSupportDirectory.appendingPathComponent("user_settings.json") }

    /// SwiftData store — explicit path inside appSupportDirectory so it's isolated
    /// per build (the default store location is NOT bundle-id-namespaced for a
    /// non-sandboxed macOS app, which would share dev + prod data).
    static var storeFile: URL {
        #if DEBUG
        if PerfLibrary.isActive { return appSupportDirectory.appendingPathComponent("perf_skrift.store") }   // Q313
        #endif
        return appSupportDirectory.appendingPathComponent("skrift.store")
    }

    /// LOCAL mirror store for the CloudKit-backed Memo container (MAC_CLOUDKIT_PLAN.md
    /// 8a-iii). SEPARATE file from `storeFile` (the two SwiftData containers must not
    /// share a store), and explicit + dev/prod-suffixed for the same reason as
    /// `storeFile`: dev (syncing iCloud.com.skrift.mobile.dev) and prod (…mobile)
    /// would otherwise collide their CloudKit-mirror metadata in one file.
    static var memoCloudStoreFile: URL {
        #if DEBUG
        if PerfLibrary.isActive { return PerfLibrary.storeURL }   // Q313: perf.store, CloudKit off
        #endif
        return appSupportDirectory.appendingPathComponent("memo_cloud.store")
    }

    /// Q397 (ICLOUD_MERGE A1): the `CloudFirstImport` stamp — "the store at
    /// `memoCloudStoreFile` has finished its first CloudKit import". Names that store file by
    /// identity, so it stays behind harmlessly when the store family is moved out.
    static var memoCloudFirstImportStamp: URL {
        appSupportDirectory.appendingPathComponent("memo_cloud.first-import.json")
    }

    /// Where a Mac RECORDING is written before it is ingested (2026-07-28, the Mac grew a
    /// record button). Same member name as the iOS side on purpose — `RecordingCore` and
    /// `MacRecorder` don't branch on platform to find it. Inside appSupport rather than
    /// Documents so it is dev/prod-suffixed like every other store: a Dev take must never
    /// land in the real library. The file leaves here the moment `IngestService` copies it
    /// into its working folder, so this stays a staging area, not a second library.
    static let recordingsDirectory: URL = {
        #if DEBUG
        let folder = PerfLibrary.isActive ? "recordings_perf" : "recordings"   // Q313
        #else
        let folder = "recordings"
        #endif
        return ensureDirectory(appSupportDirectory.appendingPathComponent(folder, isDirectory: true))
    }()

    static let audioOutputDirectory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        #if DEBUG
        let perfSuffix = PerfLibrary.isActive ? " Perf" : ""   // Q313: perf working folders stay apart from the Dev ones
        #else
        let perfSuffix = ""
        #endif
        return ensureDirectory(base.appendingPathComponent(
            "Voice Transcription Pipeline Audio Output\(dataSuffix)\(perfSuffix)", isDirectory: true))
    }()
    #endif
}
