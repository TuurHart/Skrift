import Foundation

/// Q353 (D90, D144): a podcast episode enters the Library through the show's PUBLIC RSS feed (an
/// audio enclosure), never by scraping a player page. This file is the pure half: feed parse, link
/// classification, link-to-feed resolution and the episode pick. The network half is `PodcastImporter`.

// MARK: - Refusals

/// A link Skrift will not take, with ONE plain sentence for the person (D14: a broken feature is
/// worse than a missing one).
struct PodcastRefusal: Error, Equatable, LocalizedError {
    let message: String
    var errorDescription: String? { message }

    static let notAFeed = PodcastRefusal(message: "That link isn't a podcast feed Skrift can read.")
    static let noPublicFeed = PodcastRefusal(message: "This show has no public feed, so Skrift can't take it.")
    static let spotifyExclusive = PodcastRefusal(message: "This episode is only on Spotify and has no public feed, so Skrift can't take it.")
    static let subscribersOnly = PodcastRefusal(message: "That episode is in the show's feed, but it is for subscribers only, so Skrift can't download it.")
    static let episodeNotInFeed = PodcastRefusal(message: "That episode isn't in the show's public feed any more.")
    static let notALink = PodcastRefusal(message: "Paste a podcast link, from Apple Podcasts, Spotify or a feed address.")
    static let noAudio = PodcastRefusal(message: "That episode has no audio file Skrift can download.")
}

// MARK: - Feed model

struct PodcastEpisode: Equatable, Sendable, Identifiable {
    var title: String
    var guid: String
    var publishedAt: Date?
    var duration: TimeInterval?
    var enclosureURL: URL
    var mimeType: String?
    var artworkURL: URL?
    var summary: String

    var id: String { guid.isEmpty ? enclosureURL.absoluteString : guid }
}

struct PodcastShow: Equatable, Sendable {
    var title: String
    var author: String
    var artworkURL: URL?
    /// Feed order, which is newest first for every real feed; `PodcastPick` never relies on it
    /// for anything but the "no hint" default.
    var episodes: [PodcastEpisode]
}

// MARK: - Parser

enum PodcastFeedParser {
    static func parse(_ data: Data) throws -> PodcastShow {
        let handler = FeedHandler()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        parser.shouldProcessNamespaces = false
        guard parser.parse(), handler.sawChannel else { throw PodcastRefusal.notAFeed }
        return PodcastShow(
            title: handler.showTitle.trimmed,
            author: handler.showAuthor.trimmed,
            artworkURL: handler.showArtwork,
            episodes: handler.episodes
        )
    }

