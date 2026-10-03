import Foundation
import SwiftData

/// ONE backlink scan for both apps (Q120, C239/C115): "who links HERE" and "which notes are
/// linked at all" over every body a note can carry a `[[memo:UUID|…]]` link in. A Mac-made
/// link lands in the polished copy-edit (or the name-linked `sanitised`) and syncs to the phone
/// as a `MemoEnhancement`, so a scan of `transcript` alone misses it — the panel listed the
/// backlink while `MemoLifecycle` let the linked note fade. The lifecycle, both Connections
/// panels and the phone footer all call this; nothing else parses link targets for backlinks.
enum Backlinks {
    /// One candidate linker: its id and every body that may hold a link (nil/empty skipped).
    struct Row {
        let id: UUID
        let bodies: [String?]

        init(id: UUID, bodies: [String?]) {
            self.id = id
            self.bodies = bodies
        }

        /// The `Memo` shape: raw transcript + the Mac's copy-edit.
        init(id: UUID, transcript: String?, copyedit: String?) {
            self.init(id: id, bodies: [transcript, copyedit])
        }
    }

    /// The link targets across `bodies` (cheap `contains` pre-filter, exact via `MemoLinkSyntax`).
    static func targets(in bodies: [String?]) -> Set<UUID> {
        var out: Set<UUID> = []
        for body in bodies {
            guard let body, body.contains("[[memo:") else { continue }
            out.formUnion(MemoLinkSyntax.targets(in: body))
        }
        return out
    }

    /// The ids of `rows` that link to `target` (never `target` itself), in row order.
    static func scan(for target: UUID, in rows: some Sequence<Row>) -> [UUID] {
        let marker = "[[memo:\(target.uuidString)"
        return rows.compactMap { row in
            guard row.id != target else { return nil }
            let hit = row.bodies.contains { body in
                guard let body, body.contains(marker) else { return false }
                return MemoLinkSyntax.targets(in: body).contains(target)
            }
            return hit ? row.id : nil
        }
    }

    /// Every id linked from any of `rows` (the lifecycle's "backlinked notes never fade").
    static func linkedIDs(in rows: some Sequence<Row>) -> Set<UUID> {
        var out: Set<UUID> = []
        for row in rows { out.formUnion(targets(in: row.bodies)) }
        return out
    }

    /// memoID → polished copy-edit, one query. Empty copy-edits are dropped.
    static func copyeditsByMemoID(_ enhancements: [MemoEnhancement]) -> [UUID: String] {
        var out: [UUID: String] = [:]
        for e in enhancements where !e.copyedit.isEmpty { out[e.memoID] = e.copyedit }
        return out
    }

    /// `copyeditsByMemoID` straight from a context (the Mac call sites hold a cloud context).
    static func copyeditsByMemoID(in context: ModelContext) -> [UUID: String] {
        copyeditsByMemoID((try? context.fetch(FetchDescriptor<MemoEnhancement>())) ?? [])
    }
}
