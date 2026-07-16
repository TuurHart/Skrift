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

    #if os(iOS)
    // iOS: bundle-id namespaced containers give dev ("com.skrift.mobile.dev") and
    // prod their own sandboxes for free — no path suffixing needed. Audio, photos,
    // and word-timing sidecars live in `Documents/recordings` (the RN-era layout).
    static var documentsDirectory: URL { URL.documentsDirectory }

    static var recordingsDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var namesFile: URL {
        documentsDirectory.appendingPathComponent(namesFileName)
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

    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Skrift\(dataSuffix)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var namesFile: URL { appSupportDirectory.appendingPathComponent(namesFileName) }
    static var settingsFile: URL { appSupportDirectory.appendingPathComponent("user_settings.json") }

    /// SwiftData store — explicit path inside appSupportDirectory so it's isolated
    /// per build (the default store location is NOT bundle-id-namespaced for a
    /// non-sandboxed macOS app, which would share dev + prod data).
    static var storeFile: URL { appSupportDirectory.appendingPathComponent("skrift.store") }

    /// LOCAL mirror store for the CloudKit-backed Memo container (MAC_CLOUDKIT_PLAN.md
    /// 8a-iii). SEPARATE file from `storeFile` (the two SwiftData containers must not
    /// share a store), and explicit + dev/prod-suffixed for the same reason as
    /// `storeFile`: dev (syncing iCloud.com.skrift.mobile.dev) and prod (…mobile)
    /// would otherwise collide their CloudKit-mirror metadata in one file.
    static var memoCloudStoreFile: URL { appSupportDirectory.appendingPathComponent("memo_cloud.store") }

    static var audioOutputDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Voice Transcription Pipeline Audio Output\(dataSuffix)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    #endif
}
