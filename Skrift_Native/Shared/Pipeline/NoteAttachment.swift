import Foundation
import CoreGraphics
import UniformTypeIdentifiers

/// One video or file inside a note body (D199, D202). Rides the synced metadata blob
/// (`MemoMetadata.attachmentManifest`, ADDITIVE), so no new CloudKit field: the bytes travel as a
/// `MemoAsset` of kind `video` / `file` named `filename`.
struct NoteAttachmentEntry: Codable, Equatable, Sendable {
    /// `NoteAttachment.Kind.video` / `.file`.
    var kind: String
    /// The on-disk + `MemoAsset` filename (`NoteAttachment.filename`).
    var filename: String
    /// The name the file came in with ("fan-loom-bracket-rev-c.dxf"): the card's title and the
    /// exported file's name.
    var name: String
    /// The file's uniform type identifier ("com.adobe.pdf"), for the card's kind label and icon.
    var uti: String
    var byteCount: Int
    /// A video's length, for the duration label (pick 5). nil for a file.
    var durationSeconds: Double? = nil
}

/// Videos and files inside a note body, the rules both apps share (D199, D202, mock
/// Q384-note-attachments). Markers, the manifest lookup, filenames, the small/large state, the
/// card's words and the export embed all live here once; the phone and the Mac only draw.
/// Foundation + CoreGraphics + UTType only, so the host-less Mac test bundle drives it.
enum NoteAttachment {

    enum Kind {
        static let video = "video"
        static let file = "file"
    }

    // MARK: Markers (one vocabulary, like `BodyV2Marker`)

