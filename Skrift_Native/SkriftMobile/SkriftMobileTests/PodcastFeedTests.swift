import XCTest
@testable import SkriftMobile

/// Q353 (D90, D144, Q6 mock "Episode player"): a podcast episode enters the Library through the
/// show's PUBLIC RSS feed, never a scraped player page. Pure parsing and link resolution, fed with
/// saved responses, no network. The feed fixture is a trimmed copy of `https://rss.art19.com/het-uur`
/// (NRC Het Uur, 4 of 200 items, including the D90 first fixture, Joris Luyendijk, 2026-06-26).
final class PodcastFeedTests: XCTestCase {

    // MARK: - Fixtures

    private func fixture(_ name: String) throws -> Data {
        // .../Skrift_Native/SkriftMobile/SkriftMobileTests/PodcastFeedTests.swift -> repo root is 4 up.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return try Data(contentsOf: url.appendingPathComponent("test-fixtures/podcasts/\(name)"))
    }

    private func hetUur() throws -> PodcastShow {
        try PodcastFeedParser.parse(fixture("het-uur-feed.xml"))
    }

    private func json(_ s: String) -> Data { Data(s.utf8) }

    // MARK: - Feed parse

    func testParsesShowHeaderFromTheNRCFeed() throws {
        let show = try hetUur()
        XCTAssertEqual(show.title, "NRC Het Uur")
        XCTAssertEqual(show.author, "NRC")
        XCTAssertEqual(show.episodes.count, 4)
        XCTAssertEqual(show.artworkURL?.host, "content.production.cdn.art19.com")
    }

