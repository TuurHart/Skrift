import Foundation

/// "Export all notes…" (D218, D219, Q516; mock `mocks/Q515-export-all.html`): every note not in
/// the trash, locked ones included, compiled with export v2 into the vault layout and written to
/// one archive. ONE engine for the phone and the Mac: each app turns its notes into `Item`s (its
/// own export v2 inputs, as its vault export builds them); this decides the layout, the names,
/// the stamp and the order, and streams each note's files to a `Sink` one note at a time, so the
/// whole library is never in memory. It never writes into a vault: the sink is the only output.
///
/// Layout, under one folder named for the day (`Skrift notes 2026-10-24/`), as D189:
/// - `Personal/<stem>.md`, media in `Personal/Images|Recordings|Documents/` (`VaultLayout`);
/// - `Portfolio/_inbox/<stem>.md`, media beside the note (`ExportProfile.assetsBesideNote`).
enum ExportAll {

    /// One note's files, named for the stem `write` gave it. `markdown` is pre-stamp.
    struct Compiled {
        var markdown: String
        var pictures: [VaultAsset] = []
        var audio: VaultAsset?
        var documents: [VaultAsset] = []
    }

    /// One note to export. `compile` builds its files against the stem the archive gives it, on
    /// the main actor (it reads the app's models); `nil` = nothing to write for this note.
    struct Item {
        var id: UUID
        var destination: NoteDestination
        var title: String?
        var filenameFallback: String
        var recordedAt: Date?
        var compile: @MainActor (_ stem: String) throws -> Compiled?
    }

    /// Where the files go: the zip writer (`ExportAllZip`, which writes off the main actor).
    protocol Sink: AnyObject {
        func add(_ path: String, _ source: VaultAsset.Source) async throws
    }

    struct Cancelled: Error {}

    /// `Skrift notes 2026-10-24`: the archive's top folder and its file name.
    static func rootName(on date: Date, timeZone: TimeZone = ExportNaming.deviceZone) -> String {
        "Skrift notes \(ExportNaming.localDay(date, timeZone: timeZone))"
    }

    /// The folder a destination's notes sit in, under the root.
    static func noteFolder(_ destination: NoteDestination) -> String {
        [destination.label, destination.portfolioFolder].compactMap { $0 }.joined(separator: "/")
    }

    /// Writes every item to `sink` under `root`, in order, and returns how many notes went in.
    /// `progress(done, total)` after each note; `isCancelled` is asked before each note and each
    /// file, and throws `Cancelled` (the caller deletes the half-written archive). A note whose
    /// compile throws is skipped, never fatal: one bad note must not cost him the other 300.
    @MainActor
    static func write(_ items: [Item], to sink: Sink, root: String, now: Date = Date(),
                      progress: (Int, Int) -> Void = { _, _ in },
                      isCancelled: () -> Bool = { false }) async throws -> Int {
        var used = Set<String>()
        var written = 0
        progress(0, items.count)
        for (index, item) in items.enumerated() {
            if isCancelled() { throw Cancelled() }
            let profile = ExportProfile.of(item.destination)
            let folder = root + "/" + noteFolder(item.destination)
            let stem = freeStem(for: item, profile: profile, folder: folder, used: &used)
            if var compiled = try? item.compile(stem) {
                used.insert(folder + "/" + stem + ".md")
                func assetPath(_ asset: VaultAsset, _ sub: String) -> (VaultAsset, String) {
                    let dir = profile.assetsBesideNote ? folder : folder + "/" + sub
                    var name = asset.name
                    if used.contains(dir + "/" + name) {
                        let ext = (name as NSString).pathExtension
                        let base = (name as NSString).deletingPathExtension + " " + item.id.uuidString.prefix(8)
                        name = ext.isEmpty ? base : base + "." + ext
                        compiled.markdown = compiled.markdown
                            .replacingOccurrences(of: "[[\(asset.name)]]", with: "[[\(name)]]")
                            .replacingOccurrences(of: "](\(asset.name))", with: "](\(name))")
                    }
                    used.insert(dir + "/" + name)
                    return (asset, dir + "/" + name)
                }
                let files = compiled.pictures.map { assetPath($0, VaultLayout.images) }
                    + compiled.documents.map { assetPath($0, VaultLayout.documents) }
                    + (compiled.audio.map { [assetPath($0, VaultLayout.audio)] } ?? [])
                let stamped = VaultStamp.apply(to: compiled.markdown, id: item.id, touchedAt: now)
                try await sink.add(folder + "/" + stem + ".md", .data(Data(stamped.utf8)))
                for (asset, path) in files {
                    if isCancelled() { throw Cancelled() }
                    try await sink.add(path, asset.source)
                }
                written += 1
            }
            progress(index + 1, items.count)
            await Task.yield()   // let the progress row draw between notes
        }
        return written
    }

    /// The vault's own naming (`VaultName`): the plain stem, else the id-suffixed one, else
    /// counted, so two notes called the same never share a file.
    static func freeStem(for item: Item, profile: ExportProfile, folder: String, used: inout Set<String>) -> String {
        let stem = VaultName.stem(title: item.title, filename: item.filenameFallback,
                                  profile: profile, recordedAt: item.recordedAt)
        var candidates = [stem, VaultName.disambiguated(stem, id: item.id, profile: profile)]
        candidates += (2...99).map { "\(candidates[1]) \($0)" }
        return candidates.first { !used.contains(folder + "/" + $0 + ".md") } ?? candidates[1] + " " + UUID().uuidString
    }
}
