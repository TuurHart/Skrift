import SwiftUI
import UserNotifications

/// Print-to-wall (backlog 🖨️ design, locked 2026-07-07): a note crossing into
/// the ORANGE importance tier (≥0.8) prints a designed card on the home
/// printer — the physical commonplace wall.
///
/// Mechanics: silent AirPrint via a saved printer (`printToPrinter`, no dialog).
/// Away from the printer, crossings ENQUEUE; the queue drains on foreground
/// when the printer answers (iOS can't print from the background). Surfaced
/// twice by design: a local notification AND an in-app "cards waiting" row on
/// Journal home (people dismiss notifications). `printedAt` ledger = a note
/// prints once, ever — re-rating never reprints; ⋯ → "Print Card" is the
/// manual/reprint path. Ledger + queue are LOCAL (the wall is per-home).
@MainActor
final class WallPrinter: ObservableObject {
    static let shared = WallPrinter()

    /// The orange tier — where the circles change color (SignificanceScale).
    static let threshold = 0.8

    private let defaults = UserDefaults.standard
    private enum Key {
        static let printerURL = "wallPrinterURL"
        static let autoPrint = "wallAutoPrint"
        static let queue = "wallPrintQueue"       // [memoID uuidString]
        static let ledger = "wallPrintedLedger"   // [memoID: printedAt]
    }

    @Published private(set) var queuedCount = 0
    @Published private(set) var printerName: String?
    @Published var autoPrint: Bool {
        didSet { defaults.set(autoPrint, forKey: Key.autoPrint) }
    }

    private init() {
        autoPrint = defaults.bool(forKey: Key.autoPrint)
        queuedCount = defaults.stringArray(forKey: Key.queue)?.count ?? 0
        printerName = defaults.string(forKey: Key.printerURL).map { _ in "Saved printer" }
    }

    var hasPrinter: Bool { defaults.string(forKey: Key.printerURL) != nil }

    // ── trigger (SignificanceCircles commit) ──

    /// Pure gate, unit-tested: enqueue exactly when the rating sits in the
    /// orange tier and the note was never printed nor already queued.
    nonisolated static func shouldEnqueue(significance: Double,
                                          alreadyPrinted: Bool,
                                          alreadyQueued: Bool) -> Bool {
        significance >= threshold && !alreadyPrinted && !alreadyQueued
    }

    func ratingCommitted(_ memo: Memo, repository: NotesRepository) {
        guard autoPrint, hasPrinter else { return }
        var queue = defaults.stringArray(forKey: Key.queue) ?? []
        let id = memo.id.uuidString
        guard Self.shouldEnqueue(significance: memo.significance,
                                 alreadyPrinted: printedAt(memo.id) != nil,
                                 alreadyQueued: queue.contains(id)) else { return }
        queue.append(id)
        defaults.set(queue, forKey: Key.queue)
        queuedCount = queue.count
        Task { await tryDrain(repository) }
    }

    func printedAt(_ memoID: UUID) -> Date? {
        (defaults.dictionary(forKey: Key.ledger) as? [String: Date])?[memoID.uuidString]
    }

    /// ⋯ → "Print Card": manual path — prints (or reprints) immediately.
    func printCard(_ memo: Memo, repository: NotesRepository) {
        var queue = defaults.stringArray(forKey: Key.queue) ?? []
        if !queue.contains(memo.id.uuidString) {
            queue.append(memo.id.uuidString)
            defaults.set(queue, forKey: Key.queue)
            queuedCount = queue.count
        }
        // Manual = allowed to reprint: clear the ledger stamp first.
        var ledger = (defaults.dictionary(forKey: Key.ledger) as? [String: Date]) ?? [:]
        ledger.removeValue(forKey: memo.id.uuidString)
        defaults.set(ledger, forKey: Key.ledger)
        Task { await tryDrain(repository) }
    }

    // ── drain ──

    /// Foreground drain: contact the saved printer; reachable → print every
    /// queued card; unreachable → leave the queue + nudge via notification
    /// (the Journal-home row is the persistent surface).
    func tryDrain(_ repository: NotesRepository) async {
        let queue = defaults.stringArray(forKey: Key.queue) ?? []
        guard !queue.isEmpty,
              let urlString = defaults.string(forKey: Key.printerURL),
              let url = URL(string: urlString) else { return }

        let printer = UIPrinter(url: url)
        let reachable = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            printer.contactPrinter { cont.resume(returning: $0) }
        }
        guard reachable else { notifyQueued(queue.count); return }

