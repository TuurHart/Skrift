#if DEBUG
import Foundation
import SwiftData
import CoreGraphics
import ImageIO
import AVFoundation

/// Q313: the perf-library generator. ONE generator for both apps (phone `-perfLibrary`, Mac
/// `-perfLibrary`): ~2,000 deterministic synthetic notes spread over three years, built from
/// word lists in this file (no text from any private fixture), inserted as the same shared
/// `@Model` rows a synced phone store holds. Deterministic: a fixed RNG seed and an injectable
/// `now`, so two runs with the same `Plan` and `now` produce the same library.
///
/// Shape (counts for `Plan()` at 2,000): 1,400 voice notes (70, of which 5% run 2,000-6,000
/// words, the rest 50-400), 200 conversations (`**Name:**` turns), 200 typed notes, 100 link
/// captures, 100 audiobook quotes; 300 notes carry 1-4 generated ~2000 px JPEGs, 60 carry a real
/// AAC clip; 150 people (names.json shape, with aliases); 200 notes link other notes; ratings are
/// a mix incl. unrated; 100 notes sit on the Fading shelf, 50 in the trash, 40 are locked.
///
/// The dates are placed so the library is STABLE under the at-open fading sweep: every unrated
/// note old enough to fade (30 days) is either one of the 100 deliberate Fading notes (30-59
/// days old), or held off the clock (touched in the last 29 days, locked, or backlinked), so a
/// first launch does not quietly move hundreds of notes to Recently Deleted.
enum PerfLibrarySeeder {

    // MARK: Plan

    struct Plan: Equatable {
        var total = 2000
        /// Mac: every recording-shaped note also carries a (tiny) real audio asset, because the
        /// Mac ingest builds no `PipelineFile` for a voice memo whose audio blob is absent.
        /// The phone leaves the other ~1,540 recordings without a file (3 minutes of audio each
        /// is not what a speed sweep measures).
        var tinyAudioForEveryRecording = false
        /// Q336: stamp every note's metadata with `testLibrary: true` (the removable-test-notes marker).
        var markAsTestLibrary = false
        /// Q336: ids already in the store. Their notes (and assets) are generated, so every random
        /// draw stays in step, but not inserted again: seeding twice never duplicates.
        var skipIDs: Set<UUID> = []

        var voice: Int { total * 70 / 100 }
        var conversations: Int { total * 10 / 100 }
        var typed: Int { total * 10 / 100 }
        var links: Int { total * 5 / 100 }
        var quotes: Int { total - voice - conversations - typed - links }
        var longVoice: Int { voice * 5 / 100 }
        var photoNotes: Int { total * 15 / 100 }
        var audioNotes: Int { total * 3 / 100 }
        var people: Int { 150 }
        var linkSources: Int { total / 10 }
        var fading: Int { total * 5 / 100 }
        var trashed: Int { total * 25 / 1000 }
        var recent: Int { total * 75 / 1000 }
        var keptUnrated: Int { total * 5 / 100 }
        var forcedUnratedTargets: Int { total * 15 / 1000 }
        var locked: Int { total * 2 / 100 }
    }

    struct Summary: Equatable {
        var memos = 0, assets = 0, photoAssets = 0, audioAssets = 0, people = 0
        var linkSources = 0
    }

    enum SeedError: Error { case imageEncode, audioEncode }

    static let rngSeed: UInt64 = 0x5C21F7_0B313

    // MARK: Entry point

