import Foundation
import Network

/// A Mac found on the local network (or seeded for tests). `host`/`port` are
/// known immediately for seeded/manual entries; for a real Bonjour result they
/// are eager-resolved shortly after the service appears (so the row can show the
/// IP, which is how you tell two Macs apart on a shared network).
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
/// Two refinements for the multi-Mac case: each discovered service is
/// **eager-resolved** to a concrete host/port (shown per row), and the "looking
/// for more Macs" spinner **caps** after a quiet settle window instead of
/// spinning forever.
///
/// The Simulator can't see the real Mac, so UI tests pass `-seedDiscoveredMacs`
/// to inject entries; the live discovery + resolve is device/network-owed.
@MainActor
final class MacDiscovery: ObservableObject {
    @Published private(set) var macs: [DiscoveredMac] = []
    @Published private(set) var searching = false

    private var browser: NWBrowser?
    private let seeded: Bool
    /// How long after the last discovery change to keep the spinner up.
    private let settleSeconds: Double
    private var settleTask: Task<Void, Never>?
    private var resolving: Set<String> = []

    init(seeded: Bool = LaunchFlags.seedDiscoveredMacs) {
        self.seeded = seeded
        self.settleSeconds = seeded ? 2.0 : 6.0
    }

    func start() {
        if seeded {
            searching = true
            macs = [
                DiscoveredMac(id: "Skrift Desktop", name: "Skrift Desktop", host: "studio.local", port: 8000),
                DiscoveredMac(id: "Tiuri's MacBook", name: "Tiuri's MacBook", host: "192.168.1.22", port: 8000),
            ]
            armSettle()
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
        armSettle()
    }

    func stop() {
        browser?.cancel()
        browser = nil
        settleTask?.cancel()
        settleTask = nil
        searching = false
    }

    /// "Search again" affordance once discovery has settled (or found nothing):
    /// a clean stop + start re-issues the mDNS query.
    func restart() {
        stop()
        start()
    }

    private func apply(_ results: Set<NWBrowser.Result>) {
        // Preserve already-resolved host/port across result churn so rows don't
        // flicker back to "resolving…" every time the set changes.
        var existing: [String: DiscoveredMac] = [:]
        for m in macs { existing[m.id] = m }

        var next: [DiscoveredMac] = []
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            if let prior = existing[name], prior.host != nil {
                var m = prior
                m.endpoint = result.endpoint
                next.append(m)
            } else {
                let m = DiscoveredMac(id: name, name: name, host: nil, port: nil, endpoint: result.endpoint)
                next.append(m)
                resolveEagerly(m)
            }
        }
        macs = next.sorted { $0.name < $1.name }
        // Results just changed — keep the spinner up a little longer, then cap.
        searching = true
        armSettle()
    }

    /// Resolve a discovered service's host/port in the background and patch it
    /// onto the matching row (so the IP shows without the user tapping Connect).
    private func resolveEagerly(_ mac: DiscoveredMac) {
        guard !resolving.contains(mac.id) else { return }
        resolving.insert(mac.id)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let conn = await self.resolve(mac)
            self.resolving.remove(mac.id)
            guard let conn else { return }
            if let idx = self.macs.firstIndex(where: { $0.id == mac.id }) {
                self.macs[idx].host = conn.host
                self.macs[idx].port = conn.port
            }
        }
    }

    /// Cap the spinner: flip `searching` off `settleSeconds` after the most recent
    /// discovery change. Re-armed on every change, so it stays up while Macs keep
    /// appearing and stops once the network goes quiet. The browser stays alive,
    /// so a Mac that appears later re-arms the spinner naturally.
    private func armSettle() {
        settleTask?.cancel()
        let seconds = settleSeconds
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.searching = false
        }
    }

    /// Resolve a discovered service to a concrete `MacConnection`. Seeded/manual
    /// entries (and already eager-resolved ones) return immediately; a real
    /// Bonjour endpoint resolves its host/port via a short connection.
    func resolve(_ mac: DiscoveredMac) async -> MacConnection? {
        if let host = mac.host { return MacConnection(host: host, port: mac.port ?? MacConnection.defaultPort) }
        guard let endpoint = mac.endpoint else { return nil }
        return await withCheckedContinuation { continuation in
            // Force IPv4: Bonjour often resolves to a link-local IPv6 address
            // (fe80::…) that's unroutable without an interface zone and awkward
            // in a URL. The Mac's IPv4 (e.g. 192.168.1.139) is reachable + clean.
            let params = NWParameters.tcp
            if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ip.version = .v4
            }
            let connection = NWConnection(to: endpoint, using: params)
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
