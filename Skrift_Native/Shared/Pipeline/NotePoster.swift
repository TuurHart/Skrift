import Foundation
import AVFoundation
import CoreGraphics

/// A video block's poster frame, made OFF the main thread and kept once per file (Q391, both
/// apps). `frame(for:)` never decodes: a miss starts one background generation and answers nil
/// (the painter draws the block without its picture); when the frame lands, `ready` posts on the
/// main thread with the file URL as its object and the editors swap that block's picture in place.
final class NotePoster: @unchecked Sendable {

    static let shared = NotePoster()

    /// Posted on the main thread when a poster lands. `object` = the video's file URL.
    static let ready = Notification.Name("NotePoster.ready")

    /// One frame per file, big enough for the widest block (720 pt at 2x).
    static let maxPixel: CGFloat = 1440

    private let lock = NSLock()
    private var frames: [String: CGImage] = [:]
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    private var started = 0

    /// How many generations have started (test seam: one per file, however often it is drawn).
    var generationCount: Int { lock.lock(); defer { lock.unlock() }; return started }

    private static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    /// The poster when it is already made; otherwise nil, and (once per file) a background
    /// generation starts. Safe to call from any thread; never blocks on the file.
    func frame(for url: URL) -> CGImage? {
        let k = Self.key(url)
        lock.lock()
        if let hit = frames[k] { lock.unlock(); return hit }
        let start = !inFlight.contains(k) && !failed.contains(k)
        if start { inFlight.insert(k); started += 1 }
        lock.unlock()
        if start { generate(url, key: k) }
        return nil
    }

    private func generate(_ url: URL, key k: String) {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: Self.maxPixel, height: Self.maxPixel)
        let at = NSValue(time: CMTime(seconds: 0.1, preferredTimescale: 600))
        // AVFoundation runs this on its own queue and calls back there.
        gen.generateCGImagesAsynchronously(forTimes: [at]) { [weak self] _, cg, _, _, _ in
            guard let self else { return }
            self.lock.lock()
            self.inFlight.remove(k)
            if let cg { self.frames[k] = cg } else { self.failed.insert(k) }
            self.lock.unlock()
            _ = gen   // keep the generator alive until its callback
            guard cg != nil else { return }
            DispatchQueue.main.async { NotificationCenter.default.post(name: Self.ready, object: url) }
        }
    }
}
