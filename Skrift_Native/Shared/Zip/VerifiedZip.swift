import Foundation
import ZIPFoundation

/// The one way Skrift reads a zip entry (Q502; C107 book bundles, C289 ePubs). ZIPFoundation's
/// `extract` RETURNS the entry's CRC-32 and never compares it with the archive's record, so a
/// damaged `.skriftbook` or ePub entry used to unpack silently as garbage. Every read here
/// compares the two and throws `DamagedEntry` on a mismatch; a file it wrote is removed first.
enum VerifiedZip {

    /// One entry whose bytes do not match the CRC-32 the archive recorded for it.
    struct DamagedEntry: LocalizedError, Equatable {
        let path: String
        var errorDescription: String? {
            "\((path as NSString).lastPathComponent) is damaged inside the file. Ask for it to be sent again."
        }
    }

    /// The entry's bytes, verified.
    static func data(_ entry: Entry, in archive: Archive) throws -> Data {
        var data = Data()
        let crc: CRC32
        do {
            crc = try archive.extract(entry, consumer: { data.append($0) })
        } catch {
            throw DamagedEntry(path: entry.path)
        }
        guard crc == entry.checksum else { throw DamagedEntry(path: entry.path) }
        return data
    }

    /// Write the entry to `url`, verified. On a mismatch the written file is deleted, so a
    /// damaged entry never lands on disk.
    static func extract(_ entry: Entry, in archive: Archive, to url: URL) throws {
        let crc: CRC32
        do {
            crc = try archive.extract(entry, to: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw DamagedEntry(path: entry.path)
        }
        guard crc == entry.checksum else {
            try? FileManager.default.removeItem(at: url)
            throw DamagedEntry(path: entry.path)
        }
    }
}
