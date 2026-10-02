import Foundation

/// The confirm step in front of "delete person" (R79 / C266), on every entry point in both apps
/// (phone `PersonEditorView` + `PersonDetailView`, Mac `PersonEditor`). Delete tombstones the
/// person and the tombstone goes out over CloudKit at once, so a stray tap must not fire it.
/// Pure state, no UI: a view calls `request`, shows its own dialog while `isPending`, and only
/// `confirm()` hands back the canonical to delete.
struct NameDeleteConfirm: Equatable {
    /// The canonical waiting on an answer; nil = no dialog.
    private(set) var pending: String?

    var isPending: Bool { pending != nil }

    /// Delete was tapped: park the canonical, delete nothing yet. A blank canonical is ignored.
    mutating func request(_ canonical: String) {
        let c = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = c.isEmpty ? nil : canonical
    }

    /// The user said "Delete": returns the canonical to delete (once), clears the dialog.
    mutating func confirm() -> String? {
        defer { pending = nil }
        return pending
    }

    /// The user cancelled or dismissed.
    mutating func cancel() { pending = nil }

    /// Dialog title, e.g. "Delete Jack Bauer?".
    static func title(for canonical: String) -> String {
        "Delete \(NamesMerge.keyName(canonical))?"
    }

    static let message = "This removes the person from your names on every device."
    static let confirmLabel = "Delete person"
}
