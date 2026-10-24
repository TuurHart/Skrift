import Foundation
import SwiftData

extension ReconcileV2 {

    /// First contact: a synced `Memo` + its assets become ONE working folder and ONE row, mapped
    /// field by field with no multipart detour (C44). The row id is the memo id (the contract
    /// spine). Everything here is plain file writes plus building an unsaved row; the sweep inserts
    /// it on the main actor and saves once.
    enum Ingest {

        /// What a memo is, from its own fields (C43, never sniffed from the bytes):
        /// - audio: it names an audio file (its blob may still be on its way: the row waits);
        /// - capture: something shared into Skrift (`sharedContent`), never transcribed;
        /// - typed: neither — words somebody typed.
        enum Kind: Equatable { case audio, capture, typed }

        nonisolated static func kind(of memo: Memo, hasAudioAsset: Bool) -> Kind? {
            if hasAudioAsset { return .audio }
            if jsonObject(memo.sharedContentData) != nil { return .capture }
            // A named audio file whose blob has not synced: NOT a typed note (it would strand its
            // audio forever, the 2026-07-25 case). No row yet; the next sweep retries.
            return memo.audioFilename.isEmpty ? .typed : nil
        }

        /// C42, the one trust rule for the phone's words on a Mac row: an audio row takes them only
        /// when they are final and trusted (`userEdited || confidence ≥ 0.7`), else the Mac's own
        /// ASR fills it; a typed note's words are its body. First contact and the reflect both ask.
        nonisolated static func phoneWords(_ memo: Memo, audio: Bool) -> String? {
            guard audio else { return memo.transcript }
            guard memo.transcriptStatus == .done,
                  Memo.isTrustedTranscript(userEdited: memo.transcriptUserEdited, confidence: memo.transcriptConfidence)
            else { return nil }
            return memo.transcript
        }

        /// The row's filename and the legacy-row match key: the memo's own, else `memo_<uuid>.m4a`.
        nonisolated static func audioFilename(for memo: Memo) -> String {
            memo.audioFilename.isEmpty ? "memo_\(memo.id.uuidString).m4a" : memo.audioFilename
        }

        /// A row's fields, its folder already written. Sendable: `prepare` may run on a background
        /// context (the first-enable ingest), `commit` builds the row on the main actor.
        struct Prepared: Sendable {
            var id: String, filename: String, path: String, size: Int, sourceType: SourceType
            var mediaSource: String?, transcript: String?, languageMode: String?
            var wordTimings: [WordTiming] = [], segments: [DiarizedSegment] = []
            var metadataJSON: Data, uploadedAt: Date?, title: String?, significance: Double?
        }

        /// One prepared memo: its fields, nothing yet (an audio memo whose blob has not arrived),
        /// or the error that stopped it.
        enum Attempt: Sendable { case ready(UUID, Prepared), waiting(UUID), failed(UUID, String) }

        nonisolated static func attempt(_ id: UUID, _ work: () throws -> Prepared?) -> Attempt {
            do { return try work().map { .ready(id, $0) } ?? .waiting(id) } catch { return .failed(id, String(describing: error)) }
        }

