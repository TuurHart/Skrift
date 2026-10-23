import Foundation
import SwiftData

extension ReconcileV2 {

    /// What assets exist, read from ONE blob-free fetch (memo id, kind, filename, size). An asset row
    /// faults in its whole blob when touched, so the sweep decides from this index whether a
    /// memo's blobs are needed at all; an unchanged store fetches none (R29), and a manifest that
    /// names a photo whose blob never synced costs nothing either.
    final class AssetIndex {
        private let context: ModelContext
        private var names: [UUID: [String: [String: Int]]]?   // memo → kind → filename → bytes
        private var loaded: [UUID: [MemoAsset]] = [:]

        init(_ context: ModelContext) { self.context = context }

        /// `minBytes`: an asset smaller than this holds nothing worth reading (an empty timings
        /// list is `[]`), so a note whose timings asset is empty costs no fetch every sweep.
        func has(_ memoID: UUID, _ kind: String, named filename: String? = nil, minBytes: Int = 1) -> Bool {
            if names == nil {
                ReconcileWork.bump(\.assetIndexFetches)
                var d = FetchDescriptor<MemoAsset>()
                d.propertiesToFetch = [\.memoID, \.kind, \.filename, \.byteCount]
                var built: [UUID: [String: [String: Int]]] = [:]
                for a in (try? context.fetch(d)) ?? [] { built[a.memoID, default: [:]][a.kind, default: [:]][a.filename] = a.byteCount }
                names = built
            }
            guard let files = names?[memoID]?[kind] else { return false }
            if let filename { return (files[filename] ?? 0) >= minBytes }
            return files.values.contains { $0 >= minBytes }
        }

