import XCTest
@testable import SkriftMobile

/// A1/C4 pure HTML extraction — the parsing half of link enrichment.
final class HTMLMetaTests: XCTestCase {

    private let article = """
    <html><head>
      <title>Fallback &amp; Title</title>
      <meta property="og:title" content="The Real&#8217;s Title">
      <meta content="A description of the piece." property="og:description">
      <meta property="og:image" content="/img/hero.jpg">
      <script>var x = "<p>not content</p>";</script>
    </head><body>
      <nav><p>Home News Sport Weather and a long menu of links everywhere</p></nav>
      <article>
        <p>First paragraph of the article body, long enough to count as real prose for the reader,
        and padded further so the combined length of the run comfortably clears the extraction floor.</p>
        <p>Second paragraph with more substance, also comfortably past the per-paragraph threshold,
        because a real article paragraph tends to run to a few sentences rather than a fragment.</p>
        <p>Third paragraph closing the argument out, again with enough words to be a paragraph
        that a reader would recognise as one, rather than a stray caption or a button label.</p>
        <p>Fourth paragraph so the total clears the four-hundred character floor with plenty of
        room to spare, which keeps this fixture honest about what the heuristic requires.</p>
      </article>
      <footer><p>Copyright bla bla bla bla bla bla bla bla bla bla bla bla</p></footer>
    </body></html>
    """

    func testOgTagsBothAttributeOrders() {
        let p = HTMLMeta.parse(article, baseURL: URL(string: "https://example.com/story"))
        XCTAssertEqual(p.title, "The Real’s Title", "og:title wins; numeric entity decoded")
        XCTAssertEqual(p.description, "A description of the piece.", "content-first attribute order parsed")
    }

    func testRelativeOgImageResolvesAgainstBase() {
        let p = HTMLMeta.parse(article, baseURL: URL(string: "https://example.com/story"))
        XCTAssertEqual(p.imageURL?.absoluteString, "https://example.com/img/hero.jpg")
    }

    func testArticleTextPrefersArticleScopeAndSkipsChrome() throws {
        let p = HTMLMeta.parse(article, baseURL: nil)
        let text = try XCTUnwrap(p.articleText)
        XCTAssertTrue(text.hasPrefix("First paragraph"))
        XCTAssertTrue(text.contains("Fourth paragraph"))
        XCTAssertFalse(text.contains("Home News Sport"), "nav stripped")
        XCTAssertFalse(text.contains("Copyright"), "footer stripped")
        XCTAssertFalse(text.contains("not content"), "script stripped")
    }

    func testTitleFallsBackToTitleTag() {
        let html = "<html><head><title>Only &amp; Title</title></head><body><p>x</p></body></html>"
        XCTAssertEqual(HTMLMeta.parse(html, baseURL: nil).title, "Only & Title")
    }

    func testLandingPageYieldsNoArticle() {
        let html = "<html><body><p>Buy now.</p><div>App store badges</div></body></html>"
        XCTAssertNil(HTMLMeta.parse(html, baseURL: nil).articleText,
                     "a page without a paragraph run is not an article")
    }

    func testEntityDecoding() {
        XCTAssertEqual(HTMLMeta.decodeEntities("Fish &amp; Chips &#x2014; &#8220;yes&#8221;"),
                       "Fish & Chips — “yes”")
    }
}