        /// Write `memo`'s working folder under `outputDir` and return the row's fields; nil =
        /// nothing to ingest yet. File writes only, no SwiftData row: safe off the main actor.
        nonisolated static func prepare(_ memo: Memo, assets: [MemoAsset], outputDir: URL) throws -> Prepared? {
            let audio = assets.first { $0.kind == MemoAsset.Kind.audio }
            guard let kind = kind(of: memo, hasAudioAsset: audio != nil) else { return nil }
            let id = memo.id.uuidString
            let blob = jsonObject(memo.metadataData)
            let words = memo.transcriptStatus == .done ? (memo.transcript ?? "") : ""
            let fm = FileManager.default
            var p: Prepared
            let folder: URL
            func base(_ filename: String, _ path: String, _ size: Int, _ type: SourceType) -> Prepared {
                Prepared(id: id, filename: filename, path: path, size: size, sourceType: type,
                         metadataJSON: metadataJSON(for: memo), uploadedAt: nil, title: nil, significance: nil)
            }

            switch kind {
            case .audio:
                let filename = audioFilename(for: memo)
                folder = outputDir.appendingPathComponent("\(id)_\(filename)", isDirectory: true)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let ext = (filename as NSString).pathExtension
                let original = folder.appendingPathComponent("original.\(ext.isEmpty ? "m4a" : ext)")
                let bytes = audio?.blob ?? Data()
                try bytes.write(to: original)
                // C63 / D172: the kept movie of a video note (only the one `videoFilename` names;
                // a video inside the body is not this note's source).
                if let name = memo.metadata?.videoFilename,
                   let movie = assets.first(where: { $0.kind == MemoAsset.Kind.video && $0.filename == name }),
                   !movie.blob.isEmpty {
                    try? movie.blob.write(to: folder.appendingPathComponent(VideoKeep.macSourceName(forAssetFilename: name)))
                }
                let size = ((try? fm.attributesOfItem(atPath: original.path))?[.size] as? Int) ?? bytes.count
                p = base(filename, original.path, size, .audio)
                p.mediaSource = SourceKind.mediaMarker(in: blob)
                // C42: the phone's words stand in for the Mac's ASR only when trusted, and the
                // sidecars (timings, diarization) only ever ride a trusted transcript.
                if !words.isEmpty, phoneWords(memo, audio: true) != nil {
                    (p.transcript, p.languageMode) = (words, memo.transcriptLanguageMode)
                    p.wordTimings = decodeTimings(assets) ?? []
                    p.segments = decodeDiarization(assets) ?? []
                }

            case .typed:
                // Shaped like an imported note: the words in `original.md`, the transcript done.
                folder = outputDir.appendingPathComponent("\(id)_note", isDirectory: true)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let dest = folder.appendingPathComponent("original.md")
                try Data(words.utf8).write(to: dest)
                p = base("\(id).md", dest.path, words.utf8.count, .note)
                if let media = (blob?["mediaSource"] as? String)?.trimmingCharacters(in: .whitespaces), !media.isEmpty {
                    p.mediaSource = media
                }
                p.transcript = words

            case .capture:
                let name = "capture_\(id)"
                folder = outputDir.appendingPathComponent(name, isDirectory: true)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                if let doc = assets.first(where: { $0.kind == MemoAsset.Kind.document }), !doc.blob.isEmpty {
                    let dir = folder.appendingPathComponent("files", isDirectory: true)
                    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    try? doc.blob.write(to: dir.appendingPathComponent(doc.filename))
                }
                if let thumb = assets.first(where: { $0.kind == MemoAsset.Kind.thumbnail }), !thumb.blob.isEmpty,
                   !thumb.filename.isEmpty, !thumb.filename.contains("/") {
                    try? thumb.blob.write(to: folder.appendingPathComponent(thumb.filename))
                }
                p = base(name, folder.path, 0, .capture)
                // The annotation is the body; non-nil even when empty, so nothing is ever heard.
                p.transcript = memo.annotationText ?? ""
            }

            if kind != .capture {
                // C188: the CONTENT date (a video keeps its filming date), never ingest time. A
                // capture keeps its arrival time and carries no title of its own.
                p.uploadedAt = memo.recordedAt
                if let title = memo.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { p.title = title }
            }
            if memo.significance > 0 { p.significance = memo.significance }
            try writePhotos(assets.filter { $0.kind == MemoAsset.Kind.photo }.sorted { $0.filename < $1.filename },
                            manifest: (blob?["imageManifest"] as? [[String: Any]]) ?? [], into: folder)
            return p
        }

