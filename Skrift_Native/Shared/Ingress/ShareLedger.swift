import CryptoKit
import Foundation

/// C127 (D36): the same file shared twice is ONE note. The share extension fingerprints the
/// bytes it keeps (clips, a movie, a document, pictures) and looks them up here before it shows
/// the sheet; a hit shows "Already in Skrift" and writes nothing. A save records the fingerprint
/// against the entry id, which is the memo id the drain gives the note (C147). The app prunes
/// rows whose note is gone, so a deleted note can be shared in again.
///
/// One small JSON file in the App Group container (`CaptureInbox.containerURL`). Foundation +
/// CryptoKit only, so the extension, the app and the host-less Mac test bundle compile it.
struct ShareLedger {

    struct Row: Codable, Equatable {
        var fingerprint: String
        var id: UUID
        /// Q464: the note's title and its notes-list line, refreshed by the app on every drain so
        /// the "Already in Skrift" screen can draw the note it already is. nil until the app saw it.
        var title: String? = nil
        var line: String? = nil
    }

    /// Newest last; the oldest rows fall off past this.
    static let cap = 500

    let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    /// The ledger beside the inbox, or nil when the App Group container is unavailable.
    static func inContainer(_ container: URL?) -> ShareLedger? {
        container.map { ShareLedger(fileURL: $0.appendingPathComponent("share-ledger.json")) }
    }

    func rows() -> [Row] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Row].self, from: data)) ?? []
    }

    /// The note an earlier share of these exact bytes made, or nil.
    func existing(_ fingerprint: String) -> UUID? {
        existingRow(fingerprint)?.id
    }

    func existingRow(_ fingerprint: String) -> Row? {
        rows().last { $0.fingerprint == fingerprint }
    }

    /// Q464: refresh each row's title + list line from its note (`describe` answers nil for a
    /// row whose note the app has not made yet; that row keeps what it had).
    func describe(_ describe: (UUID) -> (title: String, line: String)?) {
        let all = rows()
        let next = all.map { row -> Row in
            guard let d = describe(row.id) else { return row }
            var r = row
            r.title = d.title
            r.line = d.line
            return r
        }
        if next != all { write(next) }
    }

    @discardableResult
    func record(_ fingerprint: String, id: UUID) -> Bool {
        var all = rows().filter { $0.fingerprint != fingerprint }
        all.append(Row(fingerprint: fingerprint, id: id))
        if all.count > Self.cap { all.removeFirst(all.count - Self.cap) }
        return write(all)
    }

    /// Drop every row whose note no longer exists (`keep` says which ids still have a note or a
    /// pending inbox entry).
    func prune(keep: (UUID) -> Bool) {
        let all = rows()
        let kept = all.filter { keep($0.id) }
        if kept.count != all.count { write(kept) }
    }

    @discardableResult
    private func write(_ all: [Row]) -> Bool {
        guard let data = try? JSONEncoder().encode(all) else { return false }
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }
}

/// The bytes of one share as one hex SHA-256. Each file is hashed in 1 MB chunks (a movie
/// never loads whole into the extension's memory); the per-item digests, in order, are hashed
/// again. Same bytes in the same order = the same fingerprint, whatever the files are called.
/// nil when there is nothing to fingerprint or a file cannot be read.
enum ShareFingerprint {

    static func of(files: [URL], datas: [Data] = []) -> String? {
        guard !files.isEmpty || !datas.isEmpty else { return nil }
        var outer = SHA256()
        for url in files {
            guard let digest = digest(of: url) else { return nil }
            outer.update(data: digest)
        }
        for data in datas { outer.update(data: Data(SHA256.hash(data: data))) }
        return outer.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func digest(of url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            // `read(upToCount:)` answers nil OR empty data at the end; only a throw is a failure.
            let chunk: Data?
            do { chunk = try handle.read(upToCount: 1 << 20) } catch { return nil }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize())
    }
}
