import XCTest
@testable import SkriftMobile

/// Q476 (C72, D90): every pasted podcast link finds the show's PUBLIC feed and the episode in it.
/// Each folder under `test-fixtures/podcast-links/` is one real link (Tuur's Spotify and Deezer links,
/// an Acast page, an Apple, an Overcast and a Pocket Casts link) with the responses recorded from
/// the real services on 2026-10-16: the oEmbed / page meta / iTunes Search / feed answers its
/// resolution asks for, plus the redirect chain of a short link. Tests replay them; a request the
/// recording does not hold fails the test, so nothing here ever touches the network.
final class SpotifyFeedResolveTests: XCTestCase {

    // MARK: - Recorded link folders

    private struct Expect: Decodable {
        var outcome: String
        var feed: String
        var episodeTitle: String
    }

    private struct Response: Decodable {
        var file: String?
        var redirect: String?
    }

    private struct Manifest: Decodable {
        var link: String
        var expect: Expect
        var responses: [String: Response]
    }

    private static var root: URL {
        // .../Skrift_Native/SkriftMobile/SkriftMobileTests/<this file> -> repo root is 4 up.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("test-fixtures")
    }

    /// host + path + sorted query, the key the recorder wrote.
    private static func key(_ url: URL) -> String {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = (comps?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") }
            .sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
        return (url.host ?? "") + url.path + (query.isEmpty ? "" : "?" + query)
    }

    /// Replays one folder: `fetch` and `redirect` answer from the manifest; everything else is recorded in `missing`.
    private final class Replay: @unchecked Sendable {
        let manifest: Manifest
        let folder: URL
        var override: (@Sendable (URL) -> Data?)?
        private let lock = NSLock()
        private var _fetched: [String] = []
        private var _missing: [String] = []
        var fetched: [String] { lock.lock(); defer { lock.unlock() }; return _fetched }
        var missing: [String] { lock.lock(); defer { lock.unlock() }; return _missing }

        init(folder name: String) throws {
            self.folder = SpotifyFeedResolveTests.root.appendingPathComponent("podcast-links/\(name)")
            self.manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        }

        var fetch: PodcastImporter.Fetch {
            { [self] url in
                lock.lock(); _fetched.append(url.absoluteString); lock.unlock()
                if let data = override?(url) { return data }
                guard let r = manifest.responses[SpotifyFeedResolveTests.key(url)], let file = r.file else {
                    lock.lock(); _missing.append(url.absoluteString); lock.unlock()
                    throw URLError(.notConnectedToInternet)
                }
                return try Data(contentsOf: folder.appendingPathComponent(file))
            }
        }

        var redirect: PodcastImporter.Redirect {
            { [self] url in
                guard let r = manifest.responses[SpotifyFeedResolveTests.key(url)], let to = r.redirect, let final = URL(string: to) else {
                    lock.lock(); _missing.append("redirect " + url.absoluteString); lock.unlock()
                    throw URLError(.notConnectedToInternet)
                }
                return final
            }
        }
    }

    /// Resolves the folder's link offline and checks the outcome the recording promised.
    private func assertResolves(_ folder: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let replay = try Replay(folder: folder)
        let expect = replay.manifest.expect
        switch expect.outcome {
        case "episode":
            let result = try await PodcastImporter.resolve(replay.manifest.link, fetch: replay.fetch, redirect: replay.redirect)
            guard case .episode(let show, let episode) = result else {
                return XCTFail("\(folder): expected one episode, got \(result)", file: file, line: line)
            }
            XCTAssertEqual(episode.title, expect.episodeTitle, file: file, line: line)
            XCTAssertFalse(show.title.isEmpty, file: file, line: line)
            XCTAssertTrue(replay.fetched.contains(expect.feed), "\(folder): feed \(expect.feed) not read; read \(replay.fetched)", file: file, line: line)
        case "subscribersOnly":
            do {
                let result = try await PodcastImporter.resolve(replay.manifest.link, fetch: replay.fetch, redirect: replay.redirect)
                XCTFail("\(folder): expected the subscribers-only refusal, got \(result)", file: file, line: line)
            } catch let refusal as PodcastRefusal {
                XCTAssertEqual(refusal, PodcastRefusal.subscribersOnly, file: file, line: line)
            }
            XCTAssertTrue(replay.fetched.contains(expect.feed), "\(folder): feed \(expect.feed) not read; read \(replay.fetched)", file: file, line: line)
        default:
            XCTFail("unknown outcome \(expect.outcome)", file: file, line: line)
        }
        XCTAssertEqual(replay.missing, [], "\(folder): requests the recording does not hold", file: file, line: line)
    }

    // MARK: - The real links

    /// Tuur's link (Dev 192): the episode is in the Economist Podcasts feed. That feed lists it as a
    /// subscribers-only item with no audio file, so the answer is the plain "subscribers only", not
    /// "only on Spotify".
    func testSpotifyEpisodeLinkFindsTheShowFeedAndNamesWhyItCannotBeTaken() async throws {
        try await assertResolves("spotify-ng-ai-doom")
    }

    /// Tuur's Deezer share link: link.deezer.com/s/… redirects to deezer.com/episode/947688582, whose page
    /// names the show (Blindboy) and the episode; the public feed is found through the iTunes search.
    func testDeezerShortLinkResolvesToTheEpisodeInThePublicFeed() async throws {
        try await assertResolves("deezer-fashion-neurosis")
    }

    func testAcastEpisodePageReadsTheShowFeedByItsSlug() async throws {
        try await assertResolves("acast-babbage-public")
    }

    func testAcastPageOfASubscribersOnlyEpisodeSaysSo() async throws {
        try await assertResolves("acast-ng-locked")
    }

    func testAppleEpisodeLinkStillResolvesFromTheLookup() async throws {
        try await assertResolves("apple-blindboy")
    }

    func testOvercastEpisodeLinkResolvesFromItsPageTitle() async throws {
        try await assertResolves("overcast-do-by-friday")
    }

    func testPocketCastsShareLinkResolvesFromItsRedirectAndShowNotes() async throws {
        try await assertResolves("pocketcasts-blindboy")
    }

    // MARK: - Honest refusals

    /// A Deezer episode with no public feed says so BY NAME, not "isn't a podcast feed".
    func testDeezerEpisodeWithNoPublicFeedNamesDeezer() async throws {
        let replay = try Replay(folder: "deezer-fashion-neurosis")
        replay.override = { url in
            url.host == "itunes.apple.com" ? Data(#"{"resultCount":0,"results":[]}"#.utf8) : nil
        }
        do {
            _ = try await PodcastImporter.resolve(replay.manifest.link, fetch: replay.fetch, redirect: replay.redirect)
            XCTFail("expected a refusal")
        } catch let refusal as PodcastRefusal {
            XCTAssertEqual(refusal, PodcastRefusal.appOnly("Deezer"))
            XCTAssertEqual(refusal.message, "Skrift can't read Deezer-only episodes: no public feed for this one turned up.")
        }
    }

    func testSpotifyEpisodeWithNoPublicFeedStillSaysSpotify() async throws {
        let replay = try Replay(folder: "spotify-ng-ai-doom")
        replay.override = { url in
            url.host == "itunes.apple.com" ? Data(#"{"resultCount":0,"results":[]}"#.utf8) : nil
        }
        do {
            _ = try await PodcastImporter.resolve(replay.manifest.link, fetch: replay.fetch, redirect: replay.redirect)
            XCTFail("expected a refusal")
        } catch let refusal as PodcastRefusal {
            XCTAssertEqual(refusal, PodcastRefusal.spotifyExclusive)
        }
    }

    // MARK: - Any web page (rel=alternate), short links

    func testWebPageWithAnRSSAlternateLinkFindsItsFeed() async throws {
        let feed = try Data(contentsOf: Self.root.appendingPathComponent("podcasts/het-uur-feed.xml"))
        let page = Data("""
        <!doctype html><html><head><title>NRC Het Uur</title>
        <link rel="stylesheet" href="/site.css">
        <link rel="alternate" type="application/rss+xml" title="Het Uur" href="/feeds/het-uur.rss">
        </head><body>podcast</body></html>
        """.utf8)
        let fetch: PodcastImporter.Fetch = { url in
            switch url.absoluteString {
            case "https://example.org/het-uur": return page
            case "https://example.org/feeds/het-uur.rss": return feed
            default: throw URLError(.notConnectedToInternet)
            }
        }
        let result = try await PodcastImporter.resolve("https://example.org/het-uur", fetch: fetch)
        guard case .chooseEpisode(let show) = result else { return XCTFail("expected a show to pick from") }
        XCTAssertEqual(show.title, "NRC Het Uur")
    }

    func testWebPageWithoutAFeedNamesTheSite() async throws {
        let fetch: PodcastImporter.Fetch = { _ in Data("<html><head><title>x</title></head><body></body></html>".utf8) }
        do {
            _ = try await PodcastImporter.resolve("https://example.org/post", fetch: fetch)
            XCTFail("expected a refusal")
        } catch let refusal as PodcastRefusal {
            XCTAssertEqual(refusal, PodcastRefusal.noFeedOnPage(host: "example.org"))
            XCTAssertTrue(refusal.message.contains("example.org"))
        }
    }

    func testShortLinkThatGoesNowhereNamesTheApp() async throws {
        let fetch: PodcastImporter.Fetch = { _ in throw URLError(.notConnectedToInternet) }
        let same: PodcastImporter.Redirect = { $0 }
        do {
            _ = try await PodcastImporter.resolve("https://link.deezer.com/s/abc123", fetch: fetch, redirect: same)
            XCTFail("expected a refusal")
        } catch let refusal as PodcastRefusal {
            XCTAssertEqual(refusal, PodcastRefusal.appOnly("Deezer"))
        }
    }

    // MARK: - Pure pieces

    func testClassifiesTheNewLinkKinds() {
        XCTAssertEqual(PodcastLink.classify("https://link.deezer.com/s/34GX09Z75In2EBkZKHjWB"),
                       .shortLink(URL(string: "https://link.deezer.com/s/34GX09Z75In2EBkZKHjWB")!))
        XCTAssertEqual(PodcastLink.classify("https://www.deezer.com/pt/episode/947688582?host=1"), .deezerEpisode(id: "947688582"))
        XCTAssertEqual(PodcastLink.classify("https://www.deezer.com/show/1234"), .deezerShow(id: "1234"))
        XCTAssertEqual(PodcastLink.classify("https://shows.acast.com/theeconomistbabbage/episodes/andrew-ng-on-the-ai-doom-delusion"),
                       .acast(show: "theeconomistbabbage", slug: "andrew-ng-on-the-ai-doom-delusion"))
        XCTAssertEqual(PodcastLink.classify("https://shows.acast.com/theeconomistbabbage"),
                       .acast(show: "theeconomistbabbage", slug: nil))
        XCTAssertEqual(PodcastLink.classify("https://play.acast.com/s/blindboy/the-slug"), .acast(show: "blindboy", slug: "the-slug"))
        XCTAssertEqual(PodcastLink.classify("https://overcast.fm/+HfJiJmHrg"), .overcast(URL(string: "https://overcast.fm/+HfJiJmHrg")!))
        XCTAssertEqual(PodcastLink.classify("https://overcast.fm/itunes1300577518/the-blindboy-podcast"),
                       .apple(showID: 1300577518, episodeID: nil))
        XCTAssertEqual(PodcastLink.classify("https://pca.st/episode/02dca6b7-7626-4699-bdeb-f9f2059f8df1"),
                       .pocketCasts(URL(string: "https://pca.st/episode/02dca6b7-7626-4699-bdeb-f9f2059f8df1")!))
        XCTAssertEqual(PodcastLink.classify("https://spotify.link/AbCdEf"), .shortLink(URL(string: "https://spotify.link/AbCdEf")!))
        XCTAssertEqual(PodcastLink.appName(forHost: "link.deezer.com"), "Deezer")
        XCTAssertEqual(PodcastLink.appName(forHost: "pca.st"), "Pocket Casts")
    }

    func testParserKeepsSubscriberOnlyItemsApartFromPlayableOnes() throws {
        let locked = try Data(contentsOf: Self.root.appendingPathComponent("podcast-links/acast-ng-locked/feed.xml"))
        let show = try PodcastFeedParser.parse(locked)
        XCTAssertTrue(show.lockedEpisodes.contains { $0.title == "Andrew Ng on the delusion of AI doom" && $0.pageSlug == "andrew-ng-on-the-ai-doom-delusion" })
        XCTAssertFalse(show.episodes.contains { $0.title.contains("Andrew Ng") })

        let open = try Data(contentsOf: Self.root.appendingPathComponent("podcast-links/acast-babbage-public/feed.xml"))
        let playable = try PodcastFeedParser.parse(open)
        XCTAssertEqual(playable.episodes.first { $0.pageSlug == "trailer-tocqueville-road-trip" }?.title, "Trailer: Tocqueville Road Trip")
    }

    func testPickMatchesARenamedEpisodeOnlyWhenTheDateAgrees() {
        let published = ISO8601DateFormatter().date(from: "2026-10-14T14:00:00Z")!
        let show = PodcastShow(title: "Babbage", author: "", artworkURL: nil, episodes: [
            PodcastEpisode(title: "Andrew Ng on the delusion of AI doom", guid: "g1", publishedAt: published, duration: nil,
                           enclosureURL: URL(string: "https://example.org/a.mp3")!, mimeType: nil, artworkURL: nil, summary: ""),
        ])
        let close = PodcastHint(guid: nil, title: "Andrew Ng on the AI doom delusion", publishedAt: published.addingTimeInterval(86_400))
        XCTAssertEqual(PodcastPick.episode(in: show, hint: close)?.guid, "g1")
        let far = PodcastHint(guid: nil, title: "Andrew Ng on the AI doom delusion", publishedAt: published.addingTimeInterval(5 * 86_400))
        XCTAssertNil(PodcastPick.episode(in: show, hint: far))
        let undated = PodcastHint(guid: nil, title: "Andrew Ng on the AI doom delusion")
        XCTAssertNil(PodcastPick.episode(in: show, hint: undated))
    }

    func testPageMetaForSpotifyAndOvercast() throws {
        let spotify = try Data(contentsOf: Self.root.appendingPathComponent("podcast-links/spotify-ng-ai-doom/page.html"))
        let info = PodcastResolver.spotifyPage(fromMeta: PodcastResolver.htmlMeta(spotify))
        XCTAssertEqual(info.show, "Economist Podcasts")
        XCTAssertEqual(info.released, ISO8601DateFormatter().date(from: "2026-10-14T14:00:00Z"))

        let overcast = try Data(contentsOf: Self.root.appendingPathComponent("podcast-links/overcast-do-by-friday/page.html"))
        let named = PodcastResolver.overcastPage(fromMeta: PodcastResolver.htmlMeta(overcast))
        XCTAssertEqual(named?.show, "Do By Friday")
        XCTAssertEqual(named?.episode, "Dingaling-Rich Environment")
    }

    func testShowSearchTermsAddThePublisherVariants() {
        XCTAssertEqual(PodcastResolver.showSearchTerms(for: "Economist Podcasts"),
                       ["Economist Podcasts", "Economist Podcasts from The Economist", "Economist Podcasts from Economist"])
        XCTAssertEqual(PodcastResolver.showSearchTerms(for: "Blindboy"), ["Blindboy"])
    }
}
