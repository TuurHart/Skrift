import Foundation
import SwiftData

/// "Export all notes…" on the Mac (D218, D219, Q516): the Mac's notes as `ExportAll.Item`s.
/// Every row not in the trash, then every live memo the Mac has no row for (an unrated note,
/// projected the way the note view opens it, `MemoNoteProjection`). Locked notes go in (D219).
/// Each item compiles through the vault export's own v2 builder (`v2Note`) with a placer that
/// only records which file goes in under which name: no gate, no ledger, no vault.
extension VaultExporter {

    @MainActor
    static func exportAllItems(rows: [PipelineFile], memos: [Memo], assets: @escaping (UUID) -> [MemoAsset],
                               people: [Person], author: String) -> [ExportAll.Item] {
        let live = rows.filter { $0.deletedAt == nil }
        let covered = Set(rows.flatMap { ReconcileV2.Writers.candidates(for: $0) })
        var items = live.map { pf in item(pf, people: people, author: author, prepare: {}) }
        for memo in MemoDuplicates.canonicalRows(memos) where memo.deletedAt == nil && !covered.contains(memo.id) {
            let pf = MemoNoteProjection.file(for: memo)
            items.append(item(pf, people: people, author: author, prepare: {
                MemoNoteProjection.materialiseMedia(for: memo, into: pf) { assets(memo.id) }
                _ = MacNoteAttachments.materializeMissing(memo: memo, pf: pf) { assets(memo.id) }
            }, document: {
                assets(memo.id).first { $0.kind == MemoAsset.Kind.document && !$0.blob.isEmpty }
                    .map { (memo.sharedContent?.fileName ?? $0.filename, $0.blob) }
            }))
        }
        return items
    }

    /// `prepare` puts the note's media on disk first (a projected memo's blobs); `document` is
    /// a projected capture's shared file, which has no working-folder copy.
    @MainActor
    private static func item(_ pf: PipelineFile, people: [Person], author: String,
                             prepare: @escaping () -> Void,
                             document: @escaping () -> (name: String, data: Data)? = { nil }) -> ExportAll.Item {
        let capture = captureDate(for: pf)
        return ExportAll.Item(id: ledgerID(for: pf), destination: pf.destination, title: pf.exportTitle,
                              filenameFallback: pf.filename,
                              recordedAt: MemoDate.isUnknown(capture) ? nil : capture) { stem in
            prepare()
            return compileForArchive(pf, stem: stem, people: people, author: author, document: document())
        }
    }

    /// `exportV2`'s compile and asset steps, with every asset recorded instead of copied. Audio
    /// always goes in (the archive is his copy of everything, not the vault's `includeAudio`).
    @MainActor
    static func compileForArchive(_ pf: PipelineFile, stem: String, people: [Person], author: String,
                                  document blob: (name: String, data: Data)? = nil) -> ExportAll.Compiled {
        let profile = ExportProfile.of(pf.destination)
        let id = ledgerID(for: pf)
        let working = pf.workingFolder
        let imagesDir = working?.appendingPathComponent("images")
        let attachmentsDir = working.map { MacNoteAttachments.folder(in: $0) }
        let nowhere = URL(fileURLWithPath: "/", isDirectory: true)   // names only; the archive places them
        var pictures: [VaultAsset] = []
        let record: Placer = { src, name, dir in
            pictures.append(VaultAsset(name: name, source: .file(src)))
            return dir.appendingPathComponent(name)
        }
        func placed(_ file: URL?, _ name: String) -> String? {
            guard let file, FileManager.default.fileExists(atPath: file.path) else { return nil }
            return record(file, name, nowhere)?.lastPathComponent
        }

        var documents: [VaultAsset] = []
        var note = v2Note(pf, people: people, author: author)
        if pf.sourceType == .capture, let working,
           let doc = (try? FileManager.default.contentsOfDirectory(at: working.appendingPathComponent("files"),
                                                                    includingPropertiesForKeys: nil))?
               .first(where: { !$0.lastPathComponent.hasPrefix(".") }) {
            let name = ExportV2.documentName(stem: stem, sourceName: doc.lastPathComponent)
            documents.append(VaultAsset(name: name, source: .file(doc)))
            note.documentName = name
        } else if let blob {
            let name = ExportV2.documentName(stem: stem, sourceName: blob.name)
            documents.append(VaultAsset(name: name, source: .data(blob.data)))
            note.documentName = name
        }
        if profile == .portfolio, let working, let movie = keptSourceVideo(in: working) {
            documents.append(VaultAsset(name: stem + "." + movie.pathExtension, source: .file(movie)))
        }

        var out = ExportV2.compile(note, profile: profile, stem: stem, placePicture: { source, name in
            placed(imagesDir?.appendingPathComponent(source), name)
        }, placeAttachment: { source, name in
            placed(attachmentsDir?.appendingPathComponent(source), name)
        }, poster: { _, name in
            placed(working.flatMap { MacNoteAttachments.posterFrame(in: $0) }, name)
        })
        if let imagesDir, pf.sourceType == .capture, !(pf.transcript ?? "").contains("[[img_"), out.pictures.isEmpty,
           FileManager.default.fileExists(atPath: imagesDir.path) {
            out.markdown = copyCaptureFolderImages(imagesDir: imagesDir, into: nowhere, markdown: out.markdown,
                                                   id: id, place: record).0
        }
        if pf.sourceType == .note, !pf.path.isEmpty {
            let src = URL(fileURLWithPath: pf.path).deletingLastPathComponent().appendingPathComponent("Attachments")
            if FileManager.default.fileExists(atPath: src.path) {
                out.markdown = convertNoteAttachments(out.markdown, attachmentsSrc: src, into: nowhere, id: id,
                                                      place: record, profile: profile).0
            }
        }

        var audio: VaultAsset?
        if pf.sourceType == .audio, !pf.path.isEmpty, FileManager.default.fileExists(atPath: pf.path) {
            let ext = URL(fileURLWithPath: pf.path).pathExtension
            audio = VaultAsset(name: stem + "." + (ext.isEmpty ? "m4a" : ext), source: .file(URL(fileURLWithPath: pf.path)))
        }
        return ExportAll.Compiled(markdown: out.markdown, pictures: pictures, audio: audio, documents: documents)
    }

    /// How many notes "Export all notes…" would put in the archive: what the Settings row shows.
    @MainActor
    static func exportAllCount(rows: [PipelineFile], memos: [Memo]) -> Int {
        let covered = Set(rows.flatMap { ReconcileV2.Writers.candidates(for: $0) })
        return rows.filter { $0.deletedAt == nil }.count
            + MemoDuplicates.canonicalRows(memos).filter { $0.deletedAt == nil && !covered.contains($0.id) }.count
    }
}
