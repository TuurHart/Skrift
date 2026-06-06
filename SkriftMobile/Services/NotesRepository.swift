import Foundation
import SwiftData

/// Owns the SwiftData `ModelContainer` for memos and exposes CRUD. Honors
/// `-inMemoryStore` so UI tests get a fresh, deterministic store per launch.
@MainActor
final class NotesRepository {
    static let shared = NotesRepository(inMemory: LaunchFlags.inMemoryStore)

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init(inMemory: Bool) {
        let schema = Schema([Memo.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Unable to create ModelContainer for Memo: \(error)")
        }
    }

    func insert(_ memo: Memo) {
        context.insert(memo)
        save()
    }

    /// Newest first — the order the memos list renders.
    func allMemos() -> [Memo] {
        let descriptor = FetchDescriptor<Memo>(sortBy: [SortDescriptor(\.recordedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func memo(id: UUID) -> Memo? {
        let descriptor = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    func delete(_ memo: Memo) {
        context.delete(memo)
        save()
    }

    func save() {
        try? context.save()
    }
}
