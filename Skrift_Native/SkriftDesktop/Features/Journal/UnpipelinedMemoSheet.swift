import SwiftUI
import SwiftData
import AppKit

/// The triage peek (m6, mocks/lifecycle-triage-peek.html — signed 2026-07-22,
/// replacing the v1 "Not rated" sheet): ONE clock chip + ONE explanatory
/// sentence instead of the contradicting "Not rated"/"kept — edited" pair,
/// photos rendered at their `[[img_NNN]]` markers, the importance circles AS
/// the flag (no button, no silent 0.1 — the user states the number), and a
/// quiet Delete so the peek can finally say "no" (the Mac's first way to
/// delete a synced note). Lock is deliberately NOT here — background verb
/// (quiet-row right-click + the phone's toggle; Tuur: locked one note ever).
struct UnpipelinedMemoSheet: View {
    /// `.process` = the band/river case (circles + Delete); `.bringBack` = the
    /// conveyor case (Bring back + Delete for a fading row — Tuur's 2026-07-21
    /// round: "I have the urge to click a note to see what's in it first").
    enum PeekAction { case process, bringBack }

    let memoID: String
    var action: PeekAction = .process
    /// Corpus backlink set when the caller has it (SidebarView) — lets a
    /// linked note read "linked — won't fade" instead of a clock line.
    var backlinked: Set<UUID> = []
    var onClose: () -> Void = {}
    /// Fired after a rating write kicked the reconcile sweep — the caller
    /// dismisses and jumps to the queue row, which appears once the sweep
    /// ingests it (the existing `@Query` picks it up reactively). Also fired
    /// by Bring back (caller just refreshes).
    var onProcessed: (String) -> Void = { _ in }
    /// Fired after Delete (soft — Recently Deleted). Separate from
    /// `onProcessed` so RootView doesn't jump to a queue row that won't exist.
    var onDeleted: (String) -> Void = { _ in }

    @State private var memo: Memo?
    @State private var loaded = false
    /// Body runs: text interleaved with resolved photos, in marker order.
    @State private var runs: [BodyRun] = []
    /// Circles state — nil until the user rates; the write happens in
    /// `onChange` (the rating IS the flag).
    @State private var rating: Double?