    /// `HH:MM:SS`, `MM:SS` or plain seconds.
    static func parseDuration(_ raw: String) -> TimeInterval? {
        let parts = raw.trimmed.split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    static func parseDate(_ raw: String) -> Date? {
        let text = raw.trimmed
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z",
                       "EEE, d MMM yyyy HH:mm:ss Z"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return ISO8601DateFormatter().date(from: text)
    }

    /// Plain text from the feed's HTML description: tags dropped, entities left to the XML layer.
    static func plainText(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: "<br\\s*/?>|</p>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return noTags.trimmed
    }

    private final class FeedHandler: NSObject, XMLParserDelegate {
        var sawChannel = false
        var showTitle = ""
        var showAuthor = ""
        var showArtwork: URL?
        var episodes: [PodcastEpisode] = []

        private var path: [String] = []
        private var text = ""
        private var item: ItemDraft?

        private struct ItemDraft {
            var title = ""
            var guid = ""
            var pubDate = ""
            var duration = ""
            var description = ""
            var summary = ""
            var artwork: URL?
            var enclosureURL: URL?
            var mime: String?
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes attrs: [String: String] = [:]) {
            path.append(name)
            text = ""
            switch name {
            case "channel": sawChannel = true
            case "item": item = ItemDraft()
            case "itunes:image":
                guard let href = attrs["href"], let url = URL(string: href) else { break }
                if item != nil { item?.artwork = url } else if path.count <= 3 { showArtwork = showArtwork ?? url }
            case "enclosure":
                guard item != nil, let raw = attrs["url"], let url = URL(string: raw) else { break }
                let type = attrs["type"]?.lowercased()
                let isAudio = type?.hasPrefix("audio") == true
                    || (type == nil && ["mp3", "m4a", "aac", "wav"].contains(url.pathExtension.lowercased()))
                if isAudio, item?.enclosureURL == nil {
                    item?.enclosureURL = url
                    item?.mime = type
                }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            defer { path.removeLast(); text = "" }
            let parent = path.dropLast().last
            if item != nil {
                switch name {
                case "title" where parent == "item": item?.title = text.trimmed
                case "guid": item?.guid = text.trimmed
                case "pubDate": item?.pubDate = text
                case "itunes:duration": item?.duration = text
                case "description": item?.description = text
                case "itunes:summary": item?.summary = text
                case "item": finishItem()
                default: break
                }
                return
            }
            // Channel level (items already handled above).
            switch name {
            case "title" where parent == "channel": showTitle = text
            case "itunes:author" where parent == "channel": showAuthor = text
            case "url" where parent == "image":
                if showArtwork == nil { showArtwork = URL(string: text.trimmed) }
            default: break
            }
        }

        private func finishItem() {
            defer { item = nil }
            guard let d = item, let enclosure = d.enclosureURL else { return }
            let body = d.description.trimmed.isEmpty ? d.summary : d.description
            episodes.append(PodcastEpisode(
                title: d.title,
                guid: d.guid,
                publishedAt: PodcastFeedParser.parseDate(d.pubDate),
                duration: PodcastFeedParser.parseDuration(d.duration),
                enclosureURL: enclosure,
                mimeType: d.mime,
                artworkURL: d.artwork,
                summary: PodcastFeedParser.plainText(body)
            ))
        }
    }
}

// MARK: - Episode pick

enum PodcastPick {
    /// The feed episode a link named. GUID first, then the normalised title (case, accents and
    /// punctuation ignored; a title may carry a trailing " | Show" the other side lacks). With no
    /// hint at all the newest episode. A hint that matches nothing returns nil, never "the newest":
    /// importing the wrong episode silently would be worse than saying so.
    static func episode(in show: PodcastShow, guid: String?, title: String?) -> PodcastEpisode? {
        if guid == nil, title == nil { return show.episodes.first }
        if let guid, !guid.isEmpty, let hit = show.episodes.first(where: { $0.guid == guid }) { return hit }
        if let title {
            let wanted = normalise(title)
            guard wanted.count >= 8 else { return nil }
            if let exact = show.episodes.first(where: { normalise($0.title) == wanted }) { return exact }
            return show.episodes.first {
                let n = normalise($0.title)
                return n.hasPrefix(wanted) || wanted.hasPrefix(n)
            }
        }
        return nil
    }

    /// Lowercase, accents folded, every run of non-alphanumerics a single space.
    static func normalise(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let words = folded.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(words).split(separator: " ").joined(separator: " ")
    }
}

// MARK: - Links

enum PodcastLink: Equatable, Sendable {
    case apple(showID: Int, episodeID: Int?)
    case spotifyEpisode(id: String)
    case spotifyShow(id: String)
    case feed(URL)

    /// What a pasted string is, or nil when it is not a web link at all.
    static func classify(_ raw: String) -> PodcastLink? {
        let text = raw.trimmed
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if host == "podcasts.apple.com" || host == "itunes.apple.com" {
            guard let idPart = parts.last(where: { $0.hasPrefix("id") && Int($0.dropFirst(2)) != nil }),
                  let show = Int(idPart.dropFirst(2)) else { return nil }
            let episode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "i" }?.value.flatMap { Int($0) }
            return .apple(showID: show, episodeID: episode)
        }
        if host == "open.spotify.com" || host == "spotify.link" {
            if let i = parts.firstIndex(of: "episode"), parts.indices.contains(i + 1) {
                return .spotifyEpisode(id: parts[i + 1])
            }
            if let i = parts.firstIndex(of: "show"), parts.indices.contains(i + 1) {
                return .spotifyShow(id: parts[i + 1])
            }
            return nil
        }
        return .feed(url)
    }
}

// MARK: - Resolution (pure; the importer does the fetching)

/// What a link says about WHICH episode, matched later against the feed.
struct PodcastHint: Equatable, Sendable {
    var guid: String?
    var title: String?
}

struct PodcastMatch: Equatable, Sendable {
    var feedURL: URL
    var hint: PodcastHint
    var showName: String
}

enum PodcastResolver {
    // MARK: URLs to fetch

