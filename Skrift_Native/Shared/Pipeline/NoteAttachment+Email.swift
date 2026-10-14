import Foundation

/// C142 (Q448): an email share keeps its attachments as note attachments, the way Q385 stores a
/// picked file: one `NoteAttachmentEntry` per file (owner = the memo's id, so the on-disk and
/// `MemoAsset` filename is unique), one `[[file_NNN]]` / `[[vid_NNN]]` marker per entry as its
/// own paragraph after the body, in attachment order. The phone drain and the Mac folder/drop
/// ingest both call this, so the two notes have the same shape (C77).
extension NoteAttachment {

    /// One attachment of a parsed email, ready to be written under `entry.filename`.
    struct EmailFile: Equatable {
        let entry: NoteAttachmentEntry
        let data: Data
    }

    /// The entries (and their bytes) of a message's attachments, numbered 1... in attachment
    /// order. A part with no bytes is not a file and is skipped (it takes no number); a name is
    /// reduced to its last path component so nothing escapes the folder.
    static func emailFiles(_ attachments: [EmailShare.Attachment], owner: UUID) -> [EmailFile] {
        var out: [EmailFile] = []
        for a in attachments where !a.data.isEmpty {
            let shown = (a.name as NSString).lastPathComponent
            let name = shown.isEmpty ? "attachment" : shown
            let entry = makeEntry(owner: owner, number: out.count + 1, originalName: name,
                                  uti: nil, byteCount: a.data.count)
            out.append(EmailFile(entry: entry, data: a.data))
        }
        return out
    }

    /// `body` with one marker paragraph per entry after it, in order. Blank body = markers only.
    static func appendingMarkers(to body: String, entries: [NoteAttachmentEntry]) -> String {
        guard !entries.isEmpty else { return body }
        let markers = entries.enumerated()
            .map { literal(kind: $0.element.kind, number: $0.offset + 1) }
            .joined(separator: "\n\n")
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? markers : trimmed + "\n\n" + markers
    }
}
