import Foundation

/// C275: a spoken hashtag becomes a real tag, by rule and never by the model. "hashtag
/// motivation" / "hashtag motivatie" → `#motivation` / `#motivatie` where it was said; a run of
/// spoken hashtags at the END of a note becomes one tag line of its own, and a trailing "Okay"
/// after the run is dropped. Inside that run a custom-vocabulary acronym spoken letter by letter
/// counts as a tag too (C85: "C and C" → `#cnc` when CNC is a vocab word — the ASR hears the N
/// as "and"). Runs on the SHOWN body (the polish) on both apps; the raw transcript keeps the
/// words. Idempotent: a body that already carries the tags comes back unchanged.
enum SpokenHashtags {

    private static let filler: Set<String> = ["okay", "ok", "oké", "oke", "okee"]
    /// How a spoken letter can reach the transcript ("and" / "en" for N).
    private static let letterWords: [String: Character] = ["and": "n", "en": "n", "an": "n"]

    private struct Word { let text: String; let range: Range<String.Index> }

    /// The polish a person reads, with real tags: `apply` over everything but an audiobook
    /// capture's leading quote, which stays byte-identical (C1). A body of speaker turns is
    /// left verbatim (C179). What both polishers call.
    static func shownBody(_ body: String, vocabulary: [String]) -> String {
        guard SpeakerTranscript.parse(body) == nil else { return body }
        guard let split = QuoteProtection.splitLeadingQuote(body) else { return apply(body, vocabulary: vocabulary) }
        return QuoteProtection.reassemble(quote: split.quote, ramble: apply(split.ramble, vocabulary: vocabulary))
    }

    static func apply(_ body: String, vocabulary: [String] = []) -> String {
        let acronyms = Set(vocabulary.map { $0.lowercased() }.filter { $0.count >= 2 && $0.allSatisfy(\.isLetter) })
        let words = tokens(body)
        let (prefixEnd, found) = trailingRun(words, in: body, acronyms: acronyms)
        let head = inline(String(body[..<prefixEnd]))
        guard !found.isEmpty else { return head }
        var seen = Set<String>()
        let tags = found.filter { seen.insert($0).inserted }   // spoken order, no repeats
        let prose = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = tags.map { "#" + $0 }.joined(separator: " ")
        return prose.isEmpty ? line : prose + "\n\n" + line
    }

    // MARK: - the end-of-note run

    /// Where the prose before the trailing run ends, and the run's tags in spoken order. No run
    /// → (end of body, []).
    private static func trailingRun(_ words: [Word], in body: String,
                                    acronyms: Set<String>) -> (String.Index, [String]) {
        var i = words.count - 1
        if i >= 0, filler.contains(words[i].text.lowercased()) { i -= 1 }
        var tags: [String] = []
        var start = body.endIndex
        var hashtagItems = 0
        while i >= 0 {
            if let (tag, first) = hashtagItem(endingAt: i, words) {
                tags.insert(tag, at: 0); start = words[first].range.lowerBound
                hashtagItems += 1; i = first - 1
                continue
            }
            // An acronym counts only BETWEEN two spoken hashtags.
            if hashtagItems > 0, let (tag, first) = acronymItem(endingAt: i, words, acronyms),
               first > 0, hashtagItem(endingAt: first - 1, words) != nil {
                tags.insert(tag, at: 0); start = words[first].range.lowerBound
                i = first - 1
                continue
            }
            break
        }
        guard hashtagItems > 0 else { return (body.endIndex, []) }
        // One hashtag closing a running sentence stays inline ("felt good hashtag motivation");
        // a run of them, or one standing as its own sentence, is the tag line.
        let before = body[..<start].trimmingCharacters(in: .whitespaces)
        let standsAlone = before.isEmpty || before.last.map { ".!?\n".contains($0) } == true
        guard tags.count >= 2 || standsAlone else { return (body.endIndex, []) }
        return (start, tags)
    }

    /// "hashtag X" / "hash tag X" whose X is `words[i]`: (tag, index of the first word).
    private static func hashtagItem(endingAt i: Int, _ words: [Word]) -> (String, Int)? {
        guard i >= 1, let tag = tagText(words[i].text) else { return nil }
        if words[i - 1].text.lowercased() == "hashtag" { return (tag, i - 1) }
        if i >= 2, words[i - 1].text.lowercased() == "tag", words[i - 2].text.lowercased() == "hash" {
            return (tag, i - 2)
        }
        return nil
    }

    /// A vocab acronym spoken letter by letter, ending at `words[i]`: (tag, index of first word).
    private static func acronymItem(endingAt i: Int, _ words: [Word],
                                    _ acronyms: Set<String>) -> (String, Int)? {
        var letters = ""
        var j = i
        while j >= 0, i - j < 8 {
            let w = words[j].text.lowercased()
            guard let c = w.count == 1 && w.first!.isLetter ? w.first : letterWords[w] else { return nil }
            letters.insert(c, at: letters.startIndex)
            if letters.count >= 2, acronyms.contains(letters) { return (letters, j) }
            j -= 1
        }
        return nil
    }

    // MARK: - inline

    private static let inlinePattern = try! NSRegularExpression(
        pattern: #"(?i)\bhash\s?tag\s+([\p{L}\p{N}][\p{L}\p{N}_-]*)"#)

    private static func inline(_ text: String) -> String {
        let ns = text as NSString
        var out = text
        for m in inlinePattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let tag = tagText(ns.substring(with: m.range(at: 1))),
                  let r = Range(m.range, in: out) else { continue }
            out.replaceSubrange(r, with: "#" + tag)
        }
        return out
    }

    // MARK: - words

    /// An Obsidian tag from a spoken word: lowercased, letters / digits / `_` `-` only.
    private static func tagText(_ word: String) -> String? {
        let t = String(word.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        guard let first = t.first, first.isLetter || first.isNumber,
              !t.allSatisfy(\.isNumber),               // `#2026` is not a tag in Obsidian
              t != "hashtag" else { return nil }
        return t
    }

    private static let wordPattern = try! NSRegularExpression(pattern: #"[\p{L}\p{N}][\p{L}\p{N}_'’-]*"#)

    private static func tokens(_ text: String) -> [Word] {
        wordPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            Range(m.range, in: text).map { Word(text: String(text[$0]), range: $0) }
        }
    }
}
