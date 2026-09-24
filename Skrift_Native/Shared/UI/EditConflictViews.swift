import SwiftUI
import SwiftData

/// The edit-conflict prompt, banner and note gate — built to the signed mock
/// `SkriftDesktop/mocks/Q4-edit-conflict.html` (D139). ONE view for both apps; the phone
/// draws it as a bottom sheet with big stacked buttons, the Mac as a window sheet with a
/// default (Return) button. Colors come from each app's `NoteCardStyle`.
enum EditConflictLook { case phone, mac }

private func deviceGlyph(_ kind: String) -> String {
    switch kind {
    case "Mac": return "desktopcomputer"
    case "iPad": return "ipad"
    default: return "iphone"
    }
}

/// "this iPhone" / "the Mac" — Skrift stores no device names (Q4 finding).
private func thisName(_ kind: String) -> String { "this \(kind.isEmpty ? "device" : kind)" }
private func otherName(_ kind: String) -> String { "the \(kind.isEmpty ? "other device" : kind)" }

struct EditConflictPrompt: View {
    let conflict: EditConflict
    let look: EditConflictLook
    let style: NoteCardStyle
    let onPick: (EditConflicts.Choice) -> Void
    let onLater: () -> Void

    private var here: NoteWords { conflict.local }
    private var there: NoteWords { conflict.other }
    private var hereKind: String { here.deviceKind.isEmpty ? EditConflicts.thisDeviceKind : here.deviceKind }

    var body: some View {
        switch look {
        case .phone: phoneBody
        case .mac: macBody
        }
    }

    // MARK: phone

    private var phoneBody: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Later", action: onLater)
                    .foregroundStyle(style.accent)
                    .accessibilityIdentifier("conflict-later")
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14)
            ScrollView {
                VStack(spacing: 12) {
                    header(centered: true)
                    versionCard(here, isHere: true)
                    versionCard(there, isHere: false)
                    sameLine
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
            }
            Divider()
            VStack(spacing: 7) {
                phoneButton("Keep both", sub: "two notes, nothing is lost", primary: true) { onPick(.keepBoth) }
                    .accessibilityIdentifier("conflict-keep-both")
                phoneButton("Keep \(thisName(hereKind))'s",
                            sub: "\(otherName(there.deviceKind))'s goes to Recently Deleted for 14 days") { onPick(.keepThis) }
                    .accessibilityIdentifier("conflict-keep-this")
                phoneButton("Keep \(otherName(there.deviceKind))'s",
                            sub: "\(thisName(hereKind))'s goes to Recently Deleted for 14 days") { onPick(.keepOther) }
                    .accessibilityIdentifier("conflict-keep-other")
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 20)
        }
    }

    private func phoneButton(_ title: String, sub: String, primary: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(sub).font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(primary ? Color.white.opacity(0.82) : style.textDim)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(primary ? Color.white : style.accent)
            .background(primary ? style.accent : style.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(primary ? style.accent : style.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: mac

    private var macBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(centered: false)
            versionCard(here, isHere: true)
            versionCard(there, isHere: false)
            sameLine
            VStack(spacing: 6) {
                Button { onPick(.keepBoth) } label: { Text("Keep Both").frame(maxWidth: .infinity) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("conflict-keep-both")
                Button { onPick(.keepThis) } label: { Text("Keep \(thisName(hereKind).capitalizedFirst)'s").frame(maxWidth: .infinity) }
                    .accessibilityIdentifier("conflict-keep-this")
                Button { onPick(.keepOther) } label: { Text("Keep \(otherName(there.deviceKind))'s").frame(maxWidth: .infinity) }
                    .accessibilityIdentifier("conflict-keep-other")
                Button("Later", action: onLater)
                    .buttonStyle(.plain)
                    .foregroundStyle(style.textDim)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("conflict-later")
            }
            .controlSize(.large)
        }
        .padding(16)
        .frame(width: 380)
    }

    // MARK: shared pieces

    @ViewBuilder private func header(centered: Bool) -> some View {
        let glyph = Image(systemName: "arrow.triangle.branch")
            .font(.system(size: centered ? 20 : 16, weight: .semibold))
            .foregroundStyle(style.amber)
            .frame(width: centered ? 44 : 36, height: centered ? 44 : 36)
            .background(style.amber.opacity(0.14), in: Circle())
        let title = Text("This note was changed on two devices")
            .font(.system(size: centered ? 19 : 14, weight: .bold))
        let sub = Text("\(thisName(hereKind).capitalizedFirst) and \(otherName(there.deviceKind)) both edited it before they synced. Keep one, or keep both as two notes.")
            .font(.system(size: centered ? 13.5 : 12))
            .foregroundStyle(style.textDim)
        if centered {
            VStack(spacing: 4) { glyph; title.multilineTextAlignment(.center); sub.multilineTextAlignment(.center) }
                .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .top, spacing: 12) { glyph; VStack(alignment: .leading, spacing: 2) { title; sub } }
        }
    }

    private func versionCard(_ v: NoteWords, isHere: Bool) -> some View {
        let kind = isHere ? hereKind : v.deviceKind
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: deviceGlyph(kind))
                    .font(.system(size: 12)).foregroundStyle(style.textDim)
                    .frame(width: 22, height: 22)
                    .background(style.chipFill, in: RoundedRectangle(cornerRadius: 6))
                Text(isHere ? thisName(kind).capitalizedFirst : otherName(kind).capitalizedFirst)
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(style.text)
                Spacer(minLength: 4)
                Text("edited \(MemoDate.label(v.editedAt))")
                    .font(.system(size: 12)).foregroundStyle(style.textDim)
            }
            if let t = v.title, !t.isEmpty, t != (isHere ? there.title : here.title) {
                Text(t).font(.system(size: 14, weight: .semibold)).foregroundStyle(style.text)
            }
            Text(v.body?.isEmpty == false ? v.body! : "No words")
                .font(.system(size: look == .phone ? 14 : 12.5))
                .foregroundStyle(style.text)
                .lineLimit(look == .phone ? 8 : 5)
                .fixedSize(horizontal: false, vertical: true)
            if !v.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(v.tags, id: \.self) { tag in
                        Text("#\(tag)").font(.system(size: 11)).foregroundStyle(style.accentText)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(style.accentSoft, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
        .padding(look == .phone ? 12 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.surface, in: RoundedRectangle(cornerRadius: look == .phone ? 12 : 8))
        .overlay(RoundedRectangle(cornerRadius: look == .phone ? 12 : 8).stroke(style.border, lineWidth: 1))
    }

    private var sameLine: some View {
        var same: [String] = []
        if here.title == there.title { same.append("the title") }
        if here.tags == there.tags { same.append("the tags") }
        same.append(contentsOf: ["the recording", "the photos", "the rating"])
        return Text("Same in both: \(same.joined(separator: ", ")).")
            .font(.system(size: 12)).foregroundStyle(style.textFaint)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }
}

