import Foundation

/// Detects chapter boundaries from a book's TRANSCRIPT (the wave-2 sidecar
/// word-timings) — pure, host-less, unit-tested. This is the STANDARD chapter
/// source once a book is fully transcribed: file boundaries aren't reliably
/// chapter boundaries (arbitrary splits, time-based rips), but the narration
/// itself is — produced audiobooks announce chapters after a long silence.
///
/// Signal = a LONG pause (or a file start) followed by a short heading
/// utterance: "Chapter 7" / "Chapter Twenty-Three" / "Part Two" / "Hoofdstuk 3"
/// / a standalone section word (Prologue, Epilogue, …). The heading's number
/// must terminate cleanly (sentence punctuation or a beat of silence) so prose
/// that merely *starts* with "Chapter seven ended badly…" never matches. An
/// optional short next sentence becomes the chapter's title ("Chapter 7 —
/// The Boy Who Lived" style data, stored as title "The Boy Who Lived").
///
/// Precision beats recall throughout: `detect` returns nil (→ keep whatever
/// chapters exist today) unless it finds ≥2 confident headings with sane
/// numbering. All thresholds are internal constants, tuned in tests.
enum ChapterDetector {

    // MARK: - Tunables

    /// Silence before a heading for it to count as a structural break.
    static let gapBefore: TimeInterval = 2.0
    /// A heading's number must be followed by ≥ this much silence when it
    /// carries no sentence punctuation ("Chapter seven ended…" guard).
    static let numberEndGap: TimeInterval = 0.35
    /// Title candidate: the sentence after the heading, if it's short and ends
    /// with sentence punctuation. Longest accepted title, in words.
    static let maxTitleWords = 9
    /// A spoken title HANGS — silence after it before prose starts.
    static let titleEndGap: TimeInterval = 0.4
    /// Two same-kind detections closer than this are echoes/recaps — keep the first.
    static let minSameKindSpacing: TimeInterval = 45
    /// Below 2 detections there is no chaptering; above 400 something is wrong.
    static let minDetections = 2
    static let maxDetections = 400
    /// An implicit "Opening" chapter is prepended when the first detected
    /// heading starts later than this (title/credits announcement).
    static let openingThreshold: TimeInterval = 30

    // MARK: - Detection

