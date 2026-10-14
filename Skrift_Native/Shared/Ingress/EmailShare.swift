import Foundation

/// C142 (Q441): an email share (`.eml` / Mail) read into what a text capture needs - the
/// Subject (the title), the plain-text body, the Date header (`recordedAt`), the sender (C123)
/// and the attachments (files). Pure: Foundation only, no network, so the phone share extension,
/// the app and the Mac compile the same file. RFC 5322 headers (folded lines, RFC 2047 encoded
/// words) and RFC 2045 MIME (multipart, quoted-printable, base64, charsets) are read; an
/// HTML-only mail is reduced to its text. A message that cannot be read at all is nil, never
/// an empty note.
enum EmailShare {

    struct Attachment: Equatable, Sendable {
        var name: String
        var mimeType: String
        var data: Data
    }

    struct Message: Equatable, Sendable {
        /// The Subject header; the note's title. nil when absent or blank.
        var subject: String?
        /// The From display name ("Ana Costa"), else the address's local part; nil when no From.
        var senderName: String?
        var senderAddress: String?
        /// The Date header, nil when absent or unreadable (the capture then dates to the share).
        var date: Date?
        /// The plain text (or the text of the HTML), CRLF normalised, trimmed.
        var body: String
        var attachments: [Attachment]
    }

    /// `.eml` (RFC 822 message) and Apple Mail's `.emlx` is NOT read (it carries a byte-count
    /// prefix and a plist trailer); only `.eml`.
    static let fileExtensions: Set<String> = ["eml"]