    static func lookupURL(for link: PodcastLink) -> URL? {
        guard case .apple(let show, _) = link else { return nil }
        return URL(string: "https://itunes.apple.com/lookup?id=\(show)&entity=podcast")
    }

    /// The show's recent episodes (Apple's `i=` is an episode track id, resolved against these).
    static func episodeLookupURL(showID: Int) -> URL? {
        URL(string: "https://itunes.apple.com/lookup?id=\(showID)&entity=podcastEpisode&limit=200")
    }

    static func oEmbedURL(for link: PodcastLink) -> URL? {
        switch link {
        case .spotifyEpisode(let id): URL(string: "https://open.spotify.com/oembed?url=https://open.spotify.com/episode/\(id)")
        case .spotifyShow(let id): URL(string: "https://open.spotify.com/oembed?url=https://open.spotify.com/show/\(id)")
        case .apple, .feed: nil
        }
    }

    static func searchURL(term: String, entity: String) -> URL? {
        var c = URLComponents(string: "https://itunes.apple.com/search")
        c?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: "10"),
        ]
        return c?.url
    }

    // MARK: Responses

    private static func results(_ data: Data) -> [[String: Any]] {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["results"] as? [[String: Any]] ?? []
    }

    /// Apple lookup of a show → its public feed. A show with no `feedUrl` (Apple-only or paid) is refused.
    static func feedURL(fromAppleLookup data: Data) throws -> URL {
        for r in results(data) {
            if let raw = r["feedUrl"] as? String, let url = URL(string: raw), url.scheme?.hasPrefix("http") == true {
                return url
            }
        }
        throw PodcastRefusal.noPublicFeed
    }

    /// Apple episode lookup + the `i=` track id → the guid and title to find in the feed.
    static func appleEpisodeHint(fromLookup data: Data, trackID: Int) -> PodcastHint? {
        for r in results(data) where (r["trackId"] as? Int) == trackID && r["wrapperType"] as? String == "podcastEpisode" {
            return PodcastHint(guid: r["episodeGuid"] as? String, title: r["trackName"] as? String)
        }
        return nil
    }

    /// Spotify's oEmbed `title`: the episode title for an episode link, the show name for a show link.
    static func spotifyTitle(fromOEmbed data: Data) throws -> String {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let title = (json["title"] as? String)?.trimmed, !title.isEmpty else {
            throw PodcastRefusal.spotifyExclusive
        }
        return title
    }

    /// iTunes episode search for a Spotify episode title: a result whose title is the same title is
    /// the episode's public feed. No match means the episode lives only on Spotify.
    static func spotifyMatch(title: String, searchResults data: Data) throws -> PodcastMatch {
        let wanted = PodcastPick.normalise(title)
        for r in results(data) {
            guard let name = r["trackName"] as? String, PodcastPick.normalise(name) == wanted,
                  let raw = r["feedUrl"] as? String, let feed = URL(string: raw) else { continue }
            return PodcastMatch(feedURL: feed,
                                hint: PodcastHint(guid: r["episodeGuid"] as? String, title: name),
                                showName: r["collectionName"] as? String ?? "")
        }
        throw PodcastRefusal.spotifyExclusive
    }

    /// iTunes show search for a Spotify show name.
    static func spotifyShowMatch(name: String, searchResults data: Data) throws -> PodcastMatch {
        let wanted = PodcastPick.normalise(name)
        for r in results(data) {
            guard let show = r["collectionName"] as? String, PodcastPick.normalise(show) == wanted,
                  let raw = r["feedUrl"] as? String, let feed = URL(string: raw) else { continue }
            return PodcastMatch(feedURL: feed, hint: PodcastHint(guid: nil, title: nil), showName: show)
        }
        throw PodcastRefusal.spotifyExclusive
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
