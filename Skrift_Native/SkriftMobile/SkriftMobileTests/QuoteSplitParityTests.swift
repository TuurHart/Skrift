import XCTest
@testable import SkriftMobile

/// Q149 / C172: ONE quote splitter and ONE attribution builder. The same fixtures run in
/// `SkriftDesktopTests/QuoteSplitParityTests.swift` — keep the two fixture tables identical.
/// `QuoteProtection.splitLeadingQuote` (copy-edit escrow, name-link protection, export) is an
/// adapter over `CaptureQuote.split` (the display splitter), so a body that DISPLAYS as a
/// quote is protected and exported as one; a leading blank line or an indented `>` used to
/// slip through as plain text (books-116).
final class QuoteSplitParityTests: XCTestCase {

    /// body, displayText (nil = not a quote), ramble
    private let fixtures: [(body: String, display: String?, ramble: String)] = [
        ("> One.\n> Two.\n\nMy ramble.", "One.\nTwo.", "My ramble."),
        ("> Only a quote.", "Only a quote.", ""),
        ("\n> Leading blank line.\n\nRamble.", "Leading blank line.", "Ramble."),
        ("  > Indented marker.\n\nRamble.", "Indented marker.", "Ramble."),
        ("\n\n  > Both.\n  >\n  > Para two.\n\n\n\nRamble.", "Both.\n\nPara two.", "Ramble."),
        (">Tight marker.\n\nRamble.", "Tight marker.", "Ramble."),
        ("Plain memo, no quote.", nil, ""),
        ("Intro first.\n> quoted later", nil, ""),
        (">", nil, ""),
        (">\n>  ", nil, ""),
        ("", nil, ""),
    ]

    func testBothSplittersAgreeOnEveryFixture() {
        for f in fixtures {
            let display = CaptureQuote.split(f.body)
            let protection = QuoteProtection.splitLeadingQuote(f.body)
            XCTAssertEqual(display?.displayText, f.display, "display: \(f.body.debugDescription)")
            XCTAssertEqual(display == nil, protection == nil,
                           "display and protection must agree on whether this is a quote: \(f.body.debugDescription)")
            guard let display, let protection else { continue }
            XCTAssertEqual(display.ramble, f.ramble, "ramble: \(f.body.debugDescription)")
            XCTAssertEqual(protection.ramble, display.ramble)
            // The protected quote is the leading bytes of the body, byte for byte.
            XCTAssertTrue(f.body.hasPrefix(protection.quote), "quote bytes: \(f.body.debugDescription)")
            XCTAssertEqual(protection.quote, display.quoteBlock)
        }
    }

    func testIndentedAndBlankLedQuotesAreProtectedLikeAnyOther() {
        for body in ["\n> Leading blank.\n\nRamble words.", "  > Indented.\n\nRamble words."] {
            let split = QuoteProtection.splitLeadingQuote(body)
            XCTAssertNotNil(split, body.debugDescription)
            guard let split else { continue }
            let rejoined = QuoteProtection.reassemble(quote: split.quote, ramble: "Edited ramble.")
            XCTAssertTrue(QuoteProtection.leadingQuoteIntact(original: body, edited: rejoined))
            XCTAssertFalse(QuoteProtection.leadingQuoteIntact(
                original: body, edited: rejoined.replacingOccurrences(of: "Leading", with: "Changed")
                    .replacingOccurrences(of: "Indented", with: "Changed")))
        }
    }

    func testExportItalicisesTheSameBlockTheDisplayFinds() {
        for body in ["\n> Leading blank.\n\nRamble.", "  > Indented.\n\nRamble."] {
            let out = Compiler.audiobookBody(body, book: "Book", author: "Ann", chapter: "4")
            XCTAssertTrue(out.hasPrefix("> *"), "quote italicised, blanks/indent normalised: \(out.debugDescription)")
            XCTAssertTrue(out.contains("\n>\n> — [[Ann]], *Book*, ch. 4"), out)
            XCTAssertTrue(out.hasSuffix("Ramble."))
        }
    }

    /// book, author, chapter, plain caption, vault line (nil = no attribution at all).
    private let attributions: [(book: String?, author: String?, chapter: String?, plain: String?, vault: String?)] = [
        ("Book", "Ann", "4", "— Ann, Book · ch. 4", "— [[Ann]], *Book*, ch. 4"),
        ("Book", "", "4", "— Book · ch. 4", "— *Book*, ch. 4"),          // never "— , Book"
        ("Book", "  ", nil, "— Book", "— *Book*"),
        ("Book", nil, nil, "— Book", "— *Book*"),
        ("Book", "Ann", "The Spark", "— Ann, Book · The Spark", "— [[Ann]], *Book*, The Spark"),   // a name as-is
        ("Book", "Ann", "", "— Ann, Book", "— [[Ann]], *Book*"),
        (nil, "Ann", "4", nil, nil),
        ("  ", "Ann", "4", nil, nil),
    ]

    func testOneAttributionBuilderForCaptionPreviewAndVault() {
        for a in attributions {
            XCTAssertEqual(CaptureQuote.attribution(book: a.book, author: a.author, chapter: a.chapter), a.plain,
                           "plain \(a)")
            XCTAssertEqual(CaptureQuote.attribution(book: a.book, author: a.author, chapter: a.chapter, style: .vault),
                           a.vault, "vault \(a)")
            // The preview composes lead + title + tail from the same parts.
            let parts = CaptureQuote.attributionParts(book: a.book, author: a.author, chapter: a.chapter)
            XCTAssertEqual(parts.map { $0.lead + $0.title + $0.tail }, a.plain, "preview \(a)")
        }
    }

    func testVaultLineInsideTheCompilerUsesTheSameBuilder() {
        for a in attributions {
            guard let book = a.book?.trimmingCharacters(in: .whitespaces), !book.isEmpty else { continue }
            let out = Compiler.audiobookBody("> Q.\n\nR.", book: book, author: a.author, chapter: a.chapter)
            XCTAssertTrue(out.contains("> " + (a.vault ?? "")), "\(a) → \(out.debugDescription)")
        }
    }
}
