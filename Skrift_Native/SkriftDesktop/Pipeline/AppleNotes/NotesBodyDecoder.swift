import Foundation
import Compression

/// Q333: turns one `ZICNOTEDATA.ZDATA` blob (gzip of an Apple Notes protobuf `Document`) into
/// Markdown + the tags and media a note carries. Pure (Foundation + Compression), no SQLite,
/// so it is testable from bytes alone.
///
/// The wire layout (from the open-source parsers named in plan/research/apple-notes-export.md:
/// apple_cloud_notes_parser, apple-notes-parser): `Document { 2: version, 3: Note }`,
/// `Note { 2: note_text, 5: repeated AttributeRun }`, `AttributeRun { 1: length (UTF-16 units),
/// 2: ParagraphStyle, 9: link, 12: AttachmentInfo }`, `ParagraphStyle { 1: style, 4: indent,
/// 5: Todo { 2: done } }`, `AttachmentInfo { 1: identifier, 2: type_uti }`. NOT verified against
/// a live NoteStore.sqlite on this Mac (no Full Disk Access for the worker): an unknown field is
/// skipped, never fatal, and a blob that does not parse yields `nil` so the caller can say so.
enum NotesBodyDecoder {

    /// What a decoded note carries beyond its words.
    struct Media: Equatable, Sendable {
        var pictures = 0, drawings = 0, scans = 0, tables = 0, pdfs = 0, audio = 0, video = 0, other = 0, links = 0
        var checklistItems = 0, checklistDone = 0
        var isEmpty: Bool { self == Media() }
    }

    struct Decoded: Equatable, Sendable {
        /// Markdown: first line is `# <title>`, then paragraphs; list/checklist markers kept.
        var markdown: String
        var title: String
        /// Tags as Notes spells them, no leading `#`, in first-seen order, de-duplicated by case.
        var tags: [String]
        var media: Media
    }

    static let hashtagUTI = "com.apple.notes.inlinetextattachment.hashtag"
    static let mentionUTI = "com.apple.notes.inlinetextattachment.mention"
    static let linkUTI = "com.apple.notes.inlinetextattachment.link"

    /// `altText` maps an inline attachment's identifier to what it reads as ("#kiln", "@Rui").
    static func decode(zdata: Data, altText: [String: String] = [:]) -> Decoded? {
        let raw: Data
        if zdata.count > 2, zdata[zdata.startIndex] == 0x1f, zdata[zdata.startIndex + 1] == 0x8b {
            guard let inflated = gunzip(zdata) else { return nil }
            raw = inflated
        } else {
            raw = zdata
        }
        guard let parsed = parseDocument([UInt8](raw)) else { return nil }
        return render(parsed, altText: altText)
    }

    // MARK: - gzip