    /// Build and insert the whole library. `recordingsDirectory` receives the generated photo and
    /// audio files under the app's own filenames (the phone reads them from disk); pass nil on
    /// the Mac, which reads the `MemoAsset` blobs only. `progress(phase, done, total)` fires every
    /// ~100 notes; call this off the main thread (the work is a few seconds of CPU).
    @discardableResult
    static func seed(into context: ModelContext, recordingsDirectory: URL?, now: Date = Date(),
                     plan: Plan = Plan(),
                     progress: ((String, Int, Int) -> Void)? = nil) throws -> Summary {
        var rng = PerfRNG(seed: rngSeed)
        let people = makePeople(count: plan.people, now: now)
        let firstNames = people.map { $0.short ?? $0.displayName }
        if let dir = recordingsDirectory {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // ---- assign kinds and roles --------------------------------------------------------
        var kinds: [Kind] = []
        kinds += Array(repeating: .voice, count: plan.voice)
        kinds += Array(repeating: .conversation, count: plan.conversations)
        kinds += Array(repeating: .typed, count: plan.typed)
        kinds += Array(repeating: .link, count: plan.links)
        kinds += Array(repeating: .quote, count: plan.quotes)
        rng.shuffle(&kinds)
        let n = kinds.count

        var order = Array(0..<n)
        rng.shuffle(&order)
        var roles = [Role](repeating: .old, count: n)
        var cursor = 0
        func take(_ count: Int, as role: Role) {
            for i in order[cursor..<min(n, cursor + count)] { roles[i] = role }
            cursor = min(n, cursor + count)
        }
        take(plan.trashed, as: .trash)
        take(plan.fading, as: .fading)
        take(plan.recent, as: .recent)
        take(plan.keptUnrated, as: .keptUnrated)
        let oldIdx = (0..<n).filter { roles[$0] == .old }

        // Old notes that are deliberately UNRATED: held by being a link target (forced below)
        // or by a lock. Everything else old is rated.
        var oldShuffled = oldIdx; rng.shuffle(&oldShuffled)
        let forcedTargets = Array(oldShuffled.prefix(plan.forcedUnratedTargets))
        let lockedUnrated = Array(oldShuffled.dropFirst(plan.forcedUnratedTargets).prefix(plan.locked / 2))
        let lockedRated = Array(oldShuffled.dropFirst(plan.forcedUnratedTargets + plan.locked / 2)
            .prefix(plan.locked - plan.locked / 2))
        let forcedSet = Set(forcedTargets), lockedUnratedSet = Set(lockedUnrated), lockedSet = Set(lockedUnrated + lockedRated)

        func indices(of ks: Set<Kind>) -> [Int] { (0..<n).filter { ks.contains(kinds[$0]) } }
        var voiceIdx = indices(of: [.voice]); rng.shuffle(&voiceIdx)
        let longVoiceSet = Set(voiceIdx.prefix(plan.longVoice))
        var photoPool = indices(of: [.voice, .typed]); rng.shuffle(&photoPool)
        let photoSet = Set(photoPool.prefix(plan.photoNotes))
        let audioVoice = plan.audioNotes * 3 / 4
        let audioQuote = min(plan.audioNotes - audioVoice, plan.quotes)
        var quoteIdx = indices(of: [.quote]); rng.shuffle(&quoteIdx)
        let audioSet = Set(voiceIdx.prefix(audioVoice)).union(quoteIdx.prefix(audioQuote))

        // ---- media pools -------------------------------------------------------------------
        let imagePool: [Data] = try photoSet.isEmpty ? [] : (0..<min(24, max(2, photoSet.count))).map { i in
            guard let d = jpegImage(portrait: i % 2 == 1, variant: i) else { throw SeedError.imageEncode }
            return d
        }
        let audioPoolSize = min(60, max(1, audioSet.count))
        let audioPool: [(data: Data, seconds: Double)] = try (0..<audioPoolSize).map { i in
            let seconds = 2.5 + Double(i % 5) * 0.5
            guard let d = aacTone(seconds: seconds, frequency: 196 + Double(i) * 23) else { throw SeedError.audioEncode }
            return (d, seconds)
        }

        // ---- build every note --------------------------------------------------------------
        var entries: [Entry] = []
        entries.reserveCapacity(n)
        var photoSerial = 0, audioSerial = 0
        let day: TimeInterval = 86_400
        for i in 0..<n {
            let kind = kinds[i], role = roles[i]
            let id = rng.uuid()
            var assets: [MemoAsset] = []

            // dates
            let recordedAt: Date
            switch role {
            case .fading: recordedAt = now.addingTimeInterval(-(31 + rng.unit() * 27) * day)
            case .recent: recordedAt = now.addingTimeInterval(-rng.unit() * 28 * day)
            case .trash:  recordedAt = now.addingTimeInterval(-(20 + rng.unit() * 1075) * day)
            case .old, .keptUnrated:
                recordedAt = now.addingTimeInterval(-(61 + rng.unit() * 1034) * day)
            }

            // content
            var paragraphs: [String] = []
            var title: String? = nil
            var metadata = MemoMetadata()
            var mediaSource: String? = nil
            var sharedContent: SharedContent? = nil
            var annotation: String? = nil
            var duration: TimeInterval = 0
            var audioFilename = ""
            var transcriptStatus = TranscriptStatus.done
            var confidence: Double? = 0.82 + rng.unit() * 0.16
            var userEdited = false
            let photoCount = photoSet.contains(i) ? rng.pick(weights: [40, 30, 20, 10]) + 1 : 0
            let dutch = rng.unit() < 0.1
            let minParagraphs = photoCount + 1

            switch kind {
            case .voice:
                let words = longVoiceSet.contains(i) ? 2000 + rng.int(4001) : 50 + Int(pow(rng.unit(), 2) * 350)
                paragraphs = PerfText.paragraphs(words: words, minParagraphs: minParagraphs, dutch: dutch,
                                                 names: firstNames, rng: &rng)
                if rng.unit() < 0.15 { title = PerfText.title(dutch: dutch, rng: &rng) }
                duration = max(6, Double(words) / 2.6)
                audioFilename = "memo_\(id.uuidString).m4a"
                metadata = contextMetadata(recordedAt: recordedAt, rng: &rng)
            case .conversation:
                paragraphs = PerfText.conversation(names: firstNames, rng: &rng)
                if rng.unit() < 0.3 { title = PerfText.title(dutch: dutch, rng: &rng) }
                duration = Double(paragraphs.joined(separator: " ").split(separator: " ").count) / 2.6
                audioFilename = "memo_\(id.uuidString).m4a"
                metadata = contextMetadata(recordedAt: recordedAt, rng: &rng)
                confidence = 0.9
            case .typed:
                let words = 20 + Int(pow(rng.unit(), 2) * 280)
                paragraphs = PerfText.typed(words: words, minParagraphs: minParagraphs, dutch: dutch,
                                            names: firstNames, rng: &rng)
                if rng.unit() < 0.7 { title = PerfText.title(dutch: dutch, rng: &rng) }
                mediaSource = "typed"
                confidence = nil
                userEdited = true
            case .link:
                let (sc, thought) = PerfText.linkCapture(names: firstNames, rng: &rng)
                sharedContent = sc
                annotation = thought
                confidence = nil
            case .quote:
                let (quote, ramble, book) = PerfText.audiobookQuote(rng: &rng)
                paragraphs = [quote] + (ramble.map { [$0] } ?? [])
                metadata.bookTitle = book.title
                metadata.bookAuthor = book.author
                metadata.bookChapter = String(1 + rng.int(30))
                metadata.bookID = book.id
                metadata.bookPosition = Double(rng.int(36_000))
                confidence = 0.9
            }

            // photos
            var manifest: [ImageManifestEntry] = []
            if photoCount > 0 && !imagePool.isEmpty {
                for p in 1...photoCount {
                    let name = "photo_\(id.uuidString)_\(String(format: "%03d", p)).jpg"
                    let bytes = imagePool[(photoSerial * 7 + p) % imagePool.count]
                    photoSerial += 1
                    assets.append(MemoAsset(memoID: id, kind: MemoAsset.Kind.photo, filename: name,
                                            blob: bytes, createdAt: recordedAt))
                    if let dir = recordingsDirectory { try? bytes.write(to: dir.appendingPathComponent(name)) }
                    // `text: ""` = already indexed, no text found, so the launch OCR sweep has
                    // nothing to do (750 Vision passes would swamp the thing being measured).
                    manifest.append(ImageManifestEntry(filename: name,
                                                       offsetSeconds: duration * Double(p) / Double(photoCount + 1),
                                                       text: ""))
                }
                metadata.imageManifest = manifest
                // Markers go BETWEEN paragraphs, one per photo, in order.
                var withMarkers: [String] = []
                for (pi, para) in paragraphs.enumerated() {
                    withMarkers.append(para)
                    if pi < manifest.count { withMarkers.append("[[img_\(String(format: "%03d", pi + 1))]]") }
                }
                paragraphs = withMarkers
            }

            // audio
            if audioSet.contains(i) {
                let clip = audioPool[audioSerial % audioPool.count]
                audioSerial += 1
                let name = kind == .quote ? "memo_\(id.uuidString).m4a" : audioFilename
                audioFilename = name
                duration = clip.seconds
                assets.append(MemoAsset(memoID: id, kind: MemoAsset.Kind.audio, filename: name,
                                        blob: clip.data, createdAt: recordedAt))
                if let dir = recordingsDirectory { try? clip.data.write(to: dir.appendingPathComponent(name)) }
            } else if plan.tinyAudioForEveryRecording, !audioFilename.isEmpty {
                assets.append(MemoAsset(memoID: id, kind: MemoAsset.Kind.audio, filename: audioFilename,
                                        blob: audioPool[0].data, createdAt: recordedAt))
            }

            // trust mix: ~8% of recordings fall below the 0.7 trust line (the Mac re-transcribes those)
            if kind == .voice, rng.unit() < 0.08 { confidence = 0.45 + rng.unit() * 0.24 }
            if kind == .voice, rng.unit() < 0.02 { userEdited = true }
            if kind == .link || kind == .typed { transcriptStatus = .done }

            metadata.tags = pickTags(rng: &rng)
            if plan.markAsTestLibrary { metadata.testLibrary = true }
            let metadataData = blob(metadata, mediaSource: mediaSource)
            let transcript: String? = (kind == .link) ? nil : paragraphs.joined(separator: "\n\n")

            let memo = Memo(
                id: id,
                audioFilename: audioFilename,
                duration: duration,
                recordedAt: recordedAt,
                tags: metadata.tags,
                syncStatus: .synced,
                title: title,
                transcript: transcript,
                transcriptStatus: transcriptStatus,
                transcriptConfidence: confidence,
                transcriptUserEdited: userEdited,
                transcriptMarkersInjected: photoCount > 0,
                significance: 0,
                deletedAt: nil,
                createdAt: recordedAt,
                editedAt: nil,
                metadataData: metadataData,
                sharedContentData: sortedJSON(sharedContent),
                annotationText: annotation,
                nameResolutionsData: nil,
                recordingDeviceID: "perf-phone-0001")
            if rng.unit() < 0.15 { memo.destination = [.inspiration, .idea, .project][rng.int(3)] }

            // rating + lifecycle by role
            switch role {
            case .old:
                if forcedSet.contains(i) || lockedUnratedSet.contains(i) { memo.significance = 0 }
                else { memo.significance = rating(&rng) }
                if memo.significance > 0, rng.unit() < 0.2 {   // some rated notes were edited later
                    let edited = recordedAt.addingTimeInterval(3600 + rng.unit() * 30 * day)
                    memo.editedAt = min(edited, now); memo.keptAt = memo.editedAt
                }
            case .recent:
                memo.significance = rng.unit() < 0.55 ? rating(&rng) : 0
            case .fading:
                memo.significance = 0
            case .keptUnrated:
                memo.significance = 0
                let touched = now.addingTimeInterval(-(1 + rng.unit() * 26) * day)
                memo.keptAt = touched; memo.editedAt = touched
            case .trash:
                memo.significance = rng.unit() < 0.5 ? rating(&rng) : 0
                let deleted = now.addingTimeInterval(-(1 + rng.unit() * 9) * day)
                memo.deletedAt = deleted
                memo.trashSeenAt = deleted.addingTimeInterval(60)
            }
            if lockedSet.contains(i) { memo.locked = true }
            entries.append(Entry(memo: memo, assets: assets, kind: kind, role: role))

            if i % 200 == 199 { progress?("building", i + 1, n) }
        }

        // ---- memo links between notes ------------------------------------------------------
        // Sources: live voice/typed notes (their links count as backlinks only while live).
        // Targets: forced-unrated old notes first (they are HELD OFF the fade clock by the link),
        // then random live non-fading notes.
        let liveTargetPool = (0..<n).filter { [.old, .recent, .keptUnrated].contains(entries[$0].role) }
        var sourcePool = (0..<n).filter { (entries[$0].kind == .voice || entries[$0].kind == .typed)
            && entries[$0].role != .trash && entries[$0].role != .fading && entries[$0].kind != .link }
        rng.shuffle(&sourcePool)
        var forcedQueue = forcedTargets
        var linked = Set<Int>()
        var linkSources = 0
        for s in sourcePool.prefix(plan.linkSources) {
            let count = 1 + rng.int(2)
            var targets: [Int] = []
            for _ in 0..<count {
                if !forcedQueue.isEmpty { targets.append(forcedQueue.removeFirst()) }
                else if !liveTargetPool.isEmpty { targets.append(liveTargetPool[rng.int(liveTargetPool.count)]) }
            }
            targets = targets.filter { $0 != s }
            guard !targets.isEmpty else { continue }
            linked.formUnion(targets)
            let links = targets.map { t -> String in
                let m = entries[t].memo
                return MemoLinkSyntax.link(id: m.id, title: m.title ?? snapshotTitle(m.transcript ?? m.annotationText))
            }
            let line = (rng.unit() < 0.5 ? "See also " : "Related: ") + links.joined(separator: " and ")
            let memo = entries[s].memo
            memo.transcript = (memo.transcript ?? "") + "\n\n" + line
            linkSources += 1
        }
        // Any forced target the sources did not reach still needs a hold: lock it (the
        // alternative is the first launch trashing it).
        for t in forcedTargets where !linked.contains(t) { entries[t].memo.locked = true }

        // ---- insert --------------------------------------------------------------------------
        var summary = Summary()
        summary.linkSources = linkSources
        for (i, e) in entries.enumerated() {
            if plan.skipIDs.contains(e.memo.id) { continue }
            context.insert(e.memo)
            for a in e.assets {
                context.insert(a)
                summary.assets += 1
                if a.kind == MemoAsset.Kind.photo { summary.photoAssets += 1 }
                if a.kind == MemoAsset.Kind.audio { summary.audioAssets += 1 }
            }
            summary.memos += 1
            if (i + 1) % 100 == 0 {
                try context.save()
                progress?("saving", i + 1, n)
            }
        }
        try context.save()
        progress?("saving", n, n)
        summary.people = people.count
        return summary
    }

    // MARK: Internals

    enum Kind { case voice, conversation, typed, link, quote }
    enum Role { case old, recent, fading, keptUnrated, trash }
    private struct Entry { let memo: Memo; let assets: [MemoAsset]; let kind: Kind; let role: Role }

    private static func rating(_ rng: inout PerfRNG) -> Double {
        // weights over 0.1 ... 1.0 (a bit top-light, like a real library)
        let steps = rng.pick(weights: [12, 12, 14, 12, 12, 10, 10, 8, 6, 4]) + 1
        return Double(steps) / 10
    }

    private static func snapshotTitle(_ text: String?) -> String {
        let words = (text ?? "").split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ")
        return words.isEmpty ? "Untitled" : words
    }

    static let tagPool: [String] = {
        let areas = ["work", "life", "ideas", "reading", "health", "travel", "money", "family"]
        let subs = ["planning", "journal", "questions", "draft", "review", "followup", "memory", "goal", "idea", "note"]
        return areas.flatMap { a in subs.map { "\(a)/\($0)" } }   // 80
    }()

    private static func pickTags(rng: inout PerfRNG) -> [String] {
        let count = rng.pick(weights: [20, 25, 25, 20, 10])   // 0...4
        var out: [String] = []
        for _ in 0..<count {
            let idx = Int(pow(rng.unit(), 1.8) * Double(tagPool.count))   // a few tags dominate
            let t = tagPool[min(idx, tagPool.count - 1)]
            if !out.contains(t) { out.append(t) }
        }
        return out
    }

    private static let places: [(String, Double, Double)] = [
        ("Alvalade", 38.7532, -9.1440), ("Jardim da Estrela", 38.7139, -9.1607), ("Home", 38.7370, -9.1500),
        ("Cais do Sodré", 38.7060, -9.1450), ("Amsterdam", 52.3702, 4.8952), ("Porto", 41.1579, -8.6291),
        ("Sintra", 38.7978, -9.3881), ("Utrecht", 52.0907, 5.1214), ("Café Pastelaria", 38.7223, -9.1393),
        ("Oriente", 38.7679, -9.0990), ("Cascais", 38.6979, -9.4215), ("Rotterdam", 51.9244, 4.4777),
    ]

    private static func contextMetadata(recordedAt: Date, rng: inout PerfRNG) -> MemoMetadata {
        var m = MemoMetadata(capturedAt: ISO8601.string(from: recordedAt))
        if rng.unit() < 0.6 {
            let p = places[rng.int(places.count)]
            m.location = LocationInfo(latitude: p.1, longitude: p.2, placeName: p.0)
        }
        if rng.unit() < 0.5 {
            m.weather = WeatherInfo(conditions: ["Clear", "Cloudy", "Rain", "Partly cloudy"][rng.int(4)],
                                    temperature: 8 + rng.int(22), temperatureUnit: "C")
            m.pressure = PressureInfo(hPa: 1000 + rng.int(30), trend: [.rising, .steady, .falling][rng.int(3)])
        }
        let hour = Calendar.current.component(.hour, from: recordedAt)
        m.dayPeriod = hour < 12 ? .morning : hour < 17 ? .afternoon : hour < 21 ? .evening : .night
        if rng.unit() < 0.7 { m.steps = rng.int(15_000) }
        return m
    }

    /// The metadata JSON blob; typed notes also carry the `mediaSource` marker `Memo.newTyped` writes.
    private static func sortedJSON<T: Encodable>(_ v: T?) -> Data? {
        guard let v else { return nil }
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]   // deterministic bytes, run to run
        return try? e.encode(v)
    }

