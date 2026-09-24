import AVFoundation
import Foundation
import os

/// Release-safe recording-lifecycle log (C287). Every transition of a take —
/// start, segment, interrupt, finalize, recover — goes to the unified log
/// (`os_log`, subsystem `com.skrift.mobile`, category `recording`), which
/// survives Release builds unlike the DEBUG-only `DevLog`. A small in-memory
/// mirror of the last lines lets tests assert the order of events.
enum RecordingLifecycleLog {
    static let subsystem = "com.skrift.mobile"
    static let category = "recording"
    private static let logger = Logger(subsystem: subsystem, category: category)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var mirror: [String] = []

    /// One lifecycle line, e.g. `log("segment", "take=… reason=60s")`.
    static func log(_ event: String, _ detail: String = "") {
        let line = detail.isEmpty ? "rec \(event)" : "rec \(event) — \(detail)"
        logger.notice("\(line, privacy: .public)")
        lock.lock()
        mirror.append(line)
        if mirror.count > 200 { mirror.removeFirst(mirror.count - 200) }
        lock.unlock()
        DevLog.log(line)
    }

    /// The most recent lines, oldest first (tests).
    static var recent: [String] {
        lock.lock(); defer { lock.unlock() }
        return mirror
    }
}

/// The durable row a take leaves on disk while it records (C99/D26). Written
/// when the take starts and rewritten on every segment, so a launch sweep can
/// find a take the process never finished and rebuild the note from it.
struct RecordingMarker: Codable, Equatable {
    var takeID: String
    /// The process run that owns the take. A marker from THIS run belongs to a
    /// live recording and is never swept.
    var sessionID: String
    var startedAt: Date
    /// The take's main file (`rec_tmp_<take>.m4a`) — only readable once closed.
    var mainFilename: String
    /// Closed, readable segment files in take order.
    var segments: [String]
    /// True when the main file was closed cleanly (stop, or a force-quit that
    /// delivered `willTerminate`) — the sweep then prefers it over the segments.
    var finalized: Bool
    var updatedAt: Date
}

/// Persists a take in closed ~60 s segments beside the main `.m4a` (C99/D26).
///
/// The main file is AAC-in-MP4: its index is written only when it is closed, so a
/// kill mid-take leaves it unreadable. Each segment here is its own small `.m4a`
/// that gets CLOSED every 60 s of audio and on every interruption, memory warning
/// and trip to the background, and the marker is rewritten to list it — so after
/// any death the launch sweep can rebuild everything up to the last close.
///
/// Threading: `write`/`rotate`/`finalize`/`close` run on the recorder's serial
/// writer queue (or with that queue drained); the class holds no locks itself.
final class RecordingCheckpoint: @unchecked Sendable {
    static let segmentSeconds: Double = 60
    /// One id per process run — see `RecordingMarker.sessionID`.
    static let currentSessionID = UUID().uuidString

    static func markerFilename(take: String) -> String { "rec_ckpt_\(take).json" }
    static func mainFilename(take: String) -> String { "rec_tmp_\(take).m4a" }
    static func segmentFilename(take: String, index: Int) -> String {
        "rec_seg_\(take)_\(String(format: "%03d", index)).m4a"
    }

    let directory: URL
    let takeID: String
    private let settings: [String: Any]
    private let segmentFrames: AVAudioFramePosition
    private(set) var marker: RecordingMarker
    private var current: AVAudioFile?
    private var currentName: String?
    private var nextIndex = 1

    var markerURL: URL { directory.appendingPathComponent(Self.markerFilename(take: takeID)) }
    var mainURL: URL { directory.appendingPathComponent(marker.mainFilename) }

    /// Creates the marker on disk immediately — the take is findable from its
    /// first instant, before any audio lands.
    init(directory: URL, takeID: String, settings: [String: Any], sampleRate: Double,
         segmentSeconds: Double = RecordingCheckpoint.segmentSeconds, startedAt: Date = Date()) {
        self.directory = directory
        self.takeID = takeID
        self.settings = settings
        self.segmentFrames = AVAudioFramePosition(max(1, sampleRate * segmentSeconds))
        self.marker = RecordingMarker(takeID: takeID, sessionID: Self.currentSessionID,
                                      startedAt: startedAt, mainFilename: Self.mainFilename(take: takeID),
                                      segments: [], finalized: false, updatedAt: startedAt)
        saveMarker()
    }

    /// Append one write-format buffer to the open segment (opened lazily, so a
    /// rotation never leaves an empty file). Closes the segment once it holds
    /// `segmentSeconds` of audio. Throws on a failed write (disk full).
    func write(_ buffer: AVAudioPCMBuffer) throws {
        if current == nil {
            let name = Self.segmentFilename(take: takeID, index: nextIndex)
            nextIndex += 1
            current = try AVAudioFile(forWriting: directory.appendingPathComponent(name), settings: settings)
            currentName = name
        }
        try current?.write(from: buffer)
        if let current, current.length >= segmentFrames { rotate(reason: "60s") }
    }

    /// Close the open segment and list it in the marker. No-op without one.
    func rotate(reason: String) {
        guard let file = current, let name = currentName else { return }
        file.close()
        current = nil
        currentName = nil
        marker.segments.append(name)
        saveMarker()
        RecordingLifecycleLog.log("segment", "take=\(takeID) n=\(marker.segments.count) reason=\(reason)")
    }

    /// Close the open segment and mark the main file as cleanly closed.
    func finalize() {
        rotate(reason: "finalize")
        marker.finalized = true
        saveMarker()
    }

    /// The take ended normally and its main file is safe: delete the segments
    /// and the marker.
    func discard() {
        current?.close()
        current = nil
        let fm = FileManager.default
        for name in Self.takeFiles(take: takeID, in: directory) where name != marker.mainFilename {
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
        try? fm.removeItem(at: markerURL)
    }

    /// Closed segment URLs, in take order.
    var segmentURLs: [URL] { marker.segments.map { directory.appendingPathComponent($0) } }

    private func saveMarker() {
        marker.updatedAt = Date()
        do {
            let data = try JSONEncoder().encode(marker)
            try data.write(to: markerURL, options: .atomic)
        } catch {
            RecordingLifecycleLog.log("marker-write-failed", "take=\(takeID) \(error.localizedDescription)")
        }
    }

    /// Every file on disk that belongs to a take (main, segments, marker).
    static func takeFiles(take: String, in directory: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter {
            $0 == mainFilename(take: take) || $0 == markerFilename(take: take)
                || $0.hasPrefix("rec_seg_\(take)_")
        }.sorted()
    }

    /// Delete every file belonging to `take` from disk. Only ever safe to call
    /// once the take's audio has been merged into a new memo file that opened
    /// with frames and was inserted + saved to the repository — an unreadable /
    /// unrecoverable take is quarantined instead (see `RecordingRecovery`, C288).
    static func discardTakeFiles(take: String, in directory: URL) {
        let fm = FileManager.default
        for f in takeFiles(take: take, in: directory) {
            try? fm.removeItem(at: directory.appendingPathComponent(f))
        }
    }

    /// Delete a single scratch file if it exists — used for working output that
    /// never became a note (e.g. a failed audio merge attempt), never for a
    /// take's own recorded audio.
    static func discardIfExists(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// True when `url` opens as audio with at least one frame.
    static func isReadableAudio(_ url: URL) -> Bool {
        guard let f = try? AVAudioFile(forReading: url) else { return false }
        return f.length > 0
    }
}
