import Foundation

/// Q434 (C2): the Mac's export through export v2 (`Shared/ExportV2`). The same write path as
/// `VaultExporter.export` — the gate, the destination move, the writer's assess and commit, the
/// ownership-safe asset copies — with v2 compiling the note. `export` routes here when
/// `ExportV2.isLive` (off until the swap, Q436); the export harness calls it directly.
extension VaultExporter {
    @discardableResult
    static func exportV2(_ pf: PipelineFile, settings: AppSettings, session: ExportSession? = nil) throws -> Result {
        if let failure = ExportGate.check(gateFacts(for: pf, settings: settings, processed: true),
                                          device: .mac, scope: .engine) {
            throw ExportError(failure)
        }
        let profile = ExportProfile.of(pf.destination)
        guard let home = exportHome(for: pf, settings: settings) else {
            throw ExportError(pf.destination.isPortfolio ? .noPortfolioFolder : .noVaultFolder)
        }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let id = ledgerID(for: pf)
        let move = destinationMove(pf, id: id, settings: settings, session: session)
        if case .refused(let refusal) = move { return refusal }
        let writer = VaultWriter(root: home, ledger: session?.ledger(for: home) ?? .default(for: home), profile: profile)
        let capture = captureDate(for: pf)
        let relPath: String
        switch writer.assess(id: id, title: pf.exportTitle, filenameFallback: pf.filename,
                             recordedAt: MemoDate.isUnknown(capture) ? nil : capture) {
        case .refused(let outcome):
            return Result(outcome: outcome, markdownURL: home.appendingPathComponent(outcome.relativePath),
                          audioURL: nil, imageCount: 0)
        case .proceed(let rel, _):
            relPath = rel
        }
        if case .removeOld(let rel, let old, let ledger) = move {
            DestinationMove.removeOld(relativePath: rel, id: id, oldHome: old, ledger: ledger)
        }
        let safe = ((relPath as NSString).lastPathComponent as NSString).deletingPathExtension
        let attDir = imageDestination(vaultURL: home, relativePath: relPath, profile: profile)
        let working = pf.workingFolder
        let imagesDir = working?.appendingPathComponent("images")
        let place = owned(id)

        // R38: a `.file` capture's document goes with the note, named by its stem.
        var documents: [VaultAsset] = []
        var documentName: String?
        if pf.sourceType == .capture, let working,
           let doc = (try? FileManager.default.contentsOfDirectory(at: working.appendingPathComponent("files"),
                                                                    includingPropertiesForKeys: nil))?
               .first(where: { !$0.lastPathComponent.hasPrefix(".") }) {
            let ext = doc.pathExtension.isEmpty ? "pdf" : doc.pathExtension
            let name = safe.lowercased().hasSuffix("." + ext.lowercased()) ? safe : safe + "." + ext
            documents.append(VaultAsset(name: name, source: .file(doc)))
            documentName = name
        }
        if profile == .portfolio, let working, let movie = keptSourceVideo(in: working) {
            documents.append(VaultAsset(name: safe + "." + movie.pathExtension, source: .file(movie)))
        }

        var note = v2Note(pf, people: session?.people ?? NamesStore.shared.livePeople(),
                          author: settings.authorName, linkLedger: writer.ledger)
        note.documentName = documentName
        let attachmentsDir = working.map { MacNoteAttachments.folder(in: $0) }

        var out = ExportV2.compile(note, profile: profile, stem: safe, placePicture: { source, name in
            guard let file = imagesDir?.appendingPathComponent(source),
                  FileManager.default.fileExists(atPath: file.path) else { return nil }
            return place(file, name, attDir)?.lastPathComponent
        }, placeAttachment: { source, name in
            guard let file = attachmentsDir?.appendingPathComponent(source),
                  FileManager.default.fileExists(atPath: file.path) else { return nil }
            return place(file, name, attDir)?.lastPathComponent
        }, poster: { _, name in
            guard let working, let frame = MacNoteAttachments.posterFrame(in: working) else { return nil }
            return place(frame, name, attDir)?.lastPathComponent
        })
        var count = out.pictures.count + out.attachments
        // A legacy marker-less capture: its pictures under their own names, as the block embeds them.
        if let imagesDir, pf.sourceType == .capture, !(pf.transcript ?? "").contains("[[img_"),
           FileManager.default.fileExists(atPath: imagesDir.path) {
            let (md, copied) = copyCaptureFolderImages(imagesDir: imagesDir, into: attDir, markdown: out.markdown,
                                                       id: id, place: place)
            out.markdown = md
            count += copied
        }
        // An Apple Note's `(Attachments/x)` refs, in this profile's embed (R51).
        if pf.sourceType == .note, !pf.path.isEmpty {
            let src = URL(fileURLWithPath: pf.path).deletingLastPathComponent().appendingPathComponent("Attachments")
            if FileManager.default.fileExists(atPath: src.path) {
                let (md, copied) = convertNoteAttachments(out.markdown, attachmentsSrc: src, into: attDir, id: id,
                                                          place: place, profile: profile)
                out.markdown = md
                count += copied
            }
        }

        var audio: VaultAsset?
        if pf.includeAudioInExport, pf.sourceType == .audio, !pf.path.isEmpty,
           FileManager.default.fileExists(atPath: pf.path) {
            let ext = URL(fileURLWithPath: pf.path).pathExtension
            audio = VaultAsset(name: safe + "." + (ext.isEmpty ? "m4a" : ext), source: .file(URL(fileURLWithPath: pf.path)))
        }
        let removed: [VaultAsset] = out.removedPictures.compactMap { p in
            guard let src = imagesDir?.appendingPathComponent(p.source),
                  FileManager.default.fileExists(atPath: src.path) else { return nil }
            return VaultAsset(name: p.embedName, source: .file(src))
        }
        let r = try writer.commit(markdown: out.markdown, id: id, relativePath: relPath, audio: audio,
                                  documents: documents, removedAttachments: removed)
        return Result(outcome: r.outcome, markdownURL: r.markdownURL, audioURL: r.audioURL,
                      imageCount: count, removedPictures: r.removedAttachments)
    }

