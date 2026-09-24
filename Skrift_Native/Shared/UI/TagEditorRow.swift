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
    @State private var removed: (tag: String, index: Int)?
    @State private var refusalHint: String?
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(tags, id: \.self) { chip($0) }
                addControl
            }
            if editing, !matches.isEmpty {
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
            if let removed {
                HStack(spacing: 8) {
                    Text("Removed #\(removed.tag)")
                        .font(.system(size: 12)).foregroundStyle(style.dimTextColor)
                    Button("Undo") { undoRemove() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(style.textColor)
                }
            } else if let refusalHint {
                Text(refusalHint).font(.system(size: 11.5)).foregroundStyle(style.dangerColor)
            }
        }
        .onAppear { if seedAdding { editing = true; draft = seedDraft } }
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
                .onSubmit {
                    if typed.isEmpty { editing = false } else { commitDraft(); fieldFocused = true }
                }
                .onChange(of: draft) { _, v in
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
        removed = (tag, i)
        onChanged()
        let token = tag
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if removed?.tag == token { removed = nil }
        }
    }

    private func undoRemove() {
        guard let removed else { return }
        let idx = min(removed.index, tags.count)
        tags.insert(removed.tag, at: idx)
        self.removed = nil
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
