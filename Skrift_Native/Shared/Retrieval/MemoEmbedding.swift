import Foundation
import SwiftData

/// One embedding row (P8 retrieval index). `chunkIndex 0` = the memo's GIST
/// vector; `1…n` = body chunks (`MemoGist.chunks`).
///
/// **Derived-local, never synced**: this @Model lives in its OWN local-only
/// container (`EmbeddingStore`) — deliberately NOT the CloudKit store, so the
/// synced `Memo` schema (prod deploy pending, Stz020) is never perturbed and
/// each device re-derives its index for free. Delete the store file and the
/// sweep rebuilds everything.
@Model
final class MemoEmbedding {
    var memoID: UUID = UUID()
    var chunkIndex: Int = 0
    /// Character offsets into the speaker-stripped body (0/0 for the gist row).
    var charStart: Int = 0
    var charEnd: Int = 0
    /// Float32 little-endian, unit-normalized. Data blob — the SwiftData
    /// Codable-struct-attribute trap is real (see CLAUDE.md).
    var vector: Data = Data()
    /// `MemoGist.textHash(gist + body)` at embed time — the invalidation key.
    var textHash: String = ""
    /// Engine + dim that produced this row; a rev change invalidates it.
    var modelRev: String = ""
    var updatedAt: Date = Date()

    init(memoID: UUID, chunkIndex: Int, charStart: Int, charEnd: Int,
         vector: [Float], textHash: String, modelRev: String) {
        self.memoID = memoID
        self.chunkIndex = chunkIndex
        self.charStart = charStart
        self.charEnd = charEnd
        self.vector = Self.encode(vector)
        self.textHash = textHash
        self.modelRev = modelRev
        self.updatedAt = Date()
    }

    var floats: [Float] {
        vector.withUnsafeBytes { raw in
            let count = raw.count / MemoryLayout<Float>.stride
            // loadUnaligned: Data from the store gives no alignment guarantee.
            return (0..<count).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self) }
        }
    }

    static func encode(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