        /// The rows for prepared memos, on the main actor: insert, first contact, then the fresh
        /// reflect (C46: the cloud's polish, this Mac's own included, may be the only copy). A
        /// memo trashed or un-rated while it was prepared, or that already has a row, is skipped.
        /// `save`: false inside the sweep (it saves once); true for the background ingest's commit.
        @discardableResult
        static func commit(_ attempts: [Attempt], memos: [Memo], enhancements: [UUID: MemoEnhancement],
                           into local: ModelContext, context ctx: Context, outcome: inout Outcome,
                           save: Bool) -> [PipelineFile] {
            let byID = Dictionary(memos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let have = Set(((try? local.fetch(FetchDescriptor<PipelineFile>())) ?? []).map(\.id))
            var rows: [PipelineFile] = []
            for a in attempts {
                switch a {
                case .failed(let id, let message):
                    outcome.ingestFailures += 1
                    AppLog.cloudkit.error("reconcile v2: ingest of \(id, privacy: .public) failed: \(message, privacy: .public)")
                case .waiting(let id):
                    if let m = byID[id], m.deletedAt == nil, NoteConsent.isRated(m) {
                        outcome.stranded += 1
                        AppLog.cloudkit.error("reconcile v2: rated memo \(id, privacy: .public) still has no row (waiting for its audio)")
                    }
                case .ready(let id, let p):
                    guard let memo = byID[id], memo.deletedAt == nil, NoteConsent.isRated(memo), !have.contains(p.id) else { continue }
                    let row = makeRow(p, memo: memo)
                    local.insert(row)
                    outcome.created += 1
                    rows.append(row)
                    if Reflect.apply(memo: memo, enhancement: enhancements[id], to: row, context: ctx, freshRow: true).changed {
                        outcome.updatedIDs.append(row.id)
                    }
                }
            }
            if save, !rows.isEmpty {
                ReconcileWork.bump(\.saves)
                do { try local.save() } catch {
                    AppLog.cloudkit.error("reconcile v2: ingest save failed: \(String(describing: error), privacy: .public)")
                }
            }
            return rows
        }

        static func makeRow(_ p: Prepared, memo: Memo) -> PipelineFile {
            let row = PipelineFile(id: p.id, filename: p.filename, path: p.path, size: p.size, sourceType: p.sourceType)
            row.audioMetadataJSON = p.metadataJSON
            if let d = p.uploadedAt { row.uploadedAt = d }
            if let m = p.mediaSource { row.mediaSource = m }
            if let t = p.title { row.enhancedTitle = t }
            if let s = p.significance { row.significance = s }
            if let t = p.transcript {
                row.transcript = t
                row.transcriptLanguageMode = p.languageMode
                row.transcribeStatus = .done
            }
            if !p.wordTimings.isEmpty { row.wordTimings = p.wordTimings }
            if !p.segments.isEmpty { row.diarizationSegments = p.segments }
            firstContact(row, memo: memo)
            return row
        }

        /// What a fresh row takes from its memo beyond its folder (lock, reminder, tags, rating,
        /// destination, edit time, name decisions, the audio-export switch, OCR) and the
        /// watermark a later phone edit is measured against.
        static func firstContact(_ row: PipelineFile, memo: Memo) {
            row.syncedSourceEditedAt = memo.lastEditedAt
            row.imageOCRText = ocrText(for: memo)
            for field in Fields.all { _ = field.adopt(memo, row) }
            NameResolutionsMirror.pull(memo, into: row)
            ExportAudioMirror.pull(memo, into: row)
        }

        nonisolated static func decodeTimings(_ assets: [MemoAsset]) -> [WordTiming]? {
            guard let a = assets.first(where: { $0.kind == MemoAsset.Kind.wordTimings }), !a.blob.isEmpty,
                  let words = try? JSONDecoder().decode([WordTiming].self, from: a.blob), !words.isEmpty else { return nil }
            return words
        }

        nonisolated static func decodeDiarization(_ assets: [MemoAsset]) -> [DiarizedSegment]? {
            guard let a = assets.first(where: { $0.kind == MemoAsset.Kind.diarization }), !a.blob.isEmpty,
                  let d = try? JSONDecoder().decode(PhoneDiarizationBlob.self, from: a.blob), !d.segments.isEmpty
            else { return nil }
            return d.segments
        }

        /// The photos under `images/` plus `image_manifest.json`, named from the memo's manifest.
        /// C41: the manifest is written even when no photo blob has arrived yet, so the photo
        /// heal of a later sweep finds the names it waits for (v1 wrote none, and its second sweep
        /// wrote it as a "heal" — `pic-missing-file`).
        nonisolated private static func writePhotos(_ photos: [MemoAsset], manifest: [[String: Any]], into folder: URL) throws {
            guard !photos.isEmpty || !manifest.isEmpty else { return }
            var saved: [[String: Any]] = []
            if !photos.isEmpty {
                let dir = folder.appendingPathComponent("images", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for (i, photo) in photos.enumerated() {
                    let entry = i < manifest.count ? manifest[i] : [:]
                    let name = (entry["filename"] as? String)
                        ?? (photo.filename.isEmpty ? String(format: "img_%03d.jpg", i + 1) : photo.filename)
                    try photo.blob.write(to: dir.appendingPathComponent(name))
                    saved.append(["filename": name, "offsetSeconds": entry["offsetSeconds"] ?? 0])
                }
            } else {
                saved = manifest.compactMap { e in
                    (e["filename"] as? String).map { ["filename": $0, "offsetSeconds": e["offsetSeconds"] ?? 0] }
                }
            }
            let data = try JSONSerialization.data(withJSONObject: saved, options: [.prettyPrinted])
            try data.write(to: folder.appendingPathComponent("image_manifest.json"))
        }

        // MARK: - the row's copy of the memo's metadata

        /// The phone's metadata blob overlaid with the memo-level fields every Mac reader expects
        /// (source, tags, dates, duration, trust flags, title, rating, annotation, shared
        /// content). Sorted keys: the same memo always gives the same bytes, so the reflect can
        /// compare bytes.
        nonisolated static func metadataJSON(for memo: Memo) -> Data {
            let key = MetadataKey(memo)
            cacheLock.lock()
            let hit = metadataCache[memo.id]
            cacheLock.unlock()
            if let hit, hit.key == key { return hit.json }
            ReconcileWork.bump(\.metadataSerialisations)
            var dict = jsonObject(memo.metadataData) ?? [:]
            dict["source"] = "mobile"
            dict["tags"] = memo.tags
            dict["recordedAt"] = ISO8601.string(from: memo.recordedAt)
            dict["duration"] = memo.duration
            dict["transcriptUserEdited"] = memo.transcriptUserEdited
            dict["transcriptMarkersInjected"] = memo.transcriptMarkersInjected
            if let c = memo.transcriptConfidence { dict["transcriptConfidence"] = c }
            if let t = memo.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { dict["title"] = t }
            if memo.significance > 0 { dict["significance"] = memo.significance }
            if let a = memo.annotationText { dict["annotationText"] = a }
            if let sc = jsonObject(memo.sharedContentData) { dict["sharedContent"] = sc }
            let json = (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])) ?? Data("{}".utf8)
            cacheLock.lock()
            metadataCache[memo.id] = (key, json)
            cacheLock.unlock()
            return json
        }

