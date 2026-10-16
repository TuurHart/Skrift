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
    /// A player-exclusive episode, named after the app so the person knows which link failed.
    static func appOnly(_ app: String) -> PodcastRefusal {
        PodcastRefusal(message: "Skrift can't read \(app)-only episodes: no public feed for this one turned up.")
    }
    static func noFeedOnPage(host: String) -> PodcastRefusal {
        PodcastRefusal(message: "Skrift can't read links from \(host): the page names no public podcast feed.")
    }
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
    /// Acast's `acast:episodeUrl` (the last part of the episode page address), "" for other hosts.
    var pageSlug: String = ""

    var id: String { guid.isEmpty ? enclosureURL.absoluteString : guid }
}

/// An episode the feed lists but gives no audio file for: a subscriber-only (premium) item. Kept so a
/// link to it says "subscribers only" instead of "not in the feed" (Q476).
struct PodcastLockedEpisode: Equatable, Sendable {
    var title: String
    var guid: String
    var publishedAt: Date?
    var pageSlug: String
}

struct PodcastShow: Equatable, Sendable {
    var title: String
    var author: String
    var artworkURL: URL?
    /// Feed order, which is newest first for every real feed; `PodcastPick` never relies on it
    /// for anything but the "no hint" default.
    var episodes: [PodcastEpisode]
    var lockedEpisodes: [PodcastLockedEpisode] = []
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
            episodes: handler.episodes,
            lockedEpisodes: handler.lockedEpisodes
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
        var lockedEpisodes: [PodcastLockedEpisode] = []

        private var path: [String] = []
        private var text = ""
        private var item: ItemDraft?
        private var locked: LockedDraft?

