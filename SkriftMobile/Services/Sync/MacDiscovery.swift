import Foundation
import Network

/// A Mac found on the local network (or seeded for tests). `host`/`port` are
/// known immediately for seeded/manual entries; for a real Bonjour result they
/// resolve when the user taps Connect.
struct DiscoveredMac: Identifiable, Equatable {
    let id: String          // service name (unique on the network)
    let name: String
    var host: String?
    var port: Int?
    var endpoint: NWEndpoint?
}

/// Browses for the native Mac server's Bonjour service (`_skrift._tcp`, advertised
/// by `SkriftDesktop/Server`). Auto-discovery + resolve replaces the old QR flow.
///
/// The Simulator can't see the real Mac, so UI tests pass `-seedDiscoveredMacs`
/// to inject entries; the live discovery + resolve is device/network-owed.
@MainActor
final class MacDiscovery: ObservableObject {
    @Published private(set) var macs: [DiscoveredMac] = []
    @Published private(set) var searching = false

    private var browser: NWBrowser?
    private let seeded: Bool

    init(seeded: Bool = LaunchFlags.seedDiscoveredMacs) {
        self.seeded = seeded
    }

    func start() {
        if seeded {
            searching = true
            macs = [
                DiscoveredMac(id: "Skrift Desktop", name: "Skrift Desktop", host: "studio.local", port: 8000),
                DiscoveredMac(id: "Tiuri's MacBook", name: "Tiuri's MacBook", host: "192.168.1.22", port: 8000),
            ]
            return
        }
        guard browser == nil else { return }
        searching = true
        let browser = NWBrowser(for: .bonjour(type: "_skrift._tcp", domain: nil), using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.apply(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { Task { @MainActor in self?.searching = false } }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        searching = false
    }

    private func apply(_ results: Set<NWBrowser.Result>) {
        macs = results.compactMap { result in
            guard case let .service(name, _, _, _) = result.endpoint else { return nil }
            return DiscoveredMac(id: name, name: name, host: nil, port: nil, endpoint: result.endpoint)
        }
        .sorted { $0.name < $1.name }
    }

    /// Resolve a discovered service to a concrete `MacConnection`. Seeded/manual
    /// entries return immediately; a real Bonjour endpoint resolves its host/port
    /// via a short connection (device-owed).
    func resolve(_ mac: DiscoveredMac) async -> MacConnection? {
        if let host = mac.host { return MacConnection(host: host, port: mac.port ?? MacConnection.defaultPort) }
        guard let endpoint = mac.endpoint else { return nil }
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)
            var resumed = false
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, port)? = connection.currentPath?.remoteEndpoint {
                        let hostString = "\(host)".components(separatedBy: "%").first ?? "\(host)"
                        if !resumed { resumed = true; continuation.resume(returning: MacConnection(host: hostString, port: Int(port.rawValue))) }
                    } else if !resumed {
                        resumed = true; continuation.resume(returning: nil)
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    if !resumed { resumed = true; continuation.resume(returning: nil) }
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }
}