    /// What export v2 reads about a Mac row — the one builder the export and its tests share.
    /// `created:` and "he gave this title" are the memo's, mirrored onto the row (Q511).
    static func v2Note(_ pf: PipelineFile, people: [Person], author: String,
                       linkLedger: ExportLedger? = nil) -> ExportV2.Note {
        var input = pf.compilerInput(people: people)
        // Memo-links follow the files this vault's ledger holds (sticky across retitles), as v1's do.
        let linked = input.sanitised ?? input.enhancedCopyedit ?? input.transcript ?? ""
        if !MemoLinkSyntax.occurrences(in: linked).isEmpty, let context = pf.modelContext {
            input.setLinkStems(MemoLinkStems.map(context, ledger: linkLedger))
        }
        let entries = pf.workingFolder.map { pictureEntries(imagesDir: $0.appendingPathComponent("images")) } ?? []
        var note = ExportV2.Note(input: input, title: pf.exportTitle)
        note.heGaveTitle = pf.memoTitleIsHis
        note.createdAt = pf.memoCreatedAt
        note.duration = pf.sourceType == .audio && pf.durationSeconds > 0 ? pf.durationSeconds : nil
        note.people = people
        note.author = author
        note.pictureManifest = entries.map(\.filename)
        note.pictureText = Dictionary(uniqueKeysWithValues: entries.enumerated().compactMap { i, e in
            e.text.map { (i + 1, $0) } })
        note.attachments = pf.workingFolder.map { MacNoteAttachments.manifest(in: $0) } ?? []
        return note
    }

    /// `image_manifest.json`'s entries (filename + OCR text), else the sorted `images/` listing.
    static func pictureEntries(imagesDir: URL) -> [ImageManifestEntry] {
        let url = imagesDir.deletingLastPathComponent().appendingPathComponent("image_manifest.json")
        if let data = try? Data(contentsOf: url),
           let entries = try? JSONDecoder().decode([ImageManifestEntry].self, from: data) { return entries }
        return pictureManifest(imagesDir: imagesDir).map { ImageManifestEntry(filename: $0, offsetSeconds: 0) }
    }
}