    /// `[[vid_NNN]]` / `[[file_NNN]]`. Group 1 = the prefix, group 2 = the number. N is 1-based
    /// into `attachmentManifest`; a marker whose N has no entry of its kind stays the author's text.
    static let regex = try! NSRegularExpression(pattern: #"\[\[(vid|file)_(\d+)\]\]"#)

    static func prefix(forKind kind: String) -> String { kind == Kind.video ? "vid" : "file" }

    static func literal(kind: String, number n: Int) -> String {
        "[[\(prefix(forKind: kind))_\(String(format: "%03d", n))]]"
    }

    struct Marker: Equatable {
        let range: NSRange
        let kind: String
        let number: Int
    }

    /// Every attachment marker in body order.
    static func markers(in text: String) -> [Marker] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let n = Int(ns.substring(with: m.range(at: 2))) else { return nil }
            let kind = ns.substring(with: m.range(at: 1)) == "vid" ? Kind.video : Kind.file
            return Marker(range: m.range, kind: kind, number: n)
        }
    }

    /// The entry a marker stands for, or nil when it is the author's text (no entry, wrong kind).
    static func entry(kind: String, number: Int, manifest: [NoteAttachmentEntry]) -> NoteAttachmentEntry? {
        guard number >= 1, number <= manifest.count else { return nil }
        let e = manifest[number - 1]
        guard e.kind == kind, !e.filename.isEmpty else { return nil }
        return e
    }

    /// What a marker stands for right now: the same four slots a photo has (`NotePhoto.Slot`).
    static func slot(kind: String, number: Int, manifest: [NoteAttachmentEntry],
                     fileExists: (String) -> Bool, hasAsset: (String) -> Bool) -> NotePhoto.Slot {
        guard let e = entry(kind: kind, number: number, manifest: manifest) else { return .text }
        switch MediaSyncState.of(filePresent: fileExists(e.filename), hasAsset: hasAsset(e.filename)) {
        case .present: return .present
        case .downloading: return .downloading
        case .missing: return .missing
        }
    }

    // MARK: Adding one at the caret

    /// Video file extensions the note takes as a video (the rest of the non-picture files are files).
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm", "3gp"]

    /// `video` or `file` for a picked file, by its type (a movie conforms to `.movie`).
    static func kind(forFilename name: String, uti: String? = nil) -> String {
        if let uti, let t = UTType(uti), t.conforms(to: .movie) || t.conforms(to: .video) { return Kind.video }
        return videoExtensions.contains((name as NSString).pathExtension.lowercased()) ? Kind.video : Kind.file
    }

    /// The type identifier for a filename (the picker's own type wins when it has one).
    static func uti(forFilename name: String) -> String {
        UTType(filenameExtension: (name as NSString).pathExtension)?.identifier ?? UTType.data.identifier
    }

    /// `video_<owner>_<NNN>.<ext>` / `file_<owner>_<NNN>.<ext>`: unique (the owner is the memo's
    /// UUID), so the `MemoAsset` filename invariant holds. The shown name lives in the entry.
    static func filename(owner: UUID, number: Int, kind: String, ext: String) -> String {
        let fallback = kind == Kind.video ? "mov" : "bin"
        return "\(kind)_\(owner.uuidString)_\(String(format: "%03d", number)).\(ext.isEmpty ? fallback : ext.lowercased())"
    }

    /// A new entry for a file copied into the note.
    static func makeEntry(owner: UUID, number: Int, originalName: String, uti: String? = nil,
                          byteCount: Int, durationSeconds: Double? = nil) -> NoteAttachmentEntry {
        let kind = kind(forFilename: originalName, uti: uti)
        let ext = (originalName as NSString).pathExtension
        return NoteAttachmentEntry(kind: kind,
                                   filename: filename(owner: owner, number: number, kind: kind, ext: ext),
                                   name: originalName.isEmpty ? "Attachment" : originalName,
                                   uti: uti ?? Self.uti(forFilename: originalName),
                                   byteCount: byteCount,
                                   durationSeconds: kind == Kind.video ? durationSeconds : nil)
    }

    /// The model text with the marker put at UTF-16 offset `caret`, stored the v2 way: its own
    /// paragraph, after the sentence the caret is in (C10, the same spot a photo takes). Returns
    /// the stored text and where the marker starts in it.
    static func inserting(kind: String, number: Int, into text: String,
                          atOffset caret: Int) -> (text: String, markerOffset: Int) {
        let ns = text as NSString
        let at = max(0, min(caret, ns.length))
        let spot = at == 0 || ns.length == 0 ? at : BodyV2.spot(after: at - 1, in: ns)
        let marker = literal(kind: kind, number: number)
        let raw = ns.replacingCharacters(in: NSRange(location: spot, length: 0), with: "\n\n" + marker + "\n\n")
        let stored = BodyV2Text.normalised(raw)
        let found = (stored as NSString).range(of: marker)
        return (stored, found.location == NSNotFound ? spot : found.location)
    }

    private static let blockRegex = try! NSRegularExpression(pattern: #"[ \t]*\n*[ \t]*(\[\[(?:vid|file)_\d+\]\])[ \t]*\n*"#)

    /// The editors' commit step (both apps): every resolving attachment marker made its own
    /// paragraph (C10), whatever newlines the editor left around its glyph. Markers with no entry
    /// stay where they are, as text.
    static func blockShaped(_ text: String, manifest: [NoteAttachmentEntry]) -> String {
        guard !manifest.isEmpty, text.contains("[[vid_") || text.contains("[[file_") else { return text }
        let ns = text as NSString
        var edits: [(NSRange, String)] = []
        for m in blockRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let lit = ns.substring(with: m.range(at: 1))
            guard let marker = markers(in: lit).first,
                  entry(kind: marker.kind, number: marker.number, manifest: manifest) != nil else { continue }
            let atStart = m.range.location == 0
            let atEnd = NSMaxRange(m.range) >= ns.length
            edits.append((m.range, (atStart ? "" : "\n\n") + lit + (atEnd ? "" : "\n\n")))
        }
        return edits.isEmpty ? text : BodyV2Text.normalised(Sanitiser.nsReplace(text, edits: edits))
    }

    // MARK: Small / large (D202: Apple's switch, SMALL by default, synced per attachment)

    enum Size: String, Equatable { case small, large }

    /// The size an attachment draws at. `large` = `MemoMetadata.largeAttachments`.
    static func size(of filename: String, large: [String]?) -> Size {
        (large ?? []).contains(filename) ? .large : .small
    }

    /// `large` with one attachment switched. nil when nothing is large (the default, stored as absent).
    static func setting(_ filename: String, to size: Size, in large: [String]?) -> [String]? {
        var set = (large ?? []).filter { $0 != filename }
        if size == .large { set.append(filename) }
        return set.isEmpty ? nil : set
    }

    /// The ⋯ menu's "Set All to Small" / "Set All to Large": every attachment the note holds.
    static func settingAll(_ size: Size, filenames: [String]) -> [String]? {
        size == .small || filenames.isEmpty ? nil : filenames
    }

    static let setAllSmallTitle = "Set All to Small"
    static let setAllLargeTitle = "Set All to Large"
    static let viewSmallTitle = "View as Small"
    static let viewLargeTitle = "View as Large"

    // MARK: Card words (pick 4 / pick 5)

    /// The duration label on a video (bottom right, pick 5).
    static func durationLabel(_ entry: NoteAttachmentEntry) -> String? {
        entry.durationSeconds.map { DurationFormat.label(seconds: $0) }
    }

    /// "412 KB": the size on the card.
    static func sizeLabel(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// "DXF drawing", "PDF document", "Video": the kind on the card.
    static func kindLabel(_ entry: NoteAttachmentEntry) -> String {
        if entry.kind == Kind.video { return "Video" }
        if let d = UTType(entry.uti)?.localizedDescription, !d.isEmpty, entry.uti != UTType.data.identifier {
            return d.prefix(1).uppercased() + d.dropFirst()
        }
        let ext = (entry.name as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "File" : "\(ext) file"
    }

    /// The card's second line: "DXF drawing · 412 KB", a video "Video · 0:42 · 18 MB".
    static func subtitle(_ entry: NoteAttachmentEntry) -> String {
        [kindLabel(entry), durationLabel(entry), sizeLabel(entry.byteCount)].compactMap { $0 }.joined(separator: " · ")
    }

    /// The short badge on the card's file icon ("DXF", "XLSX").
    static func badge(_ entry: NoteAttachmentEntry) -> String {
        let ext = (entry.name as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : String(ext.prefix(4))
    }

    /// The badge colour by family (mock: drawing slate, spreadsheet green, pdf red, rest grey).
    static func badgeHex(_ entry: NoteAttachmentEntry) -> UInt32 {
        guard let t = UTType(entry.uti) else { return 0x6c6c72 }
        if t.conforms(to: .pdf) { return 0xc8463d }
        if t.conforms(to: .spreadsheet) { return 0x2f8a52 }
        if t.conforms(to: .presentation) { return 0xd9772b }
        if t.conforms(to: .text) || t.conforms(to: .compositeContent) { return 0x3b6fd4 }
        if t.conforms(to: .archive) { return 0x8a6d3b }
        return 0x5b6b8a
    }

    /// Whether a file attachment is a PDF (large = its first page, D126 / pick 7).
    static func isPDF(_ entry: NoteAttachmentEntry) -> Bool {
        UTType(entry.uti)?.conforms(to: .pdf) == true || entry.name.lowercased().hasSuffix(".pdf")
    }

    // MARK: Look (mock Q384)

    /// A tall video is cut to this height on the phone, the poster cropped to its middle (pick 2, D202).
    static let phoneVideoMaxHeight: CGFloat = 420
    /// …and to this on iPad and Mac (pick 2).
    static let wideVideoMaxHeight: CGFloat = 560
    /// Media is at most this wide on iPad and Mac, left-aligned (pick 8).
    static let wideMediaMaxWidth: CGFloat = 720
    /// The PDF page and the file card are at most this wide there (pick 8).
    static let widePageMaxWidth: CGFloat = 520
    static let mediaCornerRadius: CGFloat = 14
    /// The grey file card (pick 4): Apple's small card.
    static let cardCornerRadius: CGFloat = 13
    static let cardMinHeight: CGFloat = 70
    static let cardFillLightHex: UInt32 = 0xececf1
    static let cardFillDarkHex: UInt32 = 0x20232f
    static let cardTitleSize: CGFloat = 15
    static let cardSubtitleSize: CGFloat = 13
    /// A small video's poster thumbnail on the card's right.
    static let cardThumbSize = CGSize(width: 46, height: 46)

    /// The block's height for a video of `natural` size drawn `width` wide: the full frame, cut at
    /// `maxHeight` (pick 2). Without a known frame, 16:9.
    static func videoHeight(width: CGFloat, natural: CGSize?, maxHeight: CGFloat) -> CGFloat {
        let ratio: CGFloat
        if let n = natural, n.width > 0, n.height > 0 { ratio = n.height / n.width } else { ratio = 9.0 / 16.0 }
        return min(maxHeight, (width * ratio).rounded())
    }

    // MARK: Export (D199: beside the note, like photos)

    /// The vault name for an attachment: a video `<stem>_video_NNN.<ext>`, a file its own name
    /// prefixed by the note's stem so two notes' "quote.xlsx" never collide by name.
    static func exportName(_ entry: NoteAttachmentEntry, number: Int, stem: String) -> String {
        if entry.kind == Kind.video {
            let ext = (entry.filename as NSString).pathExtension
            return "\(stem)_video_\(String(format: "%03d", number)).\(ext.isEmpty ? "mov" : ext)"
        }
        let safeName = entry.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(stem) - \(safeName)"
    }

    /// Replace every attachment marker with this profile's embed of the copied file (`![[x]]` in
    /// the vault). `place(source filename, preferred name)` copies the file and returns the name
    /// written, nil when it could not; a marker with no entry or no copy is DROPPED, like a photo's.
    static func convertMarkers(_ markdown: String, manifest: [NoteAttachmentEntry], stem: String,
                               profile: ExportProfile,
                               place: (_ source: String, _ preferredName: String) -> String?) -> (markdown: String, placed: Int) {
        let found = markers(in: markdown)
        guard !found.isEmpty else { return (markdown, 0) }
        var edits: [(NSRange, String)] = []
        var placed = 0
        for m in found {
            guard let e = entry(kind: m.kind, number: m.number, manifest: manifest),
                  let written = place(e.filename, exportName(e, number: m.number, stem: stem)) else {
                edits.append((m.range, ""))
                continue
            }
            placed += 1
            edits.append((m.range, profile.imageMarkdown(written)))
        }
        return (Sanitiser.nsReplace(markdown, edits: edits), placed)
    }
}
