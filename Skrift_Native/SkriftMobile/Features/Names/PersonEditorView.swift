import SwiftUI

/// The on-device person editor — state 5 of `mocks/phone-name-linking.html`. Edits the
/// fields the name-linker actually uses: **Full name** (the canonical / `[[link]]`
/// target), **Aliases** (spoken words recognised as this person, with a live demo),
/// **Short name** (how the inline link reads — `[[Jack|Jack]]`), and **Voice** (enroll
/// status). Reached from the name-resolution sheet ("Open … person card" / "New
/// person…") and the People-in-this-note chip bar.
///
/// Writes through the shared `NamesStore` (so the edit syncs to the Mac like any names
/// change); `onSaved` hands back the final canonical so the caller can re-link the tapped
/// occurrence + re-scan the note. The phone CAN edit aliases here (departing from the old
/// "Mac owns aliases" note) because the in-place linking surface needs alias control on
/// the device — it's still the same bidirectional names DB.
struct PersonEditorView: View {
    /// Existing person's canonical (nil = creating a new person).
    let canonical: String?
    /// Prefill for a NEW person — the spoken word that was tapped.
    var prefillName: String = ""
    /// Called after a successful save with the final (normalised, bracketed) canonical.
    var onSaved: (String) -> Void = { _ in }
    /// Called after the person is deleted.
    var onDeleted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    private let store = NamesStore.shared

    @State private var fullName = ""
    @State private var short = ""
    @State private var aliases: [String] = []
    @State private var enrolled = false
    @State private var showAddAlias = false
    @State private var newAlias = ""
    @State private var loaded = false

    private var isNew: Bool { canonical == nil }
    private var trimmedName: String { fullName.trimmingCharacters(in: .whitespaces) }
    private var demoAlias: String { aliases.first ?? (prefillName.isEmpty ? trimmedName : prefillName) }
    private var displayShort: String {
        let s = short.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { return s }
        return trimmedName.split(separator: " ").first.map(String.init) ?? trimmedName
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.skBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        fullNameField
                        aliasesField
                        shortField
                        voiceField
                        if !isNew { deleteButton }
                    }
                    .padding(Theme.Space.margin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(isNew ? "New person" : "Person")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                        .accessibilityIdentifier("person-editor-done")
                }
            }
            .onAppear(perform: loadOnce)
            .alert("Add alias", isPresented: $showAddAlias) {
                TextField("spoken word", text: $newAlias)
                Button("Add", action: commitAlias)
                Button("Cancel", role: .cancel) { newAlias = "" }
            } message: {
                Text("A spoken word that should be recognised as this person.")
            }
        }
    }

    // MARK: fields

    private var fullNameField: some View {
        field(title: "Full name",
              help: "The Obsidian note title — becomes the [[link]] target.") {
            TextField("Full name", text: $fullName)
                .font(.system(size: 15))
                .foregroundStyle(Color.skText)
                .tint(.skAccent)
                .accessibilityIdentifier("person-editor-name")
        }
    }

    private var aliasesField: some View {
        field(title: "Aliases",
              help: "Spoken words that should be recognised as this person.") {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(aliases, id: \.self) { alias in
                        Button { aliases.removeAll { $0 == alias } } label: {
                            HStack(spacing: 5) {
                                Text(alias).foregroundStyle(Color.skTextDim)
                                Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(Color.skTextFaint)
                            }
                            .font(.system(size: 13))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 6, style: .continuous))
                        }
                    }
                    Button { newAlias = ""; showAddAlias = true } label: {
                        Text("＋ add")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.skAccent)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.skAccent.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    }
                    .accessibilityIdentifier("person-editor-add-alias")
                }
                if !demoAlias.isEmpty {
                    (Text("saying “\(demoAlias)” → recognised as ")
                        .foregroundStyle(Color.skTextDim)
                     + Text(displayShort.isEmpty ? demoAlias : displayShort)
                        .foregroundStyle(Color.skAccent).fontWeight(.semibold))
                        .font(.system(size: 12))
                }
            }
        }
    }

    private var shortField: some View {
        field(title: "Short name",
              help: "How the inline link reads: [[\(trimmedName.isEmpty ? "Name" : trimmedName)|\(displayShort.isEmpty ? "Name" : displayShort)]].") {
            TextField(displayShort.isEmpty ? "Short name" : displayShort, text: $short)
                .font(.system(size: 15))
                .foregroundStyle(Color.skText)
                .tint(.skAccent)
                .accessibilityIdentifier("person-editor-short")
        }
    }

    private var voiceField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Voice").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.skText)
            if enrolled {
                HStack(spacing: 7) {
                    VoiceBars()
                    Text("Voice enrolled").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.skGreen)
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "mic").font(.system(size: 13)).foregroundStyle(Color.skTextDim)
                    Text("Not enrolled — record in a memo or on your Mac")
                        .font(.system(size: 14)).foregroundStyle(Color.skTextDim)
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: deletePerson) {
            Text("Delete person")
                .font(.system(size: 15))
                .foregroundStyle(Color.skRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .accessibilityIdentifier("person-editor-delete")
        .padding(.top, 4)
    }

    /// Labelled boxed input matching the mock's `.fld`.
    private func field<Content: View>(title: String, help: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.skText)
            Text(help).font(.system(size: 12)).foregroundStyle(Color.skTextDim)
            content()
                .padding(.horizontal, 11).padding(.vertical, 9)
                .background(Color.skElev, in: .rect(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.skBorder, lineWidth: 1))
        }
    }

    // MARK: actions

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        if let canonical, let p = store.livePeople().first(where: { $0.canonical == canonical }) {
            fullName = p.displayName
            aliases = p.aliases
            short = p.short ?? ""
            enrolled = NamesDisplay.isEnrolled(p)
        } else {
            fullName = prefillName
            aliases = prefillName.isEmpty ? [] : [prefillName]
        }
    }

    private func commitAlias() {
        let a = newAlias.trimmingCharacters(in: .whitespaces)
        newAlias = ""
        guard !a.isEmpty, !aliases.contains(where: { $0.caseInsensitiveCompare(a) == .orderedSame }) else { return }
        aliases.append(a)
    }

    private func save() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        let newCanonical = NamesMerge.normaliseCanonical(name)
        // Rename: tombstone the old canonical so we don't leave a duplicate.
        if let old = canonical, NamesMerge.normaliseCanonical(old) != newCanonical {
            store.delete(canonical: old)
        }
        // A person with NO alias never links — default the alias to the name so a fresh
        // person from the tapped word is actually recognised.
        var cleanAliases = aliases.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if cleanAliases.isEmpty { cleanAliases = [name] }
        store.upsert(canonical: name, aliases: cleanAliases, short: short.trimmingCharacters(in: .whitespaces).nilIfBlank)
        onSaved(newCanonical)
        dismiss()
    }

    private func deletePerson() {
        if let canonical { store.delete(canonical: canonical) }
        onDeleted()
        dismiss()
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self }
}
