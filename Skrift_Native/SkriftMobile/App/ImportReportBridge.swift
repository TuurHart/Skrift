import Foundation

/// Carries what the last import did from `AppURLHandler` to the notes list, which draws it as
/// a banner (Q137 / C199, the Mac's twin is `ProcessingCoordinator.importReport`). Only a report
/// with something skipped or failed is kept; a clean import clears the old banner, because the
/// new notes are the confirmation.
@MainActor
final class ImportReportBridge: ObservableObject {
    static let shared = ImportReportBridge()

    @Published private(set) var report: ImportReport?

    private init() {}

    /// An empty report (a deep link, a book bundle handed to its own sheet) changes nothing.
    func post(_ new: ImportReport) {
        guard !new.isEmpty else { return }
        report = new.banner
    }

    func dismiss() { report = nil }
}
