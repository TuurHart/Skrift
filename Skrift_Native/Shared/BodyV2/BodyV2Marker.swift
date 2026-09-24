import Foundation

/// Body v2's ONE picture-marker vocabulary (C14, C15). Every reader matches through
/// `regex` (`\d+` wide), every writer emits through `literal(_:)` (`%03d`). Marker N is
/// 1-based into `imageManifest` (C169); a marker whose N has no manifest entry is not a
/// picture and is left as the author's text.
enum BodyV2Marker {
    /// One marker; capture group 1 is the number.
    static let regex = try! NSRegularExpression(pattern: #"\[\[img_(\d+)\]\]"#)
    /// A run of adjacent markers plus the whitespace around and between them.
    static let runRegex = try! NSRegularExpression(pattern: #"\s*(?:\[\[img_\d+\]\]\s*)+"#)

    static func literal(_ n: Int) -> String { "[[img_\(String(format: "%03d", n))]]" }

    /// Consecutive picture paragraphs, in the given order (C13).
    static func block(_ numbers: [Int]) -> String { numbers.map(literal).joined(separator: "\n\n") }

    /// Marker numbers in body order.
    static func numbers(in text: String) -> [Int] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            Int(ns.substring(with: $0.range(at: 1)))
        }
    }

    /// A marker run whose every marker resolves into the manifest.
    struct Run {
        let range: NSRange
        let numbers: [Int]
        /// Newlines before the first marker / after the last one, inside the run.
        let newlinesBefore: Int
        let newlinesAfter: Int
    }

    static func runs(in text: String, manifestCount: Int) -> [Run] {
        let ns = text as NSString
        return runRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let run = ns.substring(with: m.range)
            let nums = numbers(in: run)
            guard !nums.isEmpty, nums.allSatisfy({ $0 >= 1 && $0 <= manifestCount }) else { return nil }
            let r = run as NSString
            let first = r.range(of: "[[").location
            let lastEnd = r.range(of: "]]", options: .backwards).location + 2
            func newlines(_ s: String) -> Int { s.utf16.filter { $0 == 10 }.count }
            return Run(range: m.range, numbers: nums,
                       newlinesBefore: newlines(r.substring(to: first)),
                       newlinesAfter: newlines(r.substring(from: lastEnd)))
        }
    }
}
