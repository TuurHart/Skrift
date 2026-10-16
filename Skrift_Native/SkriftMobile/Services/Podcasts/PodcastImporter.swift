import Foundation

/// What a pasted link came to: one episode ready to download, or a show whose episode the person
/// still has to pick (a show link, or a raw feed address).
enum PodcastResolution: Sendable {
    case episode(PodcastShow, PodcastEpisode)
    case chooseEpisode(PodcastShow)
}

/// Q353: the network half. Resolves a link to a public feed (D90), downloads the chosen episode's
/// MP3 enclosure into the Library as kind `episode`. Fetching is injected, so the resolution path
/// runs on saved responses in tests; nothing here ever reads a player page.
enum PodcastImporter {
    typealias Fetch = @Sendable (URL) async throws -> Data

    /// Plain `URLSession` fetch with a short timeout; non-200 answers are an error with a sentence.
    static let liveFetch: Fetch = { url in
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Skrift", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PodcastRefusal.notAFeed
        }
        return data
    }

    /// Follows redirects by hand and returns the address the chain ends on (never the body, never an
    /// error for a final 403: Pocket Casts' share page refuses scripts but the address is the answer).
    typealias Redirect = @Sendable (URL) async throws -> URL

    private final class StopRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static let liveRedirect: Redirect = { url in
        var current = url
        for _ in 0..<6 {
            var request = URLRequest(url: current, timeoutInterval: 20)
            request.setValue("Skrift", forHTTPHeaderField: "User-Agent")
            let session = URLSession(configuration: .ephemeral, delegate: StopRedirects(), delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (300..<400).contains(http.statusCode),
                  let location = http.value(forHTTPHeaderField: "Location"),
                  let next = URL(string: location, relativeTo: current)?.absoluteURL else { return current }
            current = next
        }
        return current
    }

    /// One resolver chain for every pasted podcast link (D90, Q476): the episode's public feed is
    /// found by name through the iTunes Search API, never by scraping a player.
    static func resolve(_ input: String, fetch: Fetch = liveFetch,
                        redirect: Redirect = liveRedirect) async throws -> PodcastResolution {
        guard let link = PodcastLink.classify(input) else { throw PodcastRefusal.notALink }
        return try await resolve(link: link, fetch: fetch, redirect: redirect, hops: 0)
    }

    private static func resolve(link: PodcastLink, fetch: Fetch, redirect: Redirect, hops: Int) async throws -> PodcastResolution {
        switch link {
        case .feed(let url):
            return try await resolveFeedOrPage(url, fetch: fetch)

        case .apple(let showID, let episodeID):
            guard let lookup = PodcastResolver.lookupURL(for: link) else { throw PodcastRefusal.notALink }
            let feedURL = try PodcastResolver.feedURL(fromAppleLookup: try await fetch(lookup))
            let show = try PodcastFeedParser.parse(try await fetch(feedURL))
            guard let episodeID else { return .chooseEpisode(show) }
            guard let url = PodcastResolver.episodeLookupURL(showID: showID),
                  let hint = PodcastResolver.appleEpisodeHint(fromLookup: try await fetch(url), trackID: episodeID),
                  let episode = PodcastPick.episode(in: show, guid: hint.guid, title: hint.title) else {
                throw PodcastRefusal.episodeNotInFeed
            }
            return .episode(show, episode)

        case .shortLink(let url):
            let final = try await redirect(url)
            guard hops < 2, final != url, let next = PodcastLink.classify(final.absoluteString) else {
                throw PodcastRefusal.appOnly(PodcastLink.appName(forHost: url.host ?? ""))
            }
            if case .shortLink = next { throw PodcastRefusal.appOnly(PodcastLink.appName(forHost: url.host ?? "")) }
            return try await resolve(link: next, fetch: fetch, redirect: redirect, hops: hops + 1)

        case .spotifyEpisode(let id):
            guard let oembed = PodcastResolver.oEmbedURL(for: link) else { throw PodcastRefusal.notALink }
            let title = try PodcastResolver.spotifyTitle(fromOEmbed: try await fetch(oembed))
            // The episode page's public meta names the show and the release date (no login, no scraping
            // past the meta tags); a page that will not load only costs the show-name search.
            var meta: [String: String] = [:]
            if let page = URL(string: "https://open.spotify.com/episode/\(id)"), let data = try? await fetch(page) {
                meta = PodcastResolver.htmlMeta(data)
            }
            let info = PodcastResolver.spotifyPage(fromMeta: meta)
            return try await resolveByNames(episodeTitle: title, showName: info.show, published: info.released,
                                            exclusive: PodcastRefusal.spotifyExclusive, fetch: fetch)

        case .spotifyShow:
            guard let oembed = PodcastResolver.oEmbedURL(for: link) else { throw PodcastRefusal.notALink }
            let name = try PodcastResolver.spotifyTitle(fromOEmbed: try await fetch(oembed))
            return try await resolveShowByName(name, exclusive: PodcastRefusal.spotifyExclusive, fetch: fetch)

        case .deezerEpisode(let id):
            guard let page = URL(string: "https://www.deezer.com/episode/\(id)"),
                  let named = PodcastResolver.deezerPage(fromMeta: PodcastResolver.htmlMeta(try await fetch(page))) else {
                throw PodcastRefusal.appOnly("Deezer")
            }
            return try await resolveByNames(episodeTitle: named.episode, showName: named.show, published: nil,
                                            exclusive: PodcastRefusal.appOnly("Deezer"), fetch: fetch)

        case .deezerShow(let id):
            guard let page = URL(string: "https://www.deezer.com/show/\(id)"),
                  let name = PodcastResolver.htmlMeta(try await fetch(page))["og:title"], !name.isEmpty else {
                throw PodcastRefusal.appOnly("Deezer")
            }
            return try await resolveShowByName(name, exclusive: PodcastRefusal.appOnly("Deezer"), fetch: fetch)

        case .overcast(let url):
            guard let named = PodcastResolver.overcastPage(fromMeta: PodcastResolver.htmlMeta(try await fetch(url))) else {
                throw PodcastRefusal.appOnly("Overcast")
            }
            return try await resolveByNames(episodeTitle: named.episode, showName: named.show, published: nil,
                                            exclusive: PodcastRefusal.appOnly("Overcast"), fetch: fetch)

        case .pocketCasts(let url):
            let exclusive = PodcastRefusal.appOnly("Pocket Casts")
            var address = url
            if PodcastResolver.pocketCastsRoute(address) == nil { address = try await redirect(url) }
            guard let route = PodcastResolver.pocketCastsRoute(address) else { throw exclusive }
            guard let episodeUUID = route.episodeUUID else {
                return try await resolveShowByName(route.showName, exclusive: exclusive, fetch: fetch)
            }
            var title = route.episodeSlug?.replacingOccurrences(of: "-", with: " ") ?? ""
            var published: Date?
            if let notes = PodcastResolver.pocketCastsNotesURL(podcastUUID: route.podcastUUID), let data = try? await fetch(notes),
               let episode = PodcastResolver.pocketCastsEpisode(fromNotes: data, uuid: episodeUUID) {
                title = episode.title
                published = episode.published
            }
            guard !title.isEmpty else { throw exclusive }
            return try await resolveByNames(episodeTitle: title, showName: route.showName, published: published,
                                            exclusive: exclusive, fetch: fetch)

        case .acast(let show, let slug):
            guard let feedURL = PodcastResolver.acastFeedURL(show: show) else { throw PodcastRefusal.notALink }
            let parsed: PodcastShow
            do {
                parsed = try PodcastFeedParser.parse(try await fetch(feedURL))
            } catch is PodcastRefusal {
                // The slug was not a feed address: fall back to whatever the page itself names.
                guard let page = URL(string: "https://shows.acast.com/\(show)") else { throw PodcastRefusal.notAFeed }
                return try await resolveFeedOrPage(page, fetch: fetch)
            }
            guard let slug else { return .chooseEpisode(parsed) }
            let hint = PodcastHint(guid: nil, title: nil, publishedAt: nil, slug: slug)
            if let episode = PodcastPick.episode(in: parsed, hint: hint) { return .episode(parsed, episode) }
            if PodcastPick.lockedEpisode(in: parsed, hint: hint) != nil { throw PodcastRefusal.subscribersOnly }
            throw PodcastRefusal.episodeNotInFeed
        }
    }

    // MARK: Name chains

    /// Feeds tried per link: a Spotify show can be listed under a publisher umbrella, so a few
    /// look-alikes are read, but never a long tail.
    private static let feedBudget = 5

    /// An episode known by title (and maybe show and date) to its public feed: the iTunes episode
    /// search first (the same title, in the named show), then the show search for the named show and
    /// a look through those feeds. No luck: `exclusive`, naming the app.
    static func resolveByNames(episodeTitle: String, showName: String?, published: Date?,
                               exclusive: PodcastRefusal, fetch: Fetch) async throws -> PodcastResolution {
        var tried = Set<URL>()
        var lockedHit = false
        var feedWithoutEpisode = false
        var exactMatchMissing = false

        /// Reads one feed and looks for the episode in it.
        func visit(_ feed: URL, guid: String?, requireDate: Bool) async throws -> PodcastResolution? {
            guard tried.insert(feed).inserted, tried.count <= feedBudget else { return nil }
            let show: PodcastShow
            do { show = try PodcastFeedParser.parse(try await fetch(feed)) } catch is PodcastRefusal { return nil }
            let hint = PodcastHint(guid: guid, title: episodeTitle, publishedAt: published, slug: nil)
            if let episode = PodcastPick.episode(in: show, hint: hint),
               !requireDate || PodcastPick.within(episode.publishedAt, published) {
                return .episode(show, episode)
            }
            if let locked = PodcastPick.lockedEpisode(in: show, hint: hint),
               !requireDate || PodcastPick.within(locked.publishedAt, published) {
                lockedHit = true
                return nil
            }
            feedWithoutEpisode = true
            return nil
        }

        if let url = PodcastResolver.searchURL(term: episodeTitle, entity: "podcastEpisode") {
            let data = try await fetch(url)
            var matches = PodcastResolver.episodeMatches(title: episodeTitle, showName: showName, searchResults: data)
            var requireDate = false
            if matches.isEmpty, published != nil {
                // The show is listed under another name; the release date has to vouch for it.
                matches = PodcastResolver.episodeMatches(title: episodeTitle, showName: nil, searchResults: data)
                requireDate = true
            }
            for match in matches.prefix(3) {
                if let found = try await visit(match.feedURL, guid: match.hint.guid, requireDate: requireDate) { return found }
                if lockedHit { throw PodcastRefusal.subscribersOnly }
            }
            exactMatchMissing = !matches.isEmpty && feedWithoutEpisode && !requireDate
        }

        if let showName, !showName.isEmpty {
            for term in PodcastResolver.showSearchTerms(for: showName) {
                guard let url = PodcastResolver.searchURL(term: term, entity: "podcast") else { continue }
                let candidates = PodcastResolver.showFeedCandidates(for: showName, searchResults: try await fetch(url))
                for feed in candidates {
                    if let found = try await visit(feed, guid: nil, requireDate: false) { return found }
                    if lockedHit { throw PodcastRefusal.subscribersOnly }
                }
            }
        }
        if lockedHit { throw PodcastRefusal.subscribersOnly }
        throw exactMatchMissing ? PodcastRefusal.episodeNotInFeed : exclusive
    }

    /// A show known by name to its public feed, for the person to pick an episode from.
    static func resolveShowByName(_ name: String, exclusive: PodcastRefusal, fetch: Fetch) async throws -> PodcastResolution {
        var tried = Set<URL>()
        for term in PodcastResolver.showSearchTerms(for: name) {
            guard let url = PodcastResolver.searchURL(term: term, entity: "podcast") else { continue }
            for feed in PodcastResolver.showFeedCandidates(for: name, searchResults: try await fetch(url)).prefix(2)
            where tried.insert(feed).inserted && tried.count <= feedBudget {
                do { return .chooseEpisode(try PodcastFeedParser.parse(try await fetch(feed))) } catch is PodcastRefusal { continue }
            }
        }
        throw exclusive
    }

    /// A feed address, or a web page that names its feed (`<link rel="alternate" type="application/rss+xml">`).
    static func resolveFeedOrPage(_ url: URL, fetch: Fetch) async throws -> PodcastResolution {
        let data = try await fetch(url)
        if !PodcastResolver.looksLikeHTML(data) { return .chooseEpisode(try PodcastFeedParser.parse(data)) }
        guard let feedURL = PodcastResolver.alternateFeedURL(inHTML: data, base: url) else {
            throw PodcastRefusal.noFeedOnPage(host: url.host ?? url.absoluteString)
        }
        let show = try PodcastFeedParser.parse(try await fetch(feedURL))
        // A page about one episode names it in its title: take that episode, else let the person pick.
        if let title = PodcastResolver.htmlMeta(data)["og:title"],
           let episode = PodcastPick.episode(in: show, hint: PodcastHint(guid: nil, title: title)) {
            return .episode(show, episode)
        }
        return .chooseEpisode(show)
    }

    /// The Library record for a downloaded episode: `author` carries the show, `publishedAt` the
    /// feed date. Pure, so the shape is unit-tested.
    static func makeBook(show: PodcastShow, episode: PodcastEpisode, filename: String, duration: TimeInterval,
                         hasCover: Bool, id: UUID = UUID()) -> Audiobook {
        var book = Audiobook(
            id: id,
            files: [filename],
            fileDurations: [duration],
            title: episode.title,
            author: show.title,
            duration: duration,
            hasCover: hasCover
        )
        book.kind = .episode
        book.publishedAt = episode.publishedAt
        return book
    }

    /// Downloads the enclosure and artwork into `libraryDirectory/<id>/` and returns the record
    /// (not yet added to the store). The audio goes through the book importer so duration and
    /// playability are checked the same way as a book from Files.
    static func download(show: PodcastShow, episode: PodcastEpisode, libraryDirectory: URL,
                         fetch: Fetch = liveFetch) async throws -> Audiobook {
        let ext = ["mp3", "m4a", "aac", "wav"].contains(episode.enclosureURL.pathExtension.lowercased())
            ? episode.enclosureURL.pathExtension.lowercased()
            : (episode.mimeType?.contains("mp4") == true || episode.mimeType?.contains("m4a") == true ? "m4a" : "mp3")
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("podcast-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let audioTemp = scratch.appendingPathComponent("episode.\(ext)")
        var request = URLRequest(url: episode.enclosureURL, timeoutInterval: 60)
        request.setValue("Skrift", forHTTPHeaderField: "User-Agent")
        let (downloaded, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: downloaded)
            throw PodcastRefusal.noAudio
        }
        try FileManager.default.moveItem(at: downloaded, to: audioTemp)

        let pending = try await AudiobookImporter.importBook(from: [audioTemp], libraryDirectory: libraryDirectory)
        let id = pending.book.id
        let folder = libraryDirectory.appendingPathComponent(id.uuidString, isDirectory: true)

        // Artwork: the episode's, else the show's. Failing to get it only leaves the placeholder.
        var hasCover = pending.book.hasCover
        if let art = episode.artworkURL ?? show.artworkURL, let data = try? await fetch(art), !data.isEmpty {
            do {
                try data.write(to: folder.appendingPathComponent("cover.jpg"))
                hasCover = true
            } catch { /* keep any embedded cover */ }
        }
        return makeBook(show: show, episode: episode, filename: pending.book.audioFilename,
                        duration: pending.book.duration, hasCover: hasCover, id: id)
    }
}
