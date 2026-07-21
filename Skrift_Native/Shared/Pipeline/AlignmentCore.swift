import Foundation

/// Transcript ↔ book-text word alignment — puts timestamps (from ASR transcript words)
/// onto book words that never had any, tolerating mishears, upstream ASR seam-gluing
/// (#683-class), narrator skips/additions, and self-detecting the wrong book entirely.
/// Pure text alignment, no ML, no I/O. Pipeline: unique n-gram anchors → longest
/// increasing subsequence (patience-diff trick) for monotonicity → a small banded DP in
/// each gap between surviving anchors (never a global N×M matrix — see `align`).
///
/// In-repo ancestor / consolidation note: `Karaoke.wordTimes` (this directory) solves
/// the miniature displayed-word case, and `RunFile.anchorDrift`
/// (SkriftDesktop/Features/Shell/RunFile.swift) does unique-SINGLE-WORD anchor diffing.
/// This is the generalization (n-gram anchors + real DP, not a scaled fraction) — the
/// consolidation point, not a fourth copy. Left as siblings for now (Tuur-approved
/// duplication, BASE.md); the conductor folds them together later.
enum AlignmentCore {

    // MARK: - Wire types (pinned names — LANES-2026-07-21B/BASE.md cross-lane seam)

    /// One ASR transcript word with its timing (seconds).
    struct Word: Equatable, Sendable {
        var text: String
        var start: Double
        var end: Double
    }

    /// One block of book text with NO timing — `sourceFile` is the book's own internal
    /// source (e.g. an ePub spine XHTML path), structurally mirroring `EPubBlock` on
    /// purpose. AlignmentCore never imports the ePub types directly (BASE.md seam); the
    /// conductor bridges `EPubBlock` → `AlignmentCore.Block` in the harness.
    struct Block: Equatable, Sendable {
        var text: String
        var sourceFile: String
    }

    /// Thresholds + knobs, all overridable — the conductor tunes these against the real
    /// pairs (probe: right book ≈98% coverage / 96% monotonic anchors; wrong book ≈40
    /// non-monotonic anchors, ~150:1 separation from a real pair).
    struct Config: Sendable {
        /// n-gram length for anchor candidates. 4 worked on the real probe pair.
        var anchorN: Int = 4
        /// Untimed book-word runs at most this long, bounded by timed neighbors on both
        /// sides, get linearly interpolated; longer runs stay untimed.
        var maxInterpolateWords: Int = 8
        /// Safety cap on a single gap's DP (transcriptGapLen × bookGapLen). A gap above
        /// this is left fully unmatched rather than run — this is also what makes a
        /// wrong-book attach cheap: zero surviving anchors ⇒ the whole book is one huge
        /// gap ⇒ skipped, not a full N×M attempt.
        var maxGapProduct: Int = 250_000
        /// How many of the largest unmatched spans to report, each side.
        var topSpanCount: Int = 10
        /// `aligned` requires coverageBook ≥ this AND monotonicFraction ≥ the other.
        var alignedCoverageThreshold: Double = 0.35
        var alignedMonotonicThreshold: Double = 0.8
        /// `rejected` if coverageBook < this OR monotonicFraction < the other.
        var rejectedCoverageThreshold: Double = 0.05
        var rejectedMonotonicThreshold: Double = 0.3

        init(anchorN: Int = 4, maxInterpolateWords: Int = 8, maxGapProduct: Int = 250_000,
             topSpanCount: Int = 10, alignedCoverageThreshold: Double = 0.35,
             alignedMonotonicThreshold: Double = 0.8, rejectedCoverageThreshold: Double = 0.05,
             rejectedMonotonicThreshold: Double = 0.3) {
            self.anchorN = anchorN
            self.maxInterpolateWords = maxInterpolateWords
            self.maxGapProduct = maxGapProduct
            self.topSpanCount = topSpanCount
            self.alignedCoverageThreshold = alignedCoverageThreshold
            self.alignedMonotonicThreshold = alignedMonotonicThreshold
            self.rejectedCoverageThreshold = rejectedCoverageThreshold
            self.rejectedMonotonicThreshold = rejectedMonotonicThreshold
        }
    }

    enum Verdict: String, Sendable, Equatable {
        case aligned, partial, rejected
    }

