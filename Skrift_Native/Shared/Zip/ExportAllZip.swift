import Foundation
import ZIPFoundation

/// The zip `ExportAll` writes into (D218, Q516). Entries stream from their file or bytes straight
/// into the archive, off the main actor, one at a time; media is stored (it is already
/// compressed), markdown deflated. ZIP64 past 4 GB, so a big library still makes one file.
final class ExportAllZip: ExportAll.Sink, @unchecked Sendable {
    private let archive: Archive

    init(creating url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        archive = try Archive(url: url, accessMode: .create)
    }

    func add(_ path: String, _ source: VaultAsset.Source) async throws {
        let method: CompressionMethod = path.hasSuffix(".md") ? .deflate : .none
        let archive = archive
        try await Task.detached(priority: .userInitiated) {
            switch source {
            case .file(let url):
                try archive.addEntry(with: path, fileURL: url, compressionMethod: method)
            case .data(let data):
                try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                                     compressionMethod: method) { position, size in
                    data.subdata(in: Int(position)..<Int(position) + size)
                }
            }
        }.value
    }
}

/// One "Export all notes…" run, for the Settings row on both apps: Ready → Building (done of
/// total, Cancel) → Finished (the share sheet / save panel takes the file) → Ready. The zip
/// lives in a temp folder only Skrift writes; Cancel, a failure and `finish()` all delete it.
@MainActor
final class ExportAllRun: ObservableObject {
    enum State: Equatable {
        case ready
        case building(done: Int, total: Int)
        case finished(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .ready
    private var cancelled = false
    private var task: Task<Void, Never>?

    init(state: State = .ready) { self.state = state }

    static var tempFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ExportAll", isDirectory: true)
    }

    var isBuilding: Bool { if case .building = state { return true } else { return false } }

    /// Gather the notes (on the main actor) and build the zip.
    func start(gather: @escaping @MainActor () -> [ExportAll.Item]) {
        guard !isBuilding else { return }
        cancelled = false
        let now = Date()
        let root = ExportAll.rootName(on: now)
        task = Task { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            try? fm.removeItem(at: Self.tempFolder)
            let url = Self.tempFolder.appendingPathComponent(root + ".zip")
            do {
                try fm.createDirectory(at: Self.tempFolder, withIntermediateDirectories: true)
                let items = gather()
                self.state = .building(done: 0, total: items.count)
                let zip = try ExportAllZip(creating: url)
                _ = try await ExportAll.write(items, to: zip, root: root, now: now,
                                              progress: { done, total in self.state = .building(done: done, total: total) },
                                              isCancelled: { self.cancelled })
                self.state = .finished(url)
            } catch {
                try? fm.removeItem(at: Self.tempFolder)
                self.state = error is ExportAll.Cancelled
                    ? .ready : .failed("Couldn't build the zip: \(error.localizedDescription)")
            }
        }
    }

    func cancel() { cancelled = true }

    /// The share sheet or save panel is done with the file: delete it and go back to Ready.
    func finish() {
        try? FileManager.default.removeItem(at: Self.tempFolder)
        state = .ready
    }
}