    /// RFC 1952 header skip + raw DEFLATE through Compression's `COMPRESSION_ZLIB`.
    static func gunzip(_ data: Data) -> Data? {
        let b = [UInt8](data)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { return nil }
        let flags = b[3]
        var i = 10
        if flags & 4 != 0 {
            guard i + 2 <= b.count else { return nil }
            i += 2 + (Int(b[i]) | Int(b[i + 1]) << 8)
        }
        if flags & 8 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }
        if flags & 16 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }
        if flags & 2 != 0 { i += 2 }
        guard i < b.count - 8 else { return nil }
        let payload = Array(b[i..<(b.count - 8)])
        var capacity = max(payload.count * 8, 4096)
        while capacity <= 256 << 20 {
            var out = [UInt8](repeating: 0, count: capacity)
            let n = compression_decode_buffer(&out, capacity, payload, payload.count, nil, COMPRESSION_ZLIB)
            if n == 0 { return nil }
            if n < capacity { return Data(out[0..<n]) }
            capacity *= 4
        }
        return nil
    }

    // MARK: - protobuf

    private struct Reader {
        let b: [UInt8]
        var i = 0
        init(_ b: [UInt8]) { self.b = b }
        var atEnd: Bool { i >= b.count }
        mutating func varint() -> UInt64? {
            var result: UInt64 = 0, shift: UInt64 = 0
            while i < b.count, shift < 70 {
                let byte = b[i]; i += 1
                if shift < 64 { result |= UInt64(byte & 0x7f) << shift }
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }
        mutating func key() -> (field: Int, wire: Int)? {
            guard let k = varint() else { return nil }
            return (Int(k >> 3), Int(k & 7))
        }
        mutating func bytes() -> [UInt8]? {
            guard let n = varint(), n <= UInt64(b.count - i) else { return nil }
            let out = Array(b[i..<(i + Int(n))]); i += Int(n); return out
        }
        mutating func skip(wire: Int) -> Bool {
            switch wire {
            case 0: return varint() != nil
            case 1: guard i + 8 <= b.count else { return false }; i += 8; return true
            case 2: return bytes() != nil
            case 5: guard i + 4 <= b.count else { return false }; i += 4; return true
            default: return false
            }
        }
    }

    private struct Run {
        var length = 0
        var style = -1
        var indent = 0
        var done = false
        var link: String?
        var attachmentID: String?
        var uti: String?
    }

    private struct Parsed { var text: String; var runs: [Run] }

    private static func parseDocument(_ doc: [UInt8]) -> Parsed? {
        var r = Reader(doc)
        var noteBytes: [UInt8]?
        while !r.atEnd {
            guard let (f, w) = r.key() else { return nil }
            if f == 3, w == 2 { noteBytes = r.bytes() } else if !r.skip(wire: w) { return nil }
        }
        guard let nb = noteBytes else { return nil }
        var n = Reader(nb)
        var text: String?
        var runs: [Run] = []
        while !n.atEnd {
            guard let (f, w) = n.key() else { break }
            if f == 2, w == 2, let t = n.bytes() { text = String(decoding: t, as: UTF8.self) }
            else if f == 5, w == 2, let rb = n.bytes() { runs.append(parseRun(rb)) }
            else if !n.skip(wire: w) { break }
        }
        guard let text else { return nil }
        return Parsed(text: text, runs: runs)
    }

    private static func parseRun(_ bytes: [UInt8]) -> Run {
        var run = Run()
        var r = Reader(bytes)
        while !r.atEnd {
            guard let (f, w) = r.key() else { break }
            switch (f, w) {
            case (1, 0): run.length = Int(truncatingIfNeeded: r.varint() ?? 0)
            case (2, 2):
                guard let pb = r.bytes() else { return run }
                var p = Reader(pb)
                while !p.atEnd {
                    guard let (pf, pw) = p.key() else { break }
                    switch (pf, pw) {
                    case (1, 0): run.style = Int(Int32(truncatingIfNeeded: p.varint() ?? 0))
                    case (4, 0): run.indent = Int(truncatingIfNeeded: p.varint() ?? 0)
                    case (5, 2):
                        guard let tb = p.bytes() else { break }
                        var t = Reader(tb)
                        while !t.atEnd {
                            guard let (tf, tw) = t.key() else { break }
                            if tf == 2, tw == 0 { run.done = (t.varint() ?? 0) != 0 } else if !t.skip(wire: tw) { break }
                        }
                    default: if !p.skip(wire: pw) { break }
                    }
                }
            case (9, 2): if let l = r.bytes() { run.link = String(decoding: l, as: UTF8.self) }
            case (12, 2):
                guard let ab = r.bytes() else { return run }
                var a = Reader(ab)
                while !a.atEnd {
                    guard let (af, aw) = a.key() else { break }
                    if af == 1, aw == 2, let s = a.bytes() { run.attachmentID = String(decoding: s, as: UTF8.self) }
                    else if af == 2, aw == 2, let s = a.bytes() { run.uti = String(decoding: s, as: UTF8.self) }
                    else if !a.skip(wire: aw) { break }
                }
            default: if !r.skip(wire: w) { return run }
            }
        }
        return run
    }

    // MARK: - rendering

    private static func render(_ doc: Parsed, altText: [String: String]) -> Decoded {
        let units = Array(doc.text.utf16)
        var media = Media()
        var tags: [String] = []
        func addTag(_ raw: String) {
            let t = raw.trimmingCharacters(in: CharacterSet(charactersIn: "# \t"))
            guard !t.isEmpty, !tags.contains(where: { $0.lowercased() == t.lowercased() }) else { return }
            tags.append(t)
        }

        // 1. Walk runs → paragraphs (style of the run that holds the paragraph's first character).
        var paragraphs: [(run: Run, text: String)] = []
        var current = ""
        var currentRun: Run?
        var offset = 0
        for run in doc.runs {
            let end = min(units.count, offset + max(0, run.length))
            let slice = String(decoding: units[min(offset, end)..<end], as: UTF16.self)
            offset = end
            var piece = slice
            if let uti = run.uti {
                switch uti {
                case hashtagUTI:
                    let alt = run.attachmentID.flatMap { altText[$0] } ?? ""
                    addTag(alt)
                    piece = alt.isEmpty ? "" : (alt.hasPrefix("#") ? alt : "#" + alt)
                case mentionUTI:
                    piece = run.attachmentID.flatMap { altText[$0] } ?? ""
                case linkUTI:
                    piece = run.attachmentID.flatMap { altText[$0] } ?? ""
                    media.links += 1
                default:
                    count(uti: uti, into: &media)
                    piece = ""
                }
            } else if let link = run.link, !slice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !slice.contains("\n"), link != slice {
                piece = "[\(slice)](\(link))"
            }
            let parts = piece.components(separatedBy: "\n")
            for (k, part) in parts.enumerated() {
                if currentRun == nil { currentRun = run }
                current += part
                if k < parts.count - 1 {
                    paragraphs.append((currentRun ?? run, current))
                    current = ""; currentRun = nil
                }
            }
        }
        if let currentRun { paragraphs.append((currentRun, current)) }
        else if !current.isEmpty { paragraphs.append((Run(), current)) }
        // No runs at all (rare): the text stands as plain paragraphs.
        if doc.runs.isEmpty {
            paragraphs = doc.text.components(separatedBy: "\n").map { (Run(), $0) }
        }

        // 2. Paragraphs → Markdown.
        var lines: [(text: String, isList: Bool)] = []
        var title = ""
        var number = 0
        var sawFirst = false
        for (run, text) in paragraphs {
            let body = text.replacingOccurrences(of: "\u{FFFC}", with: "")
            let trimmed = body.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { number = 0; continue }
            let pad = String(repeating: "  ", count: max(0, run.indent))
            var line: String
            var isList = false
            if !sawFirst {
                sawFirst = true
                title = trimmed.hasPrefix("#") ? trimmed.drop(while: { $0 == "#" || $0 == " " }).description : trimmed
                lines.append(("# " + title, false)); number = 0
                continue
            }
            switch run.style {
            case 0, 1: line = "## " + trimmed; number = 0
            case 2: line = "### " + trimmed; number = 0
            case 4, 5: line = pad + "- " + trimmed; isList = true; number = 0
            case 6: number += 1; line = pad + "\(number). " + trimmed; isList = true
            case 100:
                media.checklistItems += 1
                if run.done { media.checklistDone += 1 }
                line = pad + (run.done ? "- [x] " : "- [ ] ") + trimmed; isList = true; number = 0
            default: line = trimmed; number = 0
            }
            lines.append((line, isList))
        }
        var out = ""
        for (k, l) in lines.enumerated() {
            if k > 0 { out += (l.isList && lines[k - 1].isList) ? "\n" : "\n\n" }
            out += l.text
        }
        if title.isEmpty { title = "Untitled" }
        return Decoded(markdown: out, title: title, tags: tags, media: media)
    }

    private static func count(uti: String, into m: inout Media) {
        let u = uti.lowercased()
        if u == "com.apple.paper" || u.contains("drawing") || u.contains("sketch") { m.drawings += 1 }
        else if u == "com.apple.notes.gallery" || u.contains("scan") { m.scans += 1 }
        else if u == "com.apple.notes.table" { m.tables += 1 }
        else if u == "public.jpeg" || u == "public.png" || u == "public.heic" || u == "public.tiff" || u == "com.compuserve.gif"
                    || u.hasPrefix("public.image") { m.pictures += 1 }
        else if u == "com.adobe.pdf" || u == "public.pdf" { m.pdfs += 1 }
        else if u.contains("audio") || u == "public.mpeg-4-audio" { m.audio += 1 }
        else if u.contains("movie") || u.contains("video") || u == "public.mpeg-4" { m.video += 1 }
        else if u == "public.url" || u.contains("link") { m.links += 1 }
        else { m.other += 1 }
    }
}
