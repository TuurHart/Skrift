import Foundation

/// Detects chapter boundaries from a book's TRANSCRIPT (the wave-2 sidecar
/// word-timings) — pure, host-less, unit-tested. This is the STANDARD chapter
/// source once a book is fully transcribed: file boundaries aren't reliably
/// chapter boundaries (arbitrary splits, time-based rips), but the narration
/// is — production specs (ACX) have narrators read each section heading
/// exactly as the manuscript writes it, then pause.
///
/// The manuscript decides the STYLE — "Chapter Seven", a bare "Seven.", or
/// just a title ("A Lopsided Arms Race.") — but a book uses ONE style
/// throughout (narrator guides call mixed styles a defect). So v2 works as a
/// style VOTE, not one grammar:
///   1. harvest candidates after silences (all styles at once),
///   2. pick the style the book itself corroborates —
///      keyword headings › bare numbers › title-only, in falling confidence,
///      each with its own quorum + sanity gates,
///   3. validate the winner against duration priors (chapters are minutes,
///      not seconds — the m4b-tool prior), else return nil.
///
/// Precision beats recall throughout: `detect` returns nil (→ keep whatever
/// chapters exist today) unless one style clears its gates.
enum ChapterDetector {

    // MARK: - Tunables

    /// Smallest silence that anchors a candidate (ACX post-heading pause is
    /// 1–3 s; chunk seams can shave it, so the floor sits below that).
    static let gapBefore: TimeInterval = 1.2
    /// A heading's number/keyword must be followed by ≥ this much silence when
    /// it carries no sentence punctuation ("Chapter seven ended…" guard).
    static let numberEndGap: TimeInterval = 0.35
    /// Title candidate: the sentence after the heading, if it's short and ends
    /// with sentence punctuation. Longest accepted title, in words.
    static let maxTitleWords = 9
    /// A spoken title HANGS — silence after it before prose starts.
    static let titleEndGap: TimeInterval = 0.4
    /// Two same-identity detections closer than this are echoes — keep the first.
    static let minSameKindSpacing: TimeInterval = 45
    /// Numbered/title headings closer than this to the PREVIOUS accepted one
    /// are prose artifacts (a counting scene, a list) — chapters are minutes.
    static let minChapterSpacing: TimeInterval = 120
    /// Below 2 detections there is no chaptering; above 400 something is wrong.
    static let minDetections = 2
    static let maxDetections = 400
    /// Bare-number style needs a stronger quorum than keyword style.
    static let minBareNumberQuorum = 3
    /// Title-only style is the weakest signal: it needs this many candidates
    /// AND most of the book's biggest silences to look title-shaped.
    static let minTitleOnlyQuorum = 5
    static let titleOnlyDominance = 0.6
    /// Duration priors (validated against m4b-tool's 5–15 min forced-cut
    /// heuristic, relaxed for gift-books with short chapters).
    static let minMedianChapterSeconds: TimeInterval = 240
    static let maxChaptersPerSecond = 1.0 / 120.0
    /// An implicit "Opening" chapter is prepended when the first detected
    /// heading starts later than this (title/credits announcement).
    static let openingThreshold: TimeInterval = 30

    // MARK: - Model

