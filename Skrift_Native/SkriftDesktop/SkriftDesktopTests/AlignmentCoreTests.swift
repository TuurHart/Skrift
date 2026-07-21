import XCTest
import Foundation

/// AlignmentCore: transcript ↔ book-text word alignment. Fixtures are original
/// text authored for this test file (NOT real book content, per BASE.md's
/// copyright rule) plus short synthetic phrases for the sharper mechanism checks
/// (number-word gluing, seam-eaten-letter gluing). Twin file — identical body,
/// see the sibling SkriftMobileTests copy; only the import header differs
/// (desktop's SkriftDesktopTests compiles Shared/Pipeline host-lessly, mobile
/// needs `@testable import SkriftMobile`).
final class AlignmentCoreTests: XCTestCase {

    // MARK: - Fixture: an original ~440-word passage (never a real book's text)

    private let baseText = """
    The old orchard sat behind the schoolhouse, forgotten by everyone except the \
    crows and the boy who fed them stale bread every morning before the first bell. \
    He was not supposed to be there. The gate had rusted shut years earlier, and the \
    fence sagged in three places where earlier children had climbed over rather than \
    around. Still, every dawn found him crouched beneath the tallest apple tree, \
    scattering crumbs across the frost while the birds circled and waited for him to \
    step back. The tree itself was ancient, its bark cracked into long gray ridges, \
    its lowest branches propped up with wooden poles someone had planted decades \
    before he was born. Nobody remembered who had planted the orchard or why it had \
    been left to grow wild once the school took over the land. Some said a farmer \
    had once lived on the property and sold his fruit at the market square on \
    Saturdays. Others insisted the trees predated the town itself, seeded by \
    travelers passing through on the old coach road. The boy did not care much for \
    the history. What mattered to him was the quiet, the way the orchard swallowed \
    every sound from the street beyond the fence, the way the crows recognized his \
    footsteps and stopped their noise the moment he appeared. He liked to imagine \
    that the birds were waiting just for him, that they trusted him the way they \
    trusted no one else in town. In truth they were only waiting for breakfast, but \
    a boy of eight does not need to know that yet. When the first bell finally rang, \
    echoing faintly across the frozen grass, he would brush the crumbs from his \
    palms, climb back over the sagging fence, and walk the last stretch to school \
    with his coat pockets still smelling faintly of bread and cold morning air. \
    Nobody at school ever asked where he went before the bell. Nobody noticed the \
    small tears in his sleeves from the fence, or the frost that clung to his boots \
    long after the classroom had warmed. He kept the orchard to himself for three \
    winters, until the year the town finally tore the old fence down and paved the \
    lot for a parking area, and the crows, without ceremony, simply flew somewhere \
    else across the valley toward the hills where the older orchards still stood \
    untouched by roads or houses or anyone who might notice a boy with crumbs in his \
    pockets and frost on his boots and no good reason at all to be standing beneath \
    a tree before the sun had properly cleared the rooftops of the sleeping town.
    """

    /// A second, topically unrelated original passage — the "wrong book" fixture.
    private let wrongBookText = """
    Numbers arrange themselves into patterns that mathematicians have studied for \
    centuries without ever exhausting their strange beauty. Prime factorization \
    reduces every integer to a unique fingerprint of smaller primes multiplied \
    together, a theorem so fundamental that entire branches of number theory rest \
    upon it. Consider the sequence of triangular numbers, each one formed by \
    summing consecutive integers from one upward, forming shapes that tile neatly \
    into larger geometric figures when arranged correctly on a grid. Students often \
    meet these ideas first through simple counting exercises, only later realizing \
    how deeply interconnected arithmetic, geometry, and abstract algebra truly are \
    beneath the surface of ordinary calculation. A classroom fraction hides within \
    it the entire machinery of ratios, proportions, and eventually the real number \
    line stretching infinitely in both directions, a line no ruler could ever fully \
    measure no matter how finely divided. Long division, taught almost mechanically \
    to children everywhere, quietly encodes the Euclidean algorithm for computing \
    greatest common divisors, an algorithm invented more than two thousand years \
    ago and still taught essentially unchanged today in schools across the world. \
    Even something as ordinary as a multiplication table conceals symmetry: every \
    entry mirrors another across its diagonal, a small but genuine glimpse of the \
    commutative property at work in something children memorize by rote before \
    they ever hear that word spoken aloud in a proper lesson.
    """