    private static func blob(_ m: MemoMetadata, mediaSource: String?) -> Data? {
        guard let data = sortedJSON(m) else { return nil }
        guard let mediaSource,
              var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return data }
        obj["mediaSource"] = mediaSource
        return try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }

    // MARK: People (names.json shape)

    private static let firstNames = [
        "Jack", "Jan", "Hendri", "Rose", "Sanne", "Pieter", "Mariana", "João", "Inês", "Tiago", "Sofia", "Luuk",
        "Femke", "Daan", "Noor", "Bram", "Lotte", "Ruben", "Marta", "Diogo", "Beatriz", "Sem", "Eva", "Thijs",
        "Carlota", "Rui", "Anouk", "Mees", "Catarina", "Joost", "Leonor", "Niels", "Isa", "Vasco", "Fleur",
        "Gonçalo", "Lieke", "Duarte", "Maud", "Hugo", "Teresa", "Stijn", "Clara", "Bruno", "Ilse", "Rafael",
        "Yara", "Wouter", "Matilde", "Floris", "Ana", "Kees", "Lena", "Pedro", "Saskia", "Tomás", "Rita",
        "Olaf", "Joana", "Gijs",
    ]
    private static let lastNames = [
        "de Vries", "Silva", "Jansen", "Santos", "Bakker", "Ferreira", "Visser", "Costa", "Smit", "Pereira",
        "Meijer", "Oliveira", "Mulder", "Rodrigues", "de Boer", "Martins", "Bos", "Sousa", "Vos", "Fernandes",
        "Peters", "Gonçalves", "Hendriks", "Gomes", "van Dijk", "Lopes", "Dekker", "Marques", "Brouwer", "Alves",
        "de Groot", "Almeida", "Willems", "Ribeiro", "Hoekstra", "Carvalho", "Kok", "Teixeira", "Jacobs", "Moreira",
        "van Leeuwen", "Correia", "Maas", "Mendes", "Hermans", "Nunes", "Schouten", "Soares", "Kuipers", "Vieira",
        "Post", "Monteiro", "Vermeulen", "Cardoso", "Prins", "Rocha", "Kramer", "Ramos", "Wolff", "Reis",
    ]

    /// The roster: `count` distinct people, `[[First Last]]`, aliases = the first name (so a few
    /// first names are ambiguous, as in real life), some with a "First L." alias. Deterministic.
    static func makePeople(count: Int, now: Date) -> [Person] {
        var rng = PerfRNG(seed: rngSeed ^ 0xA11CE)
        var seen = Set<String>(), out: [Person] = []
        var i = 0
        while out.count < count {
            let first = firstNames[i % firstNames.count]
            let last = lastNames[(i * 7 + (i / firstNames.count) * 13) % lastNames.count]
            i += 1
            let full = "\(first) \(last)"
            guard seen.insert(full).inserted else { continue }
            var aliases = [first]
            if rng.unit() < 0.4, let initial = last.split(separator: " ").last?.first { aliases.append("\(first) \(initial).") }
            let stamp = ISO8601.string(from: now.addingTimeInterval(-rng.unit() * 400 * 86_400))
            out.append(Person(canonical: "[[\(full)]]", aliases: aliases, short: first, lastModifiedAt: stamp))
        }
        return out
    }

    // MARK: Media generation (CoreGraphics + ImageIO + AVFoundation: both platforms)

    /// A ~2000 px photo-ish JPEG: a gradient sky/ground plus soft shapes. Real JPEG bytes.
    static func jpegImage(portrait: Bool, variant: Int) -> Data? {
        let w = portrait ? 1500 : 2000, h = portrait ? 2000 : 1500
        var rng = PerfRNG(seed: 0x1111 &+ UInt64(variant))
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        func color(_ a: CGFloat = 1) -> CGColor {
            CGColor(red: CGFloat(rng.unit()), green: CGFloat(rng.unit()), blue: CGFloat(rng.unit()), alpha: a)
        }
        if let g = CGGradient(colorsSpace: cs, colors: [color(), color()] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(h)), end: .zero, options: [])
        }
        for _ in 0..<18 {
            ctx.setFillColor(color(0.35))
            let r = CGRect(x: CGFloat(rng.int(w)), y: CGFloat(rng.int(h)),
                           width: CGFloat(120 + rng.int(700)), height: CGFloat(120 + rng.int(700)))
            if rng.unit() < 0.5 { ctx.fillEllipse(in: r) } else { ctx.fill(r) }
        }
        guard let image = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// A few seconds of AAC (`.m4a`): a warbling tone, so the bytes are a real, decodable clip.
    static func aacTone(seconds: Double, frequency: Double) -> Data? {
        let sr = 44_100.0
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_tone_\(Int(frequency))_\(Int(seconds * 10))_\(UUID().uuidString.prefix(6)).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sr, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * sr)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(seconds * sr)
        for i in 0..<Int(buffer.frameLength) {
            let t = Double(i) / sr
            let envelope = max(0, min(1, t / 0.05, (seconds - t) / 0.1))
            channel[i] = Float(0.3 * sin(2 * .pi * frequency * t) * envelope * (0.6 + 0.4 * sin(2 * .pi * 3 * t)))
        }
        do {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sr,
                                           AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000]
            var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: settings,
                                                     commonFormat: .pcmFormatFloat32, interleaved: false)
            try file?.write(from: buffer)
            file = nil   // finalises the container
        } catch { return nil }
        guard let data = try? Data(contentsOf: url), data.count > 1_000 else { return nil }
        return data
    }
}

