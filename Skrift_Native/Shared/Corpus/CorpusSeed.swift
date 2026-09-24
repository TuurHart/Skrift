#if DEBUG
import Foundation
import SwiftData

/// Seeds the SYNTHETIC note corpus (`test-fixtures/corpus/`, built by `generate.py`) into a
/// `Memo` store — the same rows a phone would have synced, so both apps exercise their real
/// paths on it: the phone renders/edits/exports them, the Mac's reconcile sweep ingests them.
///
/// ONE loader for both apps (Shared/Corpus): it uses only the shared `@Model`s and the
/// blob-based `Memo` init, never a platform type. Idempotent by memo id — re-seeding skips
/// notes already present, so a Dev store can be topped up after the corpus grows.
///
/// DEBUG only, never in a Release binary: the corpus is a testing vault, not a feature.
/// Launch: `-corpus <path-to-test-fixtures/corpus>` on either app.
enum CorpusSeed {

    // MARK: note.json (the schema generate.py writes — keep the two in step)

    struct Manifest: Decodable {
        struct Entry: Decodable { let index: Int; let slug: String; let id: String; let folder: String }
        let count: Int
        let notes: [Entry]
    }

    struct Note: Decodable {
        struct Photo: Decodable { let filename: String; let file: String }
        struct SharedFile: Decodable { let file: String; let filename: String }
        struct Enhancement: Decodable {
            let copyedit: String; let title: String; let summary: String
            let enhancedAt: String; let processedAt: String?; let enhancedByDeviceID: String?
        }
        let id: String
        let slug: String
        let kind: String
        let title: String?
        let recordedAt: String
        let createdAt: String?
        let editedAt: String?
        let duration: Double
        let audio: String?
        let transcript: String?
        let transcriptStatus: String
        let transcriptConfidence: Double?
        let transcriptUserEdited: Bool
        let transcriptMarkersInjected: Bool
        let significance: Double
        let tags: [String]
        let destination: String
        let locked: Bool
        let deletedAt: String?
        let trashSeenAt: String?
        let keptAt: String?
        let remindAt: String?
        let recordingDeviceID: String?
        let annotationText: String?
        /// Kept as raw JSON: it IS the `metadataData` blob (MemoMetadata's wire shape plus
        /// any extra keys such as `mediaSource`, which the app's decoder ignores).
        let metadata: JSONValue
        let sharedContent: JSONValue?
        let photos: [Photo]
        let sharedFile: SharedFile?
        let wordTimings: String?
        let diarization: String?
        let enhancement: Enhancement?
        /// The corpus author's expected-behaviour note (`generate.py`'s `expect` dict) —
        /// prose only, read by the golden/expectation harness, never by app code.
        /// `{}` (no keys) when the note carries no specific expectation.
        let expect: Expect?

        struct Expect: Decodable {
            /// A plain expectation for this note's shape.
            let note: String?
            /// A known v1 defect this note demonstrates (v1's golden is expected to be wrong).
            let bug: String?
            /// A defect already fixed by the time this note was authored.
            let bugFixed: String?
            /// A behaviour Tuur hasn't ruled on yet — not a pass/fail criterion.
            let needsVerdict: String?
            enum CodingKeys: String, CodingKey {
                case note, bug
                case bugFixed = "bug-fixed"
                case needsVerdict = "needs-verdict"
            }
        }
    }

