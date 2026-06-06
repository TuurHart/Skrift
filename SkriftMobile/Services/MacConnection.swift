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

    private var base: String { "http://\(host):\(port)" }
    var namesBaseURL: URL? { URL(string: "\(base)/api/names") }
    var healthURL: URL? { URL(string: "\(base)/api/system/health") }
    var uploadURL: URL? { URL(string: "\(base)/api/files/upload") }
    var filesURL: URL? { URL(string: "\(base)/api/files/") }

    /// Parse a pairing QR of the form `skrift://{host}:{port}/{name}` (the format
    /// the Mac shows). The name segment is ignored here.
    static func parse(qr: String) -> MacConnection? {
        guard let url = URL(string: qr.trimmingCharacters(in: .whitespaces)),
              url.scheme == "skrift",
              let host = url.host, !host.isEmpty else { return nil }
        return MacConnection(host: host, port: url.port ?? defaultPort)
    }
}
