import Foundation
import SwiftData

/// Owns the retrieval index's SwiftData container — a fully SEPARATE container
/// from `NotesRepository`'s CloudKit store (the plan's sanctioned shape: local
/// derived data, zero risk to the synced schema, and no edits to the contested
/// `NotesRepository` while other lanes are hot).
final class EmbeddingStore {
    let container: ModelContainer

    init(inMemory: Bool = false) {
        let schema = Schema([MemoEmbedding.self])
        let config = ModelConfiguration("SkriftEmbeddings",
                                        schema: schema,
                                        isStoredInMemoryOnly: inMemory,
                                        cloudKitDatabase: .none)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // Derived data: on any store-level failure, start clean in memory
            // rather than crash — the sweep rebuilds from the memos.
            let fallback = ModelConfiguration("SkriftEmbeddings",
                                              schema: schema,
                                              isStoredInMemoryOnly: true,
                                              cloudKitDatabase: .none)
            container = try! ModelContainer(for: schema, configurations: fallback)
        }
    }
}
