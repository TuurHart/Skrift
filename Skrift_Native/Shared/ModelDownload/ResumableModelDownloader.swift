import Foundation
import MLXLMCommon

/// Fetches a model repo so that a stumble costs seconds instead of the whole download.
///
/// **Why this exists.** The stock `#hubDownloader()` fetches each file with
/// `URLSession.download`, which buffers the ENTIRE file into a system temp location and
/// discards it if the transfer fails — so nothing is ever left to resume from, and its
/// `Range:` retry loop finds a zero-byte partial every time. On the 4.9 GB shard of
/// `gemma-4-e4b-it-8bit` that means one blip anywhere in 4.9 GB restarts all of it. Tuur's
/// iPad never once completed it, while the 294 MB embedder and the many-small-files
/// transcription models downloaded fine on the same connection — the size and the
/// all-or-nothing transfer were the whole difference (2026-08-14).
///
/// **What's different here.** We stream with `URLSession.bytes(for:)` and append to a
/// `.partial` file as bytes arrive, so progress is ON DISK continuously. A failed attempt
/// leaves a partial we resume from with `Range: bytes=<have>-`; the CDN supports it
/// (`accept-ranges: bytes`, verified). A 4.9 GB file interrupted at 90% costs the last 10%.
///
/// **It also closes the completeness hole.** Every file's expected size comes from the Hub
/// API, so a short file is never mistaken for a finished one — the failure mode that let a
/// half-fetched model report "Downloaded ✓" and then die inside MLX.
///
/// Conforms to `MLXLMCommon.Downloader`, so it drops into `loadContainer(from:)` in place of
/// the stock downloader. The layout is our own flat directory — the protocol only promises
/// "a local directory containing the requested files", so none of Hugging Face's
/// blobs/snapshots/symlink bookkeeping is needed (and its symlinks are what made the cache
/// unreadable over `devicectl` besides).
public struct ResumableModelDownloader: Downloader {

    /// Where snapshots live. One directory per repo + revision, so a re-pin downloads
    /// beside the old one rather than half-overwriting it.
    private let root: URL
    /// Retries per file before giving up. Each one resumes, so this is 5 chances to make
    /// forward progress, not 5 chances to start over.
    private let attemptsPerFile: Int

    public init(root: URL? = nil, attemptsPerFile: Int = 5) {
        self.root = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PolishModels", isDirectory: true)
        self.attemptsPerFile = attemptsPerFile
    }

    // MARK: - Downloader

    public func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let rev = revision ?? "main"
        let dir = root
            .appendingPathComponent(id.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
            .appendingPathComponent(rev, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let wanted = try await manifest(id: id, revision: rev)
            .filter { file in patterns.isEmpty || patterns.contains { Self.glob($0, matches: file.name) } }
        guard !wanted.isEmpty else { throw DownloadError.emptyManifest(id) }

        let total = wanted.reduce(Int64(0)) { $0 + $1.size }
        let progress = Progress(totalUnitCount: total)
        // Bytes already on disk from earlier runs count as done, so a resumed download
        // doesn't restart the bar at 0% and read as "stuck" (it did — 2026-08-12).
        var completedBefore: Int64 = 0
        for f in wanted { completedBefore += Self.sizeOnDisk(dir.appendingPathComponent(f.name)) }
        progress.completedUnitCount = min(completedBefore, total)
        progressHandler(progress)

        for file in wanted {
            try await fetch(file, id: id, revision: rev, into: dir) { delta in
                progress.completedUnitCount = min(progress.completedUnitCount + delta, total)
                progressHandler(progress)
            }
        }

        progress.completedUnitCount = total
        progressHandler(progress)
        return dir
    }

    // MARK: - One file, resumably

    private func fetch(_ file: RemoteFile, id: String, revision: String, into dir: URL,
                       advanced: @Sendable @escaping (Int64) -> Void) async throws {
        let dest = dir.appendingPathComponent(file.name)
        let partial = dir.appendingPathComponent(file.name + ".partial")
        let fm = FileManager.default

        // Already whole? Trust SIZE, never mere existence — a truncated file that merely
        // exists is exactly what poisoned the iPad's cache.
        if Self.sizeOnDisk(dest) == file.size { try? fm.removeItem(at: partial); return }
        if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }

        // Adopt anything the stock downloader already fetched. Switching to this
        // downloader must not cost a device 8.9 GB it is holding two directories away
        // (it did, once, on Tuur's Mac). A hardlink is instant and adds no disk; the
        // size check means we never adopt a truncated leftover.
        if let seed = Self.hubCacheCopy(of: file, id: id, revision: revision),
           Self.sizeOnDisk(seed) == file.size {
            if (try? fm.linkItem(at: seed, to: dest)) != nil || (try? fm.copyItem(at: seed, to: dest)) != nil {
                try? fm.removeItem(at: partial)
                advanced(file.size)
                return
            }
        }

        try fm.createDirectory(at: dest.deletingLastPathComponent(),
                               withIntermediateDirectories: true)

        var lastError: Error?
        for attempt in 1...attemptsPerFile {
            let have = Self.sizeOnDisk(partial)
            if have == file.size {                        // finished on a previous pass
                try fm.moveItem(at: partial, to: dest); return
            }
            if have > file.size {                          // corrupt/overshot — start it over
                try? fm.removeItem(at: partial)
            }
            do {
                try await stream(file, id: id, revision: revision,
                                 from: Self.sizeOnDisk(partial), to: partial, advanced: advanced)
                guard Self.sizeOnDisk(partial) == file.size else {
                    throw DownloadError.shortFile(file.name,
                                                  got: Self.sizeOnDisk(partial), want: file.size)
                }
                if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                try fm.moveItem(at: partial, to: dest)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                // Back off a little; the partial stays on disk and the next attempt
                // picks up where this one stopped.
                if attempt < attemptsPerFile {
                    try? await Task.sleep(for: .seconds(Double(attempt) * 2))
                }
            }
        }
        throw DownloadError.exhausted(file.name, underlying: lastError)
    }

