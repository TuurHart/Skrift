import SwiftUI
import SwiftData

/// The ingest queue / worklist. Organized around the daily loop:
/// memos arrive → Process the pile → review what's Ready → Export.
struct SidebarView: View {
    @Bindable var model: AppModel
    let files: [PipelineFile]
    /// Snapshot mode renders the queue without a ScrollView (ImageRenderer can't
    /// lay out scroll contents). The live app keeps `true` for real scrolling.
    var scrollable = true
    @Environment(\.modelContext) private var ctx

    private var filtered: [PipelineFile] { files.filter { model.matchesFilter($0) } }
    private var orderedIDs: [String] { filtered.map(\.id) }
    private var readyCount: Int { files.filter { $0.queueStatus == .ready }.count }
    private var queuedCount: Int { files.filter { $0.queueStatus == .queued }.count }
    private var pendingCount: Int {
        files.filter { $0.queueStatus == .queued || $0.queueStatus == .transcribed }.count
    }

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
                    iconButton("gearshape") { /* Settings — Phase 8 */ }
                }
            }

            HStack(spacing: 7) {
                actionButton(title: "Upload", system: "plus", filled: false) { /* ingest — Phase 8 */ }
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
        Button(action: { /* run pipeline — wired with BatchRunner */ }) {
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
            .background(Theme.accent.opacity(pendingCount > 0 ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(pendingCount == 0)
    }

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
        if model.selection.count > 1 {
            selectionBar
        } else {
            footer
        }
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
            pillButton("Process", fg: .white, bg: Theme.accent) { /* run selection */ }
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
