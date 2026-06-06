import Foundation

/// Minimal Mac connection config (host + port), persisted in UserDefaults.
/// Pairing is Bonjour auto-discovery + a manual host/port fallback (`PairMacView`
/// / `MacDiscovery`) — the QR flow was dropped.
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
}
