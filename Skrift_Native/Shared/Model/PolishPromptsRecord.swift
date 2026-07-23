import Foundation
import SwiftData

/// CloudKit-synced carrier for the polish PROMPTS (iPad wave v2, 2026-07-23 —
/// Tuur: "do llm prompt syncing as well"), so a prompt tuned on the Mac and the
/// iPad's on-demand polisher always speak with one voice.
///
/// The local source of truth stays per-app (`AppSettings.prompts` in the Mac's
/// settings.json; `PolishPromptsStore`/UserDefaults on the iPad) — this carrier
/// mirrors the three effective prompt TEXTS for sync; `PolishPromptsSyncCore`
/// reconciles whole-blob LWW by `modifiedAt` (a reset-to-default on one device
/// propagates — union semantics make no sense for prose).
///
/// One row by convention (collapsed in the core). CloudKit shape rules:
/// every attribute defaulted, no `@Attribute(.unique)`.
@Model
final class PolishPromptsRecord {
    var copyEdit: String = ""
    var summary: String = ""
    var title: String = ""
    var modifiedAt: Date = Date()

    init(copyEdit: String, summary: String, title: String, modifiedAt: Date = Date()) {
        self.copyEdit = copyEdit
        self.summary = summary
        self.title = title
        self.modifiedAt = modifiedAt
    }
}
