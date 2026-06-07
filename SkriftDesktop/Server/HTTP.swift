import Foundation

/// Minimal HTTP/1.1 primitives for the thin sync server. Just enough to serve the
/// phone↔Mac contract (plan §4): GET/PUT JSON + a multipart POST. Kept dependency-
/// free (Network framework only at the transport layer) and pure here so the parser
/// + router + handlers unit-test host-less.

enum HTTPMethod: String, Sendable {
    case GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
}

struct HTTPRequest: Sendable {
    var method: HTTPMethod
    var path: String                 // path only, no query
    var query: [String: String]
    var headers: [String: String]    // keys lowercased
    var body: Data

    func header(_ name: String) -> String? { headers[name.lowercased()] }
    var contentLength: Int { Int(header("content-length") ?? "") ?? 0 }
    var contentType: String? { header("content-type") }
}

struct HTTPResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var body: Data

    init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    static func json(raw: Data, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status,
                     headers: ["Content-Type": "application/json; charset=utf-8"],
                     body: raw)
    }

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return .json(raw: data, status: status)
    }

    static func text(_ string: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status,
                     headers: ["Content-Type": "text/plain; charset=utf-8"],
                     body: Data(string.utf8))
    }

    static func status(_ code: Int, _ message: String? = nil) -> HTTPResponse {
        .text(message ?? Self.reason(code), status: code)
    }

    static func reason(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        default:  return "Status \(code)"
        }
    }

    /// Wire bytes: status line + headers (+ Content-Length + Connection: close) + body.
    func serialize() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        var h = headers
        h["Content-Length"] = String(body.count)
        h["Connection"] = "close"
        for (k, v) in h { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(body)
        return out
    }
}

enum HTTPParser {
    /// Peek the declared `Content-Length` once the header block (`\r\n\r\n`) has
    /// fully arrived, so the transport can reject an oversized body BEFORE buffering
    /// all of it in RAM. Returns nil while headers are still incomplete; 0 when the
    /// headers are complete but carry no Content-Length.
    static func declaredContentLength(_ data: Data) -> Int? {
        let sep = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: sep) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        for line in headerText.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            if key == "content-length" {
                return Int(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    /// Parse a full request from accumulated bytes. Returns nil when the header
    /// block or the Content-Length body hasn't fully arrived yet (caller keeps
    /// reading). Only Content-Length bodies are supported (URLSession sends them).
    static func parse(_ data: Data) -> HTTPRequest? {
        let sep = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: sep) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }

        let requestLine = lines.removeFirst().split(separator: " ", maxSplits: 2).map(String.init)
        guard requestLine.count >= 2, let method = HTTPMethod(rawValue: requestLine[0].uppercased()) else {
            return nil
        }
        let target = requestLine[1]

        // Split path?query
        let pathParts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let path = pathParts[0]
        var query: [String: String] = [:]
        if pathParts.count > 1 {
            for pair in pathParts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 {
                    query[kv[0].removingPercentEncoding ?? kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
                } else if kv.count == 1 {
                    query[kv[0]] = ""
                }
            }
        }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let bodyStart = headerEnd.upperBound
        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        let available = data.distance(from: bodyStart, to: data.endIndex)
        if available < contentLength { return nil }  // body not fully arrived

        let bodyEnd = data.index(bodyStart, offsetBy: contentLength)
        let body = data.subdata(in: bodyStart..<bodyEnd)

        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: body)
    }
}
