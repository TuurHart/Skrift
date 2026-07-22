import XCTest
import Foundation

/// EPubParse (Shared/Pipeline/EPubParse.swift) — the ePub -> book-text extractor spike-4 lane
/// built (📖 ePub alignment, LANE_EPUB). Same file in both suites (mobile adds the @testable
/// import); the desktop host-less test bundle compiles Shared/Pipeline directly. Fixtures are
/// in-source string literals only — no bundled files, no real book text (copyright).
final class EPubParseTests: XCTestCase {

    // MARK: - Fixture builder

    private let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    private func data(_ s: String) -> Data { s.data(using: .utf8)! }

    private func makeEntries(
        opf: String, ncx: String? = nil, nav: String? = nil,
        chapters: [String: String], encryption: String? = nil, rights: String? = nil
    ) -> [String: Data] {
        var entries: [String: Data] = [
            "META-INF/container.xml": data(containerXML),
            "OEBPS/content.opf": data(opf),
        ]
        if let ncx { entries["OEBPS/toc.ncx"] = data(ncx) }
        if let nav { entries["OEBPS/nav.xhtml"] = data(nav) }
        for (path, xhtml) in chapters { entries[path] = data(xhtml) }
        if let encryption { entries["META-INF/encryption.xml"] = data(encryption) }
        if let rights { entries["META-INF/rights.xml"] = data(rights) }
        return entries
    }

    private func chapter(_ title: String, _ paragraphs: [String]) -> String {
        let body = paragraphs.map { "<p>\($0)</p>" }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>\(title)</title></head>
        <body>
        <h1>\(title)</h1>
        \(body)
        </body>
        </html>
        """
    }

    private func singleChapterOPF(id: String, href: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
          <metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test Book</dc:title></metadata>
          <manifest>
            <item id="\(id)" href="\(href)" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="\(id)"/>
          </spine>
        </package>
        """
    }

    // MARK: - 1. Baseline EPUB2, 3 chapters — block text/order/sourceFile + TOC titles/targets

    func testEPUB2BaselineBlocksAndTOC() throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
          <metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test Book</dc:title></metadata>
          <manifest>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch3" href="chapter3.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine toc="ncx">
            <itemref idref="ch1"/>
            <itemref idref="ch2"/>
            <itemref idref="ch3"/>
          </spine>
        </package>
        """
        let ncx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <navMap>
            <navPoint id="np1" playOrder="1">
              <navLabel><text>Chapter One</text></navLabel>
              <content src="chapter1.xhtml"/>
            </navPoint>
            <navPoint id="np2" playOrder="2">
              <navLabel><text>Chapter Two</text></navLabel>
              <content src="chapter2.xhtml"/>
            </navPoint>
            <navPoint id="np3" playOrder="3">
              <navLabel><text>Chapter Three</text></navLabel>
              <content src="chapter3.xhtml"/>
            </navPoint>
          </navMap>
        </ncx>
        """
        let entries = makeEntries(opf: opf, ncx: ncx, chapters: [
            "OEBPS/chapter1.xhtml": chapter("Chapter One", [
                "It was a bright cold day in April.", "The clocks were striking thirteen.",
            ]),
            "OEBPS/chapter2.xhtml": chapter("Chapter Two", ["Winston Smith walked briskly."]),
            "OEBPS/chapter3.xhtml": chapter("Chapter Three", ["The Ministry of Truth rose."]),
        ])

        let book = try EPubParse.parse(entries: entries)