    func testParsesTheLuyendijkEpisodeFields() throws {
        let show = try hetUur()
        let ep = try XCTUnwrap(show.episodes.first { $0.title.hasPrefix("Joris Luyendijk") })
        XCTAssertEqual(ep.title, "Joris Luyendijk: 'Ik zit in een rouwproces om de wereld die er niet meer is' | Voormalig journalist | Het Uur")
        XCTAssertEqual(ep.guid, "gid://art19-episode-locator/V0/ahfQYZiRwdjp4LjGAVA6x_EaPXOZC-Pe76aCcVfjQ7U")
        XCTAssertEqual(ep.duration, 1 * 3600 + 3 * 60 + 34)
        XCTAssertEqual(ep.mimeType, "audio/mpeg")
        XCTAssertEqual(ep.enclosureURL.pathExtension, "mp3")
        XCTAssertNotNil(ep.artworkURL)
        XCTAssertTrue(ep.summary.contains("rouwproces"))

        let utc = Calendar(identifier: .gregorian)
        var cal = utc
        cal.timeZone = TimeZone(identifier: "UTC")!
        let parts = cal.dateComponents([.year, .month, .day], from: try XCTUnwrap(ep.publishedAt))
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 6)
        XCTAssertEqual(parts.day, 26)
    }

    func testEpisodesKeepFeedOrderNewestFirst() throws {
        let dates = try hetUur().episodes.compactMap(\.publishedAt)
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    func testItemWithoutAnAudioEnclosureIsSkipped() throws {
        let xml = """
        <?xml version="1.0"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
        <title>Show</title>
        <item><title>No audio</title><guid>a</guid></item>
        <item><title>A video</title><guid>b</guid><enclosure url="https://x.test/v.mp4" type="video/mp4" length="1"/></item>
        <item><title>Good</title><guid>c</guid><enclosure url="https://x.test/c.m4a" type="audio/x-m4a" length="1"/></item>
        </channel></rss>
        """
        let show = try PodcastFeedParser.parse(json(xml))
        XCTAssertEqual(show.episodes.map(\.title), ["Good"])
    }

    func testDurationFormats() {
        XCTAssertEqual(PodcastFeedParser.parseDuration("00:56:23"), 3383)
        XCTAssertEqual(PodcastFeedParser.parseDuration("56:23"), 3383)
        XCTAssertEqual(PodcastFeedParser.parseDuration("3383"), 3383)
        XCTAssertNil(PodcastFeedParser.parseDuration("soon"))
    }

    func testNotAFeedThrowsAPlainSentence() {
        XCTAssertThrowsError(try PodcastFeedParser.parse(json("<html><body>Not a feed</body></html>"))) { error in
            XCTAssertEqual((error as? PodcastRefusal)?.message, PodcastRefusal.notAFeed.message)
        }
    }

    // MARK: - Enclosure pick

    func testPickByGUIDThenByTitleThenNewest() throws {
        let show = try hetUur()
        let luyendijk = try XCTUnwrap(show.episodes.first { $0.title.hasPrefix("Joris Luyendijk") })

        XCTAssertEqual(PodcastPick.episode(in: show, guid: luyendijk.guid, title: nil)?.guid, luyendijk.guid)
        // Title match ignores case, punctuation and the " | Show" suffix noise.
        XCTAssertEqual(PodcastPick.episode(in: show, guid: nil,
                                           title: "joris luyendijk ik zit in een rouwproces om de wereld die er niet meer is")?.guid,
                       luyendijk.guid)
        // Nothing to go on: the newest.
        XCTAssertEqual(PodcastPick.episode(in: show, guid: nil, title: nil)?.title.hasPrefix("Elmer"), true)
        // A hint that matches nothing is NOT silently replaced by the newest.
        XCTAssertNil(PodcastPick.episode(in: show, guid: "nope", title: "also nope"))
    }

    // MARK: - Link classification

    func testClassifiesTheLinkKinds() {
        XCTAssertEqual(PodcastLink.classify("https://podcasts.apple.com/nl/podcast/nrc-het-uur/id1643003287?i=1000700000001"),
                       .apple(showID: 1643003287, episodeID: 1000700000001))
        XCTAssertEqual(PodcastLink.classify("https://podcasts.apple.com/us/podcast/nrc-het-uur/id1643003287"),
                       .apple(showID: 1643003287, episodeID: nil))
        XCTAssertEqual(PodcastLink.classify("https://open.spotify.com/episode/6w01CT5nyx5EmACYk5H80U"),
                       .spotifyEpisode(id: "6w01CT5nyx5EmACYk5H80U"))
        XCTAssertEqual(PodcastLink.classify("https://open.spotify.com/episode/22QF1duMlwvws0QbMFJVLA?si=abc123"),
                       .spotifyEpisode(id: "22QF1duMlwvws0QbMFJVLA"))
        XCTAssertEqual(PodcastLink.classify("https://open.spotify.com/show/1234abcd"), .spotifyShow(id: "1234abcd"))
        XCTAssertEqual(PodcastLink.classify("  https://rss.art19.com/het-uur \n"),
                       .feed(URL(string: "https://rss.art19.com/het-uur")!))
        XCTAssertNil(PodcastLink.classify("not a link"))
        XCTAssertNil(PodcastLink.classify(""))
    }

    // MARK: - Apple link to feed URL

    private let appleShowLookup = """
    {"resultCount":1,"results":[{"wrapperType":"track","kind":"podcast","collectionId":1643003287,
    "collectionName":"NRC Het Uur","artistName":"NRC","feedUrl":"https://rss.art19.com/het-uur",
    "artworkUrl600":"https://is1-ssl.mzstatic.com/image/thumb/x/600x600bb.jpg"}]}
    """

    func testAppleLinkResolvesToTheFeedURL() throws {
        let link = PodcastLink.classify("https://podcasts.apple.com/nl/podcast/nrc-het-uur/id1643003287")!
        XCTAssertEqual(PodcastResolver.lookupURL(for: link)?.absoluteString,
                       "https://itunes.apple.com/lookup?id=1643003287&entity=podcast")
        XCTAssertEqual(try PodcastResolver.feedURL(fromAppleLookup: json(appleShowLookup)).absoluteString,
                       "https://rss.art19.com/het-uur")
    }

    func testAppleEpisodeLinkNamesTheEpisodeGUIDFromTheEpisodeLookup() throws {
        let episodes = """
        {"resultCount":3,"results":[
         {"wrapperType":"track","kind":"podcast","collectionId":1643003287,"feedUrl":"https://rss.art19.com/het-uur"},
         {"wrapperType":"podcastEpisode","trackId":1000700000002,"trackName":"Other","episodeGuid":"guid-other"},
         {"wrapperType":"podcastEpisode","trackId":1000700000001,"trackName":"Joris Luyendijk","episodeGuid":"guid-luy"}]}
        """
        let hint = PodcastResolver.appleEpisodeHint(fromLookup: json(episodes), trackID: 1000700000001)
        XCTAssertEqual(hint?.guid, "guid-luy")
        XCTAssertEqual(hint?.title, "Joris Luyendijk")
        XCTAssertNil(PodcastResolver.appleEpisodeHint(fromLookup: json(episodes), trackID: 42))
    }

    func testAppleShowWithoutAPublicFeedIsRefusedInOneSentence() {
        let noFeed = """
        {"resultCount":1,"results":[{"wrapperType":"track","kind":"podcast","collectionId":9,"collectionName":"Paid Show"}]}
        """
        XCTAssertThrowsError(try PodcastResolver.feedURL(fromAppleLookup: json(noFeed))) { error in
            let message = (error as? PodcastRefusal)?.message ?? ""
            XCTAssertEqual(message, PodcastRefusal.noPublicFeed.message)
            XCTAssertTrue(message.hasSuffix("."))
            XCTAssertEqual(message.filter { $0 == "." }.count, 1, "one plain sentence")
        }
    }

    // MARK: - Spotify (oEmbed title, then iTunes search)

    private let oembedBronze = """
    {"provider_name":"Spotify","type":"rich","title":"Bronze Age Reset: De- and Re-Mythologizing the Manosphere",
    "thumbnail_url":"https://image-cdn-ak.spotifycdn.com/image/ab67656300005f1fd65fb7375f1c1420076314ab"}
    """

    private let searchBronze = """
    {"resultCount":2,"results":[
     {"wrapperType":"podcastEpisode","kind":"podcast-episode","trackName":"Another talk on the manosphere",
      "collectionName":"Elsewhere","feedUrl":"https://example.test/other.rss","episodeGuid":"zzz"},
     {"wrapperType":"podcastEpisode","kind":"podcast-episode",
      "trackName":"Bronze Age Reset: De- and Re-Mythologizing the Manosphere","collectionName":"The Emerald",
      "feedUrl":"https://rss.buzzsprout.com/317042.rss","episodeGuid":"Buzzsprout-1"}]}
    """

    func testSpotifyEpisodeLinkResolvesToItsShowFeed() throws {
        let link = PodcastLink.classify("https://open.spotify.com/episode/6w01CT5nyx5EmACYk5H80U")!
        XCTAssertEqual(PodcastResolver.oEmbedURL(for: link)?.absoluteString,
                       "https://open.spotify.com/oembed?url=https://open.spotify.com/episode/6w01CT5nyx5EmACYk5H80U")
        let title = try PodcastResolver.spotifyTitle(fromOEmbed: json(oembedBronze))
        XCTAssertEqual(title, "Bronze Age Reset: De- and Re-Mythologizing the Manosphere")

        let match = try PodcastResolver.spotifyMatch(title: title, searchResults: json(searchBronze))
        XCTAssertEqual(match.feedURL.absoluteString, "https://rss.buzzsprout.com/317042.rss")
        XCTAssertEqual(match.hint.guid, "Buzzsprout-1")
        XCTAssertEqual(match.showName, "The Emerald")
    }

    func testSpotifyExclusiveEpisodeIsRefusedNeverScraped() throws {
        let exclusive = """
        {"resultCount":1,"results":[{"wrapperType":"podcastEpisode","trackName":"Something unrelated",
         "collectionName":"Elsewhere","feedUrl":"https://example.test/other.rss"}]}
        """
        XCTAssertThrowsError(try PodcastResolver.spotifyMatch(title: "A Spotify Original Episode",
                                                              searchResults: json(exclusive))) { error in
            XCTAssertEqual((error as? PodcastRefusal)?.message, PodcastRefusal.spotifyExclusive.message)
        }
        let empty = #"{"resultCount":0,"results":[]}"#
        XCTAssertThrowsError(try PodcastResolver.spotifyMatch(title: "A Spotify Original Episode",
                                                              searchResults: json(empty))) { error in
            XCTAssertEqual((error as? PodcastRefusal)?.message, PodcastRefusal.spotifyExclusive.message)
        }
        XCTAssertEqual(PodcastRefusal.spotifyExclusive.message.filter { $0 == "." }.count, 1)
    }

    func testSpotifyShowMatchesByShowNameAndKeepsNoEpisodeHint() throws {
        let oembed = #"{"title":"The Emerald","type":"rich"}"#
        let search = """
        {"resultCount":1,"results":[{"wrapperType":"track","kind":"podcast","collectionName":"The Emerald",
         "feedUrl":"https://rss.buzzsprout.com/317042.rss"}]}
        """
        let match = try PodcastResolver.spotifyShowMatch(name: try PodcastResolver.spotifyTitle(fromOEmbed: json(oembed)),
                                                         searchResults: json(search))
        XCTAssertEqual(match.feedURL.absoluteString, "https://rss.buzzsprout.com/317042.rss")
        XCTAssertNil(match.hint.guid)
    }

    // MARK: - Raw RSS URL

    func testRawFeedURLNeedsNoLookup() {
        let link = PodcastLink.classify("https://rss.art19.com/het-uur")!
        XCTAssertNil(PodcastResolver.lookupURL(for: link))
        XCTAssertNil(PodcastResolver.oEmbedURL(for: link))
    }

    // MARK: - The Library record

    func testEpisodeBecomesALibraryRecordOfKindEpisode() throws {
        let show = try hetUur()
        let ep = try XCTUnwrap(show.episodes.first { $0.title.hasPrefix("Joris Luyendijk") })
        let record = PodcastImporter.makeBook(show: show, episode: ep, filename: "book.mp3", duration: 3814, hasCover: true)
        XCTAssertEqual(record.sourceKind, .episode)
        XCTAssertEqual(record.title, ep.title)
        XCTAssertEqual(record.author, "NRC Het Uur")
        XCTAssertEqual(record.publishedAt, ep.publishedAt)
        XCTAssertTrue(record.hasCover)
        XCTAssertEqual(record.files, ["book.mp3"])
        // The date and kind survive the synced blob.
        let back = try JSONDecoder().decode(Audiobook.self, from: JSONEncoder().encode(record.sanitizedForSync()))
        XCTAssertEqual(back.sourceKind, .episode)
        XCTAssertEqual(back.publishedAt, ep.publishedAt)
    }

    func testPodcastDoorIsShownOnceItsImporterExists() {
        XCTAssertTrue(LibraryDoor.visible.contains(.podcast))
    }
}
