import Foundation
import UIKit
import Vision

/// On-device OCR for memo photos (note feature wave, chunk 6): each photo's
/// recognized text lands on its `ImageManifestEntry.text` — INSIDE the synced
/// metadata blob, so every device (including the Mac) carries it and the memos
/// search finds text that lives in photos. Fully private: Vision runs on-device.
///
/// Idempotent sweep, same shape as `AssetMaterializer`: an entry with
/// `text == nil` whose file is on disk gets recognized exactly once ("" when
/// the photo has no readable text, so it's never re-scanned). Runs on launch,
/// on foreground, when a CloudKit sync settles (photos arriving from another
/// device), and after a photo is inserted in the editor.
@MainActor
enum PhotoTextIndexer {
    private static var running = false

    static func run(_ repository: NotesRepository) {
        guard !running else { return }
        struct Job { let memoID: UUID; let index: Int; let url: URL }
        var jobs: [Job] = []
        for memo in repository.allMemos() {
            guard let manifest = memo.metadata?.imageManifest else { continue }
            for (i, entry) in manifest.enumerated() where entry.text == nil {
                let url = AppPaths.recordingsDirectory.appendingPathComponent(entry.filename)
                if FileManager.default.fileExists(atPath: url.path) {
                    jobs.append(Job(memoID: memo.id, index: i, url: url))
                }
            }
        }
        guard !jobs.isEmpty else { return }
        running = true
        Task {
            defer { running = false }
            var indexed = 0
            for job in jobs {
                let text = await Self.recognize(at: job.url)
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
