import SwiftUI

/// The tag CHIP editor (note-editing chunk 3 — replaces the comma alert AND the
/// tap-a-chip-silently-DELETES behaviour): current tags as chips with an explicit
/// ✕, a type-to-add field (comma still splits, kept by user request), and
/// tap-to-add suggestions autocompleted from every tag across the library —
/// "pick, not retype".
struct TagEditorSheet: View {
    @Bindable var memo: Memo
    /// Every live tag across the library, most-used first (suggestion source).
    let allTags: [String]
    var onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    /// Suggestions: library tags the memo doesn't have yet, prefix-filtered by
    /// what's being typed.
    private var suggestions: [String] {
        let typed = input.trimmingCharacters(in: .whitespaces).lowercased()
        return allTags.filter { tag in
            !memo.tags.contains(tag) && (typed.isEmpty || tag.lowercased().hasPrefix(typed))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.skBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !memo.tags.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel("ON THIS NOTE")
                                FlowLayout(spacing: 8, lineSpacing: 8) {
                                    ForEach(memo.tags, id: \.self) { tag in
                                        Button { remove(tag) } label: {
                                            HStack(spacing: 5) {
                                                Text("#\(tag)")
                                                    .font(.system(size: 13, weight: .medium))
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(Color.skAccentText.opacity(0.7))
                                            }
                                            .foregroundStyle(Color.skAccentText)
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Color.skAccentSoft, in: .capsule)
                                            .overlay(Capsule().strokeBorder(Color.skAccent.opacity(0.35), lineWidth: 1))
                                        }
                                        .accessibilityIdentifier("tag-chip-\(tag)")
                                        .accessibilityLabel("Remove tag \(tag)")
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("ADD")
                            TextField("tag, tag, tag", text: $input)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.skText)
                                .tint(.skAccent)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($inputFocused)
                                .onSubmit(addTyped)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(Color.skElev, in: .rect(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle.sk(10).stroke(
                                    inputFocused ? Color.skAccent.opacity(0.45) : Color.skBorder, lineWidth: 1))
                                .accessibilityIdentifier("tag-input")
                            Text("Separate multiple tags with commas.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.skTextFaint)
                        }

                        if !suggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel("FROM YOUR NOTES")
                                FlowLayout(spacing: 8, lineSpacing: 8) {
                                    ForEach(suggestions, id: \.self) { tag in
                                        Button { add([tag]) } label: {
                                            Text("#\(tag)")
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color.skTextDim)
                                                .padding(.horizontal, 10).padding(.vertical, 6)
                                                .background(Color.white.opacity(0.05), in: .capsule)
                                                .overlay(Capsule().strokeBorder(Color.skBorder, lineWidth: 1))
                                        }
                                        .accessibilityIdentifier("tag-suggestion-\(tag)")
                                    }
                                }
                            }
                        }
                    }
                    .padding(Theme.Space.margin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        addTyped()
                        dismiss()
                    }
                    .accessibilityIdentifier("tag-editor-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { inputFocused = true }
    }

    private func addTyped() {
        let incoming = Memo.parseTagInput(input)
        input = ""
        add(incoming)
    }

    private func add(_ incoming: [String]) {
        var added = false
        for t in incoming where !memo.tags.contains(t) {
            memo.tags.append(t)
            added = true
        }
        if added { memo.markEdited(); onChanged() }
    }

    private func remove(_ tag: String) {
        memo.tags.removeAll { $0 == tag }
        memo.markEdited()
        onChanged()
    }
}
