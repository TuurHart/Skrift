import Foundation

/// `[[img_NNN]]` marker insertion — pure + host-testable, and SHARED: the phone
/// injects markers at record time and the Mac injects them for its own ingests
/// (`transcriptMarkersInjected` tells the Mac not to re-inject), so placement
/// must be identical on both. Ported verbatim from the RN `ParakeetModule` /
/// backend `_insert_image_markers`. Works in UTF-16 (NSString) indices
/// throughout; spot-check multibyte/emoji parity vs the Python era if it drifts.
enum ImageMarkers {

    /// Insert a marker at the word whose start time is closest to each photo's
    /// offset (numbering ascends by offset).
    static func insert(transcript: String, words: [TimedWord], manifest: [ImageManifestEntry]) -> String {
        guard !words.isEmpty, !manifest.isEmpty else { return transcript }

        var charEnd = [Int](repeating: 0, count: words.count)
        let nsTranscript = transcript as NSString
        var scanPos = 0
        let totalLen = nsTranscript.length
        let totalDuration = max(1.0, words.last?.end ?? 1.0)

        for i in words.indices {
            let needle = words[i].text as NSString
            var found = -1
            if scanPos < totalLen {
                let range = NSRange(location: scanPos, length: totalLen - scanPos)
                let r = nsTranscript.range(of: needle as String, options: [], range: range)
                if r.location != NSNotFound {
                    found = r.location
                    charEnd[i] = found + needle.length
                    scanPos = found + needle.length
                }
            }
            if found == -1 {
                let estimated = Int(Double(totalLen) * words[i].start / totalDuration)
                charEnd[i] = min(max(0, estimated), totalLen)
            }
        }

        let sorted = manifest.sorted { $0.offsetSeconds < $1.offsetSeconds }
        var insertions: [(pos: Int, marker: String)] = []
        for (i, entry) in sorted.enumerated() {
            var bestIdx = 0
            var bestDiff = abs(words[0].start - entry.offsetSeconds)
            for (wi, w) in words.enumerated() {
                let diff = abs(w.start - entry.offsetSeconds)
                if diff < bestDiff {
                    bestDiff = diff
                    bestIdx = wi
                }
            }
            insertions.append((charEnd[bestIdx], "\n\n[[img_\(String(format: "%03d", i + 1))]]\n\n"))
        }

        var result = transcript
        for (pos, marker) in insertions.sorted(by: { $0.pos > $1.pos }) {
            let nsResult = result as NSString
            let safePos = min(max(0, pos), nsResult.length)
            result = nsResult.substring(to: safePos) + marker + nsResult.substring(from: safePos)
        }
        return result
    }
}