    // MARK: - Fixture helpers

    private func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Sequential synthetic timestamps: word i spans [i*step, i*step+dur).
    private func makeTranscript(_ toks: [String], step: Double = 0.4, dur: Double = 0.3) -> [AlignmentCore.Word] {
        toks.enumerated().map { i, w in
            AlignmentCore.Word(text: w, start: Double(i) * step, end: Double(i) * step + dur)
        }
    }

    private func makeBook(_ text: String, sourceFile: String = "book.xhtml") -> [AlignmentCore.Block] {
        [AlignmentCore.Block(text: text, sourceFile: sourceFile)]
    }

    /// Deterministic filler vocabulary — every word embeds its own index, so it (and
    /// every n-gram containing it) is trivially globally unique. Used only for the
    /// efficiency smoke test, where content realism doesn't matter, density does.
    private func syntheticLongText(wordCount: Int) -> [String] {
        let syllables = ["ka", "ri", "mo", "tel", "van", "dor", "fes", "lin", "bra", "zon", "hu", "pel", "gra", "nis", "wex", "tov"]
        return (0..<wordCount).map { i in
            let a = syllables[i % syllables.count]
            let b = syllables[(i * 7 + 3) % syllables.count]
            return "\(a)\(b)\(i)"
        }
    }

    // MARK: - Identity alignment

    func testIdentityAlignment() {
        let toks = words(baseText)
        let result = AlignmentCore.align(transcript: makeTranscript(toks), book: makeBook(baseText))
        XCTAssertEqual(result.verdict, .aligned)
        XCTAssertGreaterThan(result.coverageBook, 0.95, "identical text should time nearly every book word")
        XCTAssertGreaterThan(result.coverageTranscript, 0.95)
        XCTAssertGreaterThan(result.monotonicFraction, 0.95)
        XCTAssertGreaterThan(result.anchorCount, 50, "a ~440-word varied passage should yield plenty of unique 4-gram anchors")
    }

    // MARK: - Scattered ASR mishears

    func testScatteredSubstitutionsStillAligned() {
        var toks = words(baseText)
        let mishears = ["zibbertosh", "quonderay", "vashtril", "plimtose", "nardequin"]
        var m = 0
        var i = 12
        while i < toks.count - 10 {
            toks[i] = mishears[m % mishears.count]
            m += 1
            i += 17
        }
        let result = AlignmentCore.align(transcript: makeTranscript(toks), book: makeBook(baseText))
        XCTAssertEqual(result.verdict, .aligned, "a handful of scattered mishears shouldn't derail alignment")
        XCTAssertGreaterThan(result.coverageBook, 0.9)
    }

    // MARK: - Glued tokens (#683-class)

    /// Two adjacent book words get glued into ONE transcript token (ASR gluing) —
    /// the aligner must still time BOTH book words from the one glued token.
    func testGluedPairMatchesBothBookWords() {
        var toks = words(baseText)
        guard let idx = toks.firstIndex(where: { $0.hasPrefix("schoolhouse") }), toks[idx + 1].hasPrefix("forgotten") else {
            return XCTFail("fixture words not found at the expected adjacency")
        }
        let merged = toks[idx] + toks[idx + 1]
        toks.replaceSubrange(idx...(idx + 1), with: [merged])
        let result = AlignmentCore.align(transcript: makeTranscript(toks), book: makeBook(baseText))
        XCTAssertEqual(result.verdict, .aligned)
        let covered = result.matchedRanges.contains { $0.bookWordStart <= idx && $0.bookWordEnd >= idx + 2 }
        XCTAssertTrue(covered, "the glued transcript token should still time BOTH book words")
    }

