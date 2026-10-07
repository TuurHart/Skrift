import SwiftUI
import AppKit

/// Q333: the Apple Notes triage sheet, built to mocks/Q71-apple-notes-triage-v3.html (the phone
/// frame) on the Mac layout of mocks/Q67-apple-notes-triage.html: a 232 pt rail with the ten notes
/// of the batch beside the open note, a 720 pt sheet. Colours come from `Theme`, which reads the
/// same `Palette` table the mock's `--a-*` tokens were drawn from.
struct AppleNotesTriageView: View {
    @Bindable var model: AppleNotesTriageModel
    var onClose: () -> Void = {}

    @State private var openList: Set<String> = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline.opacity(0.09))
            HStack(spacing: 0) {
                if model.phase == .triage { rail }
                content
            }
            Divider().overlay(Theme.hairline.opacity(0.09))
            footer
        }
        .frame(width: 720, height: 600)
        .background(Theme.bg)
        .foregroundStyle(Theme.textPrimary)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .onAppear { focused = true }
        .overlay(alignment: .bottom) { toast }
        .task { if model.phase == .loading { await model.load() } }
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Import Apple Notes").font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(subtitle)
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary).monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var subtitle: String {
        let c = model.counts
        switch model.phase {
        case .loading: return "Reading Notes"
        case .denied, .failed: return "Not read"
        case .triage:
            let p = model.position
            return "\(model.cursor + 1) of \(model.batchIDs.count) · batch \(p.number) of \(p.of)"
        case .start: return "\(c.decided) of \(c.total) decided"
        case .report(let end): return end ? "All \(c.total) decided" : "So far · \(c.decided) of \(c.total)"
        }
    }

    // MARK: - rail (the ten)

    private var rail: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BATCH \(model.position.number) OF \(model.position.of)")
                .font(.system(size: 11, weight: .semibold)).tracking(0.55)
                .foregroundStyle(Theme.textSecondary).padding(.horizontal, 9).padding(.bottom, 6)
            ForEach(Array(model.batchIDs.enumerated()), id: \.element) { k, id in
                if let n = model.note(id) { railRow(n, k) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 12)
        .frame(width: 232).frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline.opacity(0.09)).frame(width: 1) }
    }

    private func railRow(_ n: AppleNoteSummary, _ k: Int) -> some View {
        let selected = k == model.cursor
        return Button { model.select(k) } label: {
            HStack(spacing: 6) {
                cell(model.decision(n.id))
                VStack(alignment: .leading, spacing: 0) {
                    Text(n.title).font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
                    Text(dateText(n.created)).font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(selected ? Theme.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("applenotes.rail.\(k)")
    }

    private func cell(_ d: TriageDecision?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(d?.kind == .rated ? Theme.accent.opacity(0.13) : Theme.chip)
            switch d?.kind {
            case .rated:
                HStack(spacing: 2) {
                    ForEach(0..<(d?.rating ?? 1), id: \.self) { _ in Circle().fill(Theme.accent).frame(width: 5, height: 5) }
                }
            case .skipped: Text("–").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.textSecondary)
            case .never: Text("×").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.destructive)
            case nil: EmptyView()
            }
        }
        .frame(width: 30, height: 24)
        .overlay(alignment: .bottom) {
            if d?.skriftID != nil { Capsule().fill(Theme.green).frame(height: 2).padding(.horizontal, 5).padding(.bottom, 3) }
        }
    }

    // MARK: - content

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading: centered { ProgressView().controlSize(.small); Text("Reading your Notes…").font(.system(size: 13)).foregroundStyle(Theme.textSecondary) }
        case .denied(let why): permission(why)
        case .failed(let why): centered { Text("Could not read Notes").font(.system(size: 15, weight: .semibold)); Text(why).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 420) }
        case .start: ScrollView { start.padding(.horizontal, 18).padding(.vertical, 14) }
        case .triage: triageBody
        case .report(let end): ScrollView { report(end: end).padding(.horizontal, 18).padding(.vertical, 14) }
        }
    }

    private func centered<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 10) { c() }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func permission(_ why: String) -> some View {
        centered {
            Image(systemName: "lock.shield").font(.system(size: 28)).foregroundStyle(Theme.accentText)
            Text("Allow Skrift to read your Notes").font(.system(size: 15, weight: .semibold))
            Text("Skrift reads a copy of the Notes database on this Mac, so it can tell notes apart even after you rename them. It never changes Notes. Turn on Full Disk Access for Skrift, then try again.")
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack {
                Button("Open Privacy Settings") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(u) }
                }
                Button("Try again") { Task { await model.load() } }.buttonStyle(.borderedProminent).tint(Theme.accent)
            }
            if !why.isEmpty { Text(why).font(.system(size: 11)).foregroundStyle(Theme.textMuted).frame(maxWidth: 440).multilineTextAlignment(.center) }
        }
    }

    // MARK: - start

    private var start: some View {
        let c = model.counts
        let next = model.position
        return VStack(alignment: .leading, spacing: 12) {
            card {
                HStack(alignment: .top, spacing: 8) {
                    Text("1").font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 22, height: 22).foregroundStyle(Theme.accentText)
                        .background(Theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reading Apple Notes on your Mac").font(.system(size: 14))
                        Text("\(c.total) notes · one list, no folders · read \(readAgo) · Full Disk Access on")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    }
                }
                hint("New notes you write in Notes show up here by themselves.")
                hint("Your Notes are one flat list, so there is no folder step and Skrift adds no folder tags.")
                if c.lockedLeftBehind > 0 { hint("\(c.lockedLeftBehind) locked note\(c.lockedLeftBehind == 1 ? "" : "s") stay\(c.lockedLeftBehind == 1 ? "s" : "") behind. Skrift cannot read them.") }
            }
            card {
                Text("Continue where you left off").font(.system(size: 17, weight: .bold))
                progressBar(c)
                (Text("\(c.decided) of \(c.total)").fontWeight(.bold) + Text(" decided · \(c.left) to go · next up: batch \(next.number) of \(next.of)"))
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 6) {
                    chip("In Skrift \(c.inSkrift)", .accent); chip("Never import \(c.never)", .plain); chip("Skipped \(c.skipped)", .plain)
                }
                VStack(spacing: 3) {
                    ForEach(Array(model.dayLog.enumerated()), id: \.offset) { _, row in
                        HStack { Text(dayText(row.day)); Spacer(); Text("\(row.decided) decided") }
                            .font(.system(size: 13, weight: Calendar.current.isDateInToday(row.day) ? .semibold : .regular)).monospacedDigit()
                    }
                }
            }
            hint("Every tap is saved the moment you make it. Close the sheet whenever you like.")
        }
    }

    private func progressBar(_ c: AppleNotesTriage.Counts) -> some View {
        GeometryReader { g in
            let total = max(1, CGFloat(c.total))
            HStack(spacing: 0) {
                Rectangle().fill(Theme.accent).frame(width: g.size.width * CGFloat(c.inSkrift) / total)
                Rectangle().fill(Theme.textMuted).frame(width: g.size.width * CGFloat(max(0, c.decided - c.inSkrift)) / total)
                Spacer(minLength: 0)
            }
            .background(Theme.chip).clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 8)
        .accessibilityLabel("\(c.decided) of \(c.total) decided")
    }

    // MARK: - triage

    private var triageBody: some View {
        ScrollView {
            if let n = model.current {
                VStack(alignment: .leading, spacing: 10) {
                    preview(n)
                    importance(n)
                    actions(n)
                    keyHints
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
            }
        }
    }

    private func preview(_ n: AppleNoteSummary) -> some View {
        let d = model.decision(n.id)
        let body = model.body(of: n)
        let dim = d?.kind == .skipped || d?.kind == .never
        return card {
            if let s = stamp(d) { s }
            HStack(spacing: 6) {
                chip(n.created == nil ? MemoDate.unknownLabel : "created " + dateText(n.created), n.created == nil ? .warn : .plain)
                chip("Apple Note", .plain)
                ForEach(AppleNotesTags.map(body?.tags ?? [], library: model.libraryTags()), id: \.self) { chip("#\($0)", .accent) }
            }
            Text(n.title).font(.system(size: 18, weight: .bold))
            ForEach(Array(previewLines(body, title: n.title).enumerated()), id: \.offset) { _, l in
                Text(l).font(.system(size: 14.5)).fixedSize(horizontal: false, vertical: true)
            }
            if let m = body?.media, !m.isEmpty {
                HStack(spacing: 6) { ForEach(Array(mediaChips(m).enumerated()), id: \.offset) { chip($0.element.0, $0.element.1) } }
            }
            if body != nil, !(body?.tags.isEmpty ?? true) { Text("Notes tags become Skrift tags.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary) }
        }
        .opacity(dim ? 0.55 : 1)
    }

    private func previewLines(_ body: NotesBodyDecoder.Decoded?, title: String) -> [String] {
        guard let body else { return ["This note's text could not be read."] }
        var lines = body.markdown.components(separatedBy: "\n").filter { !$0.isEmpty }
        if lines.first == "# " + title || lines.first?.hasPrefix("# ") == true { lines.removeFirst() }
        let shown = Array(lines.prefix(9))
        return lines.count > 9 ? shown + ["…"] : shown
    }

    private func mediaChips(_ m: NotesBodyDecoder.Media) -> [(String, ChipStyle)] {
        var out: [(String, ChipStyle)] = []
        func add(_ n: Int, _ one: String, _ many: String) { if n > 0 { out.append(("\(n) \(n == 1 ? one : many) · not imported yet", .warn)) } }
        add(m.pictures, "picture", "pictures"); add(m.drawings, "drawing", "drawings"); add(m.scans, "scan", "scans")
        add(m.tables, "table", "tables"); add(m.pdfs, "PDF", "PDFs"); add(m.audio, "audio file", "audio files"); add(m.video, "video", "videos")
        if m.checklistItems > 0 { out.append(("checklist · \(m.checklistDone) of \(m.checklistItems) ticked", .plain)) }
        return out
    }

    private func stamp(_ d: TriageDecision?) -> AnyView? {
        guard let d else { return nil }
        let (text, fg, bg): (String, Color, Color)
        if d.skriftID != nil { (text, fg, bg) = ("IN SKRIFT", Theme.green, Theme.green.opacity(0.12)) }
        else {
            switch d.kind {
            case .rated: (text, fg, bg) = ("RATED · IMPORTS ON NEXT 10", Theme.accentText, Theme.accent.opacity(0.13))
            case .skipped: (text, fg, bg) = ("SKIPPED · BACK NEXT SESSION", Theme.textSecondary, Theme.chip)
            case .never: (text, fg, bg) = ("NEVER IMPORT · STAYS IN NOTES", Theme.destructive, Theme.destructive.opacity(0.10))
            }
        }
        return AnyView(Text(text).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(0.44)
            .foregroundStyle(fg).padding(.horizontal, 8).padding(.vertical, 3)
            .background(bg, in: RoundedRectangle(cornerRadius: 6)))
    }

    private func importance(_ n: AppleNoteSummary) -> some View {
        let d = model.decision(n.id)
        let lit = d?.kind == .rated ? (d?.rating ?? 0) : 0
        let dim = d?.kind == .skipped || d?.kind == .never
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Importance").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textMuted).padding(.trailing, 0)
                HStack(spacing: 0) {
                    ForEach(1...3, id: \.self) { k in
                        Button { model.rate(k) } label: {
                            Circle().strokeBorder(k <= lit ? Theme.accent : Theme.textMuted, lineWidth: 1.5)
                                .background(Circle().fill(k <= lit ? Theme.accent : .clear))
                                .frame(width: 10, height: 10).frame(width: 20, height: 20).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Importance \(ThreeBallScale.name(forStep: k))")
                        .accessibilityIdentifier("applenotes.ball.\(k)")
                    }
                }
                Spacer()
                Text(lit > 0 ? ThreeBallScale.name(forStep: lit) : "Not rated")
                    .font(.system(size: 11.5, weight: lit > 0 ? .semibold : .medium))
                    .foregroundStyle(lit > 0 ? Theme.accentText : Theme.textMuted)
            }
            Rectangle().fill(Theme.hairline.opacity(0.09)).frame(height: 0.5).padding(.top, 11).padding(.bottom, 9)
            HStack(spacing: 5) {
                Circle().fill(lit > 0 ? Theme.green : Theme.textMuted).frame(width: 5, height: 5)
                Text(lit > 0 ? "Rated · imports into Skrift" : "Tap a ball to import it and rate it")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 13).padding(.top, 13).padding(.bottom, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline.opacity(0.09), lineWidth: 1))
        .opacity(dim ? 0.5 : 1)
    }

    private func actions(_ n: AppleNoteSummary) -> some View {
        let d = model.decision(n.id)
        return HStack(spacing: 8) {
            actButton("Skip for now", "back next session", on: d?.kind == .skipped, red: false) { model.skip() }
            actButton("Never import", "remembered by Notes ID", on: d?.kind == .never, red: true) { model.never() }
        }
    }

    private func actButton(_ title: String, _ small: String, on: Bool, red: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(small).font(.system(size: 10.5, weight: .medium)).opacity(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .foregroundStyle(on ? (red ? Color.white : Theme.bg) : (red ? Theme.destructive : Theme.textPrimary))
            .background(on ? (red ? Theme.destructive : Theme.textPrimary) : Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? .clear : Theme.hairline.opacity(0.09), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(red ? "applenotes.never" : "applenotes.skip")
    }

    private var keyHints: some View {
        HStack(spacing: 10) {
            ForEach(["1 2 3|rate", "S|skip", "⌫|never import", "↑ ↓|move", "⏎|Next 10"], id: \.self) { s in
                let p = s.components(separatedBy: "|")
                HStack(spacing: 4) {
                    Text(p[0]).font(.system(size: 10.5, design: .monospaced)).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 4))
                    Text(p[1])
                }
            }
        }
        .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
    }

    // MARK: - report

    private func report(end: Bool) -> some View {
        let c = model.counts
        let never = model.decided(.never)
        let inSkrift = model.decided(.rated, imported: true)
        let unmapped = model.unmapped.values.reduce(NotesBodyDecoder.Media()) { a, m in
            var r = a
            r.pictures += m.pictures; r.drawings += m.drawings; r.scans += m.scans; r.tables += m.tables
            r.pdfs += m.pdfs; r.audio += m.audio; r.video += m.video; return r
        }
        let undated = inSkrift.filter { $0.decision.created == nil }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 18) {
                if end {
                    bigNum(c.inSkrift, "in Skrift"); bigNum(c.never + c.skipped, "left out", dim: true)
                    bigNum(undated + unmapped.pictures + unmapped.drawings + unmapped.scans + unmapped.tables + unmapped.pdfs + unmapped.audio + unmapped.video, "need a look", amber: true)
                } else {
                    bigNum(inSkrift.count, "in Skrift in total"); bigNum(c.left, "still to decide", dim: true)
                }
            }
            if end {
                card {
                    HStack(spacing: 6) {
                        chip("Important \(c.byRating[3] ?? 0)", .accent); chip("Useful \(c.byRating[2] ?? 0)", .accent); chip("Passing \(c.byRating[1] ?? 0)", .accent)
                    }
                    hint("The Mac polishes these and exports them to Obsidian.")
                }
            }
            section("Now in Skrift")
            listCard(key: "del", title: "Safe to delete in Apple Notes", count: inSkrift.count, countColor: Theme.green,
                     why: "Everything here is in Skrift. Skrift reads Notes, so each one drops off this list once you delete it there.",
                     rows: inSkrift)
            section("Left in Apple Notes")
            VStack(spacing: 0) {
                listCard(key: "nev", title: "Never import", count: never.count, countColor: Theme.textSecondary,
                         why: "Still in Apple Notes; Skrift will not offer them again. Recognised by their Notes ID, even after edits. Delete them there if you do not need them.",
                         rows: never, flat: true)
                Divider().overlay(Theme.hairline.opacity(0.09))
                repRow("Skipped for now", c.skipped, Theme.textSecondary, "Not imported. They come back in your next session.")
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline.opacity(0.09), lineWidth: 1))
            if end {
                section("What did not map")
                VStack(spacing: 0) {
                    let rows: [(String, Int, String)] = [
                        ("Date unknown", undated, "Notes had no creation date. Shown as “Date unknown”, sorted last."),
                        ("Pictures", unmapped.pictures, "Not copied into Skrift yet. They stay in Apple Notes."),
                        ("Drawings", unmapped.drawings, "Not copied into Skrift yet. They stay in Apple Notes."),
                        ("Scanned documents", unmapped.scans, "Not copied into Skrift yet. They stay in Apple Notes."),
                        ("Tables", unmapped.tables, "Not imported yet. The rest of the note is."),
                        ("PDFs, audio, video", unmapped.pdfs + unmapped.audio + unmapped.video, "Not copied into Skrift yet. They stay in Apple Notes.")
                    ].filter { $0.1 > 0 }
                    if rows.isEmpty { repRow("Nothing", 0, Theme.textSecondary, nil) }
                    ForEach(Array(rows.enumerated()), id: \.offset) { k, r in
                        if k > 0 { Divider().overlay(Theme.hairline.opacity(0.09)) }
                        repRow(r.0, r.1, Theme.amber, r.2)
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline.opacity(0.09), lineWidth: 1))
            }
            hint("Skrift can't delete anything in Apple Notes. Deleting there is up to you.")
        }
    }

    private func listCard(key: String, title: String, count: Int, countColor: Color, why: String,
                          rows: [(id: String, decision: TriageDecision)], flat: Bool = false) -> some View {
        let open = openList.contains(key)
        let cap = open ? 40 : 5
        let content = VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 14.5, weight: .bold)); Spacer()
                Text("\(count)").font(.system(size: 14, weight: .semibold)).foregroundStyle(countColor).monospacedDigit()
            }
            Text(why).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.prefix(cap).enumerated()), id: \.offset) { _, r in
                        HStack(spacing: 4) {
                            Text("· " + r.decision.title).lineLimit(1)
                            Text("(\(dateText(r.decision.created)))").foregroundStyle(Theme.textSecondary)
                        }
                        .font(.system(size: 12.5)).padding(.vertical, 1)
                    }
                }.padding(.top, 4)
                if rows.count > 5 {
                    Text(open ? "Show fewer" : "Show \(min(40, rows.count)) of \(rows.count)")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.accentText)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if open { openList.remove(key) } else { openList.insert(key) } }
        return Group {
            if flat { content } else {
                content.background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline.opacity(0.09), lineWidth: 1))
            }
        }
    }

    private func repRow(_ title: String, _ count: Int, _ color: Color, _ why: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.system(size: 14.5, weight: .bold)); Spacer()
                if count > 0 || why != nil { Text("\(count)").font(.system(size: 14, weight: .semibold)).foregroundStyle(color).monospacedDigit() } }
            if let why { Text(why).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.horizontal, 12).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bigNum(_ n: Int, _ label: String, dim: Bool = false, amber: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(n)").font(.system(size: 36, weight: .bold)).monospacedDigit()
                .foregroundStyle(amber ? Theme.amber : (dim ? Theme.textSecondary : Theme.textPrimary))
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func section(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(0.6)
            .foregroundStyle(Theme.textSecondary).padding(.horizontal, 2).padding(.top, 4)
    }

    // MARK: - footer

    private var footer: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .triage:
                Text(model.openCount > 0 ? "Next 10 unlocks when all ten are decided."
                                         : "All ten decided. Next 10 imports the \(model.ratedPending) rated.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).monospacedDigit()
                Spacer()
                ghost("Finish later") { model.finishLater() }
                ghost("Import what I've decided so far") { Task { await model.importSoFar() } }
                nextButton
            case .start:
                ghost("What can I delete in Apple Notes?") { model.phase = .report(end: false) }
                Spacer()
                ghost("Close", onClose)
                primary("Continue · note \(model.firstOpenNumber) of \(model.counts.total)") { model.resume() }
            case .report(let end):
                Spacer()
                if end { primary("Show imported notes") { onClose() } }
                else {
                    ghost("Done for today") { model.finishLater() }
                    primary("Continue · note \(model.firstOpenNumber) of \(model.counts.total)") { model.resume() }
                }
            case .loading, .denied, .failed:
                Spacer(); ghost("Close", onClose)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var nextButton: some View {
        let locked = model.openCount > 0
        let label = model.isLastBatch ? "Finish" : "Next 10"
        return Button { Task { await model.nextTen() } } label: {
            HStack(spacing: 6) {
                if locked { Image(systemName: "lock.fill").font(.system(size: 11)) }
                Text(label).font(.system(size: 13, weight: .semibold))
                if locked { Text("· \(model.openCount) left to decide").font(.system(size: 12, weight: .medium)).opacity(0.9) }
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .foregroundStyle(locked ? Theme.textSecondary : .white)
            .background(locked ? Theme.chip : Theme.accent, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("applenotes.next")
    }

    private func primary(_ t: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }

    private func ghost(_ t: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(t).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent) }.buttonStyle(.plain)
    }

    // MARK: - pieces

    private enum ChipStyle { case plain, accent, warn }

    private func chip(_ t: String, _ s: ChipStyle) -> some View {
        Text(t).font(.system(size: 12)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(s == .accent ? Theme.accentText : s == .warn ? Theme.amber : Theme.textSecondary)
            .background(s == .accent ? Theme.accent.opacity(0.13) : s == .warn ? Theme.amber.opacity(0.13) : Theme.chip,
                        in: RoundedRectangle(cornerRadius: 8))
    }

    private func hint(_ t: String) -> some View {
        Text(t).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { c() }
            .padding(.horizontal, 13).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline.opacity(0.09), lineWidth: 1))
    }

    @ViewBuilder private var toast: some View {
        if let t = model.toast {
            Text(t).font(.system(size: 13)).foregroundStyle(Theme.bg)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 64).allowsHitTesting(false)
                .task(id: t) { try? await Task.sleep(for: .seconds(2.6)); if model.toast == t { model.toast = nil } }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard model.phase == .triage else { return .ignored }
        switch press.key {
        case .upArrow: model.select(max(0, model.cursor - 1)); return .handled
        case .downArrow: model.select(min(model.batchIDs.count - 1, model.cursor + 1)); return .handled
        case .delete, .deleteForward: model.never(); return .handled
        case .return: Task { await model.nextTen() }; return .handled
        default: break
        }
        switch press.characters {
        case "1", "2", "3": model.rate(Int(press.characters) ?? 1); return .handled
        case "s", "S": model.skip(); return .handled
        default: return .ignored
        }
    }

    private var readAgo: String { "just now" }

    private func dateText(_ d: Date?) -> String {
        guard let d else { return MemoDate.unknownLabel.lowercased() }
        return d.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func dayText(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return f.string(from: d) + (Calendar.current.isDateInToday(d) ? ", today" : "")
    }
}
