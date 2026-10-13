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

    static func resolve(_ input: String, fetch: Fetch = liveFetch) async throws -> PodcastResolution {
        guard let link = PodcastLink.classify(input) else { throw PodcastRefusal.notALink }
        switch link {
        case .feed(let url):
            return .chooseEpisode(try PodcastFeedParser.parse(try await fetch(url)))

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

        case .spotifyEpisode:
            guard let oembed = PodcastResolver.oEmbedURL(for: link) else { throw PodcastRefusal.notALink }
            let title = try PodcastResolver.spotifyTitle(fromOEmbed: try await fetch(oembed))
            guard let search = PodcastResolver.searchURL(term: title, entity: "podcastEpisode") else {
                throw PodcastRefusal.spotifyExclusive
            }
            let match = try PodcastResolver.spotifyMatch(title: title, searchResults: try await fetch(search))
            let show = try PodcastFeedParser.parse(try await fetch(match.feedURL))
            guard let episode = PodcastPick.episode(in: show, guid: match.hint.guid, title: match.hint.title) else {
                throw PodcastRefusal.episodeNotInFeed
            }
            return .episode(show, episode)

        case .spotifyShow:
            guard let oembed = PodcastResolver.oEmbedURL(for: link) else { throw PodcastRefusal.notALink }
            let name = try PodcastResolver.spotifyTitle(fromOEmbed: try await fetch(oembed))
            guard let search = PodcastResolver.searchURL(term: name, entity: "podcast") else {
                throw PodcastRefusal.spotifyExclusive
            }
            let match = try PodcastResolver.spotifyShowMatch(name: name, searchResults: try await fetch(search))
            return .chooseEpisode(try PodcastFeedParser.parse(try await fetch(match.feedURL)))
        }
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
