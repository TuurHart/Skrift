import Foundation

/// Auto-pushes the names DB to the Mac shortly after a voiceprint enroll.
///
/// Without this, naming a speaker stored the embedding in the phone's local
/// names.json but it only reached the Mac on a manual sync tap — cross-device
/// auto-match silently lacked the new voiceprint (confirmed bug, 2026-06-09).
///
/// Debounced: rapid enrolls (naming several speakers in one conversation)
/// coalesce into one push. No-op when no Mac is paired.
@MainActor
enum NamesAutoSync {
    private static var pending: Task<Void, Never>?
    /// Injectable for tests (instant debounce).
    static var debounce: Duration = .seconds(3)

    /// How many syncs actually ran (test observability).
    private(set) static var runCount = 0

    static func kick(transportProvider: @escaping @MainActor () -> NamesTransport? = {
        MacTransportFactory.makeNamesTransport()
    }) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            guard let transport = transportProvider() else { return }   // no Mac paired
            runCount += 1
            _ = await NamesSync(store: .shared, transport: transport).run()
        }
    }

    /// Await the in-flight push (tests).
    static func flush() async {
        await pending?.value
    }
}