    /// Stream bytes onto the end of `partial`. The append is what makes this resumable —
    /// every byte received is on disk before the next one arrives.
    private func stream(_ file: RemoteFile, id: String, revision: String,
                        from offset: Int64, to partial: URL,
                        advanced: @Sendable @escaping (Int64) -> Void) async throws {
        var request = URLRequest(url: Self.fileURL(id: id, revision: revision, name: file.name))
        // 60s of SILENCE fails the attempt — the whole point is to retry-and-resume rather
        // than hang for the 7-day default resource timeout.
        request.timeoutInterval = 60
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw DownloadError.badResponse(file.name) }
        switch http.statusCode {
        case 200:
            // Server ignored the Range and is sending the whole file — restart cleanly
            // rather than appending a second copy onto the first.
            if offset > 0 { try? FileManager.default.removeItem(at: partial) }
        case 206:
            break                                          // partial content, as asked
        case 416:
            try? FileManager.default.removeItem(at: partial)   // stale partial; next attempt refetches
            throw DownloadError.badResponse(file.name)
        default:
            throw DownloadError.httpStatus(file.name, http.statusCode)
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: partial.path) { fm.createFile(atPath: partial.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: partial)
        try handle.seekToEnd()
        defer { try? handle.close() }

        // ~4 MB before each write: small enough that a failure loses almost nothing,
        // large enough not to syscall per byte.
        var buffer = Data(); buffer.reserveCapacity(4 << 20)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= (4 << 20) {
                try handle.write(contentsOf: buffer)
                advanced(Int64(buffer.count))
                buffer.removeAll(keepingCapacity: true)
                try Task.checkCancellation()
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            advanced(Int64(buffer.count))
        }
    }

    // MARK: - Manifest

    struct RemoteFile: Sendable { let name: String; let size: Int64 }

    /// The repo's files AND their exact sizes, at this revision — the sizes are what let us
    /// tell "finished" from "truncated" without downloading anything twice.
    private func manifest(id: String, revision: String) async throws -> [RemoteFile] {
        var c = URLComponents(string: "https://huggingface.co/api/models/\(id)/revision/\(revision)")!
        c.queryItems = [URLQueryItem(name: "blobs", value: "true")]
        var request = URLRequest(url: c.url!)
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DownloadError.manifestUnavailable(id)
        }
        struct Payload: Decodable {
            struct Sibling: Decodable { let rfilename: String; let size: Int64? }
            let siblings: [Sibling]
        }
        return try JSONDecoder().decode(Payload.self, from: data).siblings.compactMap {
            guard let size = $0.size, size > 0 else { return nil }
            return RemoteFile(name: $0.rfilename, size: size)
        }
    }

    private static func fileURL(id: String, revision: String, name: String) -> URL {
        URL(string: "https://huggingface.co/\(id)/resolve/\(revision)/\(name)")!
    }

    /// Where the stock `#hubDownloader()` put this file, if it ever did. Same relative
    /// shape on both platforms — the caches directory differs, the layout doesn't. Snapshot
    /// entries are SYMLINKS into `blobs/`, so resolve before trusting the size.
    static func hubCacheCopy(of file: RemoteFile, id: String, revision: String) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let repoDir = "models--" + id.replacingOccurrences(of: "/", with: "--")
        let candidate = caches
            .appendingPathComponent("huggingface/hub/\(repoDir)/snapshots/\(revision)", isDirectory: true)
            .appendingPathComponent(file.name)
            .resolvingSymlinksInPath()
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    static func sizeOnDisk(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    /// Shell-style glob via `fnmatch` with flag 0, so `*` crosses `/` (a repo-relative name
    /// like `sub/config.json` matches `*.json`). Covers the patterns mlx-swift-lm passes
    /// (`*.safetensors`, `*.json`, …).
    static func glob(_ pattern: String, matches name: String) -> Bool {
        fnmatch(pattern, name, 0) == 0
    }

    enum DownloadError: LocalizedError {
        case manifestUnavailable(String)
        case emptyManifest(String)
        case badResponse(String)
        case httpStatus(String, Int)
        case shortFile(String, got: Int64, want: Int64)
        case exhausted(String, underlying: Error?)

        var errorDescription: String? {
            switch self {
            case .manifestUnavailable(let id): "Couldn't reach Hugging Face for \(id)."
            case .emptyManifest(let id): "No matching files in \(id)."
            case .badResponse(let f): "Unexpected response downloading \(f)."
            case .httpStatus(let f, let code): "Download of \(f) failed (HTTP \(code))."
            case .shortFile(let f, let got, let want):
                "\(f) arrived incomplete — \(got) of \(want) bytes."
            case .exhausted(let f, let underlying):
                "Gave up on \(f) after repeated failures\(underlying.map { " — \($0.localizedDescription)" } ?? "")."
            }
        }
    }
}