// MARK: - Deterministic RNG

/// SplitMix64: tiny, fast, and the same sequence on every run and platform.
struct PerfRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// Uniform in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    /// Uniform in 0..<n (n > 0).
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) }
    mutating func pick(weights: [Int]) -> Int {
        var r = int(weights.reduce(0, +))
        for (i, w) in weights.enumerated() { if r < w { return i }; r -= w }
        return weights.count - 1
    }
    mutating func shuffle<T>(_ a: inout [T]) {
        guard a.count > 1 else { return }
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, int(i + 1)) }
    }
    mutating func uuid() -> UUID {
        let a = next(), b = next()
        return UUID(uuid: (UInt8(truncatingIfNeeded: a), UInt8(truncatingIfNeeded: a >> 8), UInt8(truncatingIfNeeded: a >> 16),
                           UInt8(truncatingIfNeeded: a >> 24), UInt8(truncatingIfNeeded: a >> 32), UInt8(truncatingIfNeeded: a >> 40),
                           UInt8(truncatingIfNeeded: a >> 48), UInt8(truncatingIfNeeded: a >> 56),
                           UInt8(truncatingIfNeeded: b), UInt8(truncatingIfNeeded: b >> 8), UInt8(truncatingIfNeeded: b >> 16),
                           UInt8(truncatingIfNeeded: b >> 24), UInt8(truncatingIfNeeded: b >> 32), UInt8(truncatingIfNeeded: b >> 40),
                           UInt8(truncatingIfNeeded: b >> 48), UInt8(truncatingIfNeeded: b >> 56)))
    }
}

