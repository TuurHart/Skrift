import Foundation
import Network
import os

/// Abstraction over the phone's sync target so the local HTTP+Bonjour server can
/// later be swapped for CloudKit without touching callers (plan §4 — a separate
/// values call: Apple's cloud vs the local/offline ethos).
protocol SyncServer: AnyObject {
    func start() throws
    func stop()
    var port: UInt16? { get }
}

/// Tiny local-network HTTP server (Network framework) advertised over Bonjour so
/// the iPhone auto-discovers the Mac — no manual IP / QR. Stays fully local. The
/// request/response logic lives in `SyncHandlers` (unit-tested); this is just the
/// socket glue.
final class LocalHTTPServer: SyncServer {
    private let handlers: SyncHandlers
    private let preferredPort: UInt16
    private let serviceType: String
    private let serviceName: String
    private let queue = DispatchQueue(label: "com.skrift.syncserver", attributes: .concurrent)
    private var listener: NWListener?
    private(set) var port: UInt16?
    /// Request log — visible in Console.app and `log show/stream --predicate
    /// 'subsystem == "com.skrift.desktop"'`. Lets us confirm the phone↔Mac
    /// round-trip (which IP hit which path, and the response status).
    private static let log = Logger(subsystem: "com.skrift.desktop", category: "server")
    /// Hard cap on a single request body so a huge/hostile upload can't grow the
    /// accumulation buffer without bound. Voice memos are a few MB; 256 MB is ample.
    private let maxBodyBytes = 256 << 20

    init(
        handlers: SyncHandlers,
        preferredPort: UInt16 = 8000,
        serviceType: String = "_skrift._tcp",
        serviceName: String = "Skrift Desktop"
    ) {
        self.handlers = handlers
        self.preferredPort = preferredPort
        self.serviceType = serviceType
        self.serviceName = serviceName
    }

    func start() throws {
        let params = NWParameters.tcp
        // Prefer the historical port 8000; fall back to an OS-assigned one if taken.
        let made: NWListener
        if let p = NWEndpoint.Port(rawValue: preferredPort), let l = try? NWListener(using: params, on: p) {
            made = l
        } else {
            made = try NWListener(using: params)
        }
        // Advertise over Bonjour/mDNS for zero-config discovery by the phone.
        made.service = NWListener.Service(name: serviceName, type: serviceType)
        made.stateUpdateHandler = { [weak made] state in
            if case .ready = state { /* port available via made?.port */ }
            _ = made
        }
        made.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        made.start(queue: queue)
        self.listener = made
        self.port = made.port?.rawValue
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    /// Accumulate bytes until a full request (headers + Content-Length body) parses.
    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] chunk, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let chunk, !chunk.isEmpty { buf.append(chunk) }

            // Reject an oversized body before buffering it all: by the declared
            // Content-Length once headers arrive, and as a hard backstop on the
            // accumulated bytes (covers a missing/lying Content-Length).
            if (HTTPParser.declaredContentLength(buf) ?? 0) > self.maxBodyBytes || buf.count > self.maxBodyBytes {
                Self.log.warning("413 oversized \(buf.count, privacy: .public)B <- \("\(conn.endpoint)", privacy: .public)")
                self.send(conn, HTTPResponse.status(413, "Upload too large").serialize())
                return
            }

            if let request = HTTPParser.parse(buf) {
                let response = self.handlers.handle(request)
                Self.log.info("\(request.method.rawValue, privacy: .public) \(request.path, privacy: .public) <- \("\(conn.endpoint)", privacy: .public) -> \(response.status, privacy: .public) (\(buf.count, privacy: .public)B)")
                self.send(conn, response.serialize())
            } else if isComplete || error != nil {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buf)  // need more bytes
            }
        }
    }

    private func send(_ conn: NWConnection, _ data: Data) {
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
    }
}