    /// `AlignmentCore.align`'s output. Nested span/range types are this lane's own
    /// naming (not pinned by BASE.md — only `Result`/`Verdict` are).
    struct Result: Sendable {
        /// A contiguous run of book words (within ONE `sourceFile`) that got a time,
        /// directly matched or interpolated.
        struct MatchedRange: Equatable, Sendable {
            var sourceFile: String
            /// Local word index within the block, inclusive.
            var bookWordStart: Int
            /// Local word index within the block, exclusive.
            var bookWordEnd: Int
            var start: Double
            var end: Double
        }

        /// An unmatched run of TRANSCRIPT words (e.g. narrator credits with no book
        /// counterpart). Indices are into the flattened `transcript` array passed to
        /// `align`.
        struct TranscriptSpan: Equatable, Sendable {
            var wordStart: Int
            var wordEnd: Int
            var preview: String
        }

        /// An untimed run of BOOK words (e.g. a narrator skip, front matter, footnotes).
        struct BookSpan: Equatable, Sendable {
            var sourceFile: String
            var wordStart: Int
            var wordEnd: Int
            var preview: String
        }

        /// Fraction of book words that ended up with a time (direct match or
        /// interpolated).
        var coverageBook: Double
        /// Fraction of transcript words that matched some book word (excludes inserts).
        var coverageTranscript: Double
        /// Unique n-gram candidates found (both-sides-unique), BEFORE the LIS filter.
        var anchorCount: Int
        /// Fraction of `anchorCount` that survived the LIS monotonicity filter.
        var monotonicFraction: Double
        var matchedRanges: [MatchedRange]
        /// The largest unmatched spans, each side, longest first (deterministic
        /// tie-break: earlier start wins), capped at `Config.topSpanCount`.
        var largestUnmatchedTranscriptSpans: [TranscriptSpan]
        var largestUnmatchedBookSpans: [BookSpan]
        var verdict: Verdict
    }

    // MARK: - Entry point