// MARK: - Text generation (original word lists; nothing copied from any fixture)

enum PerfText {
    private static let subjects = [
        "the onboarding flow", "that pricing idea", "the garden plan", "next week's schedule", "the new bike",
        "my reading list", "the apartment search", "the budget spreadsheet", "the podcast outline",
        "the kitchen renovation", "the sync bug", "the workshop agenda", "my sleep", "the train to Porto",
        "the logo options", "the tax paperwork", "the book proposal", "my running routine", "the landing page",
        "the dinner on Friday", "the camera lens", "the garage clean-up", "the quarterly numbers",
        "the hiking trip", "the sourdough starter", "the design review", "my morning pages", "the insurance renewal",
        "the neighbourhood meeting", "the migration plan", "the playlist for the drive", "the visa forms",
        "the client proposal", "the weekend market", "the language course", "the bookshelf project",
        "the demo for Thursday", "the grocery routine", "the photo archive", "the new notebook system",
        "the roof leak", "the birthday present", "the backup strategy", "the studio lighting",
        "the cycling route", "the invoice template", "the museum visit", "the tooling decision",
        "the recipe I tried", "the call with the accountant", "the course outline", "the old laptop",
        "the Sunday plan", "the sketch from yesterday", "the standing desk", "the coffee setup",
        "the hotel booking", "the reading group", "the meeting notes", "the spare room",
    ]
    private static let predicates = [
        "keeps coming back to me", "still feels unfinished", "needs a proper decision this week",
        "is simpler than I made it", "might be worth another look", "has been on my mind all morning",
        "should probably wait until Monday", "is going better than expected", "feels slower than it should",
        "deserves a cleaner start", "is mostly a question of time", "could be done in an afternoon",
        "keeps changing shape", "is not as urgent as it felt", "needs somebody to just own it",
        "works if I keep it small", "will not fix itself", "is the part I enjoy most", "is quietly getting worse",
        "makes more sense when I write it down", "is probably fine", "needs a second opinion",
        "has too many moving parts", "is easier on a walk", "is a good problem to have",
    ]
    private static let actions = [
        "look again at", "write down", "sleep on", "ask around about", "simplify", "drop", "break up",
        "put a date on", "talk through", "photograph", "sketch out", "revisit",
    ]
    private static let openers = [
        "So", "Okay,", "Right,", "Quick thought:", "Also,", "One more thing,", "Honestly,", "I was thinking,",
        "Anyway,", "Okay so", "Basically,", "Right, so",
    ]
    private static let fillers = ["um", "you know", "kind of", "like", "I mean", "sort of"]
    private static let nlSubjects = [
        "de planning voor volgende week", "het idee voor de tuin", "de offerte voor de klant", "mijn hardloopschema",
        "de verbouwing van de keuken", "het gesprek met de buurman", "de reis naar Porto", "het boekvoorstel",
        "de belastingaangifte", "het weekendplan",
    ]
    private static let nlPredicates = [
        "blijft maar terugkomen", "voelt nog niet af", "moet deze week echt beslist worden",
        "is eenvoudiger dan ik dacht", "kan wel even wachten tot maandag", "gaat eigenlijk best goed",
        "heeft een tweede mening nodig", "is een kwestie van tijd",
    ]