    /// The `works.eep` ← "works."+"keep" class (#683, backlog 📖 item 6): a glued
    /// token missing ONE seam character (the leading "k" of "keep" eaten).
    func testGluedPairToleratesOneEatenSeamCharacter() {
        let sentence = "she said it works keep trying tomorrow after today always"
        var toks = words(sentence)
        let idx = toks.firstIndex(of: "works")!
        XCTAssertEqual(toks[idx + 1], "keep")
        toks[idx] = "workseep"   // "works" + "keep" with the leading k eaten
        toks.remove(at: idx + 1)
        let result = AlignmentCore.align(
            transcript: makeTranscript(toks), book: makeBook(sentence), config: .init(anchorN: 2)
        )
        XCTAssertEqual(result.verdict, .aligned)
        let covered = result.matchedRanges.contains { $0.bookWordStart <= idx && $0.bookWordEnd >= idx + 2 }
        XCTAssertTrue(covered, "the eaten-letter glue should still time both book words")
    }

    // MARK: - Deleted book span (narrator skip)

    func testDeletedBookSpanStaysUntimedButVerdictAligned() {
        let bookToks = words(baseText)
        var transcriptToks = bookToks
        let skipStart = 60
        let skipLen = 15   // > default maxInterpolateWords(8) — stays genuinely untimed
        transcriptToks.removeSubrange(skipStart..<(skipStart + skipLen))
        let result = AlignmentCore.align(transcript: makeTranscript(transcriptToks), book: makeBook(baseText))
        XCTAssertEqual(result.verdict, .aligned, "one skipped passage in a ~440-word book shouldn't break the verdict")
        let hasSkipSpan = result.largestUnmatchedBookSpans.contains { $0.wordEnd - $0.wordStart >= 10 }
        XCTAssertTrue(hasSkipSpan, "the skipped passage should surface as a sizeable untimed book span")
    }

    // MARK: - Inserted transcript span (narrator credits)

    func testInsertedTranscriptSpanReported() {
        let bookToks = words(baseText)
        var transcriptToks = bookToks
        let credits = ["zorblatt", "kwenling", "yastrovic", "plimsom", "hobartrix", "wexnell", "abbotcairn", "dunvain"]
        transcriptToks.insert(contentsOf: credits, at: 50)
        let result = AlignmentCore.align(transcript: makeTranscript(transcriptToks), book: makeBook(baseText))
        XCTAssertEqual(result.verdict, .aligned)
        let hasCreditsSpan = result.largestUnmatchedTranscriptSpans.contains { $0.wordEnd - $0.wordStart >= 6 }
        XCTAssertTrue(hasCreditsSpan, "the inserted credits block should surface as an unmatched transcript span")
    }

    // MARK: - Reordered front matter (monotonicity filter)

    func testReorderedFrontMatterFilteredByMonotonicity() {
        let bookToks = words(baseText)
        let previewSnippet = Array(bookToks.suffix(10))   // narrator reads a closing-line preview upfront
        let transcriptToks = previewSnippet + bookToks
        let result = AlignmentCore.align(transcript: makeTranscript(transcriptToks), book: makeBook(baseText))
        XCTAssertEqual(result.verdict, .aligned, "the reordered snippet shouldn't derail the main alignment")
        XCTAssertLessThan(result.monotonicFraction, 1.0, "the out-of-order preview anchors should get filtered by the LIS pass")
        XCTAssertGreaterThan(result.monotonicFraction, 0.8, "but the vast majority of anchors (main content) still survive")
    }

    // MARK: - Number forms (EN + NL)