        /// Every memo field `metadataJSON` reads: an equal key gives equal bytes.
        private struct MetadataKey: Equatable {
            let metadata, shared: Data?
            let tags: [String]
            let recordedAt: Date
            let duration: TimeInterval
            let edited, markers: Bool
            let confidence: Double?
            let title: String?
            let significance: Double
            let annotation: String?
            init(_ m: Memo) {
                (metadata, shared, tags, recordedAt, duration) = (m.metadataData, m.sharedContentData, m.tags, m.recordedAt, m.duration)
                (edited, markers, confidence) = (m.transcriptUserEdited, m.transcriptMarkersInjected, m.transcriptConfidence)
                (title, significance, annotation) = (m.title, m.significance, m.annotationText)
            }
        }
        /// Locked: `prepare` builds metadata off the main actor while the sweep reads it on it.
        nonisolated(unsafe) private static var metadataCache: [UUID: (key: MetadataKey, json: Data)] = [:]
        nonisolated private static let cacheLock = NSLock()

        /// The photos' OCR text joined, for search (`imageManifest[].text`). nil when none.
        nonisolated static func ocrText(for memo: Memo) -> String? {
            let texts = (memo.metadata?.imageManifest ?? [])
                .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return texts.isEmpty ? nil : texts.joined(separator: "\n")
        }

        nonisolated static func jsonObject(_ data: Data?) -> [String: Any]? {
            data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        }
    }
}