        var remaining = queue
        var ledger = (defaults.dictionary(forKey: Key.ledger) as? [String: Date]) ?? [:]
        for id in queue {
            guard let uuid = UUID(uuidString: id),
                  let memo = repository.allMemos().first(where: { $0.id == uuid }) else {
                remaining.removeAll { $0 == id }
                continue
            }
            let ok = await printOne(memo, to: printer)
            guard ok else { break } // printer hiccup — retry the rest next drain
            ledger[id] = Date()
            remaining.removeAll { $0 == id }
        }
        defaults.set(ledger, forKey: Key.ledger)
        defaults.set(remaining, forKey: Key.queue)
        queuedCount = remaining.count
        DevLog.log("Wall: printed \(queue.count - remaining.count), queued \(remaining.count)")
    }

    private func printOne(_ memo: Memo, to printer: UIPrinter) async -> Bool {
        let renderer = ImageRenderer(content: WallCardView(memo: memo))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return false }

        let controller = UIPrintInteractionController()
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "Skrift wall card"
        controller.printInfo = info
        controller.printingItem = image
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            controller.print(to: printer) { _, completed, error in
                if let error { DevLog.log("Wall print failed: \(error)") }
                cont.resume(returning: completed)
            }
        }
    }

    // ── printer pick (one-time, then silent forever) ──

    func pickPrinter() {
        let picker = UIPrinterPickerController(initiallySelectedPrinter: nil)
        picker.present(animated: true) { [weak self] controller, selected, _ in
            guard selected, let printer = controller.selectedPrinter, let self else { return }
            self.defaults.set(printer.url.absoluteString, forKey: Key.printerURL)
            self.printerName = printer.displayName
            if !self.autoPrint { self.autoPrint = true }
        }
    }

    private func notifyQueued(_ count: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(count) card\(count == 1 ? "" : "s") waiting for the wall"
            content.body = "Open Skrift when you're near your printer to print them."
            let request = UNNotificationRequest(identifier: "wall-queue",
                                                content: content, trigger: nil)
            center.add(request)
        }
    }
}

/// The paper card — mono-first (home lasers), designed not dumped: quote deco,
/// serif title + body, date/place footer. Shared soul with P6's quote cards.
struct WallCardView: View {
    let memo: Memo

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("❝")
                .font(.system(size: 42, weight: .bold, design: .serif))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.bottom, -18)
            Text(memo.displayTitle)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(.black)
            Text(bodyText)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(.black.opacity(0.9))
                .lineSpacing(4)
                .lineLimit(24)
            Spacer(minLength: 8)
            Rectangle().fill(.black.opacity(0.8)).frame(height: 1.5)
            HStack {
                Text(footer)
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(.black.opacity(0.7))
                Spacer()
                Text("SKRIFT")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(2)
                    .foregroundStyle(.black.opacity(0.45))
            }
        }
        .padding(28)
        .frame(width: 420, height: 594, alignment: .topLeading) // A-series aspect
        .background(.white)
    }

    private var bodyText: String {
        let repo = NotesRepository.shared
        let polished = repo.enhancement(forMemo: memo.id)
        let text = (polished?.hasContent == true ? polished?.copyedit : nil)
            ?? memo.transcript ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var footer: String {
        var parts = [LookbackProvider.journalDate(memo)
            .formatted(.dateTime.day().month(.wide).year())]
        if let place = memo.metadata?.location?.placeName { parts.append(place) }
        return parts.joined(separator: " · ")
    }
}

/// Settings → "Wall printer": pick once, then the wall runs itself.
struct WallPrinterSettingsSection: View {
    @ObservedObject private var wall = WallPrinter.shared
    private let repository = NotesRepository.shared

    var body: some View {
        Section {
            Button {
                wall.pickPrinter()
            } label: {
                HStack {
                    Text("Printer")
                    Spacer()
                    Text(wall.printerName ?? "Choose…")
                        .foregroundStyle(Color.skTextDim)
                }
            }
            .accessibilityIdentifier("wall-printer-pick")
            Toggle("Auto-print Important notes", isOn: $wall.autoPrint)
                .disabled(!wall.hasPrinter)
                .accessibilityIdentifier("wall-auto-print")
            if wall.queuedCount > 0 {
                Button {
                    Task { await wall.tryDrain(repository) }
                } label: {
                    HStack {
                        Text("\(wall.queuedCount) card\(wall.queuedCount == 1 ? "" : "s") queued")
                        Spacer()
                        Text("Print now").foregroundStyle(Color.skAccentText)
                    }
                }
            }
        } header: {
            Text("Wall printer")
        } footer: {
            Text("Rate a note into the orange tier and a designed card prints on your home printer — your wall becomes the commonplace book. Away from home, cards queue and print when you're back. Each note prints once; reprint from its ⋯ menu.")
        }
    }
}