    func testNumberFormsMatchDigitsToSpelledWords() {
        // English: book prints "2012", ASR (low confidence) spelled it "twenty
        // twelve" — both spelled tokens must glue onto the one book digit
        // (backlog 📖 item 6's ASR-numbers-aren't-guaranteed-digits finding).
        let bookTextEN = "the letter was dated 2012 quietly"
        let transcriptTokEN = ["the", "letter", "was", "dated", "twenty", "twelve", "quietly"]
        let resultEN = AlignmentCore.align(
            transcript: makeTranscript(transcriptTokEN), book: makeBook(bookTextEN), config: .init(anchorN: 2)
        )
        XCTAssertEqual(resultEN.verdict, .aligned)
        XCTAssertEqual(resultEN.coverageTranscript, 1.0, accuracy: 0.001,
                        "both spelled-number tokens should glue onto the one book digit, nothing left unmatched")
        XCTAssertTrue(resultEN.largestUnmatchedTranscriptSpans.isEmpty)

        // Dutch: single-token cardinal ↔ digit — a direct 1:1 match key, no glue needed.
        let bookTextNL = "hij was negentien jaar oud"
        let transcriptTokNL = ["hij", "was", "19", "jaar", "oud"]
        let resultNL = AlignmentCore.align(
            transcript: makeTranscript(transcriptTokNL), book: makeBook(bookTextNL), config: .init(anchorN: 2)
        )
        XCTAssertEqual(resultNL.verdict, .aligned)
        XCTAssertEqual(resultNL.coverageTranscript, 1.0, accuracy: 0.001,
                        "\"19\" and \"negentien\" normalize to the same match key")
    }

    // MARK: - Wrong book self-detects

    func testWrongBookIsRejected() {
        let result = AlignmentCore.align(transcript: makeTranscript(words(baseText)), book: makeBook(wrongBookText))
        XCTAssertEqual(result.verdict, .rejected)
        XCTAssertLessThan(result.coverageBook, 0.1)
    }

    // MARK: - Determinism

    func testDeterminismSameInputTwice() {
        let transcript = makeTranscript(words(baseText))
        let book = makeBook(baseText)
        let r1 = AlignmentCore.align(transcript: transcript, book: book)
        let r2 = AlignmentCore.align(transcript: transcript, book: book)
        XCTAssertEqual(r1.verdict, r2.verdict)
        XCTAssertEqual(r1.coverageBook, r2.coverageBook)
        XCTAssertEqual(r1.coverageTranscript, r2.coverageTranscript)
        XCTAssertEqual(r1.anchorCount, r2.anchorCount)
        XCTAssertEqual(r1.monotonicFraction, r2.monotonicFraction)
        XCTAssertEqual(r1.matchedRanges, r2.matchedRanges)
        XCTAssertEqual(r1.largestUnmatchedTranscriptSpans, r2.largestUnmatchedTranscriptSpans)
        XCTAssertEqual(r1.largestUnmatchedBookSpans, r2.largestUnmatchedBookSpans)
    }

    // MARK: - Largest-spans reporting (cap + sort order)

    func testLargestUnmatchedSpansAreCappedAndSortedByLength() {
        let original = words(baseText)
        var toks = original
        let insertPositions = [20, 40, 60, 80, 100, 120, 140, 160, 180, 200, 220, 240, 260, 280]
            .filter { $0 < original.count }
        // Insert from the highest index down so earlier indices stay valid.
        for (i, pos) in insertPositions.enumerated().reversed() {
            let blockLen = 2 + i
            let junk = (0..<blockLen).map { "zz\(i)w\($0)" }
            toks.insert(contentsOf: junk, at: pos)
        }
        let result = AlignmentCore.align(transcript: makeTranscript(toks), book: makeBook(baseText))
        XCTAssertEqual(result.verdict, .aligned)
        XCTAssertLessThanOrEqual(result.largestUnmatchedTranscriptSpans.count, 10, "capped at Config.topSpanCount")
        let lengths = result.largestUnmatchedTranscriptSpans.map { $0.wordEnd - $0.wordStart }
        XCTAssertEqual(lengths, lengths.sorted(by: >), "largest spans first")
        if let longest = lengths.first {
            XCTAssertGreaterThanOrEqual(longest, 15, "the top span should be one of the larger inserted blocks")
        }
    }

    // MARK: - Band-efficiency smoke

    func testBandEfficiencySmokeCompletesQuickly() {
        let toks = syntheticLongText(wordCount: 4000)
        let text = toks.joined(separator: " ")
        let start = Date()
        let result = AlignmentCore.align(transcript: makeTranscript(toks), book: makeBook(text))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result.verdict, .aligned)
        XCTAssertGreaterThan(result.coverageBook, 0.99)
        XCTAssertLessThan(elapsed, 5.0, "banded DP (never a global N×M matrix) should stay fast at a few thousand words")
    }
}
