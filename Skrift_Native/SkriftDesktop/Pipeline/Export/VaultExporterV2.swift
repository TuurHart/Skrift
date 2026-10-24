import Foundation

/// Q434 (C2): the Mac's export, compiled by export v2 (`Shared/ExportV2`); v1's was deleted in
/// Q437 (tag `v1-export`).
extension VaultExporter {
    /// Export through the SHARED engine (`VaultWriter`, 2026-07-26): this file keeps
    /// only the Mac's asset sourcing (working-folder images, Apple-Note attachments);
    /// naming, the stamp, the edit guard, collision handling, atomic+coordinated
    /// writes and the ledger are the one cross-app implementation. The engine is
    /// asked FIRST (`assess`) so a refused note copies zero images and touches
    /// nothing — the old path wrote `<title>.md` unconditionally over whatever was
    /// there, with a bare non-atomic write, into a folder that lives in iCloud.
    ///
    /// `session` (Q365): an export RUN shares one decoded ledger per destination and one names
    /// snapshot across its notes, and folds the ledger to disk once at `finish()`. nil = a
    /// one-off export, exactly as before (its own ledger, written on change).
    @discardableResult
    static func export(_ pf: PipelineFile, settings: AppSettings, session: ExportSession? = nil) throws -> Result {
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
        let rewritesOurOwnFile: Bool
        switch writer.assess(id: id, title: pf.exportTitle, filenameFallback: pf.filename,
                             recordedAt: MemoDate.isUnknown(capture) ? nil : capture) {
        case .refused(let outcome):
            return Result(outcome: outcome, markdownURL: home.appendingPathComponent(outcome.relativePath),
                          audioURL: nil, imageCount: 0)
        case .proceed(let rel, let creates):
            relPath = rel
            rewritesOurOwnFile = !creates
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
            let name = ExportV2.documentName(stem: safe, sourceName: doc.lastPathComponent)
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

        /// The v2 compile with every asset going through `placer` (the ownership copy, or a dry run).
        func compile(_ placer: Placer) -> ExportV2.Output {
            ExportV2.compile(note, profile: profile, stem: safe, placePicture: { source, name in
                guard let file = imagesDir?.appendingPathComponent(source),
                      FileManager.default.fileExists(atPath: file.path) else { return nil }
                return placer(file, name, attDir)?.lastPathComponent
            }, placeAttachment: { source, name in
                guard let file = attachmentsDir?.appendingPathComponent(source),
                      FileManager.default.fileExists(atPath: file.path) else { return nil }
                return placer(file, name, attDir)?.lastPathComponent
            }, poster: { _, name in
                guard let working, let frame = MacNoteAttachments.posterFrame(in: working) else { return nil }
                return placer(frame, name, attDir)?.lastPathComponent
            })
        }
        let legacyCapture = pf.sourceType == .capture && !(pf.transcript ?? "").contains("[[img_")
        let noteAttachmentsDir: URL? = pf.sourceType == .note && !pf.path.isEmpty
            ? URL(fileURLWithPath: pf.path).deletingLastPathComponent().appendingPathComponent("Attachments") : nil
        let noteAttachments = noteAttachmentsDir.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        // Q365 (G9): the skip check BEFORE any picture is placed. The ledger says we wrote
        // this very file, the dry compile equals what is there, and every asset already sits at its
        // name looking current → `.unchanged` without reading a single image byte. A legacy capture
        // and an Apple Note place assets outside the compile, so they always take the full path.
        if rewritesOurOwnFile, !legacyCapture, !noteAttachments,
           let entry = writer.ledger.entry(for: id), entry.relativePath == relPath {
            var planned: [(src: URL, dest: URL)] = []
            let dry = compile { src, name, dir in
                let dest = dir.appendingPathComponent(name)
                planned.append((src, dest))
                return dest
            }
            if planned.allSatisfy({ assetLooksCurrent(source: $0.src, vaultCopy: $0.dest, writtenAt: entry.exportedAt) }),
               writer.isUnchanged(markdown: dry.markdown, id: id, relativePath: relPath) {
                return Result(outcome: .unchanged(relativePath: relPath),
                              markdownURL: home.appendingPathComponent(relPath),
                              audioURL: nil, imageCount: dry.pictures.count + dry.attachments)
            }
        }

        var out = compile(place)
        var count = out.pictures.count + out.attachments
        // A legacy marker-less capture: its pictures under their own names, as the block embeds them.
        if let imagesDir, legacyCapture, FileManager.default.fileExists(atPath: imagesDir.path) {
            let (md, copied) = copyCaptureFolderImages(imagesDir: imagesDir, into: attDir, markdown: out.markdown,
                                                       id: id, place: place)
            out.markdown = md
            count += copied
        }
        // An Apple Note's `(Attachments/x)` refs, in this profile's embed (R51).
        if noteAttachments, let src = noteAttachmentsDir {
            let (md, copied) = convertNoteAttachments(out.markdown, attachmentsSrc: src, into: attDir, id: id,
                                                      place: place, profile: profile)
            out.markdown = md
            count += copied
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
        // Memo-links follow the files this vault's ledger holds (sticky across retitles).
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