    /// Minimal JSON passthrough so a blob round-trips byte-for-byte in meaning.
    enum JSONValue: Decodable {
        case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null }
            else if let b = try? c.decode(Bool.self) { self = .bool(b) }
            else if let n = try? c.decode(Double.self) { self = .number(n) }
            else if let s = try? c.decode(String.self) { self = .string(s) }
            else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
            else { self = .object(try c.decode([String: JSONValue].self)) }
        }
        var foundation: Any {
            switch self {
            case .object(let o): return o.mapValues(\.foundation)
            case .array(let a): return a.map(\.foundation)
            case .string(let s): return s
            case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? Int(n) as Any : n
            case .bool(let b): return b
            case .null: return NSNull()
            }
        }
        var data: Data? { try? JSONSerialization.data(withJSONObject: foundation, options: [.sortedKeys]) }
    }

    struct Result: CustomStringConvertible {
        var inserted = 0, skipped = 0, assets = 0, enhancements = 0, people = 0
        var description: String {
            "corpus: \(inserted) notes inserted, \(skipped) already present, \(assets) assets, \(enhancements) enhancements, \(people) people"
        }
    }

    // MARK: seeding

    /// Load every note under `root` into `context`. Media files are stored as `MemoAsset`
    /// rows (what CloudKit would carry) AND written to `recordingsDirectory` under the app's
    /// own filenames, so filename-based readers on the phone find them without waiting for
    /// the materializer. `names` receives the roster (upsert, never a wipe).
    @discardableResult
    static func seed(from root: URL, into context: ModelContext, recordingsDirectory: URL,
                     names: NamesStore? = nil) throws -> Result {
        var result = Result()
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let existing = Set(((try? context.fetch(FetchDescriptor<Memo>())) ?? []).map(\.id))
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        for entry in manifest.notes {
            let folder = root.appendingPathComponent("notes").appendingPathComponent(entry.folder)
            let note = try JSONDecoder().decode(Note.self, from: Data(contentsOf: folder.appendingPathComponent("note.json")))
            guard let id = UUID(uuidString: note.id) else { continue }
            if existing.contains(id) { result.skipped += 1; continue }
            let memo = makeMemo(note, id: id)
            context.insert(memo)
            result.inserted += 1

            func asset(_ kind: String, _ filename: String, _ localFile: String) {
                let src = folder.appendingPathComponent(localFile)
                guard let blob = try? Data(contentsOf: src) else { return }
                context.insert(MemoAsset(memoID: id, kind: kind, filename: filename, blob: blob))
                try? blob.write(to: recordingsDirectory.appendingPathComponent(filename))
                result.assets += 1
            }
            if let audio = note.audio { asset(MemoAsset.Kind.audio, memo.audioFilename, audio) }
            for p in note.photos { asset(MemoAsset.Kind.photo, p.filename, p.file) }
            if let wt = note.wordTimings { asset(MemoAsset.Kind.wordTimings, "wt_\(id.uuidString).json", wt) }
            if let dz = note.diarization { asset(MemoAsset.Kind.diarization, "diar_\(id.uuidString).json", dz) }
            if let sf = note.sharedFile { asset(MemoAsset.Kind.document, sf.filename, sf.file) }

            if let e = note.enhancement, let at = date(e.enhancedAt) {
                context.insert(MemoEnhancement(
                    memoID: id, copyedit: e.copyedit, title: e.title, summary: e.summary,
                    enhancedByDeviceID: e.enhancedByDeviceID ?? "corpus", enhancedAt: at,
                    processedAt: date(e.processedAt)))
                result.enhancements += 1
            }
        }
        try context.save()

        if let names {
            let rosterURL = root.appendingPathComponent("names.json")
            if let data = try? Data(contentsOf: rosterURL),
               let roster = try? JSONDecoder().decode([Person].self, from: data) {
                for person in roster { names.upsert(person, replacing: nil) }
                result.people = roster.count
            }
        }
        return result
    }

    /// The `Memo` row for one corpus note — the phone's own field mapping, nothing derived.
    static func makeMemo(_ n: Note, id: UUID) -> Memo {
        let hasAudio = n.audio != nil
        let memo = Memo(
            id: id,
            audioFilename: hasAudio ? "memo_\(id.uuidString).m4a" : "",
            duration: n.duration,
            recordedAt: date(n.recordedAt) ?? Date(),
            tags: n.tags,
            syncStatus: .synced,
            title: n.title,
            transcript: n.transcript,
            transcriptStatus: TranscriptStatus(rawValue: n.transcriptStatus) ?? .pending,
            transcriptConfidence: n.transcriptConfidence,
            transcriptUserEdited: n.transcriptUserEdited,
            transcriptMarkersInjected: n.transcriptMarkersInjected,
            significance: n.significance,
            deletedAt: date(n.deletedAt),
            createdAt: date(n.createdAt) ?? date(n.recordedAt),
            editedAt: date(n.editedAt),
            metadataData: n.metadata.data,
            sharedContentData: n.sharedContent?.data,
            annotationText: n.annotationText,
            nameResolutionsData: nil,
            recordingDeviceID: n.recordingDeviceID ?? "corpus-phone-0001"
        )
        memo.destination = NoteDestination(rawValue: n.destination) ?? .personal
        memo.locked = n.locked
        memo.trashSeenAt = date(n.trashSeenAt)
        memo.keptAt = date(n.keptAt)
        memo.remindAt = date(n.remindAt)
        return memo
    }

    /// ISO-8601 with or without fractional seconds (the app's `ISO8601` insists on them;
    /// hand-written corpus dates don't carry them).
    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        if let d = ISO8601.date(from: s) { return d }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// The `-corpus <path>` launch argument, if given.
    static var launchPath: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-corpus"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath, isDirectory: true)
    }
}
#endif