    static func isEmailFile(_ name: String) -> Bool {
        fileExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    // MARK: Parse

    static func parse(_ data: Data) -> Message? {
        guard let entity = Entity(data) else { return nil }
        let from = entity.header("from").map(decodeWords)
        let (name, address) = from.map(splitAddress) ?? (nil, nil)
        var collected = Collected()
        walk(entity, into: &collected)
        let body = collected.plain ?? collected.html.map(htmlToText) ?? ""
        let subject = entity.header("subject").map(decodeWords)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let date = entity.header("date").flatMap(parseDate)
        // Nothing readable at all: not an email.
        if subject == nil, date == nil, from == nil, body.isEmpty, collected.attachments.isEmpty { return nil }
        return Message(subject: subject, senderName: name, senderAddress: address, date: date,
                       body: body.replacingOccurrences(of: "\r\n", with: "\n")
                           .trimmingCharacters(in: .whitespacesAndNewlines),
                       attachments: collected.attachments)
    }

    // MARK: MIME walk

    private struct Collected {
        var plain: String?
        var html: String?
        var attachments: [Attachment] = []
    }

    private static func walk(_ part: Entity, into out: inout Collected) {
        let type = part.contentType
        if type.hasPrefix("multipart/"), let boundary = part.parameter("boundary", of: "content-type") {
            for child in part.multipartChildren(boundary: boundary) { walk(child, into: &out) }
            return
        }
        let disposition = part.header("content-disposition")?.lowercased() ?? ""
        let fileName = part.fileName
        let isAttachment = disposition.hasPrefix("attachment") || fileName != nil || type == "message/rfc822"
        if isAttachment {
            let decoded = part.decodedBody
            let name = fileName ?? "attachment"
            out.attachments.append(Attachment(name: name, mimeType: type, data: decoded))
            return
        }
        switch type {
        case "text/plain":
            let text = part.text
            out.plain = out.plain.map { $0 + "\n\n" + text } ?? text
        case "text/html":
            let text = part.text
            out.html = out.html.map { $0 + "\n\n" + text } ?? text
        default:
            // An inline image / unknown inline part without a name still is a file.
            if !type.hasPrefix("text/") {
                out.attachments.append(Attachment(name: fileName ?? "attachment", mimeType: type, data: part.decodedBody))
            }
        }
    }

    // MARK: Entity (headers + body)

    private struct Entity {
        var headers: [(name: String, value: String)]
        var body: Data

        init?(_ data: Data) {
            // The header block ends at the first blank line (CRLF CRLF or LF LF).
            let crlf = Data("\r\n\r\n".utf8), lf = Data("\n\n".utf8)
            var split: (Range<Data.Index>)?
            let a = data.range(of: crlf), b = data.range(of: lf)
            switch (a, b) {
            case let (x?, y?): split = x.lowerBound <= y.lowerBound ? x : y
            case let (x?, nil): split = x
            case let (nil, y?): split = y
            default: split = nil
            }
            let headerData = split.map { data[data.startIndex..<$0.lowerBound] } ?? data
            body = split.map { Data(data[$0.upperBound...]) } ?? Data()
            guard let headerText = String(data: headerData, encoding: .utf8)
                ?? String(data: headerData, encoding: .isoLatin1) else { return nil }
            var parsed: [(String, String)] = []
            for rawLine in headerText.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: true) {
                let line = String(rawLine)
                if line.first == " " || line.first == "\t" {
                    guard !parsed.isEmpty else { continue }
                    parsed[parsed.count - 1].1 += " " + line.trimmingCharacters(in: .whitespaces)   // unfold
                } else if let colon = line.firstIndex(of: ":") {
                    let name = line[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
                    let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    parsed.append((name, value))
                }
            }
            headers = parsed
            // A "message" with no header at all is not one (a plain text file renamed .eml).
            if headers.isEmpty { return nil }
        }

        func header(_ name: String) -> String? { headers.first { $0.name == name }?.value }

        var contentType: String {
            (header("content-type") ?? "text/plain").split(separator: ";").first
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? "text/plain"
        }

        /// `name="value"` / `name=value` out of a structured header, RFC 2231 `name*=utf-8''..` too.
        func parameter(_ name: String, of headerName: String) -> String? {
            guard let value = header(headerName) else { return nil }
            let pieces = value.split(separator: ";", omittingEmptySubsequences: true).dropFirst()
            for piece in pieces {
                guard let eq = piece.firstIndex(of: "=") else { continue }
                let key = piece[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
                var v = piece[piece.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
                if key == name { return decodeWords(v) }
                if key == name + "*" {
                    // RFC 2231: charset'lang'percent-encoded
                    let parts = v.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                    return (parts.count == 3 ? String(parts[2]) : v).removingPercentEncoding ?? v
                }
            }
            return nil
        }

        var fileName: String? {
            let n = parameter("filename", of: "content-disposition") ?? parameter("name", of: "content-type")
            return n?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }

        var charset: String.Encoding {
            switch (parameter("charset", of: "content-type") ?? "utf-8").lowercased() {
            case "iso-8859-1", "latin1", "l1": return .isoLatin1
            case "windows-1252", "cp1252": return .windowsCP1252
            case "us-ascii", "ascii": return .ascii
            case "utf-16": return .utf16
            default: return .utf8
            }
        }

        /// The body after the Content-Transfer-Encoding.
        var decodedBody: Data {
            switch header("content-transfer-encoding")?.lowercased() ?? "7bit" {
            case "base64":
                let s = String(decoding: body, as: UTF8.self).filter { !$0.isWhitespace }
                return Data(base64Encoded: s, options: .ignoreUnknownCharacters) ?? Data()
            case "quoted-printable": return EmailShare.decodeQuotedPrintable(body)
            default: return body
            }
        }

        var text: String {
            let d = decodedBody
            return String(data: d, encoding: charset) ?? String(data: d, encoding: .utf8)
                ?? String(data: d, encoding: .isoLatin1) ?? ""
        }

        func multipartChildren(boundary: String) -> [Entity] {
            let delimiter = Data("--\(boundary)".utf8)
            var segments: [Data] = []
            var cursor = body.startIndex
            var segmentStart: Data.Index?
            while let r = body.range(of: delimiter, in: cursor..<body.endIndex) {
                if let s = segmentStart { segments.append(Data(body[s..<r.lowerBound])) }
                // `--boundary--` closes the multipart.
                let after = body[r.upperBound...]
                if after.starts(with: Data("--".utf8)) { segmentStart = nil; break }
                // Skip the rest of the delimiter line.
                if let nl = body[r.upperBound...].firstIndex(of: 0x0A) { segmentStart = body.index(after: nl) }
                else { segmentStart = nil; break }
                cursor = r.upperBound
            }
            return segments.compactMap { seg in
                // Drop the line break that belongs to the delimiter.
                var s = seg
                if s.last == 0x0A { s.removeLast() }
                if s.last == 0x0D { s.removeLast() }
                return Entity(s)
            }
        }
    }

    // MARK: Helpers

    /// "Ana Costa <ana@example.com>" -> ("Ana Costa", "ana@example.com"); a bare address gives its
    /// local part as the name.
    static func splitAddress(_ from: String) -> (name: String?, address: String?) {
        let t = from.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lt = t.lastIndex(of: "<"), let gt = t.lastIndex(of: ">"), lt < gt {
            let address = String(t[t.index(after: lt)..<gt]).trimmingCharacters(in: .whitespaces)
            var name = String(t[..<lt]).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
            if name.isEmpty { name = address.split(separator: "@").first.map(String.init) ?? address }
            return (name.nonEmpty, address.nonEmpty)
        }
        if t.contains("@") { return (t.split(separator: "@").first.map(String.init), t) }
        return (t.nonEmpty, nil)
    }

    /// RFC 2047 encoded words (`=?utf-8?Q?Caf=C3=A9?=`, `=?UTF-8?B?...?=`) inside a header value.
    static func decodeWords(_ raw: String) -> String {
        guard raw.contains("=?") else { return raw }
        guard let regex = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#) else { return raw }
        let ns = raw as NSString
        var out = "", last = 0
        var lastWasWord = false
        for m in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            let between = ns.substring(with: NSRange(location: last, length: m.range.location - last))
            // Whitespace between two encoded words is dropped (RFC 2047 6.2).
            if !(lastWasWord && between.allSatisfy(\.isWhitespace)) { out += between }
            let charset = ns.substring(with: m.range(at: 1)).lowercased()
            let enc = ns.substring(with: m.range(at: 2)).lowercased()
            let payload = ns.substring(with: m.range(at: 3))
            let bytes: Data
            if enc == "b" { bytes = Data(base64Encoded: payload) ?? Data() }
            else { bytes = decodeQuotedPrintable(Data(payload.replacingOccurrences(of: "_", with: " ").utf8)) }
            let encoding: String.Encoding = (charset.contains("8859-1") || charset == "latin1") ? .isoLatin1
                : (charset.contains("1252") ? .windowsCP1252 : .utf8)
            out += String(data: bytes, encoding: encoding) ?? String(data: bytes, encoding: .utf8) ?? ""
            last = m.range.location + m.range.length
            lastWasWord = true
        }
        out += ns.substring(from: last)
        return out
    }

    static func decodeQuotedPrintable(_ data: Data) -> Data {
        var out = Data()
        let bytes = [UInt8](data)
        var i = 0
        func hex(_ b: UInt8) -> UInt8? {
            switch b {
            case 0x30...0x39: return b - 0x30
            case 0x41...0x46: return b - 0x41 + 10
            case 0x61...0x66: return b - 0x61 + 10
            default: return nil
            }
        }
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x3D {   // "="
                if i + 2 < bytes.count,
                   let h = hex(bytes[i + 1]), let l = hex(bytes[i + 2]) {
                    out.append(h << 4 | l); i += 3; continue
                }
                // Soft line break: "=\r\n" or "=\n".
                if i + 1 < bytes.count, bytes[i + 1] == 0x0A { i += 2; continue }
                if i + 2 < bytes.count, bytes[i + 1] == 0x0D, bytes[i + 2] == 0x0A { i += 3; continue }
            }
            out.append(b); i += 1
        }
        return out
    }

    /// RFC 5322 date, tolerant: optional weekday, optional seconds, a trailing "(UTC)" comment.
    static func parseDate(_ raw: String) -> Date? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let paren = s.firstIndex(of: "(") { s = String(s[..<paren]).trimmingCharacters(in: .whitespaces) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z",
                       "EEE, d MMM yyyy HH:mm Z", "d MMM yyyy HH:mm Z",
                       "EEE, d MMM yyyy HH:mm:ss zzz", "d MMM yyyy HH:mm:ss zzz"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// An HTML-only mail as text: scripts and styles gone, block tags as line breaks, entities
    /// for the common cases.
    static func htmlToText(_ html: String) -> String {
        var t = html
        for pattern in [#"(?is)<(script|style|head)\b.*?</\1>"#] {
            t = t.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        t = t.replacingOccurrences(of: #"(?i)<br\s*/?>|</(p|div|li|tr|h[1-6])>"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (e, c) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
            t = t.replacingOccurrences(of: e, with: c)
        }
        t = t.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
