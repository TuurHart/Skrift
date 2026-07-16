import SwiftUI

/// A request to open the shared person editor. `person == nil` is a NEW person;
/// `prefillName`/`prefillAlias` seed a new person from a note's right-click selection.
struct PersonEditorRequest: Identifiable {
    let id = UUID()
    var person: Person? = nil
    var prefillName: String = ""
    var prefillAlias: String = ""
}

/// The shared, labeled person editor (mocks/opt-in-naming.html panel 3) — ONE editor,
/// two doors: Settings → Names (tap a row / "Add person…") and a note's right-click
/// "A new person…". Full name (the `[[link]]` target), Aliases (spoken nicknames that
/// link to them), Short name (how a linked mention reads), and a read-only Voice state.
/// Builds a `Person` and hands it back via `onSave(originalCanonical, person)`; the host
/// persists (`NamesStore.upsert`) and runs any side effects (reload / re-scan the note).
struct PersonEditor: View {
    let request: PersonEditorRequest
    var onSave: (_ originalCanonical: String?, _ person: Person) -> Void
    var onDelete: ((_ canonical: String) -> Void)? = nil
    var onClose: () -> Void
    /// `false` renders fields as static Text without a ScrollView for snapshot
    /// verification (ImageRenderer can't draw AppKit TextFields / lay out scroll content).
    var interactive = true

    @State private var fullName: String
    @State private var aliases: String     // comma-separated
    @State private var short: String

    private let original: Person?
    private let enrolled: Bool

    init(request: PersonEditorRequest,
         onSave: @escaping (String?, Person) -> Void,
         onDelete: ((String) -> Void)? = nil,
         onClose: @escaping () -> Void,
         interactive: Bool = true) {
        self.request = request
        self.onSave = onSave
        self.onDelete = onDelete
        self.onClose = onClose
        self.interactive = interactive
        let p = request.person
        self.original = p
        _fullName = State(initialValue: p.map { NamesMerge.keyName($0.canonical) } ?? request.prefillName)
        _aliases = State(initialValue: p?.aliases.joined(separator: ", ") ?? request.prefillAlias)
        _short = State(initialValue: p?.short ?? "")
        self.enrolled = PersonEditCore.isEnrolled(p)
    }

    private var isNew: Bool { original == nil }
    private var canSave: Bool { !fullName.trimmingCharacters(in: .whitespaces).isEmpty }
    private var shortDisplay: String {
        let s = PersonEditCore.displayShort(fullName: fullName, short: short)
        return s.isEmpty ? "—" : s
    }
    private var firstAlias: String {
        aliases.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if interactive {
                ScrollView { fields }
            } else {
                fields
                Spacer(minLength: 0)
            }
        }
        .frame(width: 420, height: 460)
        .background(Theme.bg)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            field(label: "Full name",
                  help: "The Obsidian note title. Becomes the [[link]] target.",
                  text: $fullName, placeholder: "Bruno Aragorn")
            field(label: "Aliases",
                  help: "Spoken words (comma-separated) that should be RECOGNISED as this person.",
                  text: $aliases, placeholder: "Bruno, Bru", font: .system(size: 12)) {
                if canSave, let d = PersonEditCore.aliasDemo(firstAlias: firstAlias,
                                                             fullName: fullName, short: short) {
                    demo(d.prefix, bold: d.bold)
                }
            }
            field(label: "Short name",
                  help: "How the inline link reads: [[\(fullName.trimmingCharacters(in: .whitespaces).isEmpty ? "Full Name" : fullName.trimmingCharacters(in: .whitespaces))|\(shortDisplay)]].",
                  text: $short, placeholder: "first word of the full name", font: .system(size: 12))
            voiceField
        }
        .padding(20)
    }

    private var header: some View {
        HStack {
            Text(isNew ? "Add person" : "Edit person")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            if !isNew, let onDelete, let original {
                Button(role: .destructive) {
                    onDelete(original.canonical); onClose()
                } label: {
                    Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Theme.destructive)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Delete this person")
            }
            Button("Cancel", action: onClose)
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
            Button("Save", action: save)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(canSave ? .white : Theme.textMuted)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(canSave ? Theme.accent : Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .disabled(!canSave)
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline.opacity(0.08)).frame(height: 0.5) }
    }

    @ViewBuilder
    private func field<Extra: View>(label: String, help: String, text: Binding<String>,
                                    placeholder: String, font: Font = .system(size: 13),
                                    @ViewBuilder extra: () -> Extra = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(help).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if interactive {
                RingedField(placeholder: placeholder, text: text, font: font)
            } else {
                let v = text.wrappedValue
                Text(v.isEmpty ? placeholder : v)
                    .font(font).foregroundStyle(v.isEmpty ? Theme.textMuted : Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(Theme.hairline.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline.opacity(0.08), lineWidth: 1))
            }
            extra()
        }
    }

    private func demo(_ prefix: String, bold: String) -> some View {
        (Text(prefix).foregroundStyle(Theme.textSecondary)
         + Text(bold).foregroundStyle(Theme.accent).fontWeight(.semibold))
            .font(.system(size: 11))
    }

    private var voiceField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Voice").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.system(size: 11, weight: .semibold))
                Text(enrolled ? "Voice enrolled" : "No voice yet")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(enrolled ? Theme.green : Theme.textMuted)
            Text(enrolled ? "Conversation mode can recognise this person."
                 : "Name them in a conversation (phone or Mac) to enroll their voice.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func save() {
        // One rulebook (Shared/Naming/PersonEditCore): normalise, default-alias (a
        // person with no alias never links — the Mac previously allowed that),
        // alias de-dupe, voiceprint carry across edits incl. renames.
        guard let r = PersonEditCore.materialise(
            fullName: fullName,
            aliases: aliases.split(separator: ",").map(String.init),
            short: short, original: original) else { return }
        onSave(original?.canonical, r.person)
        onClose()
    }
}
