import Foundation
import UIKit
import Vision
import SwiftData

/// On-device OCR for memo photos (note feature wave, chunk 6): each photo's
/// recognized text lands on its `ImageManifestEntry.text` — INSIDE the synced
/// metadata blob, so every device (including the Mac) carries it and the memos
/// search finds text that lives in photos. Fully private: Vision runs on-device.
///
/// Idempotent sweep, same shape as `AssetMaterializer`: an entry with
/// `text == nil` whose file is on disk gets recognized exactly once ("" when
/// the photo has no readable text, so it's never re-scanned). Runs on launch,
/// on foreground, when a CloudKit sync settles (photos arriving from another
/// device), after a photo is inserted in the editor, and after a save lands
/// captured photos (recording / video import) — without that last trigger a
/// fresh memo's photos stayed unsearchable until the next launch (build 31).
@MainActor
enum PhotoTextIndexer {
    private static var running = false
    /// A trigger that arrived while a sweep was running (a save landing photos
    /// mid-sweep). It used to be dropped, leaving those photos unindexed until the
    /// next trigger; the running sweep now re-runs once for it when it ends.
    private static var pending: NotesRepository?

    /// The OCR call the sweep makes: real Vision in the app. Tests swap in a fake
    /// so the save -> searchable contract does not hang on Vision's cold start on
    /// a freshly erased simulator (Q310). `recognize` has its own real-Vision tests.
    static var recognizer: @Sendable (URL) async -> String = { await recognize(at: $0) }

    /// One photo waiting for OCR. Plain values, so the off-main discovery can hand them
    /// to the main actor without a SwiftData object crossing.
    struct Job: Sendable, Equatable {
        let memoID: UUID
        let index: Int
        let filename: String
        var url: URL { AppPaths.recordingsDirectory.appendingPathComponent(filename) }
    }

    /// Photos whose `text == nil` and whose file is on disk. Decodes every memo's metadata
    /// and stats each un-OCR'd photo, so launch/foreground run it on `SweepActor` (Q316).
    nonisolated static func discoverJobs(in context: ModelContext) -> [Job] {
        var jobs: [Job] = []
        let live = (try? context.fetch(FetchDescriptor<Memo>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]))) ?? []
        for memo in live {
            guard let manifest = memo.metadata?.imageManifest else { continue }
            for (i, entry) in manifest.enumerated() where entry.text == nil {
                let url = AppPaths.recordingsDirectory.appendingPathComponent(entry.filename)
                if FileManager.default.fileExists(atPath: url.path) {
                    jobs.append(Job(memoID: memo.id, index: i, filename: entry.filename))
                }
            }
        }
        return jobs
    }

    /// Main-context discovery + OCR (the recording / editor save paths).
    static func run(_ repository: NotesRepository) {
        guard !running else { pending = repository; return }
        let jobs = discoverJobs(in: repository.context)
        guard !jobs.isEmpty else { return }
        running = true
        process(jobs, repository)
    }

    /// Launch / foreground / import burst: discovery runs on `sweeps` (off the main thread),
    /// the OCR was already off-main, and the per-photo write-back stays on the main context
    /// (it re-validates against the live memo). Same re-entrancy rule as `run`.
    static func runOffMain(_ repository: NotesRepository, sweeps: SweepActor) async {
        guard !running else { pending = repository; return }
        running = true   // reserve BEFORE the await so a second trigger queues instead of racing
        let jobs = await sweeps.photoJobs()
        guard !jobs.isEmpty else { finishSweep(); return }
        process(jobs, repository)
    }

    private static func finishSweep() {
        running = false
        // A trigger that arrived mid-sweep: re-discover for it OFF the main thread.
        if let next = pending {
            pending = nil
            Task { await runOffMain(next, sweeps: LaunchSweeps.sweepActor(for: next)) }
        }
    }

    /// OCR each job and write the text back. The caller has set `running`.
    private static func process(_ jobs: [Job], _ repository: NotesRepository) {
        let recognize = recognizer
        Task {
            defer { finishSweep() }
            var indexed = 0
            for job in jobs {
                let text = await recognize(job.url)
                // Round-3 evidence: "indexed N" hid empty results — the user's
                // photos may OCR to "" (angle/handwriting) while the count
                // looks healthy. Log what Vision actually read, per photo.
                DevLog.log("photoText: \(job.url.lastPathComponent) chars=\(text.count)"
                           + (text.isEmpty ? " (no text found)" : " head='\(text.prefix(24))'"))
                // Re-validate against the LIVE memo — the manifest can change
                // under a slow OCR pass (append, sync) — then write back.
                guard let memo = repository.memo(id: job.memoID),
                      var meta = memo.metadata,
                      var manifest = meta.imageManifest,
                      job.index < manifest.count,
                      manifest[job.index].filename == job.url.lastPathComponent,
                      manifest[job.index].text == nil else { continue }
                manifest[job.index].text = text
                meta.imageManifest = manifest
                memo.metadata = meta
                indexed += 1
            }
            if indexed > 0 {
                repository.save()
                DevLog.log("photoText: indexed \(indexed) photo(s)")
            }
        }
    }

    /// Vision text recognition, off the main actor. "" = ran, nothing found
    /// (distinct from nil = never ran).
    nonisolated static func recognize(at url: URL) async -> String {
        guard let cg = UIImage(contentsOfFile: url.path)?.cgImage else { return "" }
        return await recognize(cgImage: cg)
    }

    /// The core recognizer — also used by the document scanner (chunk 9).
    nonisolated static func recognize(cgImage: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    continuation.resume(returning: "")
                    return
                }
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }
}