        XCTAssertEqual(book.blocks.map(\.text), [
            "Chapter One",
            "It was a bright cold day in April.",
            "The clocks were striking thirteen.",
            "Chapter Two",
            "Winston Smith walked briskly.",
            "Chapter Three",
            "The Ministry of Truth rose.",
        ])
        XCTAssertEqual(book.blocks.map(\.sourceFile), [
            "OEBPS/chapter1.xhtml", "OEBPS/chapter1.xhtml", "OEBPS/chapter1.xhtml",
            "OEBPS/chapter2.xhtml", "OEBPS/chapter2.xhtml",
            "OEBPS/chapter3.xhtml", "OEBPS/chapter3.xhtml",
        ])
        XCTAssertEqual(book.toc.map(\.title), ["Chapter One", "Chapter Two", "Chapter Three"])
        XCTAssertEqual(book.toc.map(\.sourceFile), [
            "OEBPS/chapter1.xhtml", "OEBPS/chapter2.xhtml", "OEBPS/chapter3.xhtml",
        ])
        XCTAssertEqual(book.toc.map(\.fragment), [nil, nil, nil])
        XCTAssertEqual(book.drm, .none)
    }

    // MARK: - 2. EPUB3 nav preferred over NCX when both exist

    func testEPUB3NavPreferredOverNCX() throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="BookId">
          <metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test Book 3</dc:title></metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine toc="ncx">
            <itemref idref="ch1"/>
            <itemref idref="ch2"/>
          </spine>
        </package>
        """
        let ncx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <navMap>
            <navPoint id="np1" playOrder="1">
              <navLabel><text>Chapter One (NCX)</text></navLabel>
              <content src="chapter1.xhtml"/>
            </navPoint>
            <navPoint id="np2" playOrder="2">
              <navLabel><text>Chapter Two (NCX)</text></navLabel>
              <content src="chapter2.xhtml"/>
            </navPoint>
          </navMap>
        </ncx>
        """
        let nav = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>Nav</title></head>
        <body>
          <nav epub:type="toc">
            <ol>
              <li><a href="chapter1.xhtml">Chapter One (Nav)</a></li>
              <li><a href="chapter2.xhtml">Chapter Two (Nav)</a></li>
            </ol>
          </nav>
        </body>
        </html>
        """
        let entries = makeEntries(opf: opf, ncx: ncx, nav: nav, chapters: [
            "OEBPS/chapter1.xhtml": chapter("Chapter One", ["Some text one."]),
            "OEBPS/chapter2.xhtml": chapter("Chapter Two", ["Some text two."]),
        ])

        let book = try EPubParse.parse(entries: entries)
        XCTAssertEqual(book.toc.map(\.title), ["Chapter One (Nav)", "Chapter Two (Nav)"])
        XCTAssertEqual(book.toc.map(\.sourceFile), ["OEBPS/chapter1.xhtml", "OEBPS/chapter2.xhtml"])
    }

    // MARK: - 3. Manifest attribute order must not matter (the real-Steal-ePub GOTCHA)

    func testManifestAttributeOrderIndependent() throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
          <metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test Book</dc:title></metadata>
          <manifest>
            <item href="toc.ncx" media-type="application/x-dtbncx+xml" id="ncx"/>
            <item media-type="application/xhtml+xml" href="chapter1.xhtml" id="ch1"/>
          </manifest>
          <spine toc="ncx">
            <itemref idref="ch1"/>
          </spine>
        </package>
        """
        let ncx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <navMap>
            <navPoint id="np1" playOrder="1">
              <navLabel><text>Chapter One</text></navLabel>
              <content src="chapter1.xhtml"/>
            </navPoint>
          </navMap>
        </ncx>
        """
        let entries = makeEntries(opf: opf, ncx: ncx, chapters: [
            "OEBPS/chapter1.xhtml": chapter("Chapter One", ["Attribute order should not matter."]),
        ])
        let book = try EPubParse.parse(entries: entries)
        XCTAssertEqual(book.blocks.map(\.text), ["Chapter One", "Attribute order should not matter."])
        XCTAssertEqual(book.toc.map(\.title), ["Chapter One"])
    }

    // MARK: - 4. Malformed chapter (&nbsp; + unclosed tag) falls back leniently

    func testMalformedChapterFallsBackLeniently() throws {
        let opf = singleChapterOPF(id: "ch1", href: "chapter1.xhtml")
        let malformed = """
        <html xmlns="http://www.w3.org/1999/xhtml">
        <body>
        <p>First&nbsp;paragraph is fine.</p>
        <p>Second paragraph never closes properly
        <p>Third paragraph.</p>
        </body>
        </html>
        """
        let entries = makeEntries(opf: opf, chapters: ["OEBPS/chapter1.xhtml": malformed])

        let book = try EPubParse.parse(entries: entries)
        XCTAssertFalse(book.blocks.isEmpty)
        let joined = book.blocks.map(\.text).joined(separator: " | ")
        XCTAssertTrue(joined.contains("First paragraph is fine."), joined)
        XCTAssertTrue(joined.contains("Second paragraph never closes properly"), joined)
        XCTAssertTrue(joined.contains("Third paragraph."), joined)
        XCTAssertFalse(joined.contains("&nbsp;"), joined)
        for block in book.blocks { XCTAssertEqual(block.sourceFile, "OEBPS/chapter1.xhtml") }
    }

    // MARK: - 5. Footnote / noteref exclusion

    func testFootnoteAndNoterefExcluded() throws {
        let opf = singleChapterOPF(id: "ch1", href: "chapter1.xhtml")
        let xhtml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <body>
        <p>Main text with a reference<a epub:type="noteref" href="notes.xhtml#n1">1</a> inline.</p>
        <aside epub:type="footnote" id="n1"><p>This is the footnote body and should be excluded.</p></aside>
        </body>
        </html>
        """
        let entries = makeEntries(opf: opf, chapters: ["OEBPS/chapter1.xhtml": xhtml])

        let book = try EPubParse.parse(entries: entries)
        XCTAssertEqual(book.blocks.count, 1)
        let text = book.blocks[0].text
        XCTAssertTrue(text.contains("Main text with a reference"), text)
        XCTAssertTrue(text.contains("inline."), text)
        XCTAssertFalse(text.contains("footnote body"), text)
        XCTAssertFalse(text.contains("reference1"), text)
    }

    // MARK: - 6. Image-only "chapter" — empty blocks, no crash, alt text never leaks

    func testImageOnlyChapterContributesNoBlocks() throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
          <metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test Book</dc:title></metadata>
          <manifest>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
            <itemref idref="ch2"/>
          </spine>
        </package>
        """
        let ch1 = chapter("Chapter One", ["Real text lives here."])
        let ch2 = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <body>
        <img src="picture1.jpg" alt="chapter2_page1.jpg"/>
        <img src="picture2.jpg" alt="chapter2_page2.jpg"/>
        </body>
        </html>
        """
        let entries = makeEntries(opf: opf, chapters: [
            "OEBPS/chapter1.xhtml": ch1,
            "OEBPS/chapter2.xhtml": ch2,
        ])

        let book = try EPubParse.parse(entries: entries)
        XCTAssertEqual(book.blocks.map(\.text), ["Chapter One", "Real text lives here."])
        XCTAssertTrue(book.blocks.allSatisfy { $0.sourceFile != "OEBPS/chapter2.xhtml" })
        for block in book.blocks { XCTAssertFalse(block.text.contains("jpg")) }
    }

    // MARK: - 7. DRM verdicts

    func testDRMAbsentIsNone() throws {
        let opf = singleChapterOPF(id: "ch1", href: "chapter1.xhtml")
        let entries = makeEntries(opf: opf, chapters: ["OEBPS/chapter1.xhtml": chapter("Ch", ["Text."])])
        let book = try EPubParse.parse(entries: entries)
        XCTAssertEqual(book.drm, .none)
    }

    func testDRMFontObfuscationOnlyIsNotProtected() throws {
        let opf = singleChapterOPF(id: "ch1", href: "chapter1.xhtml")
        let encryption = """
        <?xml version="1.0" encoding="UTF-8"?>
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">
            <EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
            <CipherData><CipherReference URI="fonts/font1.otf"/></CipherData>
          </EncryptedData>
          <EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">
            <EncryptionMethod Algorithm="http://ns.adobe.com/pdf/enc#RC"/>
            <CipherData><CipherReference URI="fonts/font2.otf"/></CipherData>
          </EncryptedData>
        </encryption>
        """
        let entries = makeEntries(
            opf: opf, chapters: ["OEBPS/chapter1.xhtml": chapter("Ch", ["Text."])],
            encryption: encryption)
        let book = try EPubParse.parse(entries: entries)
        XCTAssertEqual(book.drm, .none)
    }

    func testDRMADEPTRightsIsProtected() throws {
        let opf = singleChapterOPF(id: "ch1", href: "chapter1.xhtml")
        let encryption = """
        <?xml version="1.0" encoding="UTF-8"?>
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">
            <EncryptionMethod Algorithm="http://www.adobe.com/adept"/>
            <CipherData><CipherReference URI="OEBPS/chapter1.xhtml"/></CipherData>
          </EncryptedData>
        </encryption>
        """
        let rights = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rights xmlns="http://ns.adobe.com/adept"><licenseToken/></rights>
        """
        let entries = makeEntries(
            opf: opf, chapters: ["OEBPS/chapter1.xhtml": chapter("Ch", ["Text."])],
            encryption: encryption, rights: rights)
        let book = try EPubParse.parse(entries: entries)
        if case .protected = book.drm {
            // expected
        } else {
            XCTFail("expected .protected, got \(book.drm)")
        }
    }

    // MARK: - 8. Spine order (not manifest declaration order) drives block order

    func testBlocksFollowSpineOrderNotManifestOrder() throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
          <metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test Book</dc:title></metadata>
          <manifest>
            <item id="ch3" href="chapter3.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
            <itemref idref="ch2"/>
            <itemref idref="ch3"/>
          </spine>
        </package>
        """
        let entries = makeEntries(opf: opf, chapters: [
            "OEBPS/chapter1.xhtml": chapter("One", ["First."]),
            "OEBPS/chapter2.xhtml": chapter("Two", ["Second."]),
            "OEBPS/chapter3.xhtml": chapter("Three", ["Third."]),
        ])
        let book = try EPubParse.parse(entries: entries)
        XCTAssertEqual(book.blocks.map(\.text), ["One", "First.", "Two", "Second.", "Three", "Third."])
    }

    // MARK: - 9. TOC docs with named HTML entities (2026-07-22, the Odyssey chapter report)

    /// The nav doc is XHTML like any spine file — `&nbsp;` in it hard-fails a strict XML
    /// parse. With no NCX to fall back to, the TOC came back EMPTY (silently: no chapter
    /// marks, chapters stayed detected/embedded). The lenient retry must recover it.
    func testNavWithNamedEntitiesAndNoNCXStillYieldsTOC() throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="BookId">
          <metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">The Odyssey</dc:title></metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
            <itemref idref="ch2"/>
          </spine>
        </package>
        """
        let nav = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>Nav</title></head>
        <body>
          <nav epub:type="toc">
            <ol>
              <li><a href="chapter1.xhtml">Book&nbsp;1: The Boy &amp; the Goddess</a></li>
              <li><a href="chapter2.xhtml">Book&nbsp;2 &mdash; A Dangerous Journey</a></li>
            </ol>
          </nav>
        </body>
        </html>
        """
        let entries = makeEntries(opf: opf, nav: nav, chapters: [
            "OEBPS/chapter1.xhtml": chapter("Book 1", ["Tell me about a complicated man."]),
            "OEBPS/chapter2.xhtml": chapter("Book 2", ["When newborn Dawn appeared."]),
        ])

        let book = try EPubParse.parse(entries: entries)
        XCTAssertEqual(book.toc.map(\.title),
                       ["Book 1: The Boy & the Goddess", "Book 2 \u{2014} A Dangerous Journey"],
                       "entities substituted, XML-predefined ones (&amp;) preserved")
        XCTAssertEqual(book.toc.map(\.sourceFile), ["OEBPS/chapter1.xhtml", "OEBPS/chapter2.xhtml"],
                       "targets must still resolve to the SAME paths the spine blocks carry")
    }

    func testNCXWithNamedEntitiesStillYieldsTOC() throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
          <metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test Book</dc:title></metadata>
          <manifest>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine toc="ncx">
            <itemref idref="ch1"/>
          </spine>
        </package>
        """
        let ncx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <navMap>
            <navPoint id="np1" playOrder="1">
              <navLabel><text>Chapter&nbsp;One</text></navLabel>
              <content src="chapter1.xhtml"/>
            </navPoint>
          </navMap>
        </ncx>
        """
        let entries = makeEntries(opf: opf, ncx: ncx, chapters: [
            "OEBPS/chapter1.xhtml": chapter("Chapter One", ["Text."]),
        ])
        let book = try EPubParse.parse(entries: entries)
        XCTAssertEqual(book.toc.map(\.title), ["Chapter One"])
    }

    // MARK: - Error paths

    func testEmptyUnprotectedBookThrowsNoReadableText() throws {
        let opf = singleChapterOPF(id: "ch1", href: "chapter1.xhtml")
        let empty = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><body></body></html>
        """
        let entries = makeEntries(opf: opf, chapters: ["OEBPS/chapter1.xhtml": empty])
        XCTAssertThrowsError(try EPubParse.parse(entries: entries)) { error in
            XCTAssertEqual(error as? EPubParse.ParseError, .noReadableText)
        }
    }

    func testMissingContainerThrows() {
        XCTAssertThrowsError(try EPubParse.parse(entries: [:])) { error in
            XCTAssertEqual(error as? EPubParse.ParseError, .missingContainer)
        }
    }
}
