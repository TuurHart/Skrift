import Foundation

/// The Mac's rated-row adapter for the ONE card-content builder (`NoteCardBuilder`, Q106).
/// Everything the row shows — title, quote, snippet, source / book / domain / place chips —
/// comes out of `NoteCardBuilder.content(for:)`, the same call the phone's `MemoCard` and the
/// Mac's quiet rows make. This file only reduces a `PipelineFile` to `NoteCardFacts`.
extension PipelineFile {
    /// THE kind of this row: audiobook quote → video → typed → capture subtype → audio / no
    /// audio. A book capture and a video import are both `.audio` rows, so the markers
    /// (`bookCapture`, `mediaSource`) decide, not `sourceType`.
    var sourceKind: SourceKind {
        SourceKind.classify(hasBook: bookCapture != nil, media: mediaSource,
                            sharedType: sharedContent?.type.rawValue,
                            isCaptureRow: sourceType == .capture,
                            hasAudio: sourceType == .audio)
    }

    var cardFacts: NoteCardFacts {
        let meta = MemoMetadata.lenient(from: audioMetadataJSON)
        let isCapture = sourceType == .capture
        // The row's body: the polished text when there is one, else the transcript. A capture's
        // body IS its annotation (the Mac stores it as the transcript).
        let body = sanitised ?? enhancedCopyedit ?? transcript
        let secs = durationSeconds
        return NoteCardFacts(
            kind: sourceKind,
            title: enhancedTitle,
            body: isCapture ? nil : body,
            annotation: isCapture ? body : nil,
            shared: isCapture ? sharedContent : nil,
            book: bookCapture.map { .init(title: $0.title, chapter: $0.chapter) },
            durationSeconds: secs > 0 ? secs : nil,
            place: isCapture ? nil : meta?.location?.placeName,
            temperature: isCapture ? nil : meta?.weather?.temperature.map { Int($0.rounded()) },
            tags: tags)
    }
}
