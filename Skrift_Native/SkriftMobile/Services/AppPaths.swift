import Foundation

/// Canonical on-disk locations for app data. Audio, photos, and word-timing
/// sidecars live in `Documents/recordings`, mirroring the RN layout. `names.json`
/// lives at the Documents root (the schema the Mac sync expects).
enum AppPaths {
    static var documentsDirectory: URL { URL.documentsDirectory }

    static var recordingsDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var namesFile: URL {
        documentsDirectory.appendingPathComponent("names.json")
    }
}
