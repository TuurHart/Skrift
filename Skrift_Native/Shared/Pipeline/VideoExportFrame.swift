import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// C63 / D210: the picture a video note puts in the Obsidian vault in place of its movie (the
/// vault never gets the movie). One frame as a JPEG, picked the way the import always picked its
/// frame (~1 s in, the midpoint of a very short clip: no black opening frame). Both apps' export
/// engines call this one function; it blocks on the file, so call it only when a write happens.
enum VideoExportFrame {

    /// The vault file's name, and so the embed's: `<note stem>_frame.jpg`.
    static func exportName(stem: String) -> String { "\(stem)_frame.jpg" }

    /// The frame of `movie` as JPEG data. nil when the file is not a readable video.
    static func jpeg(from movie: URL) -> Data? {
        let asset = AVURLAsset(url: movie)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        let duration = CMTimeGetSeconds(asset.duration)
        let seconds = duration.isFinite ? min(1.0, max(0, duration / 2)) : 0
        guard let frame = try? generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
        else { return nil }
        let out = NSMutableData()
        guard let sink = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(sink, frame, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(sink) else { return nil }
        return out as Data
    }
}