        private struct LockedDraft {
            var title = ""
            var guid = ""
            var pubDate = ""
            var slug = ""
        }

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
            var slug = ""
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes attrs: [String: String] = [:]) {
            path.append(name)
            text = ""
            switch name {
            case "channel": sawChannel = true
            case "item": item = ItemDraft()
            case "podaccess:item" where item == nil: locked = LockedDraft()
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
            if locked != nil {
                switch name {
                case "itunes:title" where parent == "podaccess:item": locked?.title = text.trimmed
                case "guid": locked?.guid = text.trimmed
                case "pubDate": locked?.pubDate = text
                case "acast:episodeUrl": locked?.slug = text.trimmed
                case "podaccess:item":
                    if let d = locked, !d.title.isEmpty {
                        lockedEpisodes.append(PodcastLockedEpisode(
                            title: d.title, guid: d.guid,
                            publishedAt: PodcastFeedParser.parseDate(d.pubDate), pageSlug: d.slug))
                    }
                    locked = nil
                default: break
                }
                return
            }
            if item != nil {
                switch name {
                case "title" where parent == "item": item?.title = text.trimmed
                case "guid": item?.guid = text.trimmed
                case "pubDate": item?.pubDate = text
                case "itunes:duration": item?.duration = text
                case "description": item?.description = text
                case "itunes:summary": item?.summary = text
                case "acast:episodeUrl": item?.slug = text.trimmed
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
                summary: PodcastFeedParser.plainText(body),
                pageSlug: d.slug
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

    /// Q476: the feed episode a link's hint names (GUID, Acast page slug, then title with the date
    /// as tie-break). A hint that names nothing in the feed returns nil, never "the newest".
    static func episode(in show: PodcastShow, hint: PodcastHint) -> PodcastEpisode? {
        let entries = show.episodes.map { Entry(title: $0.title, guid: $0.guid, date: $0.publishedAt, slug: $0.pageSlug) }
        return match(entries, hint: hint).map { show.episodes[$0] }
    }

    /// Same match against the feed's subscriber-only items (no audio file in a public feed).
    static func lockedEpisode(in show: PodcastShow, hint: PodcastHint) -> PodcastLockedEpisode? {
        let entries = show.lockedEpisodes.map { Entry(title: $0.title, guid: $0.guid, date: $0.publishedAt, slug: $0.pageSlug) }
        return match(entries, hint: hint).map { show.lockedEpisodes[$0] }
    }

    /// Both dates known and no more than two days apart.
    static func within(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.timeIntervalSince(b)) <= dateWindow
    }

    private struct Entry {
        var title: String
        var guid: String
        var date: Date?
        var slug: String
    }

    private static let dateWindow: TimeInterval = 2 * 24 * 3600

    private static func match(_ entries: [Entry], hint: PodcastHint) -> Int? {
        if let guid = hint.guid, !guid.isEmpty, let i = entries.firstIndex(where: { $0.guid == guid }) { return i }
        if let slug = hint.slug, !slug.isEmpty, let i = entries.firstIndex(where: { $0.slug == slug }) { return i }
        guard let title = hint.title else { return nil }
        let wanted = normalise(title)
        guard wanted.count >= 8 else { return nil }
        func near(_ i: Int) -> Bool {
            guard let a = hint.publishedAt, let b = entries[i].date else { return true }
            return abs(a.timeIntervalSince(b)) <= dateWindow
        }
        let exact = entries.indices.filter { normalise(entries[$0].title) == wanted }
        if let i = exact.first(where: near) ?? exact.first { return i }
        let prefixed = entries.indices.filter {
            let n = normalise(entries[$0].title)
            return !n.isEmpty && (n.hasPrefix(wanted) || wanted.hasPrefix(n))
        }
        if let i = prefixed.first(where: near) ?? prefixed.first { return i }
        // Last resort: mostly the same words, and the date vouches for it (a renamed episode).
        guard let hinted = hint.publishedAt else { return nil }
        let wantedWords = Set(wanted.split(separator: " "))
        return entries.indices.first { i in
            guard let d = entries[i].date, abs(hinted.timeIntervalSince(d)) <= dateWindow else { return false }
            let words = Set(normalise(entries[i].title).split(separator: " "))
            let union = wantedWords.union(words).count
            return union > 0 && Double(wantedWords.intersection(words).count) / Double(union) >= 0.6
        }
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
    case deezerEpisode(id: String)
    case deezerShow(id: String)
    /// Acast's own page; the show's slug doubles as its public feed address.
    case acast(show: String, slug: String?)
    case overcast(URL)
    case pocketCasts(URL)
    /// A share-sheet short link that redirects to one of the others.
    case shortLink(URL)
    /// Anything else: a feed address, or a web page that may name its feed.
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
        if host == "open.spotify.com" {
            if let i = parts.firstIndex(of: "episode"), parts.indices.contains(i + 1) {
                return .spotifyEpisode(id: parts[i + 1])
            }
            if let i = parts.firstIndex(of: "show"), parts.indices.contains(i + 1) {
                return .spotifyShow(id: parts[i + 1])
            }
            return nil
        }
        // Share-sheet short links: followed to their real address, then classified again.
        if host == "spotify.link" || host == "link.deezer.com" || host == "deezer.page.link" {
            return parts.isEmpty ? nil : .shortLink(url)
        }
        if host == "deezer.com" || host.hasSuffix(".deezer.com") {
            if let i = parts.firstIndex(of: "episode"), parts.indices.contains(i + 1), Int(parts[i + 1]) != nil {
                return .deezerEpisode(id: parts[i + 1])
            }
            if let i = parts.firstIndex(of: "show"), parts.indices.contains(i + 1), Int(parts[i + 1]) != nil {
                return .deezerShow(id: parts[i + 1])
            }
            return nil
        }
        if host == "shows.acast.com" || host == "play.acast.com" {
            // shows.acast.com/<show>/episodes/<slug>, shows.acast.com/<show>, play.acast.com/s/<show>/<slug>
            var rest = parts
            if host == "play.acast.com", rest.first == "s" { rest.removeFirst() }
            guard let show = rest.first else { return nil }
            if host == "shows.acast.com" {
                if rest.count >= 3, rest[1] == "episodes" { return .acast(show: show, slug: rest[2]) }
                return .acast(show: show, slug: nil)
            }
            return .acast(show: show, slug: rest.count >= 2 ? rest[1] : nil)
        }
        if host == "overcast.fm" {
            if let first = parts.first, first.hasPrefix("+") { return .overcast(url) }
            if let first = parts.first, first.hasPrefix("itunes"), let id = Int(first.dropFirst(6)) {
                return .apple(showID: id, episodeID: nil)
            }
            return nil
        }
        if host == "pca.st" || host == "pocketcasts.com" || host == "play.pocketcasts.com" {
            return parts.isEmpty ? nil : .pocketCasts(url)
        }
        return .feed(url)
    }

    /// The app a link belongs to, for a refusal that names it ("Skrift can't read Deezer-only
    /// episodes"). The bare host for anything else.
    static func appName(forHost rawHost: String) -> String {
        let host = rawHost.lowercased()
        let known: [(String, String)] = [("spotify", "Spotify"), ("deezer", "Deezer"), ("overcast", "Overcast"),
                                         ("pca.st", "Pocket Casts"), ("pocketcasts", "Pocket Casts"),
                                         ("acast", "Acast"), ("apple.com", "Apple Podcasts")]
        return known.first { host.contains($0.0) }?.1 ?? host
    }
}

// MARK: - Resolution (pure; the importer does the fetching)

/// What a link says about WHICH episode, matched later against the feed.
struct PodcastHint: Equatable, Sendable {
    var guid: String?
    var title: String?
    var publishedAt: Date? = nil
    /// Acast page slug.
    var slug: String? = nil
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
        default: nil
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

// MARK: - Page meta and name search (Q476: Spotify, Deezer, Overcast, Pocket Casts, Acast, any web page)

extension PodcastResolver {
    /// Every `<meta>` tag of a page as `property`/`name` → `content`, entities decoded, first one wins.
    static func htmlMeta(_ data: Data) -> [String: String] {
        let html = String(decoding: data, as: UTF8.self)
        var out: [String: String] = [:]
        guard let tag = try? NSRegularExpression(pattern: "<meta\\s[^>]*>", options: [.caseInsensitive]),
              let attr = try? NSRegularExpression(pattern: "([A-Za-z:_-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')") else { return out }
        let whole = NSRange(html.startIndex..., in: html)
        for m in tag.matches(in: html, range: whole) {
            guard let r = Range(m.range, in: html) else { continue }
            let text = String(html[r])
            var values: [String: String] = [:]
            for a in attr.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let k = Range(a.range(at: 1), in: text) else { continue }
                let vRange = Range(a.range(at: 2), in: text) ?? Range(a.range(at: 3), in: text)
                if let vRange { values[text[k].lowercased()] = String(text[vRange]) }
            }
            guard let key = (values["property"] ?? values["name"])?.lowercased(), let content = values["content"] else { continue }
            if out[key] == nil { out[key] = decodeEntities(content).trimmed }
        }
        return out
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named = ["&mdash;": "\u{2014}", "&ndash;": "\u{2013}", "&rsquo;": "\u{2019}", "&lsquo;": "\u{2018}",
                     "&rdquo;": "\u{201D}", "&ldquo;": "\u{201C}", "&hellip;": "\u{2026}", "&nbsp;": " ",
                     "&quot;": "\"", "&apos;": "'", "&lt;": "<", "&gt;": ">"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        if let numeric = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") {
            for m in numeric.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                guard let whole = Range(m.range, in: out), let hex = Range(m.range(at: 1), in: out),
                      let digits = Range(m.range(at: 2), in: out),
                      let code = UInt32(out[digits], radix: out[hex].isEmpty ? 10 : 16),
                      let scalar = Unicode.Scalar(code) else { continue }
                out.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Spotify page

    /// The episode page's public meta: the show is the first part of `og:description`
    /// ("Economist Podcasts · Episode"), the release date `music:release_date`.
    static func spotifyPage(fromMeta meta: [String: String]) -> (show: String?, released: Date?) {
        let show = meta["og:description"].flatMap { $0.components(separatedBy: " \u{00B7} ").first?.trimmed }
        let released = meta["music:release_date"].flatMap { ISO8601DateFormatter().date(from: $0) }
        return (show?.isEmpty == false ? show : nil, released)
    }

    // MARK: Deezer / Overcast pages

    /// Deezer's episode page: `og:title` is the episode title, `og:description` the show name
    /// (recorded 2026-10-16: "Blindboy", an episode of "Fashion Neurosis with Bella Freud").
    static func deezerPage(fromMeta meta: [String: String]) -> (show: String, episode: String)? {
        guard let episode = meta["og:title"], let show = meta["og:description"], !show.isEmpty, !episode.isEmpty else { return nil }
        return (show, episode)
    }

    /// Overcast's episode page: `og:title` is "Episode — Show" (the show after the LAST dash).
    static func overcastPage(fromMeta meta: [String: String]) -> (show: String, episode: String)? {
        guard let title = meta["og:title"], let dash = title.range(of: " \u{2014} ", options: .backwards) else { return nil }
        let episode = String(title[..<dash.lowerBound]).trimmed
        let show = String(title[dash.upperBound...]).trimmed
        return episode.isEmpty || show.isEmpty ? nil : (show, episode)
    }

    // MARK: Pocket Casts

    struct PocketCastsRoute: Equatable {
        var showName: String
        var podcastUUID: String
        var episodeSlug: String?
        var episodeUUID: String?
    }

    /// `pocketcasts.com/podcast/<show-slug>/<podcast-uuid>[/<episode-slug>/<episode-uuid>]`.
    static func pocketCastsRoute(_ url: URL) -> PocketCastsRoute? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let i = parts.firstIndex(of: "podcast"), parts.count > i + 2 else { return nil }
        let name = parts[i + 1].replacingOccurrences(of: "-", with: " ")
        let route = PocketCastsRoute(showName: name, podcastUUID: parts[i + 2], episodeSlug: nil, episodeUUID: nil)
        guard parts.count > i + 4 else { return route }
        return PocketCastsRoute(showName: name, podcastUUID: parts[i + 2], episodeSlug: parts[i + 3], episodeUUID: parts[i + 4])
    }

    static func pocketCastsNotesURL(podcastUUID: String) -> URL? {
        URL(string: "https://podcast-api.pocketcasts.com/mobile/show_notes/full/\(podcastUUID)")
    }

    static func pocketCastsEpisode(fromNotes data: Data, uuid: String) -> (title: String, published: Date?)? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let episodes = (json["podcast"] as? [String: Any])?["episodes"] as? [[String: Any]],
              let hit = episodes.first(where: { $0["uuid"] as? String == uuid }),
              let title = (hit["title"] as? String)?.trimmed, !title.isEmpty else { return nil }
        return (title, (hit["published"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) })
    }

    // MARK: Acast

    /// Acast's show slug is also its public feed address.
    static func acastFeedURL(show: String) -> URL? {
        URL(string: "https://feeds.acast.com/public/shows/\(show)")
    }

    // MARK: Name search

    /// Episode search hits that are THIS episode: same normalised title, and, when the link names the
    /// show, a show that name belongs to. Without a show name every same-title hit counts.
    static func episodeMatches(title: String, showName: String?, searchResults data: Data) -> [PodcastMatch] {
        let wanted = PodcastPick.normalise(title)
        let show = showName.map(PodcastPick.normalise)
        var seen = Set<String>()
        var out: [PodcastMatch] = []
        for r in results(data) {
            guard let name = r["trackName"] as? String, PodcastPick.normalise(name) == wanted,
                  let raw = r["feedUrl"] as? String, let feed = URL(string: raw),
                  seen.insert(raw).inserted else { continue }
            let collection = r["collectionName"] as? String ?? ""
            if let show, !show.isEmpty, !namesRelate(PodcastPick.normalise(collection), show) { continue }
            out.append(PodcastMatch(feedURL: feed, hint: PodcastHint(guid: r["episodeGuid"] as? String, title: name),
                                    showName: collection))
        }
        return out
    }

    /// What to type into the iTunes show search for a show name: the name, then "<show> from
    /// <publisher>" with the publisher guessed from the name's first word ("Economist Podcasts" is
    /// listed as "Economist Podcasts from The Economist").
    static func showSearchTerms(for show: String) -> [String] {
        var terms = [show]
        let words = show.split(separator: " ").map(String.init)
        if let first = words.first(where: { $0.lowercased() != "the" }), words.count > 1 {
            terms.append("\(show) from The \(first)")
            terms.append("\(show) from \(first)")
        }
        return terms
    }

    /// Feeds of the shows a search returned whose name is the show's name (or starts with it:
    /// "<show> from <publisher>"), exact names first.
    static func showFeedCandidates(for show: String, searchResults data: Data) -> [URL] {
        let wanted = PodcastPick.normalise(show)
        var exact: [URL] = []
        var related: [URL] = []
        for r in results(data) {
            guard let name = r["collectionName"] as? String, let raw = r["feedUrl"] as? String,
                  let feed = URL(string: raw), feed.scheme?.hasPrefix("http") == true else { continue }
            let n = PodcastPick.normalise(name)
            if n == wanted { exact.append(feed) } else if namesRelate(n, wanted) { related.append(feed) }
        }
        return exact + related
    }

    /// `a` is `b`, or starts with `b` at a word boundary, or the other way round.
    private static func namesRelate(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.hasPrefix(b + " ") || b.hasPrefix(a + " ")
    }

    // MARK: Any web page

    /// The page's `<link rel="alternate" type="application/rss+xml" href="…">`, made absolute.
    static func alternateFeedURL(inHTML data: Data, base: URL) -> URL? {
        let html = String(decoding: data, as: UTF8.self)
        guard let tag = try? NSRegularExpression(pattern: "<link\\s[^>]*>", options: [.caseInsensitive]),
              let attr = try? NSRegularExpression(pattern: "([A-Za-z:_-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')") else { return nil }
        for m in tag.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(m.range, in: html) else { continue }
            let text = String(html[r])
            var values: [String: String] = [:]
            for a in attr.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let k = Range(a.range(at: 1), in: text) else { continue }
                if let v = Range(a.range(at: 2), in: text) ?? Range(a.range(at: 3), in: text) { values[text[k].lowercased()] = String(text[v]) }
            }
            guard values["rel"]?.lowercased().contains("alternate") == true,
                  values["type"]?.lowercased().contains("rss") == true, let href = values["href"],
                  let url = URL(string: decodeEntities(href), relativeTo: base)?.absoluteURL,
                  url.scheme?.hasPrefix("http") == true else { continue }
            return url
        }
        return nil
    }

    /// True when the bytes are a web page rather than a feed.
    static func looksLikeHTML(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        return head.contains("<!doctype html") || head.contains("<html")
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
