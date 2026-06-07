import Foundation

/// Network surface for names sync. Abstracted so unit tests can drive the full
/// flow without a server and UI tests can stub it via `-mockMac`.
protocol NamesTransport {
    /// Remote top-level `lastModifiedAt` (the cheap pre-check), or nil if absent.
    func meta() async throws -> String?
    func getAll() async throws -> NamesData
    func put(_ data: NamesData) async throws
}

enum SyncResult: Equatable {
    case unchanged
    case merged(localCount: Int, remoteCount: Int, mergedCount: Int)
    case failed(String)
}

/// Bidirectional names sync, mirroring RN `syncNames`:
/// `GET /meta` → (skip if equal to local) → `GET` full → merge (LWW +
/// voiceEmbeddings union) → save locally → `PUT` merged back so the Mac
/// converges too.
struct NamesSync {
    var store: NamesStore
    var transport: NamesTransport

    func run() async -> SyncResult {
        let local = store.load()
        do {
            let remoteMeta = try await transport.meta()
            if let remoteMeta, remoteMeta == local.lastModifiedAt {
                return .unchanged
            }
            let remote = try await transport.getAll()
            let merged = NamesMerge.mergeByCanonical(local: local.people, remote: remote.people)
            let saved = store.save(NamesData(lastModifiedAt: ISO8601.now(), people: merged))
            try await transport.put(saved)
            return .merged(localCount: local.people.count,
                           remoteCount: remote.people.count,
                           mergedCount: saved.people.count)
        } catch {
            return .failed(String(describing: error))
        }
    }
}

/// Real HTTP transport against the Mac backend (`/api/names`), matching the
/// contract endpoints in plan §4. Timeouts mirror the RN AbortController values.
struct URLSessionNamesTransport: NamesTransport {
    /// `http://{host}:{port}/api/names`
    let baseURL: URL
    var session: URLSession = .shared

    func meta() async throws -> String? {
        var req = URLRequest(url: baseURL.appendingPathComponent("meta"))
        req.timeoutInterval = 5
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj?["lastModifiedAt"] as? String
    }

    func getAll() async throws -> NamesData {
        var req = URLRequest(url: baseURL)
        req.timeoutInterval = 10
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp)
        return try JSONDecoder().decode(NamesData.self, from: data)
    }

    func put(_ data: NamesData) async throws {
        var req = URLRequest(url: baseURL)
        req.httpMethod = "PUT"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(data)
        let (_, resp) = try await session.data(for: req)
        try Self.check(resp)
    }

    private static func check(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
