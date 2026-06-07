import SwiftUI
import SwiftData
import AppKit

/// The ingest queue / worklist. Organized around the daily loop:
/// memos arrive → Process the pile → review what's Ready → Export.
struct SidebarView: View {
    @Bindable var model: AppModel
    let files: [PipelineFile]
    @Bindable var coordinator: ProcessingCoordinator
    var onOpenSettings: () -> Void = {}
    /// Snapshot mode renders the queue without a ScrollView (ImageRenderer can't
    /// lay out scroll contents). The live app keeps `true` for real scrolling.
    var scrollable = true
    @Environment(\.modelContext) private var ctx

    private var filtered: [PipelineFile] { files.filter { model.matchesFilter($0) } }
    private var orderedIDs: [String] { filtered.map(\.id) }
    private var readyCount: Int { files.filter { $0.queueStatus == .ready }.count }
    private var queuedCount: Int { files.filter { $0.queueStatus == .queued }.count }
    private var pendingFiles: [PipelineFile] {
        files.filter { $0.queueStatus == .queued || $0.queueStatus == .transcribed }
    }
    private var pendingCount: Int { pendingFiles.count }
    @State private var dragOver = false

    var body: some View {
        VStack(spacing: 0) {
            header
            triageLine
            queue
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.hairline.opacity(0.07)).frame(width: 0.5)
        }
        .dropDestination(for: URL.self) { urls, _ in ingest(urls); return true } isTargeted: { dragOver = $0 }
        .overlay {
            if dragOver {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(Theme.accent.opacity(0.06))
                    .overlay(Text("Drop to add").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    // ── Ingest ──────────────────────────────────────────────
    private func openUploadPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.prompt = "Add"
        panel.message = "Add voice memos, audio files, or an Apple Notes folder"
        guard panel.runModal() == .OK else { return }
        ingest(panel.urls)
    }

    private func ingest(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        do {
            let created = try IngestService().ingest(localURLs: urls, into: ctx)
            if let first = created.first {
                model.activeID = first.id
                model.selection = [first.id]
            }
        } catch {
            coordinator.lastError = "Import failed: \(error.localizedDescription)"
        }
    }

    // ── Header ──────────────────────────────────────────────
    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [Theme.rgb(142, 125, 255), Theme.rgb(106, 89, 239)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 22, height: 22)
                        .overlay(Text("S").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white))
                        .shadow(color: Theme.accent.opacity(0.45), radius: 3, y: 1)
                    Text("Skrift").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(Theme.green).frame(width: 6, height: 6)
                        }
                    }
                    .help("Parakeet · Gemma · server healthy")
                    iconButton("gearshape") { onOpenSettings() }
                        .accessibilityIdentifier("sidebar.settings")
                }
            }

            HStack(spacing: 7) {
                actionButton(title: "Upload", system: "plus", filled: false) { openUploadPanel() }
                processButton
            }

            filterChips
        }
        .padding(.horizontal, 12)
        .padding(.top, 38)   // room for the inset traffic lights (hidden titlebar)
        .padding(.bottom, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline.opacity(0.06)).frame(height: 0.5)
        }
    }

    private var processButton: some View {
        Button {
            let ids = pendingFiles.map(\.id)
            Task { await coordinator.process(fileIDs: ids, context: ctx) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill").font(.system(size: 10))
                Text("Process")
                if pendingCount > 0 {
                    Text("\(pendingCount)")
                        .font(.system(size: 11))
                        .padding(.horizontal, 5)
                        .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Theme.accent.opacity(canProcess ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!canProcess)
        .accessibilityIdentifier("sidebar.process")
    }

    private var canProcess: Bool { pendingCount > 0 && !coordinator.isRunning }

    private func actionButton(title: String, system: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 11, weight: .semibold))
                Text(title)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, height: 24)
                .background(Theme.hairline.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var filterChips: some View {
        HStack(spacing: 5) {
            ForEach(QueueFilter.allCases, id: \.self) { f in
                let on = model.filter == f
                Text(f.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(on ? Theme.accent : Theme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(on ? Theme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(on ? Theme.accent.opacity(0.22) : .clear, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { model.filter = f }
            }
            Spacer(minLength: 0)
        }
    }

    // ── Triage line — what needs ME right now ───────────────
    @ViewBuilder private var triageLine: some View {
        HStack(spacing: 0) {
            Text("\(readyCount) ready to review")
                .foregroundStyle(Theme.accent).fontWeight(.semibold)
            if queuedCount > 0 {
                Text(" · \(queuedCount) queued").foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 4)
    }

    // ── Queue ───────────────────────────────────────────────
    @ViewBuilder private var queue: some View {
        // Plain VStack (not Lazy) is fine for a personal-scale vault; revisit
        // windowing (List / lazy) only if a very large queue shows scroll jank.
        let content = VStack(spacing: 2) {
            ForEach(filtered) { f in
                QueueRowView(file: f, selected: model.selection.contains(f.id)) {
                    model.handleClick(f.id, in: orderedIDs)
                }
            }
        }
        .padding(8)

        if scrollable {
            ScrollView { content }
        } else {
            VStack(spacing: 0) { content; Spacer(minLength: 0) }
        }
    }

    // ── Bottom bar — footer / selection action bar ──────────
    @ViewBuilder private var bottomBar: some View {
        if let rs = coordinator.runState {
            runBar(rs)
        } else if model.selection.count > 1 {
            selectionBar
        } else {
            footer
        }
    }

    @ViewBuilder private func runBar(_ rs: ProcessingCoordinator.RunState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label = rs.loadingLabel {
                HStack {
                    Text("Loading " + label)
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.accent)
                    Spacer()
                    if let f = rs.loadingFraction {
                        Text("\(Int(f * 100))%")
                            .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                }
                progressTrack(rs.loadingFraction)
            } else {
                let pct = rs.total > 0 ? Double(rs.done) / Double(rs.total) : 0
                HStack {
                    Text("Processing \(min(rs.done + 1, rs.total)) of \(rs.total)")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.accent)
                    Spacer()
                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                }
                if let title = rs.currentTitle {
                    Text(title).font(.system(size: 11)).foregroundStyle(Theme.textMuted).lineLimit(1)
                }
                progressTrack(pct)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.accent.opacity(0.10))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5) }
    }

    private func progressTrack(_ fraction: Double?) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline.opacity(0.14)).frame(height: 5)
                Capsule().fill(Theme.accent)
                    .frame(width: geo.size.width * (fraction ?? 0.12), height: 5)
                    .opacity(fraction == nil ? 0.5 : 1)
            }
        }
        .frame(height: 5)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            engineDot("Parakeet")
            engineDot("Gemma 4")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline.opacity(0.06)).frame(height: 0.5)
        }
    }

    private func engineDot(_ name: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.green).frame(width: 6, height: 6)
            Text(name).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 7) {
            Text("\(model.selection.count) selected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            pillButton("Process", fg: .white, bg: Theme.accent) {
                let ids = Array(model.selection)
                model.selection.removeAll()
                Task { await coordinator.process(fileIDs: ids, context: ctx) }
            }
            pillButton("Delete", fg: Theme.destructive, bg: Theme.destructive.opacity(0.15)) { deleteSelected() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.accent.opacity(0.09))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5)
        }
    }

    private func pillButton(_ title: String, fg: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(fg)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(bg, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func deleteSelected() {
        let ids = model.selection
        for f in files where ids.contains(f.id) { ctx.delete(f) }
        try? ctx.save()
        model.selection.removeAll()
    }
}

// ── Row ─────────────────────────────────────────────────────
private struct QueueRowView: View {
    let file: PipelineFile
    let selected: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        let st = file.queueStatus
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: file.sourceSymbol)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Theme.accent : Theme.textMuted)
                    .frame(width: 14)
                Text(file.queueTitle)
                    .font(.system(size: 13, weight: st == .exported ? .medium : .semibold))
                    .foregroundStyle(st == .exported ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatusPill(status: st)
            }
            Text(file.queueMeta)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
                .padding(.leading, 21)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(selected ? Theme.accent.opacity(0.2) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
    }

    private var rowBackground: Color {
        if selected { return Theme.accent.opacity(0.13) }
        if hovering { return Theme.hairline.opacity(0.04) }
        return .clear
    }
}

private struct StatusPill: View {
    let status: QueueStatus
    var body: some View {
        HStack(spacing: 4) {
            if status.pulses { PulseDot(color: status.color) }
            Text(status.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(status.tint, in: Capsule())
        .fixedSize()
    }
}

private struct PulseDot: View {
    let color: Color
    @State private var on = false
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
