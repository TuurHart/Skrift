import Foundation

/// "Export all notes…" on the phone and iPad (D218, D219, Q516): every memo not in the trash,
/// locked ones included, as `ExportAll.Item`s for the shared engine. Each compiles through the
/// publisher's own export v2 inputs (`v2Note`, the same providers for blobs) with nothing
/// written to a vault: no gate, no ledger, no folder. Audio always goes in; the archive is his
/// copy of everything, not the vault's include-audio choice. The phone compiles what it has: a
/// note the Mac has not polished goes in with its raw transcript.
extension ObsidianPublisher {

    @MainActor
    func exportAllItems(_ memos: [Memo]) -> [ExportAll.Item] {
        let people = peopleProvider()
        return memos.filter { $0.deletedAt == nil }.map { memo in
            let enhancement = MemoEnhancement.current(enhancementProvider(memo.id), for: memo)
            let title = MemoExporter.exportTitle(for: memo, people: people, enhancement: enhancement)
            return ExportAll.Item(id: memo.id, destination: memo.destination, title: title,
                                  filenameFallback: memo.audioFilename.isEmpty ? "memo_\(memo.id.uuidString).m4a" : memo.audioFilename,
                                  recordedAt: MemoDate.isUnknown(memo.recordedAt) ? nil : memo.recordedAt) { stem in
                compileForArchive(memo, stem: stem, people: people, enhancement: enhancement, title: title)
            }
        }
    }

    /// `publishReport`'s export v2 branch and asset steps, returning the files instead of
    /// committing them.
    @MainActor
    func compileForArchive(_ memo: Memo, stem: String, people: [Person], enhancement: MemoEnhancement?,
                           title: String) -> ExportAll.Compiled {
        let profile = ExportProfile.of(memo.destination)
        var stems: [UUID: String] = [:]
        for id in MemoLinkSyntax.targets(in: memo.transcript ?? "") {
            if let target = memoProvider(id) {
                stems[id] = ExportNaming.stem(title: MemoExporter.exportTitle(for: target, people: people,
                                                                              enhancement: MemoEnhancement.current(enhancementProvider(id), for: target)),
                                              filename: target.audioFilename)
            }
        }
        var note = Self.v2Note(memo, people: people, author: author, enhancement: enhancement,
                               linkStems: stems, title: title)
        var documents: [VaultAsset] = []
        if memo.isShareCapture, let sc = memo.sharedContent, sc.type == .file,
           let source = sc.fileName ?? sc.filePath, let blob = documentProvider(memo) {
            let name = ExportV2.documentName(stem: stem, sourceName: source)
            note.documentName = name
            documents.append(VaultAsset(name: name, source: .data(blob)))
        }

        let attachmentEntries = memo.metadata?.attachmentManifest ?? []
        var attachmentPlan: [(entry: NoteAttachmentEntry, name: String)] = []
        var posterName: String?
        let hasMovie = posterProvider != nil || movieProvider(memo) != nil
        // A picture whose blob is not on this device drops its embed (C196), as the Mac's
        // missing file does: the archive never points at a file it does not hold.
        let photoBlobs = (memo.metadata?.imageManifest ?? []).isEmpty ? [:] : photosProvider(memo.id)
        let out = ExportV2.compile(note, profile: profile, stem: stem, placePicture: { source, name in
            photoBlobs[source] == nil ? nil : name
        }, placeAttachment: { source, preferred in
            guard let entry = attachmentEntries.first(where: { $0.filename == source }) else { return nil }
            attachmentPlan.append((entry, preferred))
            return preferred
        }, poster: { _, preferred in
            guard hasMovie else { return nil }
            posterName = preferred
            return preferred
        })

        var pictures: [VaultAsset] = out.pictures.compactMap { p in
            photoBlobs[p.source].map { VaultAsset(name: p.embedName, source: .data($0)) }
        }
        for (entry, name) in attachmentPlan {
            if let source = attachmentProvider(memo, entry) { pictures.append(VaultAsset(name: name, source: source)) }
        }
        if let posterName,
           let frame = posterProvider?(memo) ?? movieProvider(memo).flatMap({ VideoExportFrame.jpeg(from: $0) }) {
            pictures.append(VaultAsset(name: posterName, source: .data(frame)))
        }
        if profile == .portfolio, let movie = movieProvider(memo) {
            documents.append(VaultAsset(name: stem + "." + movie.pathExtension, source: .file(movie)))
        }
        var audio: VaultAsset?
        if !memo.audioFilename.isEmpty {
            let ext = (memo.audioFilename as NSString).pathExtension
            let name = stem + "." + (ext.isEmpty ? "m4a" : ext)
            // The recording on this device streams from its file; else the synced blob.
            let local = AppPaths.recordingsDirectory.appendingPathComponent(memo.audioFilename)
            if FileManager.default.fileExists(atPath: local.path) {
                audio = VaultAsset(name: name, source: .file(local))
            } else if let blob = audioProvider(memo.id) {
                audio = VaultAsset(name: name, source: .data(blob))
            }
        }
        return ExportAll.Compiled(markdown: out.markdown, pictures: pictures, audio: audio, documents: documents)
    }
}
