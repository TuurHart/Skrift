import SwiftUI

/// Per-app look for the shared tag row (C240 — one view, no `#if os()` inside it;
/// each app supplies its OWN style struct). Built to the signed mock
/// `mocks/tag-ui-revamp.html` (Q28/C241/D139): own row under the title, an inline
/// field (no sheet), and two remove idioms — phone/iPad tap-arms-then-removes,
/// Mac reveals `✕` on hover.
struct TagRowStyle {
    var chipFont: Font
    var chipHeight: CGFloat
    var chipHPad: CGFloat
    var fieldWidth: CGFloat
    /// Phone/iPad: tap arms (red + ✕), a second tap removes (D139 pick 2). Mac: a
    /// hover reveals `✕`, one click removes — no arming needed, the pointer already
    /// gives the "are you sure" beat a touch doesn't have.
    var armsOnTap: Bool
    var textColor: Color
    var backgroundColor: Color
    var dimTextColor: Color
    var elevColor: Color
    var borderColor: Color
    var dangerColor: Color
    var fieldBackground: Color
    var fieldBorder: Color
    /// Mac only (D139 signed mock `tag-ui-revamp.html`): a keyboard-navigable dropdown
    /// menu under the field (↑↓ select, Tab jumps to the top match, Return accepts the
    /// selection, a leading "Create #x" row when the typed text is new) instead of the
    /// phone/iPad's horizontal tap-to-pick strip — the Mac already has arrow keys and a
    /// pointer, so a browsable list is the native idiom there.
    var usesDropdownMenu: Bool = false
}

/// ONE shared tag editor: chips + an inline "+ tag" control that turns into a text
/// field in place (no sheet — D139 pick 1). Split/refuse/fold are `TagRules`
/// (single-sourced C93); this view only owns layout, focus and the remove gesture.
struct TagEditorRow: View {
    @Binding var tags: [String]
    /// Every live tag across the library (vault + notes), most-used first — the
    /// fold source (D139) and the typeahead source.
    let library: [String]
    let style: TagRowStyle
    /// Called after any change (add/remove/undo) so the caller can save + mirror.
    var onChanged: () -> Void = {}
    /// Appended to the `add-tag-button` accessibility identifier — the phone pager
    /// keeps an off-screen neighbour page mounted (accessibility-hiding doesn't
    /// cross the UIKit hosting boundary), so two copies of this view can coexist
    /// and XCUITest/VoiceOver need to resolve exactly one.
    var idSuffix: String = ""
    /// Snapshot/preview seed — opens the field with a draft so the suggestion strip
    /// renders (headless `-snapshot-tags`, no real keyboard/typing available there).
    var seedAdding = false
    var seedDraft = ""

    @State private var editing = false
    @State private var draft = ""
    @State private var armed: String?
    @State private var removed: (tag: String, index: Int, id: UUID)?
    @State private var refusalHint: String?
    /// Mac dropdown only: which row (`menuRows`) the arrow keys have highlighted.
    /// `-1` = nothing selected, so Return falls through to `commitDraft()`.
    @State private var selectedIndex = -1
    @FocusState private var fieldFocused: Bool

    private var typed: String { draft.trimmingCharacters(in: .whitespaces) }

    private var matches: [String] {
        let t = typed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !t.isEmpty else { return [] }
        var have = Set(tags.map { $0.lowercased() })
        var seen = Set<String>()
        var out: [String] = []
        for cand in library {
            let lc = cand.lowercased()
            guard !have.contains(lc), !seen.contains(lc), lc.hasPrefix(t) else { continue }
            seen.insert(lc); have.insert(lc)
            out.append(cand)
            if out.count >= 8 { break }
        }
        return out
    }

    /// The Mac menu's leading "Create #x" row, D139/mock `createable`: the typed text
    /// parses to exactly one clean tag (no refusal) that doesn't already exist on this
    /// note or anywhere in `library` (case-folded) — a second spelling of an existing
    /// tag offers to PICK it, not create a duplicate.
    private var creatableTag: String? {
        let split = TagRules.split(typed)
        guard split.accepted.count == 1, split.refused.isEmpty else { return nil }
        let candidate = split.accepted[0]
        let key = candidate.lowercased()
        guard !(tags + library).contains(where: { $0.lowercased() == key }) else { return nil }
        return candidate
    }

