import Foundation

/// Strip `[[img_NNN]]` markers before copy-edit and reinsert them afterward using
/// the transcript words around each marker as anchors. The LLM can't be trusted to
/// preserve markers, so they're removed, the text is edited, then markers are
/// placed back deterministically. Pure + host-testable; ported from the backend
/// `copy_edit_with_image_markers_stream` + `_reinsert_image_markers`. UTF-16
/// (NSString) offsets throughout to mirror the Python char-offset logic.
enum ImageMarkerReinsert {
    struct Anchors: Equatable, Sendable { let before: String; let after: String }

    private static let markerRegex = try! NSRegularExpression(pattern: #"\[\[img_(\d{3})\]\]"#)
    private static let sentenceEndRegex = try! NSRegularExpression(pattern: #"[.!?]\s"#)

    /// Returns the marker-stripped text, the img numbers in order, and the saved
    /// anchors (≤6 words before, ≤6 after each marker).
    static func extractAnchors(_ input: String) -> (stripped: String, imgNums: [Int], anchors: [Int: Anchors]) {
        let ns = input as NSString
        let matches = markerRegex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (collapseWhitespace(input), [], [:]) }

        var imgNums: [Int] = []
        var anchors: [Int: Anchors] = [:]
        for (i, m) in matches.enumerated() {
            let img = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let prevEnd = i > 0 ? matches[i - 1].range.location + matches[i - 1].range.length : 0
            let beforeText = ns.substring(with: NSRange(location: prevEnd, length: m.range.location - prevEnd))
            let thisEnd = m.range.location + m.range.length
            let nextStart = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
            let afterText = ns.substring(with: NSRange(location: thisEnd, length: nextStart - thisEnd))

            let beforeWords = beforeText.split(whereSeparator: { $0.isWhitespace }).suffix(6).joined(separator: " ")
            let afterWords = afterText.split(whereSeparator: { $0.isWhitespace }).prefix(6).joined(separator: " ")
            anchors[img] = Anchors(before: String(beforeWords), after: String(afterWords))
            imgNums.append(img)
        }
        let stripped = markerRegex.stringByReplacingMatches(
            in: input, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        return (collapseWhitespace(stripped), imgNums, anchors)
    }

    static func reinsert(text: String, imgNums: [Int], anchors: [Int: Anchors]) -> String {
        guard !imgNums.isEmpty else { return text }
        let ns = text as NSString
        let total = ns.length
        var targets: [(img: Int, pos: Int)] = []
        var minPos = 0

        for (i, img) in imgNums.enumerated() {
            let a = anchors[img] ?? Anchors(before: "", after: "")
            var insertPos = -1

            // "before" anchor: longest-first suffix of the words before the marker.
            if !a.before.isEmpty {
                let words = a.before.lowercased().split(separator: " ").map(String.init)
                var len = min(words.count, 6)
                while len > 0 {
                    let search = words.suffix(len).joined(separator: " ")
                    if search.count >= 4 {
                        let idx = find(ns, search, from: minPos)
                        if idx >= 0 {
                            let endOfAnchor = idx + (search as NSString).length
                            insertPos = endOfAnchor
                            if endOfAnchor < total {
                                let rest = ns.substring(from: endOfAnchor) as NSString
                                if let sm = sentenceEndRegex.firstMatch(in: rest as String, range: NSRange(location: 0, length: rest.length)) {
                                    insertPos = endOfAnchor + sm.range.location + sm.range.length
                                }
                            }
                            break
                        }
                    }
                    len -= 1
                }
            }

            // "after" anchor: longest-first prefix of the words after the marker.
            if insertPos < 0 && !a.after.isEmpty {
                let words = a.after.lowercased().split(separator: " ").map(String.init)
                var len = min(words.count, 6)
                while len > 0 {
                    let search = words.prefix(len).joined(separator: " ")
                    if search.count >= 4 {
                        let idx = find(ns, search, from: minPos)
                        if idx >= 0 {
                            let lookback = ns.substring(to: idx) as NSString
                            let last = max(rfind(lookback, ". "), max(rfind(lookback, "! "), rfind(lookback, "? ")))
                            insertPos = last >= 0 ? last + 2 : idx
                            break
                        }
                    }
                    len -= 1
                }
            }

            // Proportional fallback, snapped back to a sentence boundary.
            if insertPos < 0 {
                insertPos = Int(Double(i + 1) / Double(imgNums.count + 1) * Double(total))
                let lbStart = max(0, insertPos - 80)
                let lookback = ns.substring(with: NSRange(location: lbStart, length: insertPos - lbStart)) as NSString
                let lastPeriod = rfind(lookback, ". ")
                if lastPeriod >= 0 { insertPos = lbStart + lastPeriod + 2 }
            }

            insertPos = min(max(insertPos, minPos), total)
            targets.append((img, insertPos))
            minPos = insertPos
        }

        // Insert from the end backward so earlier insertions don't shift later offsets.
        var result = text
        for t in targets.sorted(by: { ($0.pos, $0.img) > ($1.pos, $1.img) }) {
            let r = result as NSString
            let pos = min(max(0, t.pos), r.length)
            result = r.substring(to: pos) + "\n\n[[img_\(String(format: "%03d", t.img))]]\n\n" + r.substring(from: pos)
        }
        return result
    }

    // MARK: - Helpers

    private static func find(_ haystack: NSString, _ needle: String, from: Int) -> Int {
        guard from >= 0, from <= haystack.length else { return -1 }
        let r = haystack.range(of: needle, options: .caseInsensitive,
                               range: NSRange(location: from, length: haystack.length - from))
        return r.location == NSNotFound ? -1 : r.location
    }

    private static func rfind(_ haystack: NSString, _ needle: String) -> Int {
        let r = haystack.range(of: needle, options: .backwards)
        return r.location == NSNotFound ? -1 : r.location
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