    /// Align `transcript` (ASR words WITH timestamps) onto `book` (text blocks WITHOUT).
    /// Deterministic: identical inputs always produce an identical `Result`.
    static func align(transcript: [Word], book: [Block], config: Config = .init()) -> Result {
        let bookWords = flattenBook(book)
        let T = transcript.count
        let B = bookWords.count
        let tN = transcript.map { normalizeKey($0.text) }
        let bN = bookWords.map { normalizeKey($0.text) }
        let n = max(1, config.anchorN)

        let candidates = findAnchorCandidates(tN: tN, bN: bN, n: n)
        let survivorIdx = longestIncreasingSubsequence(candidates)
        let anchors = survivorIdx.map { candidates[$0] }
        let anchorCount = candidates.count
        let monotonicFraction = anchorCount > 0 ? Double(anchors.count) / Double(anchorCount) : 0

        var bookTime = [WordSpanTime?](repeating: nil, count: B)
        var transcriptMatched = [Bool](repeating: false, count: T)

        if !anchors.isEmpty {
            var prevEndT = 0, prevEndB = 0
            for (t, b) in anchors {
                let skip = max(0, max(prevEndT - t, prevEndB - b))
                let effStartT = t + skip
                let effStartB = b + skip
                runGapDP(transcript: transcript, tN: tN, tRange: prevEndT..<effStartT,
                         bookWords: bookWords, bN: bN, bRange: prevEndB..<effStartB,
                         bookTime: &bookTime, transcriptMatched: &transcriptMatched, config: config)
                if skip < n {
                    for k in skip..<n {
                        let ti = t + k, bj = b + k
                        bookTime[bj] = WordSpanTime(start: transcript[ti].start, end: transcript[ti].end)
                        transcriptMatched[ti] = true
                    }
                }
                prevEndT = max(prevEndT, t + n)
                prevEndB = max(prevEndB, b + n)
            }
            runGapDP(transcript: transcript, tN: tN, tRange: prevEndT..<T,
                     bookWords: bookWords, bN: bN, bRange: prevEndB..<B,
                     bookTime: &bookTime, transcriptMatched: &transcriptMatched, config: config)
        }

        interpolateHoles(&bookTime, maxInterpolateWords: config.maxInterpolateWords)

        let timedBookCount = bookTime.reduce(0) { $0 + ($1 != nil ? 1 : 0) }
        let matchedTranscriptCount = transcriptMatched.reduce(0) { $0 + ($1 ? 1 : 0) }
        let coverageBook = B > 0 ? Double(timedBookCount) / Double(B) : 0
        let coverageTranscript = T > 0 ? Double(matchedTranscriptCount) / Double(T) : 0

        let matchedRuns = blockScopedRuns(bookWords) { bookTime[$0] != nil }
        let matchedRanges = matchedRuns.map { run in
            Result.MatchedRange(sourceFile: run.sourceFile, bookWordStart: run.localStart,
                                 bookWordEnd: run.localEnd, start: bookTime[run.globalStart]!.start,
                                 end: bookTime[run.globalEnd - 1]!.end)
        }

        let unmatchedBookRuns = blockScopedRuns(bookWords) { bookTime[$0] == nil }
        let bookSpans = unmatchedBookRuns
            .sorted { lengthDescThenEarlier($0.globalStart, $0.globalEnd, $1.globalStart, $1.globalEnd) }
            .prefix(config.topSpanCount)
            .map { run in
                Result.BookSpan(sourceFile: run.sourceFile, wordStart: run.localStart, wordEnd: run.localEnd,
                                 preview: preview(bookWords[run.globalStart..<run.globalEnd].map(\.text)))
            }

        let transcriptSpans = transcriptRuns(transcriptMatched)
            .sorted { lengthDescThenEarlier($0.start, $0.end, $1.start, $1.end) }
            .prefix(config.topSpanCount)
            .map { run in
                Result.TranscriptSpan(wordStart: run.start, wordEnd: run.end,
                                       preview: preview(transcript[run.start..<run.end].map(\.text)))
            }

        let verdict: Verdict
        if coverageBook >= config.alignedCoverageThreshold && monotonicFraction >= config.alignedMonotonicThreshold {
            verdict = .aligned
        } else if coverageBook < config.rejectedCoverageThreshold || monotonicFraction < config.rejectedMonotonicThreshold {
            verdict = .rejected
        } else {
            verdict = .partial
        }

        return Result(
            coverageBook: coverageBook,
            coverageTranscript: coverageTranscript,
            anchorCount: anchorCount,
            monotonicFraction: monotonicFraction,
            matchedRanges: matchedRanges,
            largestUnmatchedTranscriptSpans: Array(transcriptSpans),
            largestUnmatchedBookSpans: Array(bookSpans),
            verdict: verdict
        )
    }

    // MARK: - Book flattening

    private struct BookWordRef {
        var sourceFile: String
        var localIndex: Int
        var text: String
    }