/// The amber banner a note carries after "Later": read-only until he picks.
struct EditConflictBanner: View {
    let conflict: EditConflict
    let style: NoteCardStyle
    let onChoose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(style.amber)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Two versions of this note").font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(style.text)
                Text("Edited on \(thisName(conflict.local.deviceKind.isEmpty ? EditConflicts.thisDeviceKind : conflict.local.deviceKind)) and \(otherName(conflict.other.deviceKind)) before they synced. Pick one to edit again.")
                    .font(.system(size: 12)).foregroundStyle(style.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button("Choose", action: onChoose)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(style.amber)
                .buttonStyle(.plain)
                .accessibilityIdentifier("conflict-choose")
        }
        .padding(12)
        .background(style.amber.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(style.amber.opacity(0.45), lineWidth: 1))
        .accessibilityIdentifier("conflict-banner")
    }
}

/// The note gate: on open, a note with two versions shows the prompt; "Later" leaves the
/// banner; the body is read-only until he picks (editing now would make a third version).
struct EditConflictGate: ViewModifier {
    let memoID: UUID?
    let context: ModelContext?
    let look: EditConflictLook
    let style: NoteCardStyle
    var onResolved: (Memo, Memo) -> Void = { _, _ in }

    @State private var conflict: EditConflict?
    @State private var showPrompt = false
    @State private var promptedFor: UUID?

    private var watched: Bool { memoID.map { EditConflictWatch.shared.ids.contains($0) } ?? false }

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if let conflict {
                EditConflictBanner(conflict: conflict, style: style) { showPrompt = true }
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }
            content.disabled(conflict != nil)
        }
        .onChange(of: "\(memoID?.uuidString ?? "")|\(watched)", initial: true) { _, _ in load() }
        .sheet(isPresented: $showPrompt) {
            if let conflict {
                EditConflictPrompt(conflict: conflict, look: look, style: style,
                                   onPick: { pick($0) }, onLater: { showPrompt = false })
                    .interactiveDismissDisabled(false)
            }
        }
    }

    private func load() {
        guard let memoID, let context,
              let memo = try? context.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == memoID })).first
        else { conflict = nil; return }
        conflict = EditConflicts.conflict(for: memo, in: context)
        // The prompt opens by itself ONCE per open of a conflicted note (D139).
        if conflict != nil, promptedFor != memoID { promptedFor = memoID; showPrompt = true }
        if conflict == nil { showPrompt = false }
    }

    private func pick(_ choice: EditConflicts.Choice) {
        guard let conflict, let memoID, let context,
              let memo = try? context.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == memoID })).first
        else { return }
        if let copy = try? EditConflicts.resolve(conflict, choice: choice, memo: memo, in: context) {
            showPrompt = false
            self.conflict = nil
            EditConflictWatch.shared.refresh(in: context)
            onResolved(memo, copy)
        }
    }
}

extension View {
    func editConflictGate(memoID: UUID?, context: ModelContext?, look: EditConflictLook,
                          style: NoteCardStyle, onResolved: @escaping (Memo, Memo) -> Void = { _, _ in }) -> some View {
        modifier(EditConflictGate(memoID: memoID, context: context, look: look, style: style,
                                  onResolved: onResolved))
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