    static func sentence(dutch: Bool, names: [String], rng: inout PerfRNG) -> String {
        func pick(_ a: [String]) -> String { a[rng.int(a.count)] }
        var s: String
        if dutch {
            let sub = pick(nlSubjects), pred = pick(nlPredicates)
            switch rng.int(4) {
            case 0: s = "Ja dus \(sub) \(pred)."
            case 1: s = "Ik denk dat \(sub) \(pred), maar ik weet het nog niet zeker."
            case 2: s = "Ik moet \(pick(names)) even bellen over \(sub)."
            default: s = "Eigenlijk \(pred), want \(sub) is nog niet af."
            }
        } else {
            let sub = pick(subjects), pred = pick(predicates)
            switch rng.int(8) {
            case 0, 1: s = "\(pick(openers)) \(sub) \(pred)."
            case 2: s = "I think \(sub) \(pred), but I'm not sure yet."
            case 3: s = "What if \(sub) \(pred)?"
            case 4: s = "I should call \(pick(names)) about \(sub)."
            case 5: s = "\(pick(names)) said \(sub) \(pred)."
            case 6: s = "Maybe I should \(pick(actions)) \(sub)."
            default: s = "The thing about \(sub) is that it \(pred.replacingOccurrences(of: "is ", with: "").replacingOccurrences(of: "has ", with: ""))."
            }
            if rng.unit() < 0.08 { s = pick(fillers).capitalized + ", " + s.prefix(1).lowercased() + s.dropFirst() }
        }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// `words` words (rounded up to a whole sentence) split into at least `minParagraphs` paragraphs
    /// (and into ~90-word paragraphs on longer notes).
    static func paragraphs(words: Int, minParagraphs: Int, dutch: Bool, names: [String],
                           rng: inout PerfRNG) -> [String] {
        var sentences: [String] = [], count = 0
        while count < words {
            let s = sentence(dutch: dutch, names: names, rng: &rng)
            sentences.append(s); count += s.split(separator: " ").count
        }
        let target = max(minParagraphs, words > 150 ? words / 90 : 1)
        let per = max(1, Int((Double(sentences.count) / Double(target)).rounded(.up)))
        var out: [String] = []
        var i = 0
        while i < sentences.count { out.append(sentences[i..<min(sentences.count, i + per)].joined(separator: " ")); i += per }
        while out.count < minParagraphs { out.append(sentence(dutch: dutch, names: names, rng: &rng)) }
        return out
    }

    /// A typed note: some bullets, an occasional heading.
    static func typed(words: Int, minParagraphs: Int, dutch: Bool, names: [String], rng: inout PerfRNG) -> [String] {
        var paras = paragraphs(words: words, minParagraphs: minParagraphs, dutch: dutch, names: names, rng: &rng)
        if rng.unit() < 0.4, paras.count > 1 {
            paras[1] = (0..<3).map { _ in "- " + sentence(dutch: dutch, names: names, rng: &rng) }.joined(separator: "\n")
        }
        if rng.unit() < 0.3 { paras[0] = "# " + title(dutch: dutch, rng: &rng) + "\n\n" + paras[0] }
        return paras
    }

    static func title(dutch: Bool, rng: inout PerfRNG) -> String {
        let sub = dutch ? nlSubjects[rng.int(nlSubjects.count)] : subjects[rng.int(subjects.count)]
        return sub.prefix(1).uppercased() + sub.dropFirst()
    }

    /// `**Name:**` turns, 2-3 speakers, 8-40 turns.
    static func conversation(names: [String], rng: inout PerfRNG) -> [String] {
        let speakerCount = 2 + rng.int(2)
        var speakers: [String] = []
        while speakers.count < speakerCount {
            let candidate = rng.unit() < 0.25 ? "Speaker \(speakers.count + 1)" : names[rng.int(names.count)]
            if !speakers.contains(candidate) { speakers.append(candidate) }
        }
        var turns: [String] = []
        var last = -1
        for _ in 0..<(8 + rng.int(33)) {
            var who = rng.int(speakers.count)
            if who == last { who = (who + 1) % speakers.count }
            last = who
            let body = (0..<(1 + rng.int(3))).map { _ in sentence(dutch: false, names: names, rng: &rng) }.joined(separator: " ")
            turns.append("**\(speakers[who]):** \(body)")
        }
        return turns
    }

    private static let domains = [
        "swiftwithmajid.com", "daringfireball.net", "nytimes.com", "theverge.com", "wikipedia.org", "github.com",
        "medium.com", "arstechnica.com", "bbc.co.uk", "volkskrant.nl", "publico.pt", "substack.com",
        "youtube.com", "hackernews.example", "lobste.example", "blog.example.org",
    ]

    static func linkCapture(names: [String], rng: inout PerfRNG) -> (SharedContent, String?) {
        let sub = subjects[rng.int(subjects.count)]
        let slug = sub.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: " ", with: "-")
        let domain = domains[rng.int(domains.count)]
        let titleText = (sub.prefix(1).uppercased() + sub.dropFirst()) + " — notes and a few opinions"
        let sc = SharedContent(type: .url, url: "https://www.\(domain)/\(2021 + rng.int(5))/\(slug)",
                               urlTitle: titleText,
                               urlDescription: sentence(dutch: false, names: names, rng: &rng) + " "
                                   + sentence(dutch: false, names: names, rng: &rng))
        let thought = rng.unit() < 0.6 ? sentence(dutch: false, names: names, rng: &rng) : nil
        return (sc, thought)
    }