    private struct MenuRow { let tag: String; let isCreate: Bool }
    /// Mac dropdown rows: the Create row (if any) leads, then the prefix matches.
    private var menuRows: [MenuRow] {
        var rows: [MenuRow] = []
        if let c = creatableTag { rows.append(MenuRow(tag: c, isCreate: true)) }
        rows += matches.map { MenuRow(tag: $0, isCreate: false) }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(tags, id: \.self) { chip($0) }
                addControl
            }
            if editing, style.usesDropdownMenu, !menuRows.isEmpty {
                macMenu
            } else if editing, !style.usesDropdownMenu, !matches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(matches, id: \.self) { m in
                            Button { commit([m]); draft = ""; fieldFocused = true } label: {
                                Text("#\(m)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(style.textColor)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(style.fieldBackground, in: .capsule)
                                    .overlay(Capsule().strokeBorder(style.fieldBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let refusalHint {
                Text(refusalHint).font(.system(size: 11.5)).foregroundStyle(style.dangerColor)
            }
        }
        .onAppear { if seedAdding { editing = true; draft = seedDraft } }
        // Undo — a FLOATING toast (D139 mock: "every removal offers Undo for 4 s"),
        // not an inline row that permanently reflows the layout underneath it.
        .overlay(alignment: .bottom) { undoToastView }
    }

    /// The Mac's keyboard-navigable suggestion menu (D139 signed mock
    /// `tag-ui-revamp.html`): ↑↓ move the highlight, Tab jumps the field to the top
    /// match, Return accepts the highlighted row, a "Create #x" row leads when the
    /// typed text is new. Replaces the phone/iPad horizontal tap strip on the Mac,
    /// which has a keyboard and a pointer instead of a thumb.
    @ViewBuilder private var macMenu: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(menuRows.enumerated()), id: \.offset) { i, row in
                Button {
                    commit([row.tag]); draft = ""; selectedIndex = -1; fieldFocused = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: row.isCreate ? "plus" : "number")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 12)
                        Text(row.isCreate ? "Create #\(row.tag)" : "#\(row.tag)")
                            .font(.system(size: 12, weight: row.isCreate ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                    }
                    .foregroundStyle(row.isCreate ? style.textColor : style.dimTextColor)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(i == selectedIndex ? style.backgroundColor : .clear,
                                in: .rect(cornerRadius: 6))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tag-menu-row-\(row.tag)")
            }
            Text("↩ add · , add next · ⇥ top match · esc close")
                .font(.system(size: 10.5)).foregroundStyle(style.dimTextColor)
                .padding(.horizontal, 9).padding(.top, 3)
        }
        .padding(.vertical, 4)
        .frame(width: 250, alignment: .leading)
        .background(style.elevColor, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(style.fieldBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .accessibilityIdentifier("tag-menu")
    }

    @ViewBuilder private var undoToastView: some View {
        if let removed {
            HStack(spacing: 12) {
                Text("Removed #\(removed.tag)")
                    .font(.system(size: 13)).foregroundStyle(Color.white)
                Button("Undo") { undoRemove() }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(style.textColor, in: .capsule)
            }
            .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
            .background(Color.black.opacity(0.85), in: .capsule)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            // The overlay is proposed the ROW's current width, which can be narrower
            // than the tag row was a moment ago (a chip just left) — `.fixedSize()`
            // keeps the pill at its own ideal width instead of being squeezed and
            // truncated ("Remov…" / "U…", caught in the Q36 screenshot pass).
            .fixedSize()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityIdentifier("tag-undo-toast")
            .task(id: removed.id) {
                try? await Task.sleep(for: .seconds(4))
                if self.removed?.id == removed.id {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { self.removed = nil }
                }
            }
        }
    }

    @ViewBuilder private func chip(_ tag: String) -> some View {
        TagChipView(tag: tag, isArmed: style.armsOnTap && armed == tag, style: style,
                    onTap: {
                        guard style.armsOnTap else { return }
                        if armed == tag { removeTag(tag) } else { armed = tag }
                    },
                    onRemove: { removeTag(tag) })
    }

    @ViewBuilder private var addControl: some View {
        if editing {
            TextField("tag", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(style.textColor)
                .frame(width: style.fieldWidth)
                .padding(.horizontal, 10).frame(height: style.chipHeight - 6)
                .background(style.fieldBackground, in: .capsule)
                .overlay(Capsule().strokeBorder(style.fieldBorder, lineWidth: 1))
                .focused($fieldFocused)
                .accessibilityIdentifier("tag-input" + idSuffix)
                .onSubmit {
                    if typed.isEmpty { editing = false } else { commitDraft(); fieldFocused = true }
                }
                .onChange(of: draft) { _, v in
                    selectedIndex = -1
                    // Comma/Return-in-the-middle commits everything BEFORE the last
                    // separator and keeps typing the rest — you never lose the field
                    // (mock: "Return and comma both add and keep the field open").
                    guard let lastSep = v.lastIndex(where: { $0 == "," || $0 == "\n" }) else { return }
                    let head = String(v[..<lastSep])
                    let tail = String(v[v.index(after: lastSep)...]).trimmingCharacters(in: .whitespaces)
                    draft = tail
                    commitDraft(text: head)
                    fieldFocused = true
                }
                // Mac only (D139 mock): ↑↓ walk the menu, Tab jumps to the top match,
                // Return accepts a highlighted row, Esc closes. Unhandled keys (.ignored)
                // fall through to the field's normal typing / `onSubmit`.
                .onKeyPress(.upArrow) {
                    guard style.usesDropdownMenu, !menuRows.isEmpty else { return .ignored }
                    selectedIndex = max(-1, selectedIndex - 1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard style.usesDropdownMenu, !menuRows.isEmpty else { return .ignored }
                    selectedIndex = min(menuRows.count - 1, selectedIndex + 1)
                    return .handled
                }
                .onKeyPress(.tab) {
                    guard style.usesDropdownMenu, let top = menuRows.first(where: { !$0.isCreate }) else { return .ignored }
                    draft = top.tag
                    return .handled
                }
                .onKeyPress(.return) {
                    guard style.usesDropdownMenu, selectedIndex >= 0, selectedIndex < menuRows.count else { return .ignored }
                    commit([menuRows[selectedIndex].tag]); draft = ""; selectedIndex = -1; fieldFocused = true
                    return .handled
                }
                .onKeyPress(.escape) {
                    draft = ""; editing = false; selectedIndex = -1
                    return .handled
                }
        } else {
            Button {
                editing = true
                armed = nil
                fieldFocused = true
            } label: {
                Text("+ tag").font(.system(size: 12))
                    .foregroundStyle(style.dimTextColor)
                    .padding(.horizontal, style.chipHPad).frame(height: style.chipHeight)
                    .overlay(Capsule().strokeBorder(style.borderColor, lineWidth: 1, antialiased: true))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("add-tag-button" + idSuffix)
        }
    }

    /// Commits `text` (defaults to the live draft, which this then clears). Called
    /// both on Return/Done and mid-typing when a comma/newline separator lands.
    private func commitDraft(text: String? = nil) {
        let raw = text ?? draft
        if text == nil { draft = "" }
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let split = TagRules.split(raw)
        if !split.refused.isEmpty {
            refusalHint = "Skipped \u{201C}\(split.refused[0])\u{201D} — no letter or digit."
        } else {
            refusalHint = nil
        }
        commit(split.accepted)
    }

    private func commit(_ accepted: [String]) {
        guard !accepted.isEmpty else { return }
        let result = TagRules.fold(accepted, existing: tags, library: library)
        if !result.toAdd.isEmpty {
            tags.append(contentsOf: result.toAdd)
            onChanged()
        }
        removed = nil
    }

    private func removeTag(_ tag: String) {
        guard let i = tags.firstIndex(of: tag) else { return }
        tags.remove(at: i)
        armed = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            removed = (tag, i, UUID())
        }
        onChanged()
        // Auto-dismiss lives on the toast's own `.task(id:)` (undoToastView) — a single
        // owner, so a second removal of the same tag within the 4 s window gets its OWN
        // id and can't be clobbered by the first removal's timer.
    }

    private func undoRemove() {
        guard let removed else { return }
        let idx = min(removed.index, tags.count)
        tags.insert(removed.tag, at: idx)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { self.removed = nil }
        onChanged()
    }
}

/// One tag chip. Its own view (not a function) so hover state — the Mac's `✕` reveal
/// (D139) — is per-chip, not shared across the row.
private struct TagChipView: View {
    let tag: String
    let isArmed: Bool
    let style: TagRowStyle
    let onTap: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    /// Phone/iPad (`armsOnTap`): the `✕` only shows once armed. Mac: hover reveals
    /// it — "always visible at half opacity" is explicitly gone (mock "Gone from
    /// today").
    private var showX: Bool { isArmed || (!style.armsOnTap && hovering) }

    var body: some View {
        HStack(spacing: 6) {
            Text("#\(tag)").font(style.chipFont)
            if showX {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: style.armsOnTap ? 10 : 9, weight: .bold))
                        .opacity(isArmed ? 1 : 0.6)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(isArmed ? style.dangerColor : style.textColor)
        .padding(.horizontal, style.chipHPad).frame(height: style.chipHeight)
        .background(isArmed ? Color.clear : style.backgroundColor, in: .capsule)
        .overlay(Capsule().strokeBorder(isArmed ? style.dangerColor : .clear, lineWidth: 1.5))
        .contentShape(.capsule)
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
        .accessibilityIdentifier("tag-chip-\(tag)")
        .accessibilityLabel(isArmed ? "Remove tag \(tag)" : "Tag \(tag)")
    }
}