    /// One candidate heading, before the style vote.
    struct Heading: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case chapter(Int)          // "Chapter 7" / "Hoofdstuk 7"
            case part(Int)             // "Part 2" / "Book 2" / "Deel 2"
            case standalone(String)    // Prologue / Epilogue / …
            case bareNumber(Int)       // "Seven." (no keyword)
            case titleOnly             // a short hanging utterance, no number
        }
        let kind: Kind
        /// Global (whole-book) start second — the heading word's start.
        let start: TimeInterval
        /// Spoken title sentence, when confidently found (for `.titleOnly`
        /// this IS the label).
        let title: String?
        /// Silence before the heading (file starts report a large sentinel).
        let gapBefore: TimeInterval

        init(kind: Kind, start: TimeInterval, title: String?, gapBefore: TimeInterval = 999) {
            self.kind = kind
            self.start = start
            self.title = title
            self.gapBefore = gapBefore
        }
    }

    // MARK: - Detection

    /// Detect chapters across a whole book. `fileWords` = one word-timing array
    /// per book file (FILE-LOCAL times, the sidecars); `fileStartTimes` maps each
    /// file to its global origin. Returns a full-coverage chapter list, or nil
    /// when no style cleared its gates (caller keeps existing chapters).
    static func detect(fileWords: [[WordTiming]],
                       fileStartTimes: [TimeInterval],
                       bookDuration: TimeInterval) -> [AudiobookChapter]? {
        var all: [Heading] = []
        var unmatched: [TimeInterval] = []   // big-gap sites with NO heading (negative evidence)
        for (fileIndex, words) in fileWords.enumerated() {
            let origin = fileIndex < fileStartTimes.count ? fileStartTimes[fileIndex] : 0
            let h = harvest(in: words, globalOrigin: origin)
            all.append(contentsOf: h.headings)
            unmatched.append(contentsOf: h.unmatchedGaps)
        }
        all.sort { $0.start < $1.start }

        guard let chosen = vote(all, unmatchedGaps: unmatched, fileStartTimes: fileStartTimes,
                                bookDuration: bookDuration)
        else { return nil }
        return assemble(withBookSeparators(chosen), bookDuration: bookDuration)
    }

    /// A multi-work import (a trilogy in one audiobook) reads shuffled without
    /// context: detected numbers legitimately RESTART where the next work
    /// begins. Insert a "Book N" separator entry at each numbered RESET
    /// (Ch n → Ch m, m ≤ n) so the restarts explain themselves — unless a real
    /// part/section heading already marks that spot. N counts detected
    /// segments, so with partial recall it can undercount the true book index
    /// — still strictly clearer than an unexplained restart.
    static func withBookSeparators(_ headings: [Heading]) -> [Heading] {
        var out: [Heading] = []
        var prevNumber: Int?
        var segment = 1
        for h in headings {
            var number: Int?
            if case .chapter(let n) = h.kind { number = n }
            if case .bareNumber(let n) = h.kind { number = n }
            if let n = number {
                if let prev = prevNumber, n <= prev {
                    let marked = out.contains {
                        if case .part = $0.kind { return abs($0.start - h.start) < 60 }
                        if case .standalone = $0.kind { return abs($0.start - h.start) < 60 }
                        return false
                    }
                    if !marked {
                        segment += 1
                        out.append(Heading(kind: .standalone("Book \(segment)"),
                                           start: h.start, title: nil, gapBefore: h.gapBefore))
                    }
                }
                prevNumber = n
            }
            out.append(h)
        }
        return out
    }

    /// The style vote. Keyword chapters are trusted at quorum 2; bare numbers
    /// need 3 + spacing; title-only needs 5 + dominance of the book's biggest
    /// silences. Part/standalone keywords ride along with whichever wins.
    static func vote(_ all: [Heading], unmatchedGaps: [TimeInterval],
                     fileStartTimes: [TimeInterval] = [],
                     bookDuration: TimeInterval) -> [Heading]? {
        let deduped = dropEchoes(all)
        let structural = deduped.filter {
            if case .part = $0.kind { return true }
            if case .standalone = $0.kind { return true }
            return false
        }

        // Style 1 — keyword chapters ("Chapter N"): the production standard.
        let keyword = deduped.filter { if case .chapter = $0.kind { return true }; return false }
        if keyword.count >= minDetections, numbersAreSane(keyword, fileStartTimes: fileStartTimes) {
            return finalize(keyword + structural, bookDuration: bookDuration)
        }

        // Style 2 — bare numbers ("Seven."): manuscripts with numbered-only
        // headings. Stronger quorum, same ascending sanity.
        let bare = spaced(deduped.filter {
            if case .bareNumber = $0.kind { return true }; return false
        })
        if bare.count >= minBareNumberQuorum, numbersAreSane(bare, fileStartTimes: fileStartTimes) {
            return finalize(bare + structural, bookDuration: bookDuration)
        }

        // Style 3 — title-only ("A Lopsided Arms Race."): the weakest signal.
        // Quorum + the book's own biggest silences must be title-shaped —
        // a sting-heavy production (big gaps into flowing prose) fails here.
        let titled = spaced(deduped.filter {
            if case .titleOnly = $0.kind { return $0.title != nil }; return false
        })
        if titled.count >= minTitleOnlyQuorum,
           titleShapeDominates(candidates: deduped, unmatchedGaps: unmatchedGaps,
                               bookDuration: bookDuration) {
            return finalize(titled + structural, bookDuration: bookDuration)
        }

        // No chapter style — parts/sections alone still beat nothing when
        // there are at least two of them (they ARE announced structure).
        if structural.count >= minDetections {
            return finalize(structural, bookDuration: bookDuration)
        }
        return nil
    }

    /// Shared tail gates: count bounds + duration priors. nil vetoes the style.
    private static func finalize(_ chosen: [Heading], bookDuration: TimeInterval) -> [Heading]? {
        let sorted = chosen.sorted { $0.start < $1.start }
        guard sorted.count >= minDetections, sorted.count <= maxDetections else { return nil }
        if bookDuration > 0,
           Double(sorted.count) > max(3, bookDuration * maxChaptersPerSecond) { return nil }
        // Median resulting chapter length must be plausible (minutes, not
        // seconds) — kills counting scenes / list readings wholesale.
        if sorted.count >= 3 {
            var lengths: [TimeInterval] = []
            for (a, b) in zip(sorted, sorted.dropFirst()) { lengths.append(b.start - a.start) }
            let median = lengths.sorted()[lengths.count / 2]
            guard median >= minMedianChapterSeconds else { return nil }
        }
        return sorted
    }

    /// Enforce `minChapterSpacing` between accepted same-style headings —
    /// keeps the first of any implausibly tight run (counting scenes).
    private static func spaced(_ headings: [Heading]) -> [Heading] {
        var kept: [Heading] = []
        for h in headings.sorted(by: { $0.start < $1.start }) {
            if let last = kept.last, h.start - last.start < minChapterSpacing { continue }
            kept.append(h)
        }
        return kept
    }

    /// Title-only corroboration: of the book's BIGGEST silences (matched OR
    /// unmatched, top-K by the duration prior), at least `titleOnlyDominance`
    /// must have produced a heading. A sting-heavy production has its biggest
    /// gaps flow into ordinary prose (unmatched) and fails here. No absolute
    /// thresholds — adapts to the book's own production style.
    static func titleShapeDominates(candidates: [Heading], unmatchedGaps: [TimeInterval],
                                    bookDuration: TimeInterval) -> Bool {
        var sites: [(gap: TimeInterval, matched: Bool)] =
            candidates.filter { $0.gapBefore < 999 }.map { ($0.gapBefore, true) }
        sites.append(contentsOf: unmatchedGaps.map { ($0, false) })
        let k = max(minTitleOnlyQuorum, Int(bookDuration * maxChaptersPerSecond / 2))
        let topSites = sites.sorted { $0.gap > $1.gap }.prefix(k)
        guard !topSites.isEmpty else { return false }
        let matched = topSites.filter(\.matched).count
        return Double(matched) / Double(topSites.count) >= titleOnlyDominance
    }

    // MARK: - Candidate harvest

    struct Harvest {
        var headings: [Heading]
        /// Big-gap (≥2 s) sites where NOTHING matched — negative evidence for
        /// the title-only dominance check (a sting-heavy book is mostly these).
        var unmatchedGaps: [TimeInterval]
    }

    /// Scan one file's words for candidate headings of EVERY style (global
    /// times out). A candidate anchors at the file's first word or any word
    /// after a ≥`gapBefore` silence.
    static func harvest(in words: [WordTiming], globalOrigin: TimeInterval) -> Harvest {
        var found: [Heading] = []
        var unmatched: [TimeInterval] = []
        var i = 0
        while i < words.count {
            let gap = i == 0 ? 999 : (words[i].start - words[i - 1].end)
            if gap >= gapBefore || i == 0 {
                if let (heading, consumed) = matchHeading(words, at: i, globalOrigin: globalOrigin,
                                                          gap: gap) {
                    found.append(heading)
                    i += consumed
                    continue
                }
                if gap >= 2.0, i > 0 { unmatched.append(gap) }
            }
            i += 1
        }
        return Harvest(headings: found, unmatchedGaps: unmatched)
    }

    /// Diagnostic/back-compat view of `harvest` (probe + tests).
    static func headings(in words: [WordTiming], globalOrigin: TimeInterval) -> [Heading] {
        harvest(in: words, globalOrigin: globalOrigin).headings
    }

    // MARK: - Heading grammar

    /// Try to read a heading starting at `words[i]`. Returns the heading and
    /// how many words it consumed (heading + title), or nil.
    private static func matchHeading(_ words: [WordTiming], at i: Int,
                                     globalOrigin: TimeInterval,
                                     gap: TimeInterval) -> (Heading, Int)? {
        let first = core(words[i].word)
        let start = globalOrigin + words[i].start

        // "Chapter <n> [of <book title>.]" / "Hoofdstuk <n>" / "Part <n>" …
        if let kindWord = keywordKind(first) {
            guard let (value, numberEnd) = parseNumber(words, from: i + 1) else { return nil }
            // LibriVox format: "Chapter 4 of Pride and Prejudice." — the
            // number flows into "of <title>"; consume through that sentence.
            var end = numberEnd
            if numberEnd + 1 < words.count, core(words[numberEnd + 1].word) == "of",
               !Paragrapher.endsSentence(words[numberEnd].word) {
                var j = numberEnd + 1
                while j < words.count, j - numberEnd <= maxTitleWords {
                    if Paragrapher.endsSentence(words[j].word) { end = j; break }
                    j += 1
                }
                guard end > numberEnd else { return nil }
            } else {
                guard terminatesCleanly(words, lastIndex: numberEnd) else { return nil }
            }
            let (title, consumedTitle) = end == numberEnd
                ? titleAfter(words, index: numberEnd + 1)
                : (nil, 0)   // LibriVox headers carry the BOOK title, not a chapter title
            let kind: Heading.Kind = kindWord == .chapter ? .chapter(value) : .part(value)
            return (Heading(kind: kind, start: start, title: title, gapBefore: gap),
                    (end - i + 1) + consumedTitle)
        }

        // Standalone section word ("Prologue.", "Epilogue.", …) — must itself
        // terminate cleanly, so prose like "the introduction of…" can't match.
        if standaloneSections.contains(first) {
            guard terminatesCleanly(words, lastIndex: i) else { return nil }
            let (title, consumedTitle) = titleAfter(words, index: i + 1)
            return (Heading(kind: .standalone(first.capitalized), start: start,
                            title: title, gapBefore: gap), 1 + consumedTitle)
        }

        // Bare number ("Seven." / "23." / "Twenty-three: …") — manuscripts
        // whose headings are numbered without the word "chapter". The number
        // must terminate cleanly, so "One time my co-worker…" can't match.
        if let (value, numberEnd) = parseNumber(words, from: i),
           terminatesCleanly(words, lastIndex: numberEnd) {
            let (title, consumedTitle) = titleAfter(words, index: numberEnd + 1)
            return (Heading(kind: .bareNumber(value), start: start, title: title,
                            gapBefore: gap), (numberEnd - i + 1) + consumedTitle)
        }

        // Title-only ("A Lopsided Arms Race.") — a short utterance that ends
        // with sentence punctuation AND hangs. Only meaningful behind a real
        // silence; the vote demands quorum + dominance before trusting these.
        if gap >= 2.0, let (utterance, consumed) = shortHangingUtterance(words, from: i) {
            return (Heading(kind: .titleOnly, start: start, title: utterance,
                            gapBefore: gap), consumed)
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
        if Paragrapher.endsSentence(words[lastIndex].word) { return true }
        guard lastIndex + 1 < words.count else { return true }   // end of transcript
        return (words[lastIndex + 1].start - words[lastIndex].end) >= numberEndGap
    }

    /// A short sentence right after the heading = the spoken chapter title
    /// ("Chapter Seven. <beat> The Boy Who Lived."). Only accepted when it ends
    /// with sentence punctuation within `maxTitleWords` AND hangs — a beat of
    /// silence follows it, the way narrators read titles. A short opening prose
    /// sentence flows straight on and is rejected.
    private static func titleAfter(_ words: [WordTiming], index: Int) -> (String?, Int) {
        guard let (utterance, consumed) = shortHangingUtterance(words, from: index),
              Int(utterance) == nil,
              spelledValue(utterance.split(separator: " ").map { core(String($0)) }) == nil
        else { return (nil, 0) }   // a bare number is the NEXT heading, not a title
        return (utterance, consumed)
    }

    /// A ≤`maxTitleWords` run from `from` that ends with sentence punctuation
    /// and HANGS (≥`titleEndGap` silence after, or transcript end). Returns the
    /// cleaned text + words consumed.
    private static func shortHangingUtterance(_ words: [WordTiming],
                                              from: Int) -> (String, Int)? {
        var collected: [String] = []
        var i = from
        while i < words.count, collected.count < maxTitleWords {
            collected.append(words[i].word)
            if Paragrapher.endsSentence(words[i].word) {
                let hangs = i + 1 >= words.count
                    || (words[i + 1].start - words[i].end) >= titleEndGap
                let text = strippedSentence(collected)
                guard hangs, !text.isEmpty else { return nil }
                return (text, collected.count)
            }
            i += 1
        }
        return nil
    }

    // MARK: - Sanity

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

    /// Numbered chapters should mostly ascend. A reset to 1 after a part break
    /// is fine, and so is any reset ACROSS A FILE BOUNDARY — a multi-file
    /// import can be several works (a trilogy), each numbering from 1. Too
    /// many real inversions = the matches are prose FPs → bail.
    static func numbersAreSane(_ headings: [Heading],
                               fileStartTimes: [TimeInterval] = []) -> Bool {
        var numbered: [(n: Int, start: TimeInterval)] = []
        for h in headings {
            if case .chapter(let n) = h.kind { numbered.append((n, h.start)) }
            if case .bareNumber(let n) = h.kind { numbered.append((n, h.start)) }
        }
        guard numbered.count >= 3 else { return true }   // too few to judge
        var inversions = 0
        for (prev, next) in zip(numbered, numbered.dropFirst())
        where next.n <= prev.n && next.n != 1 {
            let crossesFile = fileStartTimes.contains { $0 > prev.start && $0 <= next.start }
            if !crossesFile { inversions += 1 }
        }
        return Double(inversions) / Double(numbered.count) <= 0.3
    }

    // MARK: - Assembly

    /// Turn the winning headings into a full-coverage chapter list.
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
    /// Bare-number headings read as chapters; title-only headings ARE their title.
    static func label(for h: Heading) -> String {
        let base: String
        switch h.kind {
        case .chapter(let n), .bareNumber(let n): base = "Chapter \(n)"
        case .part(let n): base = "Part \(n)"
        case .standalone(let s): base = s
        case .titleOnly: return h.title ?? "Chapter"
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

        // Spelled numbers: greedily extend while tokens still parse. An
        // ADJACENT DUPLICATE of the same word ("ten Ten.") is a chunk-seam
        // echo (pre-fix sidecars) — consume it without re-adding the value,
        // or "ten ten" would sum to twenty.
        var best: (Int, Int)?
        var tokens: [String] = []
        for i in from..<min(from + 4, words.count) {
            let c = core(words[i].word)
            if c != tokens.last { tokens.append(c) }
            if let v = spelledValue(tokens) { best = (v, i) }
            // Stop extending past a sentence end — "Seven. The" never joins.
            if Paragrapher.endsSentence(words[i].word) { break }
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
