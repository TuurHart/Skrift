import Foundation

/// One part of a `multipart/form-data` body.
struct MultipartPart: Sendable {
    var name: String
    var filename: String?
    var contentType: String?
    var data: Data
}

/// Minimal `multipart/form-data` parser for the phone's upload (plan §4). Pure +
/// host-testable. Boundaries are chosen by the client not to collide with content.
enum MultipartParser {
    static func boundary(fromContentType contentType: String?) -> String? {
        guard let contentType else { return nil }
        for comp in contentType.split(separator: ";") {
            let c = comp.trimmingCharacters(in: .whitespaces)
            if c.lowercased().hasPrefix("boundary=") {
                var b = String(c.dropFirst("boundary=".count))
                if b.hasPrefix("\""), b.hasSuffix("\""), b.count >= 2 { b = String(b.dropFirst().dropLast()) }
                return b.isEmpty ? nil : b
            }
        }
        return nil
    }

    static func parse(_ body: Data, boundary: String) -> [MultipartPart] {
        let delimiter = Data("--\(boundary)".utf8)
        let crlf = Data("\r\n".utf8)
        let headerSep = Data("\r\n\r\n".utf8)
        let dashes = Data("--".utf8)

        var parts: [MultipartPart] = []
        for var seg in split(body, separator: delimiter) {
            if seg.starts(with: crlf) { seg = seg.subdata(in: (seg.startIndex + 2)..<seg.endIndex) }
            if seg.starts(with: dashes) { continue }              // closing boundary
            guard let hsep = seg.range(of: headerSep) else { continue }

            let headerData = seg.subdata(in: seg.startIndex..<hsep.lowerBound)
            var content = seg.subdata(in: hsep.upperBound..<seg.endIndex)
            if content.count >= 2, content.suffix(2) == crlf {
                content = content.subdata(in: content.startIndex..<(content.endIndex - 2))
            }
            guard let headerText = String(data: headerData, encoding: .utf8) else { continue }

            var name = ""
            var filename: String?
            var contentType: String?
            for line in headerText.components(separatedBy: "\r\n") {
                let lower = line.lowercased()
                if lower.hasPrefix("content-disposition:") {
                    name = value(in: line, param: "name") ?? ""
                    filename = value(in: line, param: "filename")
                } else if lower.hasPrefix("content-type:") {
                    contentType = line.split(separator: ":", maxSplits: 1).last
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                }
            }
            if !name.isEmpty || filename != nil {
                parts.append(MultipartPart(name: name, filename: filename, contentType: contentType, data: content))
            }
        }
        return parts
    }

    /// Extract a quoted `param="value"` from a header line.
    private static func value(in line: String, param: String) -> String? {
        guard let r = line.range(of: "\(param)=\"") else { return nil }
        let rest = line[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[rest.startIndex..<end])
    }

    private static func split(_ data: Data, separator: Data) -> [Data] {
        var result: [Data] = []
        var lastEnd = data.startIndex
        var searchStart = data.startIndex
        while let r = data.range(of: separator, in: searchStart..<data.endIndex) {
            result.append(data.subdata(in: lastEnd..<r.lowerBound))
            lastEnd = r.upperBound
            searchStart = r.upperBound
        }
        result.append(data.subdata(in: lastEnd..<data.endIndex))
        return result
    }
}
