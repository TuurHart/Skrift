import Foundation

/// The Mac rated list's adapter onto the ONE shared matcher (`NoteSearch`, Q103).
extension PipelineFile {
    /// The cheap fields only — no JSON decode. `noteSearchSnapshot` adds place + shared text.
    private func noteSearchBase(unlockedThisSession: Bool) -> NoteSearchSnapshot {
        NoteSearchSnapshot(
            locked: locked, unlockedThisSession: unlockedThisSession,
            // The Mac row's set title IS the polish title (`MemoNoteProjection` copies the
            // phone's chosen title into it); it is what a locked row still shows.
            title: enhancedTitle, generatedTitle: nil,
            derivedTitle: NoteVisibility.contentVisible(locked: locked, unlockedThisSession: unlockedThisSession)
                ? queueTitle : nil,
            transcript: transcript, summary: enhancedSummary, tags: tags,
            place: nil, annotation: nil, shared: [], ocr: [imageOCRText])
    }

    /// Full snapshot (decodes the metadata blob for place + shared-capture text).
    func noteSearchSnapshot(unlockedThisSession: Bool) -> NoteSearchSnapshot {
        var s = noteSearchBase(unlockedThisSession: unlockedThisSession)
        let meta = audioMetadataJSON.flatMap { try? JSONDecoder().decode(PhoneMetadata.self, from: $0) }
        let sc = SharedContent.decode(from: audioMetadataJSON)
        s.place = meta?.location?.placeName
        s.shared = [sc?.urlTitle, sc?.urlDescription, sc?.text, sc?.fileName]
        return s
    }

    /// Search hit for this row. The Mac decodes no JSON per keystroke unless the cheap
    /// fields miss (the `imageOCRText` mirror exists for that reason).
    func matchesNoteSearch(query: String, unlockedThisSession: Bool) -> Bool {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if NoteSearch.matches(query: query, noteSearchBase(unlockedThisSession: unlockedThisSession)) { return true }
        guard audioMetadataJSON != nil else { return false }
        return NoteSearch.matches(query: query, noteSearchSnapshot(unlockedThisSession: unlockedThisSession))
    }
}