    struct Book { let id: UUID; let title: String; let author: String }
    private static let books: [Book] = {
        let titles = ["The Slow Orchard", "A Map of Small Hours", "Salt and Signal", "The Last Ferry Home",
                      "Notes From a Quiet Engine", "Paper Lanterns", "The Weight of Rivers", "Open Windows",
                      "Harbour Lights", "The Craft of Leaving", "Winter Arithmetic", "Glass Country",
                      "What the Tide Keeps", "A Short History of Rain", "The Careful Year", "Borrowed Mountains",
                      "Letters to a Young Cartographer", "The Long Afternoon", "Small Machines", "Evenings in Delft"]
        let authors = ["Mara Lindqvist", "Tomás Albuquerque", "Ines Verhoeven", "Callum Reyes", "Noor Halvorsen",
                       "Pedro Quintela", "Sanne Oosterhuis", "Leona Marsh"]
        var rng = PerfRNG(seed: 0xB00C5)
        return titles.enumerated().map { i, t in Book(id: rng.uuid(), title: t, author: authors[i % authors.count]) }
    }()
    private static let quoteBits = [
        "The harbour woke slowly, as if it had agreed with itself not to hurry.",
        "He kept every promise he made to strangers and broke the ones he made to himself.",
        "There is a kind of tiredness that only a finished thing can cure.",
        "Nobody tells you that a plan is mostly a way of being brave in advance.",
        "She read the map the way other people read faces, looking for what it was not saying.",
        "It rained the whole week, and the town learned the sound of its own roofs.",
        "What we call patience is often only the habit of being unobserved.",
        "The simplest rooms were the ones that held the most weather.",
        "A good question outlasts every answer you give it.",
        "By the second winter the house had stopped pretending to be temporary.",
    ]

    /// `> ` quote block (1-3 sentences), and an optional ramble (the user's own words).
    static func audiobookQuote(rng: inout PerfRNG) -> (quote: String, ramble: String?, book: Book) {
        let n = 1 + rng.int(3)
        var lines: [String] = []
        for _ in 0..<n { lines.append("> " + quoteBits[rng.int(quoteBits.count)]) }
        let ramble: String? = rng.unit() < 0.8
            ? (0..<(1 + rng.int(4))).map { _ in sentence(dutch: false, names: ["Jan"], rng: &rng) }.joined(separator: " ")
            : nil
        return (lines.joined(separator: "\n"), ramble, books[rng.int(books.count)])
    }
}
#endif
