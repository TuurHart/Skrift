import Foundation

// Q361 (M9): a cheap content stamp for `MacRowSnippetCache`. Sizes plus the head of each body the
// card can show, so it is safe to compute on every row body pass (a few hundred bytes per note);
// a same-length edit past the head cannot change the two-line snippet.

private func headStamp(_ s: String?, into h: inout Hasher) {
    guard let s else { h.combine(-1); return }
    h.combine(s.utf8.count)
    for b in s.utf8.prefix(256) { h.combine(b) }
}

extension PipelineFile {
    /// Everything `cardFacts` reads, reduced to a stamp.
    var cardVersion: Int {
        var h = Hasher()
        headStamp(sanitised, into: &h)
        headStamp(enhancedCopyedit, into: &h)
        headStamp(transcript, into: &h)
        h.combine(enhancedTitle)
        h.combine(tags)
        h.combine(audioMetadataJSON)
        h.combine(sourceType.rawValue)
        return h.finalize()
    }
}

extension Memo {
    /// Everything `cardFacts()` reads, reduced to a stamp.
    var cardVersion: Int {
        var h = Hasher()
        headStamp(transcript, into: &h)
        headStamp(annotationText, into: &h)
        h.combine(title)
        h.combine(tags)
        h.combine(metadataData)
        h.combine(sharedContentData)
        h.combine(duration)
        h.combine(lastEditedAt)
        return h.finalize()
    }
}
