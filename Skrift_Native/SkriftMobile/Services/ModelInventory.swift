import Foundation
import FluidAudio

/// The on-device ML models Skrift uses, with their cache locations — feeds the
/// Settings → Models tab (read-only v1: downloaded state + size on disk).
/// All models download on demand from HF and live in FluidAudio's cache dirs.
enum ModelInventory {

    struct Entry: Identifiable {
        let id: String
        let name: String
        /// What the model is for, in user words.
        let detail: String
        let directory: URL
        /// nil = not downloaded (directory missing/empty).
        let sizeBytes: Int64?

        var isDownloaded: Bool { (sizeBytes ?? 0) > 0 }
    }

    /// Snapshot of every model Skrift can have on this device.
    static func entries() -> [Entry] {
        [
            make(id: "asr", name: "Transcription",
                 detail: "Parakeet TDT 0.6B v3 — turns your voice into text, on-device.",
                 directory: AsrModels.defaultCacheDirectory(for: .v3)),
            make(id: "diarizer", name: "Speaker recognition",
                 detail: "Diarizer + voice embedder — tells speakers apart in conversations and matches enrolled voices.",
                 directory: DiarizerModels.defaultModelsDirectory()),
            make(id: "vocab", name: "Custom-word spotting",
                 detail: "CTC 110M — listens for your custom words and corrects near-misses. Downloads on the first transcription after adding words.",
                 directory: CtcModels.defaultCacheDirectory(for: .ctc110m)),
        ]
    }

    private static func make(id: String, name: String, detail: String, directory: URL) -> Entry {
        Entry(id: id, name: name, detail: detail, directory: directory,
              sizeBytes: sizeOnDisk(directory))
    }

    /// Recursive size of a directory; nil when it doesn't exist or is empty.
    static func sizeOnDisk(_ url: URL) -> Int64? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                             options: [], errorHandler: nil) else { return nil }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total > 0 ? total : nil
    }

    static func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
