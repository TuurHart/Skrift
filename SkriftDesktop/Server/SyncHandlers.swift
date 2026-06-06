import Foundation

/// Pure request → response handlers for the phone↔Mac contract (plan §4). No
/// socket/transport here, so these unit-test host-less. The transport
/// (`LocalHTTPServer`) just feeds parsed requests in and writes the responses out.
///
/// Endpoints (matching the FastAPI backend byte-for-byte):
///   GET  /api/system/health        → { status, transcription_modules, … }
///   GET  /api/names/meta           → { lastModifiedAt }
///   GET  /api/names                → full NamesData (incl. tombstones)
///   PUT  /api/names                → write merged payload verbatim + prune
///   GET  /api/files/               → [PipelineFile-shaped]  (reconcile by filename)
struct SyncHandlers {
    var namesStore: NamesStore
    /// Injected so the SwiftData fetch lands in Phase 2b without touching handlers.
    var listFilesJSON: @Sendable () -> Data = { Data("[]".utf8) }

    func handle(_ req: HTTPRequest) -> HTTPResponse {
        switch (req.method, normalise(req.path)) {
        case (.GET, "/api/system/health"), (.GET, "/health"):
            return health()
        case (.GET, "/api/names/meta"):
            return namesMeta()
        case (.GET, "/api/names"):
            return namesGet()
        case (.PUT, "/api/names"):
            return namesPut(req)
        case (.GET, "/api/files"):
            return .json(raw: listFilesJSON())
        default:
            return .status(404)
        }
    }

    /// Trim a single trailing slash so "/api/names/" and "/api/names" route alike.
    private func normalise(_ path: String) -> String {
        (path.count > 1 && path.hasSuffix("/")) ? String(path.dropLast()) : path
    }

    // MARK: - Handlers

    private func health() -> HTTPResponse {
        .json(HealthResponse())
    }

    private func namesMeta() -> HTTPResponse {
        .json(["lastModifiedAt": namesStore.load().lastModifiedAt])
    }

    private func namesGet() -> HTTPResponse {
        .json(namesStore.load())
    }

    private func namesPut(_ req: HTTPRequest) -> HTTPResponse {
        guard let payload = try? JSONDecoder().decode(NamesPutPayload.self, from: req.body) else {
            return .status(400, "Invalid names payload")
        }
        // Write verbatim (caller already merged), recompute top-level + sort, prune.
        _ = namesStore.save(NamesData(lastModifiedAt: ISO8601.now(), people: payload.people))
        _ = namesStore.pruneOldTombstones(maxAgeDays: 90)
        return .json(namesStore.load())
    }
}

/// Lenient PUT body: only `people` is required; the top-level timestamp is always
/// recomputed server-side, matching `backend/api/names.py`.
private struct NamesPutPayload: Decodable {
    var people: [Person]
}

/// Health payload — contract-shaped. Native transcription is FluidAudio, surfaced
/// under the `parakeet` key the existing client checks for availability.
private struct HealthResponse: Encodable {
    struct Module: Encodable { var available = true; var engine = "fluidaudio" }
    var status = "healthy"
    var transcription_modules = ["parakeet": Module()]
}
