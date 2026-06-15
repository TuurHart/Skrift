import Foundation

/// Memo-upload + reconcile + health surface against the Mac. Abstracted so UI
/// tests can stub it via `-mockMac` and unit tests can drive `SyncCoordinator`
/// without a server.
protocol MacTransport {
    func health() async -> Bool
    func uploadMemo(body: Data, contentType: String) async throws
    /// `GET /api/files/` → the filenames the Mac already has (reconcile).
    func listFilenames() async throws -> [String]
}

/// Real HTTP transport against the native Mac server (contract §4 endpoints).
struct URLSessionMacTransport: MacTransport {
    let connection: MacConnection
    var session: URLSession = .shared

    func health() async -> Bool {
        guard let url = connection.healthURL else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        guard let (_, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    func uploadMemo(body: Data, contentType: String) async throws {
        guard let url = connection.uploadURL else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        do {
            let (_, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            DevLog.log("sync: POST \(url.absoluteString) (\(body.count)B) → HTTP \(code)")
            guard (200..<300).contains(code) else { throw URLError(.badServerResponse) }
        } catch {
            DevLog.log("sync: POST \(url.absoluteString) FAILED → \(error)")
            throw error
        }
    }

    func listFilenames() async throws -> [String] {
        guard let url = connection.filesURL else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(code) else {
                DevLog.log("sync: GET \(url.absoluteString) → HTTP \(code)")
                throw URLError(.badServerResponse)
            }
            let objects = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
            return objects.compactMap { $0["filename"] as? String }
        } catch {
            DevLog.log("sync: GET \(url.absoluteString) FAILED → \(error)")
            throw error
        }
    }
}

/// No Mac configured yet — uploads fail (memos stay `waiting`) until paired.
struct DisconnectedMacTransport: MacTransport {
    func health() async -> Bool { false }
    func uploadMemo(body: Data, contentType: String) async throws { throw URLError(.notConnectedToInternet) }
    func listFilenames() async throws -> [String] { [] }
}

/// Records uploads in memory — for `-mockMac` UI tests + unit tests.
final class MockMacTransport: MacTransport {
    private(set) var uploadedBodies: [Data] = []
    var knownFilenames: [String] = []

    func health() async -> Bool { true }
    func uploadMemo(body: Data, contentType: String) async throws { uploadedBodies.append(body) }
    func listFilenames() async throws -> [String] { knownFilenames }
}

enum MacTransportFactory {
    @MainActor static func make() -> any MacTransport {
        if LaunchFlags.mockMac { return MockMacTransport() }
        if let connection = MacConnection.load() { return URLSessionMacTransport(connection: connection) }
        return DisconnectedMacTransport()
    }

    /// Names transport for the connect flow. nil in `-mockMac` (UI tests skip names
    /// sync) and when no Mac is configured.
    @MainActor static func makeNamesTransport() -> NamesTransport? {
        guard !LaunchFlags.mockMac,
              let connection = MacConnection.load(),
              let base = connection.namesBaseURL else { return nil }
        return URLSessionNamesTransport(baseURL: base)
    }
}
