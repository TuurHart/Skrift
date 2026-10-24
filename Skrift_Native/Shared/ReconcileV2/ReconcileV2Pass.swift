import Foundation
import SwiftData
import AVFoundation

extension ReconcileV2 {

    /// One reconcile pass around the sweep, in C185's order (`Step`): the carriers (names,
    /// vocabulary, prompts) first so linking sees the fresh roster, the sweep, the orphan trash,
    /// the save, the Mac's own memos (author backfill, then its transcripts), and the rows to
    /// re-export (C189). Synchronous on the main actor like the sweep (C294). The notice, the
    /// re-export itself and the connections index are the app's (they need its singletons).
    struct PassOutcome {
        var sweep = Outcome()
        var orphansTrashed = 0
        var authored = 0
        var reflectedTranscripts = 0
        /// Rows a phone change rewrote that are already in the vault (C189).
        var reexportIDs: [String] = []
        var snapshot = Snapshot()
    }

    /// `firstImportDone` (Q397, D203): until the cloud store's first CloudKit import has finished,
    /// a memo that is missing may simply not have downloaded — so nothing is authored and no row
    /// is trashed as an orphan before then.
    @discardableResult
    static func pass(cloud: ModelContext, local: ModelContext, context ctx: Context,
                     firstImportDone: Bool, deferNew: Bool = false, carriers: () -> Void = {},
                     fetchMemos: (ModelContext) throws -> [Memo] = { try $0.fetch(FetchDescriptor<Memo>()) })
        -> PassOutcome {
        carriers()
        var result = PassOutcome()
        (result.sweep, result.snapshot) = run(cloud: cloud, local: local, context: ctx, deferNew: deferNew, fetchMemos: fetchMemos)
        guard result.sweep.fetchFailure == nil else { return result }   // R40: nothing read, nothing to act on

        if firstImportDone {
            result.orphansTrashed = Orphans.trash(result.snapshot.rows, rowsWithMemo: result.snapshot.rowsWithMemo,
                                                  memoCount: result.snapshot.memos.count, inFlight: ctx.inFlight, now: ctx.now)
            if result.orphansTrashed > 0 { save(local, "orphan trash") }
        }
        var memosByID = Dictionary(result.snapshot.memos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        result.authored = Author.backfill(result.snapshot.rows, into: cloud, memosByID: &memosByID,
                                          firstImportDone: firstImportDone, context: ctx)
        result.reflectedTranscripts = Author.reflectTranscripts(result.snapshot.rows, into: cloud,
                                                                memosByID: memosByID, deviceID: ctx.thisDeviceID)
        if result.authored + result.reflectedTranscripts > 0 { save(cloud, "author / reflect") }
        result.reexportIDs = reexportIDs(updated: result.sweep.updatedIDs, rows: result.snapshot.rows)
        return result
    }

    private static func save(_ context: ModelContext, _ what: String) {
        ReconcileWork.bump(\.saves)
        do { try context.save() } catch {
            AppLog.cloudkit.error("reconcile v2: \(what, privacy: .public) save failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - C157: rows whose memo is gone

    enum Orphans {
        /// A live row that once had a memo (it carries a watermark) and has none now — purged on
        /// another device — goes to the trash. The vault file stays (C156); Restore brings the row
        /// back. Refused, and logged, when the store holds no memos or when more than a quarter of
        /// the linked rows (and more than two) would go at once (Q487): that is a different or
        /// half-downloaded store, never a purge, which only takes notes out of the trash one by one.
        /// A memo whose background ingest is running is not an orphan.
        @discardableResult
        static func trash(_ rows: [PipelineFile], rowsWithMemo: Set<String>, memoCount: Int,
                          inFlight: Set<UUID>, now: Date) -> Int {
            let linked = rows.filter { $0.deletedAt == nil && $0.syncedSourceEditedAt != nil }
            let orphans = linked.filter { row in
                !rowsWithMemo.contains(row.id) && !(UUID(uuidString: row.id).map(inFlight.contains) ?? false)
            }
            guard !orphans.isEmpty else { return 0 }
            guard memoCount > 0, orphans.count <= 2 || orphans.count * 4 <= linked.count else {
                AppLog.cloudkit.error("reconcile v2: \(orphans.count, privacy: .public) of \(linked.count, privacy: .public) linked rows lost their memo; not trashing (store holds \(memoCount, privacy: .public)), a different store, not a purge")
                return 0
            }
            for row in orphans { (row.deletedAt, row.lastActivityAt) = (now, now) }
            return orphans.count
        }
    }

    // MARK: - the Mac's own memos (C186: one door, the store resolves)

    enum Author {

        /// Q397: only a row THIS Mac captured (recorded or imported), live, after the first
        /// import. A row ingested from a phone memo carries the phone's id; authoring it on a
        /// fresh store would upload a Mac-shaped twin the phone never heals.
        static func mayBackfill(_ row: PipelineFile, firstImportDone: Bool) -> Bool {
            firstImportDone && row.isLocalCapture && row.deletedAt == nil
        }

        /// A memo for every Mac-captured row that has none (a take that raced the sweep, an import
        /// made with sync off). `memosByID` is the sweep's one id → memo map, grown as it goes.
        static func backfill(_ rows: [PipelineFile], into cloud: ModelContext, memosByID: inout [UUID: Memo],
                             firstImportDone: Bool, context ctx: Context) -> Int {
            guard firstImportDone else { return 0 }
            var count = 0
            for row in rows where mayBackfill(row, firstImportDone: true) && !row.path.isEmpty {
                guard let id = UUID(uuidString: row.id), memosByID[id] == nil else { continue }
                do {
                    if let memo = try author(row, into: cloud, deviceID: ctx.thisDeviceID) { memosByID[id] = memo; count += 1 }
                } catch {
                    AppLog.cloudkit.error("reconcile v2: authoring \(row.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                }
            }
            return count
        }

        /// The memo a Mac row becomes: the phone's shape (C71, R36) — metadata, audio, photos,
        /// attachments, a capture's document, a video's kept movie. Never floors the rating
        /// (D159: rating is consent). Idempotent: an id that has a memo is left alone. Does not
        /// save. The one author for every door (the sweep's backfill, a take's arrival, an import).
        static func author(_ row: PipelineFile, into cloud: ModelContext, deviceID: String = "") throws -> Memo? {
            guard let id = UUID(uuidString: row.id) else { return nil }
            ReconcileWork.bump(\.memoFetches)
            guard try cloud.fetchCount(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })) == 0 else { return nil }
            let shape = Shape(row, memoID: id)
            let capture = row.sourceType == .capture ? SharedContent.decode(from: row.audioMetadataJSON) : nil
            let words = row.transcript ?? ""
            let audioURL = row.sourceType == .audio && !row.path.isEmpty ? URL(fileURLWithPath: row.path) : nil
            let memo = Memo(id: id, audioFilename: shape.audioFilename,
                            duration: shape.hasAudio ? (duration(of: audioURL) ?? 0) : 0,
                            recordedAt: row.uploadedAt, significance: row.significance ?? 0,
                            metadataData: shape.metadata, sharedContentData: Memo.encodeJSON(capture),
                            annotationText: capture == nil || words.isEmpty ? nil : words,
                            recordingDeviceID: deviceID.isEmpty ? DeviceID.current() : deviceID)
            if capture == nil, let text = IngestService.bundleAnnotation(in: row.audioMetadataJSON) { memo.annotationText = text }
            ExportAudioMirror.push(row, to: memo)
            if capture != nil {
                memo.transcriptStatus = .done   // a capture's words are its annotation
            } else if !words.isEmpty {
                // Words already here on a fresh Mac take means a person edited it (the arrival
                // seeds the row only for an edited take).
                markTranscribed(memo, words, userEdited: row.isLocalRecording, row: row)
            }
            cloud.insert(memo)
            if capture == nil, !words.isEmpty { timingAssets(row, memoID: id, in: cloud) }

            func asset(_ kind: String, _ name: String, _ url: URL, nonEmpty: Bool = false) {
                guard let blob = try? Data(contentsOf: url, options: .mappedIfSafe), !(nonEmpty && blob.isEmpty) else { return }
                cloud.insert(MemoAsset(memoID: id, kind: kind, filename: name, blob: blob))
            }
            if shape.hasAudio, let audioURL, FileManager.default.fileExists(atPath: audioURL.path) {
                asset(MemoAsset.Kind.audio, shape.audioFilename, audioURL)
            }
            for p in shape.photos { asset(MemoAsset.Kind.photo, p.filename, p.source) }
            for a in shape.attachments { asset(a.kind, a.filename, a.source, nonEmpty: true) }
            if let name = capture?.filePath, !name.isEmpty, let folder = row.workingFolder {
                asset(MemoAsset.Kind.document, name, folder.appendingPathComponent("files").appendingPathComponent(name))
            }
            keptMovie(row, memo: memo, in: cloud)
            return memo
        }

        /// The Mac's own words onto the memo it authored, once its transcript is final: only this
        /// device's memos, only when the memo has no words yet, never a capture (its words are its
        /// annotation), and never the rough caption seed of a take still decoding. No edit-time
        /// bump (C188). Word timings and diarization ride along as the phone's assets (C245).
        /// `memosByID` nil = fetch the rows' memos (a caller outside the pass, e.g. after a run).
        static func reflectTranscripts(_ rows: [PipelineFile], into cloud: ModelContext,
                                       memosByID given: [UUID: Memo]? = nil, deviceID: String = "") -> Int {
            let me = deviceID.isEmpty ? DeviceID.current() : deviceID
            let memosByID = given ?? {
                let ids = rows.compactMap { UUID(uuidString: $0.id) }
                ReconcileWork.bump(\.memoFetches)
                let memos = (try? cloud.fetch(FetchDescriptor<Memo>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
                return Dictionary(memos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            }()
            var count = 0
            for row in rows where row.transcribeStatus == .done {
                guard let words = row.transcript, !words.isEmpty, let id = UUID(uuidString: row.id),
                      let memo = memosByID[id], memo.recordingDeviceID == me, memo.sharedContentData == nil,
                      (memo.transcript ?? "").isEmpty else { continue }
                markTranscribed(memo, words, userEdited: false, row: row)
                timingAssets(row, memoID: id, in: cloud)
                count += 1
            }
            return count
        }

        private static func markTranscribed(_ memo: Memo, _ words: String, userEdited: Bool, row: PipelineFile) {
            // Body v2 (C10): a body with pictures goes through the one writer; one without is
            // stored as is (an imported note's nested-list indentation must survive).
            let manifest = memo.metadata?.imageManifest ?? []
            memo.transcript = BodyV2Marker.runs(in: words, manifestCount: manifest.count).isEmpty ? words
                : BodyV2.committed(BodyV2.Input(text: words, manifest: manifest, source: .speech, userEdited: userEdited))
            memo.transcriptStatus = .done
            memo.transcriptConfidence = 1.0
            memo.transcriptUserEdited = userEdited
            memo.transcriptLanguageMode = row.transcriptLanguageMode   // C151: the stamp rides with the words
        }

        /// C245: the take's word timings, and its diarization when split, as the phone's assets.
        static func timingAssets(_ row: PipelineFile, memoID: UUID, in cloud: ModelContext) {
            if let blob = TimingAssets.wordTimingsBlob(row.wordTimings) {
                TimingAssets.upsert(kind: MemoAsset.Kind.wordTimings, filename: TimingAssets.wordTimingsFilename(for: memoID),
                                    blob: blob, memoID: memoID, in: cloud)
            }
            if let d = TimingAssets.diarization(segments: row.diarizationSegments,
                                                turnNames: SpeakerTranscript.parse(row.transcript)?.map(\.name) ?? []),
               let blob = TimingAssets.diarizationBlob(d) {
                TimingAssets.upsert(kind: MemoAsset.Kind.diarization, filename: TimingAssets.diarizationFilename(for: memoID),
                                    blob: blob, memoID: memoID, in: cloud)
            }
        }

        /// C63 / D188: a video row's kept movie as the memo's one `video` asset, whatever its
        /// destination. Idempotent.
        @discardableResult
        static func keptMovie(_ row: PipelineFile, memo: Memo, in cloud: ModelContext) -> Bool {
            guard let name = memo.metadata?.videoFilename, !name.isEmpty, let folder = row.workingFolder,
                  let movie = VaultExporter.keptSourceVideo(in: folder),
                  let bytes = VideoKeep.byteCount(of: movie), VideoKeep.fits(byteCount: bytes) else { return false }
            let id = memo.id, kind = MemoAsset.Kind.video
            guard ((try? cloud.fetchCount(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id && $0.kind == kind }))) ?? 1) == 0,
                  let blob = try? Data(contentsOf: movie, options: .mappedIfSafe) else { return false }
            cloud.insert(MemoAsset(memoID: id, kind: kind, filename: name, blob: blob))
            return true
        }

        private static func duration(of url: URL?) -> TimeInterval? {
            guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
            let seconds = CMTimeGetSeconds(AVURLAsset(url: url).duration)
            return seconds.isFinite && seconds > 0 ? seconds : nil
        }

        /// What a Mac row's memo carries, read from its working folder (Q139): the audio filename
        /// (a video or merged note is named after the memo, not its source), the metadata blob
        /// (media marker, place, clip manifest, picture and attachment manifests, kept movie) and
        /// the files that become assets.
        struct Shape {
            var audioFilename = "", hasAudio = false
            var metadata: Data?
            var photos: [(source: URL, filename: String)] = []
            var attachments: [(source: URL, filename: String, kind: String)] = []

            init(_ row: PipelineFile, memoID: UUID) {
                hasAudio = row.sourceType == .audio
                let ext = (row.path as NSString).pathExtension
                if hasAudio {
                    let same = ext.isEmpty || (row.filename as NSString).pathExtension.caseInsensitiveCompare(ext) == .orderedSame
                    audioFilename = same ? row.filename : "memo_\(memoID.uuidString).\(ext)"
                }
                var meta = MemoMetadata()
                let fm = FileManager.default
                if let folder = row.workingFolder {
                    let entries = MacNoteAttachments.manifest(in: folder)
                    if !entries.isEmpty {
                        meta.attachmentManifest = entries
                        for e in entries {
                            let source = MacNoteAttachments.folder(in: folder).appendingPathComponent(e.filename)
                            if fm.fileExists(atPath: source.path) { attachments.append((source, e.filename, e.kind)) }
                        }
                    }
                    if let data = try? Data(contentsOf: folder.appendingPathComponent("image_manifest.json")),
                       let images = try? JSONDecoder().decode([ImageManifestEntry].self, from: data), !images.isEmpty {
                        let dir = folder.appendingPathComponent("images", isDirectory: true)
                        meta.imageManifest = images.enumerated().map { i, entry in
                            let x = (entry.filename as NSString).pathExtension.lowercased()
                            let name = "photo_\(memoID.uuidString)_\(String(format: "%03d", i + 1)).\(x.isEmpty ? "jpg" : x)"
                            let source = dir.appendingPathComponent(entry.filename)
                            if fm.fileExists(atPath: source.path) { photos.append((source, name)) }
                            var renamed = entry
                            renamed.filename = name
                            return renamed
                        }
                    }
                    if hasAudio, let data = try? Data(contentsOf: folder.appendingPathComponent(IngestService.clipManifestName)),
                       let clips = try? JSONDecoder().decode([ClipManifestEntry].self, from: data), !clips.isEmpty {
                        meta.clipManifest = clips
                    }
                }
                if row.mediaSource == MemoMetadata.Source.video {
                    meta.sourceType = MemoMetadata.Source.video
                    if let folder = row.workingFolder, let movie = VaultExporter.keptSourceVideo(in: folder),
                       let bytes = VideoKeep.byteCount(of: movie), VideoKeep.fits(byteCount: bytes) {
                        meta.videoFilename = VideoKeep.filename(memoID: memoID, sourceExtension: movie.pathExtension)
                    }
                }
                struct Carrier: Decodable { var location: LocationInfo? }
                meta.location = row.audioMetadataJSON.flatMap { try? JSONDecoder().decode(Carrier.self, from: $0) }?.location
                let media = row.mediaSource?.trimmingCharacters(in: .whitespaces) ?? ""
                guard meta != MemoMetadata() || !media.isEmpty, let encoded = try? JSONEncoder().encode(meta),
                      var obj = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] else { return }
                if !media.isEmpty { obj["mediaSource"] = media }
                metadata = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
            }
        }
    }
}