    /// One confirmed heading, before chapter-list assembly.
    struct Heading: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case chapter(Int), part(Int), standalone(String) }
        let kind: Kind
        /// Global (whole-book) start second — the heading word's start.
        let start: TimeInterval
        /// Spoken title sentence after the heading, if one was confidently found.
        let title: String?
    }

    /// Detect chapters across a whole book. `fileWords` = one word-timing array
    /// per book file (FILE-LOCAL times, the sidecars); `fileStartTimes` maps each
    /// file to its global origin. Returns a full-coverage chapter list, or nil
    /// when no confident chaptering was found (caller keeps existing chapters).
    static func detect(fileWords: [[WordTiming]],
                       fileStartTimes: [TimeInterval],
                       bookDuration: TimeInterval) -> [AudiobookChapter]? {
        var all: [Heading] = []
        for (fileIndex, words) in fileWords.enumerated() {
            let origin = fileIndex < fileStartTimes.count ? fileStartTimes[fileIndex] : 0
            all.append(contentsOf: headings(in: words, globalOrigin: origin))
        }
        all.sort { $0.start < $1.start }

        all = dropEchoes(all)
        guard all.count >= minDetections, all.count <= maxDetections else { return nil }
        guard numbersAreSane(all) else { return nil }

        return assemble(all, bookDuration: bookDuration)
    }

    /// Scan one file's words for confirmed headings (global times out).
    static func headings(in words: [WordTiming], globalOrigin: TimeInterval) -> [Heading] {
        var found: [Heading] = []
        var i = 0
        while i < words.count {
            // Candidate = the file's first word, or any word after a long silence.
            let isCandidate = i == 0 || (words[i].start - words[i - 1].end) >= gapBefore
            if isCandidate, let (heading, consumed) = matchHeading(words, at: i, globalOrigin: globalOrigin) {
                found.append(heading)
                i += consumed
            } else {
                i += 1
            }
        }
        return found
    }

    // MARK: - Heading grammar

    /// Try to read a heading starting at `words[i]`. Returns the heading and
    /// how many words it consumed (heading + title), or nil.
    private static func matchHeading(_ words: [WordTiming], at i: Int,
                                     globalOrigin: TimeInterval) -> (Heading, Int)? {
        let first = core(words[i].word)

        // "Chapter <n>" / "Hoofdstuk <n>" / "Part <n>" / "Book <n>" / "Deel <n>"
        if let kindWord = keywordKind(first) {
            guard let (value, numberEnd) = parseNumber(words, from: i + 1) else { return nil }
            guard terminatesCleanly(words, lastIndex: numberEnd) else { return nil }
            let (title, consumedTitle) = titleAfter(words, index: numberEnd + 1)
            let kind: Heading.Kind = kindWord == .chapter ? .chapter(value) : .part(value)
            return (Heading(kind: kind, start: globalOrigin + words[i].start, title: title),
                    (numberEnd - i + 1) + consumedTitle)
        }

        // Standalone section word ("Prologue.", "Epilogue.", …) — must itself
        // terminate cleanly, so prose like "the introduction of…" can't match
        // (and the keyword must be the utterance's FIRST word — enforced by the
        // candidate anchor).
        if standaloneSections.contains(first) {
            guard terminatesCleanly(words, lastIndex: i) else { return nil }
            let (title, consumedTitle) = titleAfter(words, index: i + 1)
            return (Heading(kind: .standalone(first.capitalized),
                            start: globalOrigin + words[i].start, title: title),
                    1 + consumedTitle)
        }
        return nil
    }

    private enum KeywordKind { case chapter, part }
    private static func keywordKind(_ word: String) -> KeywordKind? {
        if word == "chapter" || word == "hoofdstuk" { return .chapter }
        if word == "part" || word == "book" || word == "deel" || word == "boek" { return .part }
        return nil
    }

    private static let standaloneSections: Set<String> = [
        "prologue", "epilogue", "introduction", "preface", "foreword", "afterword",
        "interlude", "intermezzo", "dedication", "acknowledgments", "acknowledgements",
        "proloog", "epiloog", "voorwoord", "nawoord", "inleiding", "dankwoord",
    ]

    /// The heading's last word must end a sentence or be followed by a beat of
    /// silence — the guard that rejects prose starting with a heading word.
    private static func terminatesCleanly(_ words: [WordTiming], lastIndex: Int) -> Bool {
        guard lastIndex < words.count else { return false }
        if endsSentence(words[lastIndex].word) { return true }
        guard lastIndex + 1 < words.count else { return true }   // end of transcript
        return (words[lastIndex + 1].start - words[lastIndex].end) >= numberEndGap
    }

    /// A short sentence right after the heading = the spoken chapter title
    /// ("Chapter Seven. <beat> The Boy Who Lived."). Only accepted when it ends
    /// with sentence punctuation within `maxTitleWords` AND hangs — a beat of
    /// silence follows it, the way narrators read titles. A short opening prose
    /// sentence flows straight on and is rejected.
    private static func titleAfter(_ words: [WordTiming], index: Int) -> (String?, Int) {
        var collected: [String] = []
        var i = index
        while i < words.count, collected.count < maxTitleWords {
            collected.append(words[i].word)
            if endsSentence(words[i].word) {
                let hangs = i + 1 >= words.count
                    || (words[i + 1].start - words[i].end) >= titleEndGap
                let title = strippedSentence(collected)
                // Must hang, and a bare number ("2.") or empty remainder is no title.
                guard hangs, !title.isEmpty, Int(title) == nil else { return (nil, 0) }
                return (title, collected.count)
            }
            i += 1
        }
        return (nil, 0)
    }

    // MARK: - Sanity + assembly

    /// Drop a detection that REPEATS the previous kept heading (same kind AND
    /// same number/name) implausibly soon — a re-announcement or recap echo.
    /// Distinct numbers close together are legitimately short chapters and
    /// kept; part-then-chapter adjacency is normal and kept.
    private static func dropEchoes(_ headings: [Heading]) -> [Heading] {
        var kept: [Heading] = []
        for h in headings {
            if let twin = kept.last(where: { $0.kind == h.kind }),
               h.start - twin.start < minSameKindSpacing { continue }
            kept.append(h)
        }
        return kept
    }

    /// Numbered chapters should mostly ascend (a reset to 1 after a part break
    /// is fine). Too many inversions = the matches are prose FPs → bail.
    static func numbersAreSane(_ headings: [Heading]) -> Bool {
        var numbers: [Int] = []
        for h in headings { if case .chapter(let n) = h.kind { numbers.append(n) } }
        guard numbers.count >= 3 else { return true }   // too few to judge
        var inversions = 0
        for (prev, next) in zip(numbers, numbers.dropFirst()) where next <= prev && next != 1 {
            inversions += 1
        }
        return Double(inversions) / Double(numbers.count) <= 0.3
    }

    /// Turn confirmed headings into a full-coverage chapter list.
    private static func assemble(_ headings: [Heading],
                                 bookDuration: TimeInterval) -> [AudiobookChapter] {
        var chapters: [AudiobookChapter] = []
        if let first = headings.first, first.start > openingThreshold {
            chapters.append(AudiobookChapter(title: "Opening", start: 0, duration: 0))
        }
        for h in headings {
            chapters.append(AudiobookChapter(title: label(for: h), start: h.start, duration: 0))
        }
        for i in chapters.indices {
            let end = i + 1 < chapters.count ? chapters[i + 1].start : max(bookDuration, chapters[i].start)
            chapters[i].duration = max(0, end - chapters[i].start)
        }
        return chapters
    }

    /// "Chapter 7" / "Part 2" / "Prologue", with the spoken title appended the
    /// way embedded m4b tracks carry it ("Chapter 7 — The Boy Who Lived").
    static func label(for h: Heading) -> String {
        let base: String
        switch h.kind {
        case .chapter(let n): base = "Chapter \(n)"
        case .part(let n): base = "Part \(n)"
        case .standalone(let s): base = s
        }
        guard let title = h.title else { return base }
        return base + " — " + title
    }

    // MARK: - Word plumbing

    /// Lowercased core of a token: leading/trailing punctuation stripped,
    /// diaeresis normalized (Dutch glued numbers: "drieëntwintig").
    static func core(_ token: String) -> String {
        token.trimmingCharacters(in: .alphanumerics.inverted)
            .lowercased()
            .replacingOccurrences(of: "ë", with: "e")
    }

    private static func endsSentence(_ word: String) -> Bool {
        Paragrapher.endsSentence(word)
    }

    /// Joined words with the terminal sentence punctuation stripped.
    private static func strippedSentence(_ words: [String]) -> String {
        var joined = words.joined(separator: " ")
        while let last = joined.last, ".?!\"”'’)]»".contains(last) { joined.removeLast() }
        return joined.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Number words (digits, spelled English, basic + glued Dutch)

    /// Parse a number starting at `words[from]` (up to 4 tokens: "one hundred
    /// and four", "twenty three", "23", "drieëntwintig"). Returns the value and
    /// the index of the LAST token consumed.
    static func parseNumber(_ words: [WordTiming], from: Int) -> (value: Int, lastIndex: Int)? {
        guard from < words.count else { return nil }
        // Digits first — Parakeet's ITN usually emits "Chapter 23."
        let first = core(words[from].word)
        if let n = Int(first), n > 0, n < 10_000 { return (n, from) }

        // Spelled numbers: greedily extend while tokens still parse.
        var best: (Int, Int)?
        var tokens: [String] = []
        for i in from..<min(from + 4, words.count) {
            tokens.append(core(words[i].word))
            if let v = spelledValue(tokens) { best = (v, i) }
            // Stop extending past a sentence end — "Seven. The" never joins.
            if endsSentence(words[i].word) { break }
        }
        return best
    }

    private static let units: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9,
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6,
        "seventh": 7, "eighth": 8, "ninth": 9,
        "een": 1, "twee": 2, "drie": 3, "vier": 4, "vijf": 5, "zes": 6, "zeven": 7,
        "acht": 8, "negen": 9,
        "eerste": 1, "tweede": 2, "derde": 3, "vierde": 4, "vijfde": 5, "zesde": 6,
        "zevende": 7, "achtste": 8, "negende": 9,
    ]
    private static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
        "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19,
        "tien": 10, "elf": 11, "twaalf": 12, "dertien": 13, "veertien": 14, "vijftien": 15,
        "zestien": 16, "zeventien": 17, "achttien": 18, "negentien": 19,
        "tiende": 10, "elfde": 11, "twaalfde": 12,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
        "seventy": 70, "eighty": 80, "ninety": 90,
        "twintig": 20, "dertig": 30, "veertig": 40, "vijftig": 50, "zestig": 60,
        "zeventig": 70, "tachtig": 80, "negentig": 90,
    ]

    /// Value of a spelled-number token run, or nil when it isn't one. Handles
    /// "seven", "twenty" "three", "twenty-three", "one" "hundred" ("and") "four",
    /// and Dutch glued compounds ("drieentwintig" = drie+en+twintig).
    static func spelledValue(_ tokens: [String]) -> Int? {
        var parts: [String] = []
        for t in tokens {
            // Hyphenated ("twenty-three" cores to "twentythree"? No — core keeps
            // alphanumerics only at the EDGES; internal hyphens survive) — split them.
            parts.append(contentsOf: t.split(separator: "-").map(String.init))
        }
        parts = parts.filter { $0 != "and" && $0 != "en" && $0 != "the" && $0 != "de" && $0 != "het" }
        guard !parts.isEmpty else { return nil }

        var total = 0
        var current = 0
        for p in parts {
            if let u = units[p] { current += u }
            else if let t = teens[p] { current += t }
            else if let t = tens[p] { current += t }
            else if p == "hundred" || p == "honderd" {
                current = max(current, 1) * 100
            } else if let glued = dutchGlued(p) {
                current += glued
            } else {
                return nil
            }
        }
        total += current
        return total > 0 ? total : nil
    }

    /// Dutch glued compound: "<unit>en<tens>" ("drieentwintig" → 23).
    private static func dutchGlued(_ token: String) -> Int? {
        for (tensWord, tensValue) in tens where token.hasSuffix("en" + tensWord) {
            let unitPart = String(token.dropLast(tensWord.count + 2))
            if let u = units[unitPart] { return u + tensValue }
        }
        return nil
    }
}