        /// The memo's asset rows WITH their blobs: fetched at most once per memo per sweep.
        func blobs(for memoID: UUID) -> [MemoAsset] {
            if let hit = loaded[memoID] { return hit }
            ReconcileWork.bump(\.assetBlobFetches)
            let rows = (try? context.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == memoID }))) ?? []
            loaded[memoID] = rows
            return rows
        }
    }

    /// Late assets on an existing row (C45): CloudKit delivers asset rows independently of the
    /// memo, so a photo, a movie, a link thumbnail, word timings or a diarization can arrive after
    /// the row was made. Each heal fills a hole and never overwrites what the Mac made; each is
    /// idempotent, so a settled row costs nothing on the next sweep.
    enum Heal {

        /// Run every heal; true when one wrote something.
        static func run(memo: Memo, row: PipelineFile, assets: AssetIndex, transcriptChanged: Bool) -> Bool {
            var wrote = false
            if let folder = row.workingFolder {
                wrote = linkThumbnail(memo, folder, assets) || wrote
                wrote = keptMovie(memo, folder, assets) || wrote
                wrote = attachments(memo, folder, assets) || wrote
                wrote = photos(memo, folder, assets) || wrote
            }
            wrote = timings(memo, row, assets) || wrote
            wrote = diarization(memo, row, assets, transcriptChanged: transcriptChanged) || wrote
            return wrote
        }

        /// Q260: a link capture's thumbnail, beside the capture.
        static func linkThumbnail(_ memo: Memo, _ folder: URL, _ assets: AssetIndex) -> Bool {
            guard let name = MemoAsset.Kind.linkThumbnailFilename(memo.sharedContent) else { return false }
            let dest = folder.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: dest.path),
                  assets.has(memo.id, MemoAsset.Kind.thumbnail, named: name),
                  let thumb = assets.blobs(for: memo.id).first(where: { $0.kind == MemoAsset.Kind.thumbnail && $0.filename == name }),
                  !thumb.blob.isEmpty else { return false }
            return write(thumb.blob, to: dest)
        }

        /// C63 / D172: a video note's kept movie, as `source.<ext>` where the export looks.
        static func keptMovie(_ memo: Memo, _ folder: URL, _ assets: AssetIndex) -> Bool {
            guard let name = memo.metadata?.videoFilename, !name.isEmpty,
                  VaultExporter.keptSourceVideo(in: folder) == nil,
                  assets.has(memo.id, MemoAsset.Kind.video, named: name),
                  let movie = assets.blobs(for: memo.id).first(where: { $0.kind == MemoAsset.Kind.video && $0.filename == name }),
                  !movie.blob.isEmpty else { return false }
            return write(movie.blob, to: folder.appendingPathComponent(VideoKeep.macSourceName(forAssetFilename: name)))
        }

        /// D199: the body's videos and files, under `attachments/` with their manifest. A file
        /// whose asset has not synced is skipped by name (the index), so it costs no fetch.
        static func attachments(_ memo: Memo, _ folder: URL, _ assets: AssetIndex) -> Bool {
            let entries = memo.metadata?.attachmentManifest ?? []
            guard !entries.isEmpty else { return false }
            let fm = FileManager.default
            let dir = MacNoteAttachments.folder(in: folder)
            let kinds = [MemoAsset.Kind.file, MemoAsset.Kind.video]
            let missing = Set(entries.map(\.filename).filter { name in
                !name.isEmpty && !NoteAttachment.isKeptMovie(name)
                    && !fm.fileExists(atPath: dir.appendingPathComponent(name).path)
                    && kinds.contains { assets.has(memo.id, $0, named: name) }
            })
            var wrote = false
            for a in missing.isEmpty ? [] : assets.blobs(for: memo.id)
            where missing.contains(a.filename) && kinds.contains(a.kind) && !a.blob.isEmpty {
                wrote = write(a.blob, to: dir.appendingPathComponent(a.filename)) || wrote
            }
            if MacNoteAttachments.manifest(in: folder) != entries, let data = try? JSONEncoder().encode(entries) {
                wrote = write(data, to: folder.appendingPathComponent(MacNoteAttachments.manifestName)) || wrote
            }
            return wrote
        }

        /// Photos the memo's manifest names but the folder lacks (a picture added while editing a
        /// synced note), and the manifest file brought in line when its filenames differ — the
        /// marker `[[img_NNN]]` resolves through the Nth entry.
        static func photos(_ memo: Memo, _ folder: URL, _ assets: AssetIndex) -> Bool {
            let manifest = memo.metadata?.imageManifest ?? []
            guard !manifest.isEmpty else { return false }
            let fm = FileManager.default
            let dir = folder.appendingPathComponent("images", isDirectory: true)
            var wrote = false
            let missing = Set(manifest.map(\.filename).filter {
                !$0.isEmpty && !fm.fileExists(atPath: dir.appendingPathComponent($0).path)
                    && assets.has(memo.id, MemoAsset.Kind.photo, named: $0)
            })
            if !missing.isEmpty {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                for photo in assets.blobs(for: memo.id) where photo.kind == MemoAsset.Kind.photo && missing.contains(photo.filename) {
                    wrote = write(photo.blob, to: dir.appendingPathComponent(photo.filename)) || wrote
                }
            }
            let url = folder.appendingPathComponent("image_manifest.json")
            let have = ((try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? [])
                .compactMap { $0["filename"] as? String }
            if have != manifest.map(\.filename),
               let data = try? JSONSerialization.data(withJSONObject: manifest.map { ["filename": $0.filename, "offsetSeconds": $0.offsetSeconds] },
                                                      options: [.prettyPrinted]) {
                wrote = write(data, to: url) || wrote
            }
            return wrote
        }

        /// Word timings that synced after the row was made: only into a row with none (the Mac's
        /// own ASR timings are never replaced) and only beside a finished transcript.
        static func timings(_ memo: Memo, _ row: PipelineFile, _ assets: AssetIndex) -> Bool {
            guard row.wordTimingsJSON?.isEmpty ?? true, row.transcribeStatus == .done,
                  !(row.transcript ?? "").isEmpty, assets.has(memo.id, MemoAsset.Kind.wordTimings, minBytes: 3),
                  let words = Ingest.decodeTimings(assets.blobs(for: memo.id)) else { return false }
            row.wordTimings = words
            return true
        }

        /// The phone's diarization. Adopted into a row with none (a late asset, C45), and — R57 —
        /// re-adopted whenever it changes: v1 adopted once per memo, so a conversation re-split on
        /// the phone kept its first segments on the Mac. Staleness is the CONTENT (the decoded
        /// segments), never a byte count, and it is only looked at when this sweep changed the
        /// row's transcript to the phone's trusted words (a re-split always rewrites the turns),
        /// so a steady sweep reads no diarization blob and a Mac-made split is never replaced.
        static func diarization(_ memo: Memo, _ row: PipelineFile, _ assets: AssetIndex, transcriptChanged: Bool) -> Bool {
            guard row.transcribeStatus == .done, !(row.transcript ?? "").isEmpty,
                  assets.has(memo.id, MemoAsset.Kind.diarization) else { return false }
            let empty = row.diarizationSegmentsJSON?.isEmpty ?? true
            let phoneWords = transcriptChanged && row.transcript == memo.transcript
                && Memo.isTrustedTranscript(userEdited: memo.transcriptUserEdited, confidence: memo.transcriptConfidence)
            guard empty || phoneWords,
                  let segments = Ingest.decodeDiarization(assets.blobs(for: memo.id)),
                  segments != row.diarizationSegments else { return false }
            row.diarizationSegments = segments
            return true
        }

        private static func write(_ data: Data, to url: URL) -> Bool {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return (try? data.write(to: url)) != nil
        }
    }
}
