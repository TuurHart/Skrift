import Foundation

/// Minimal Mac connection config (host + port), persisted in UserDefaults. The
/// QR pairing, health check, and multipart upload land in Phase 6 (`SyncService`);
/// this is just enough for names sync to have a target.
struct MacConnection: Equatable {
    var host: String
    var port: Int

    static let defaultPort = 8000
    private static let hostKey = "mac.host"
    private static let portKey = "mac.port"

    static func load(defaults: UserDefaults = .standard) -> MacConnection? {
        guard let host = defaults.string(forKey: hostKey), !host.isEmpty else { return nil }
        let port = defaults.integer(forKey: portKey)
        return MacConnection(host: host, port: port == 0 ? defaultPort : port)
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(host, forKey: Self.hostKey)
        defaults.set(port, forKey: Self.portKey)
    }

    var namesBaseURL: URL? {
        URL(string: "http://\(host):\(port)/api/names")
    }
}
