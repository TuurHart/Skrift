import Foundation
import CryptoKit

/// Pure text prep for the retrieval index (P8). Platform-neutral, fully testable.
///
/// A memo indexes as ONE gist vector (identity: title + summary + place + people +
/// tags) PLUS body chunks (~175 words at sentence boundaries) — chunk, don't
/// truncate: the bake-off showed a query about a long memo's buried tail ranks the
/// tail chunk #1 while the whole-memo vector ranks #7.
enum MemoGist {
    /// Words per body chunk. The model window is ~512 tokens; ~175 words leaves
    /// slack for subword splits.
    static let chunkTargetWords = 175
    /// Gist cap — the model truncates long input anyway; keep the gist tight.
    static let gistMaxChars = 800

    /// Conversation transcripts carry `**Name:**` speaker headers. Embed spoken
    /// bodies only (same lesson as the desktop's conversation-tagging fix,
    /// dda494d C2) — headers inflate similarity between unrelated conversations.
    static func stripSpeakerHeaders(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\*\*[^*\n]{1,64}:\*\*\s*"#,
            with: "",
            options: .regularExpression
        )
    }

    /// The memo's identity string: title + (summary else leading body) + context.
    static func compose(title: String?, summary: String?, body: String,
                        place: String?, people: [String], tags: [String]) -> String {
        var parts: [String] = []
        if let title, !title.isEmpty { parts.append(title) }
        if let summary, !summary.isEmpty {
            parts.append(summary)
        } else {
            parts.append(String(body.prefix(500)))
        }
        if let place, !place.isEmpty { parts.append(place) }
        if !people.isEmpty { parts.append(people.joined(separator: ", ")) }
        if !tags.isEmpty { parts.append(tags.joined(separator: " ")) }
        return String(parts.joined(separator: "\n").prefix(gistMaxChars))
    }

    struct Chunk: Equatable {
        let text: String
        /// Character offsets into the (speaker-stripped) body — kept so a later
        /// "jump to the matching part" can highlight the source span.
        let start: Int
        let end: Int
    }

    /// Sentence-boundary chunking. Sentences accumulate until ~`targetWords`,
    /// then a chunk is emitted. Short bodies produce a single chunk; empty
    /// bodies produce none.
    static func chunks(body: String, targetWords: Int = chunkTargetWords) -> [Chunk] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var out: [Chunk] = []
        var currentText = ""
        var currentStart: Int? = nil
        var currentWords = 0

        let full = body.startIndex..<body.endIndex
        body.enumerateSubstrings(in: full, options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            let sentence = String(body[range])
            let words = sentence.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            guard words > 0 else { return }
            if currentStart == nil {
                currentStart = body.distance(from: body.startIndex, to: range.lowerBound)
            }
            currentText += sentence
            currentWords += words
            if currentWords >= targetWords {
                let end = body.distance(from: body.startIndex, to: range.upperBound)
                out.append(Chunk(text: currentText.trimmingCharacters(in: .whitespacesAndNewlines),
                                 start: currentStart!, end: end))
                currentText = ""
                currentStart = nil
                currentWords = 0
            }
        }
        if let start = currentStart,
           !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(Chunk(text: currentText.trimmingCharacters(in: .whitespacesAndNewlines),
                             start: start,
                             end: body.distance(from: body.startIndex, to: body.endIndex)))
        }
        return out
    }

    /// Stable content hash (SHA-256 prefix) — the sweep's invalidation key.
    static func textHash(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