    private static func flattenBook(_ book: [Block]) -> [BookWordRef] {
        var words: [BookWordRef] = []
        for blk in book {
            let toks = tokenize(blk.text)
            for (idx, tok) in toks.enumerated() {
                words.append(BookWordRef(sourceFile: blk.sourceFile, localIndex: idx, text: tok))
            }
        }
        return words
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    // MARK: - Match-key normalization (aligner-internal; display text untouched)

    /// Casefold + strip non-alphanumerics + EN/NL number-word canonicalization, for
    /// MATCH KEYS ONLY (Tuur locked aligner-internal over wiring FluidAudio's
    /// TextNormalizer, backlog 📖 item 2). Never touches display text.
    static func normalizeKey(_ raw: String) -> String {
        let lower = raw.lowercased()
        if let n = canonicalizeNumberWord(lower) { return n }
        return String(lower.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// A single (possibly hyphenated) token's EN/NL cardinal/ordinal value as a digit
    /// string ("negentien"→"19", "twenty-three"→"23"), or nil if it isn't a number word.
    /// DELIBERATE DUPLICATION (BASE.md-noted) of the unit/teen/ten maps + Dutch-glued
    /// suffix logic in `ChapterDetector.parseNumber`/`spelledValue`/`dutchGlued`
    /// (SkriftMobile/Services/Audiobooks/ChapterDetector.swift) — that version ALSO does
    /// multi-TOKEN sum parsing for chapter headings ("one hundred and four"); this is
    /// only the single-token subset the aligner needs (multi-token number phrases like
    /// "twenty twelve" → "2012" are resolved by the glue-tolerance mechanism below, not
    /// a second number pass — see `gluesMatch`). Conductor consolidates later.
    private static func canonicalizeNumberWord(_ lower: String) -> String? {
        let core = lower.replacingOccurrences(of: "ë", with: "e")
            .trimmingCharacters(in: .alphanumerics.inverted)
        guard !core.isEmpty else { return nil }
        let linkingWords: Set<String> = ["and", "en", "the", "de", "het"]
        let rawParts: [String] = core.split(separator: "-").map(String.init)
        let parts: [String] = rawParts.filter { !linkingWords.contains($0) }
        guard !parts.isEmpty else { return nil }
        var total = 0
        for p in parts {
            if let u = units[p] { total += u }
            else if let t = teens[p] { total += t }
            else if let t = tens[p] { total += t }
            else if p == "hundred" || p == "honderd" { total = max(total, 1) * 100 }
            else if let g = dutchGlued(p) { total += g }
            else { return nil }
        }
        return total > 0 ? String(total) : nil
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

    /// Dutch glued compound: "<unit>en<tens>" ("drieentwintig" → 23). Ported from
    /// `ChapterDetector.dutchGlued` (same source file as the maps above).
    private static func dutchGlued(_ token: String) -> Int? {
        for (tensWord, tensValue) in tens where token.hasSuffix("en" + tensWord) {
            let unitPart = String(token.dropLast(tensWord.count + 2))
            if let u = units[unitPart] { return u + tensValue }
        }
        return nil
    }

    // MARK: - Anchors (unique n-grams, indexed — no linear scan per token)

    private static func ngramKey(_ norm: [String], _ start: Int, _ n: Int) -> String {
        var key = norm[start]
        if n > 1 {
            for k in 1..<n {
                key += "\u{1}"
                key += norm[start + k]
            }
        }
        return key
    }

    private static func windowHasEmpty(_ norm: [String], _ start: Int, _ n: Int) -> Bool {
        for k in 0..<n where norm[start + k].isEmpty { return true }
        return false
    }

    /// Candidates sorted by transcript index ascending (scan order) — an n-gram key that
    /// occurs EXACTLY ONCE in both the transcript and the book.
    private static func findAnchorCandidates(tN: [String], bN: [String], n: Int) -> [(t: Int, b: Int)] {
        let T = tN.count, B = bN.count
        guard T >= n, B >= n else { return [] }

        var bookKeyCount: [String: Int] = [:]
        var bookKeyFirstIndex: [String: Int] = [:]
        for j in 0...(B - n) {
            if windowHasEmpty(bN, j, n) { continue }
            let key = ngramKey(bN, j, n)
            let c = (bookKeyCount[key] ?? 0) + 1
            bookKeyCount[key] = c
            if c == 1 { bookKeyFirstIndex[key] = j }
        }

        var transcriptKeyCount: [String: Int] = [:]
        for i in 0...(T - n) {
            if windowHasEmpty(tN, i, n) { continue }
            transcriptKeyCount[ngramKey(tN, i, n), default: 0] += 1
        }

        var candidates: [(t: Int, b: Int)] = []
        for i in 0...(T - n) {
            if windowHasEmpty(tN, i, n) { continue }
            let key = ngramKey(tN, i, n)
            guard transcriptKeyCount[key] == 1, bookKeyCount[key] == 1,
                  let bIdx = bookKeyFirstIndex[key] else { continue }
            candidates.append((t: i, b: bIdx))
        }
        return candidates
    }

    /// O(n log n) patience/binary-search LIS on `.b`, over a `.t`-sorted input whose `.b`
    /// values are pairwise distinct (guaranteed by `findAnchorCandidates`). Returns
    /// indices INTO `candidates`, in surviving order.
    private static func longestIncreasingSubsequence(_ candidates: [(t: Int, b: Int)]) -> [Int] {
        guard !candidates.isEmpty else { return [] }
        var tails: [Int] = []
        var predecessor = [Int](repeating: -1, count: candidates.count)
        for i in 0..<candidates.count {
            let b = candidates[i].b
            var lo = 0, hi = tails.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if candidates[tails[mid]].b < b { lo = mid + 1 } else { hi = mid }
            }
            if lo > 0 { predecessor[i] = tails[lo - 1] }
            if lo == tails.count { tails.append(i) } else { tails[lo] = i }
        }
        guard var cur = tails.last else { return [] }
        var result: [Int] = []
        while true {
            result.append(cur)
            let p = predecessor[cur]
            if p == -1 { break }
            cur = p
        }
        return result.reversed()
    }

    // MARK: - Glue tolerance (#683 seam-gluing class + multi-token number merge)

    /// True if `single` (already a normalized key) equals the normalized concatenation
    /// of `first`+`second`, tolerating ONE character eaten at the seam either direction
    /// (the `works.eep` ← "works."+"keep" class, K eaten). Also how "twenty"+"twelve"
    /// resolves against book "2012" (both sides normalize to digit strings first).
    private static func gluesMatch(_ single: String, _ first: String, _ second: String) -> Bool {
        guard !single.isEmpty, !first.isEmpty, !second.isEmpty else { return false }
        let concat = first + second
        if single == concat { return true }
        let dropFirstTrailing = String(first.dropLast()) + second
        let dropSecondLeading = first + String(second.dropFirst())
        return single == dropFirstTrailing || single == dropSecondLeading
    }

    // MARK: - Banded DP (per gap between surviving anchors — never a global N×M matrix)

    private struct WordSpanTime {
        var start: Double
        var end: Double
    }

    private enum DPOp: UInt8 {
        case none, matchSub, insert, delete, glueT2B1, glueB2T1
    }

    /// Word-level edit-distance DP restricted to ONE gap (`tRange` × `bRange`). Skips
    /// entirely (leaving the default unmatched/untimed state) when either side is empty
    /// or the gap exceeds `Config.maxGapProduct` — the banding: total DP work sums to
    /// roughly the anchor count × a small constant, not transcript-length ×
    /// book-length.
    private static func runGapDP(
        transcript: [Word], tN: [String], tRange: Range<Int>,
        bookWords: [BookWordRef], bN: [String], bRange: Range<Int>,
        bookTime: inout [WordSpanTime?], transcriptMatched: inout [Bool],
        config: Config
    ) {
        let Lt = tRange.count, Lb = bRange.count
        guard Lt > 0, Lb > 0 else { return }
        guard Lt * Lb <= config.maxGapProduct else { return }

        let cols = Lb + 1
        var cost = [Int](repeating: 0, count: (Lt + 1) * cols)
        var op = [DPOp](repeating: .none, count: (Lt + 1) * cols)

        for i in 1...Lt { cost[i * cols] = i; op[i * cols] = .insert }
        for j in 1...Lb { cost[j] = j; op[j] = .delete }

        for i in 1...Lt {
            let ti = tRange.lowerBound + i - 1
            for j in 1...Lb {
                let bj = bRange.lowerBound + j - 1
                var bestCost = Int.max
                var bestOp = DPOp.none

                let subCost = (!tN[ti].isEmpty && tN[ti] == bN[bj]) ? 0 : 1
                let cDiag = cost[(i - 1) * cols + (j - 1)] + subCost
                if cDiag < bestCost { bestCost = cDiag; bestOp = .matchSub }

                let cUp = cost[(i - 1) * cols + j] + 1
                if cUp < bestCost { bestCost = cUp; bestOp = .insert }

                let cLeft = cost[i * cols + (j - 1)] + 1
                if cLeft < bestCost { bestCost = cLeft; bestOp = .delete }

                if i >= 2, gluesMatch(bN[bj], tN[ti - 1], tN[ti]) {
                    let cGlueT = cost[(i - 2) * cols + (j - 1)]
                    if cGlueT < bestCost { bestCost = cGlueT; bestOp = .glueT2B1 }
                }
                if j >= 2, gluesMatch(tN[ti], bN[bj - 1], bN[bj]) {
                    let cGlueB = cost[i * cols + (j - 2)]
                    if cGlueB < bestCost { bestCost = cGlueB; bestOp = .glueB2T1 }
                }

                cost[i * cols + j] = bestCost
                op[i * cols + j] = bestOp
            }
        }

        var i = Lt, j = Lb
        while i > 0 || j > 0 {
            switch op[i * cols + j] {
            case .matchSub:
                let ti = tRange.lowerBound + i - 1
                let bj = bRange.lowerBound + j - 1
                bookTime[bj] = WordSpanTime(start: transcript[ti].start, end: transcript[ti].end)
                transcriptMatched[ti] = true
                i -= 1; j -= 1
            case .insert:
                i -= 1
            case .delete:
                j -= 1
            case .glueT2B1:
                let ti2 = tRange.lowerBound + i - 1
                let ti1 = tRange.lowerBound + i - 2
                let bj = bRange.lowerBound + j - 1
                bookTime[bj] = WordSpanTime(start: transcript[ti1].start, end: transcript[ti2].end)
                transcriptMatched[ti1] = true
                transcriptMatched[ti2] = true
                i -= 2; j -= 1
            case .glueB2T1:
                let ti = tRange.lowerBound + i - 1
                let bj2 = bRange.lowerBound + j - 1
                let bj1 = bRange.lowerBound + j - 2
                let span = WordSpanTime(start: transcript[ti].start, end: transcript[ti].end)
                bookTime[bj1] = span
                bookTime[bj2] = span
                transcriptMatched[ti] = true
                i -= 1; j -= 2
            case .none:
                if i > 0 { i -= 1 } else if j > 0 { j -= 1 }
            }
        }
    }

    // MARK: - Interpolation

    /// Fills nil runs bounded by timed neighbors on both sides, length ≤
    /// `maxInterpolateWords`, with a linear split between the neighbors' times. Longer
    /// runs, and runs touching either end of the book (no bounding neighbor), stay nil.
    /// Deliberately NOT scoped per source-file — the audio timeline is continuous across
    /// ePub XHTML-file boundaries even though `MatchedRange`/`BookSpan` reporting is
    /// split per file.
    private static func interpolateHoles(_ bookTime: inout [WordSpanTime?], maxInterpolateWords: Int) {
        var i = 0
        let n = bookTime.count
        while i < n {
            if bookTime[i] != nil { i += 1; continue }
            var j = i
            while j < n, bookTime[j] == nil { j += 1 }
            let holeLen = j - i
            if i > 0, j < n, holeLen <= maxInterpolateWords,
               let left = bookTime[i - 1], let right = bookTime[j] {
                for k in 0..<holeLen {
                    let frac = Double(k + 1) / Double(holeLen + 1)
                    let t = left.end + (right.start - left.end) * frac
                    bookTime[i + k] = WordSpanTime(start: t, end: t)
                }
            }
            i = j
        }
    }

    // MARK: - Span assembly

    private static func blockScopedRuns(
        _ bookWords: [BookWordRef],
        matching predicate: (Int) -> Bool
    ) -> [(sourceFile: String, localStart: Int, localEnd: Int, globalStart: Int, globalEnd: Int)] {
        var runs: [(sourceFile: String, localStart: Int, localEnd: Int, globalStart: Int, globalEnd: Int)] = []
        var i = 0
        let n = bookWords.count
        while i < n {
            guard predicate(i) else { i += 1; continue }
            let sf = bookWords[i].sourceFile
            var j = i
            while j < n, predicate(j), bookWords[j].sourceFile == sf { j += 1 }
            runs.append((sourceFile: sf, localStart: bookWords[i].localIndex,
                         localEnd: bookWords[j - 1].localIndex + 1, globalStart: i, globalEnd: j))
            i = j
        }
        return runs
    }

    private static func transcriptRuns(_ matched: [Bool]) -> [(start: Int, end: Int)] {
        var runs: [(start: Int, end: Int)] = []
        var i = 0
        let n = matched.count
        while i < n {
            if matched[i] { i += 1; continue }
            var j = i
            while j < n, !matched[j] { j += 1 }
            runs.append((start: i, end: j))
            i = j
        }
        return runs
    }

    /// Deterministic span ordering: longest first, earlier start breaks ties. Explicit
    /// comparator (never relies on `sorted`'s stability alone for output determinism).
    private static func lengthDescThenEarlier(_ aStart: Int, _ aEnd: Int, _ bStart: Int, _ bEnd: Int) -> Bool {
        let la = aEnd - aStart, lb = bEnd - bStart
        return la != lb ? la > lb : aStart < bStart
    }

    private static func preview(_ words: [String], maxWords: Int = 8) -> String {
        let text = words.prefix(maxWords).joined(separator: " ")
        return words.count > maxWords ? text + " …" : text
    }
}