    var body: some View {
        VStack(spacing: 0) {
            header
            if let memo {
                content(memo)
            } else if loaded {
                Spacer(minLength: 0)
                Text("This note may have been removed.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textMuted)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(width: 460, height: 560)
        .background(Theme.bg)
        .task { load() }
        .onChange(of: rating) { _, new in
            if let value = new, value > 0, let memo { rate(memo, value) }
        }
        .accessibilityIdentifier("unpipelined-sheet")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Not processed")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            if let memo {
                Text(MemoSpine.chipText(for: station(memo)))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.amber.opacity(0.3), lineWidth: 1))
                    .accessibilityIdentifier("unpipelined-sheet.chip")
            }
            Spacer()
            Button(action: onClose) {
                Text("Done").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5) }
    }

    private func content(_ memo: Memo) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(WayOutRules.displayTitle(memo))
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Text(memo.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    if let place = memo.metadata?.location?.placeName { Text(place) }
                    if memo.duration > 0 { Text(SkriftFormat.clock(memo.duration)) }
                }
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                sentence(memo)
                ScrollView { bodyView }
                if action == .process {
                    circlesBlock
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            verbs(memo)
        }
    }

    /// The one explanatory line (m6): the clock truth + the gate truth in
    /// prose — replaces the "Not rated" / "kept — edited" chip contradiction.
    private func sentence(_ memo: Memo) -> some View {
        Text(MemoSpine.peekSentence(for: memo, backlinked: backlinked))
            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.hairline.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline.opacity(0.07), lineWidth: 1))
            .accessibilityIdentifier("unpipelined-sheet.sentence")
    }

    /// Transcript with photos rendered at their `[[img_NNN]]` markers (m6 —
    /// the marker used to print literally).
    private var bodyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(runs) { run in
                switch run.kind {
                case .text(let str):
                    Text(str)
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                case .photo(let image):
                    Image(nsImage: image)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.hairline.opacity(0.09), lineWidth: 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if runs.isEmpty {
                Text("No transcript yet.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The circles ARE the flag (m2/m6): tap circle N → 0.N → save + reconcile
    /// → the caller jumps to the fresh queue row. Nothing is scored for the
    /// user; "Flag for processing" no longer exists as a separate concept.
    private var circlesBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            SignificanceCircles(value: $rating)
            Text("tap a circle — any rating queues it · the rating IS the flag, no hidden 0.1")
                .font(.system(size: 10)).foregroundStyle(Theme.textMuted)
                .padding(.top, 8)
        }
        .padding(.top, 4)
        .accessibilityIdentifier("unpipelined-sheet.circles")
    }

    /// Footer verbs: Delete (the peek's "no" — soft, through Recently Deleted)
    /// and, on the conveyor peek, Bring back.
    private func verbs(_ memo: Memo) -> some View {
        HStack(spacing: 8) {
            if action == .bringBack {
                capsuleButton("Bring back", prominent: true) { bringBack(memo) }
                    .accessibilityIdentifier("unpipelined-sheet.bringback")
            }
            if memo.deletedAt == nil {
                Button { delete(memo) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 10))
                        Text("Delete").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.destructive)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Theme.destructive.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("unpipelined-sheet.delete")
            }
            Spacer(minLength: 8)
            if memo.deletedAt == nil {
                Text("to Recently Deleted · 14 days to undo")
                    .font(.system(size: 10)).foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5) }
    }

    // MARK: - data

    /// A displayable slice of the body: a text run or a resolved photo.
    private struct BodyRun: Identifiable {
        enum Kind { case text(String), photo(NSImage) }
        let id: Int
        let kind: Kind
    }

    private func station(_ memo: Memo) -> MemoSpine.Station {
        MemoSpine.station(for: .from(memo, backlinked: backlinked))
    }

    private func load() {
        defer { loaded = true }
        guard let uuid = UUID(uuidString: memoID), let ctx = MemoCloudStore.container?.mainContext else { return }
        memo = try? ctx.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == uuid })).first
        guard let memo else { return }
        runs = Self.bodyRuns(for: memo, context: ctx)
    }

    /// Split the raw transcript into text/photo runs. Marker `[[img_NNN]]`
    /// resolves through the memo's `imageManifest` (the Nth entry's filename —
    /// same rule as `NoteBody.imageURL` / `MemoPhotoMaterializer`) to a photo
    /// `MemoAsset` blob. Assets are fetched ONCE and only when the transcript
    /// actually carries markers (blob rows are heavy — MemoAsset doc).
    /// Unresolvable markers are dropped, not printed.
    private static func bodyRuns(for memo: Memo, context: ModelContext) -> [BodyRun] {
        let raw = memo.transcript ?? ""
        guard !raw.isEmpty else { return [] }
        let pieces = BodyTransform.pieces(of: raw)

        var photosByIndex: [Int: NSImage] = [:]
        let markerIndexes = pieces.compactMap { piece -> Int? in
            if case .image(let n) = piece.segment { return n }
            return nil
        }
        if !markerIndexes.isEmpty {
            let manifest = memo.metadata?.imageManifest ?? []
            let mid = memo.id
            let photoKind = MemoAsset.Kind.photo
            let assets = (try? context.fetch(FetchDescriptor<MemoAsset>(
                predicate: #Predicate { $0.memoID == mid && $0.kind == photoKind }))) ?? []
            let byFilename = Dictionary(assets.map { ($0.filename, $0) }, uniquingKeysWith: { a, _ in a })
            for n in markerIndexes {
                guard n >= 1, n <= manifest.count,
                      let asset = byFilename[manifest[n - 1].filename],
                      let image = NSImage(data: asset.blob) else { continue }
                photosByIndex[n] = image
            }
        }

        let ns = raw as NSString
        var out: [BodyRun] = []
        var textBuffer = ""
        func flushText() {
            let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out.append(BodyRun(id: out.count, kind: .text(trimmed))) }
            textBuffer = ""
        }
        for piece in pieces {
            switch piece.segment {
            case .text(let str):
                textBuffer += str
            case .image(let n):
                if let image = photosByIndex[n] {
                    flushText()
                    out.append(BodyRun(id: out.count, kind: .photo(image)))
                }
                // unresolved marker: dropped (never print [[img_NNN]] literally)
            case .task, .memoLink:
                textBuffer += ns.substring(with: piece.rawRange)
            }
        }
        flushText()
        return out
    }

    // MARK: - verbs (all one-field cloud writes on the same lane)

    /// The rating write — flag-to-process stays the contract; the user just
    /// stated the number themselves.
    private func rate(_ memo: Memo, _ value: Double) {
        memo.significance = value
        try? MemoCloudStore.container?.mainContext.save()
        MemoCloudReconciler.reconcileSoon()
        onProcessed(memoID)
    }

    /// The conveyor's rescue, same semantics as the row button (Q4: keptAt
    /// always + undelete when set) — under one clock that IS "a fresh 30 days".
    private func bringBack(_ memo: Memo) {
        WayOutRules.bringBack(memo)
        try? MemoCloudStore.container?.mainContext.save()
        onProcessed(memoID)
    }

    /// The peek's "no": soft delete into the shared Recently Deleted —
    /// restorable from either device for `TrashPolicy.retentionDays`.
    private func delete(_ memo: Memo) {
        memo.deletedAt = Date()
        try? MemoCloudStore.container?.mainContext.save()
        onDeleted(memoID)
    }
}
