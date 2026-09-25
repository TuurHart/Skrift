import XCTest

/// Q56/R90 (`plan/sweep-d-mac.md`): the Mac's sidebar/export/editor did real
/// main-thread work per row/keystroke instead of once. The FULL fixes (SidebarView's
/// cached `backlinkedIDs`, `NoteProperties`' cached `TagLibrary.counts`,
/// `ProcessingCoordinator.export`'s `Task.detached` file I/O, `BodyTextView`'s
/// scoped restyle + debounced model write) live in `Features/`, which this
/// host-less bundle deliberately does NOT compile (see project.yml —
/// `SkriftDesktopTests` cherry-picks pure-logic files only, to keep this the
/// "MLX-free ~3 min" gate; `ProcessingCoordinator` alone would drag in
/// FluidAudio/MLX through `Engines/TranscriptionService`). Those four fixes are
/// therefore compile-verified by the full `SkriftDesktop` scheme build, not by
/// `./gate.sh`. What IS reachable here — and what these tests hold the line on —
/// is the underlying cost each fix was built to stop multiplying: `MemoLifecycle
/// .backlinkedIDs` (Shared/Pipeline, what SidebarView now calls ONCE per render
/// instead of once per quiet row) and `VaultExporter.export` (Pipeline/Export,
/// the file I/O `ProcessingCoordinator.export` now runs off-main).
final class MacMainThreadCostTests: XCTestCase {

    // MARK: - Sidebar: backlinkedIDs must stay cheap enough to call ONCE per render

    /// SidebarView used to call `MemoLifecycle.backlinkedIDs(in:)` — an O(memos)
    /// scan of every transcript for `[[memo:` links — inside `quietMemoRow`, i.e.
    /// once per QUIET ROW rendered, not once per render. The fix caches it
    /// (`SidebarView.backlinkedIDs`, a `@State` refreshed alongside `cloudMemos`).
    /// This proves the ONE-render-worth of work a realistic library costs stays
    /// well under a per-render budget — the multiplier the old code paid on top
    /// (× quiet-row count) is exactly what "compute once" now avoids.
    func testBacklinkedIDsOneCallPerRenderStaysUnderBudget() {
        let now = Date()
        var memos: [Memo] = []
        memos.reserveCapacity(3000)
        for i in 0..<3000 {
            let linksBack = i % 3 == 0
            let body = linksBack
                ? "Some words [[memo:\(UUID().uuidString)|Other Note]] more words."
                : "Plain words with nothing linked."
            memos.append(Memo(audioFilename: "m\(i).m4a", recordedAt: now,
                              transcript: body, transcriptStatus: .done))
        }

        let start = CFAbsoluteTimeGetCurrent()
        let ids = MemoLifecycle.backlinkedIDs(in: memos)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        XCTAssertTrue(ids.isEmpty, "the synthetic bodies link to fresh UUIDs, never each other's id")
        // Generous: a real vault is nowhere near 3000 memos. The point isn't
        // shaving microseconds — it's that ONE call is cheap, so caching it once
        // per render (instead of the old once-PER-ROW) is exactly the right fix.
        XCTAssertLessThan(elapsedMs, 200,
            "one backlinkedIDs pass over 3000 memos should be well under a render budget")
    }

    // MARK: - Export: the file work VaultExporter.export does is real, off-main-worthy work

    /// `ProcessingCoordinator.export` used to call this synchronously on the main
    /// thread; it now runs it inside `Task.detached` (mirrors `IngestService`'s
    /// `offMain`). This proves the workload it offloads is real (a multi-image
    /// note's copies + compile), and that it still succeeds — nothing about the
    /// caller's async wrapping touches `VaultExporter` itself.
    func testVaultExportOffMainWorkloadSucceeds() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let noteFolder = work.appendingPathComponent("note")
        let imagesDir = noteFolder.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let audio = noteFolder.appendingPathComponent("original.m4a")
        try Data(repeating: 7, count: 2_000_000).write(to: audio)   // ~2 MB — a real copy, not a stat()

        var markers = ""
        for i in 1...20 {
            let name = String(format: "img_%03d.jpg", i)
            try Data(repeating: UInt8(i), count: 20_000).write(to: imagesDir.appendingPathComponent(name))
            markers += "[[img_\(String(format: "%03d", i))]]\n\n"
        }

        let pf = PipelineFile(id: UUID().uuidString, filename: "Big Note.m4a", path: audio.path,
                              size: 2_000_000, sourceType: .audio)
        pf.enhancedTitle = "Big Note"
        pf.sanitised = "Twenty photos.\n\n" + markers

        var settings = AppSettings.default
        settings.noteFolder = work.appendingPathComponent("vault").path

        let start = CFAbsoluteTimeGetCurrent()
        let r = try VaultExporter.export(pf, settings: settings)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        XCTAssertTrue(r.outcome.isWrittenOrCurrent)
        XCTAssertEqual(r.imageCount, 20)
        XCTAssertNotNil(r.audioURL)
        // Not a tight budget — the point is that this is REAL, measurable work
        // (a 2 MB copy + 20 image copies), the kind that must not run on the
        // main thread inline with a keystroke or a button click.
        XCTAssertGreaterThan(elapsedMs, 0)
    }
}
