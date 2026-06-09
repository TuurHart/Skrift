import SwiftUI

/// "Who is this speaker?" — replaces the free-text naming alert. Three ways to assign a
/// tapped speaker turn:
///  • **People** — pick someone from the Names DB (links + enrolls the voiceprint under
///    that exact person; no typos, no duplicate people).
///  • **This conversation** — send the turn to another speaker in this memo (fixes a
///    mis-split like a phantom "Speaker 3: Oh" — the turn merges into the chosen speaker).
///  • **New person** — free text, creates a new person + enrolls.
struct SpeakerAssignSheet: View {
    let speaker: String                       // the tapped label, e.g. "Speaker 3"
    let otherSpeakers: [String]               // other distinct turn labels in this memo
    let people: [Person]
    var onAssignPerson: (Person) -> Void
    var onMergeInto: (String) -> Void
    var onNewName: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.skBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !people.isEmpty {
                            section("PEOPLE") {
                                ForEach(people, id: \.canonical) { person in
                                    Button { choose { onAssignPerson(person) } } label: { personRow(person) }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("assign-person-\(NamesDisplay.name(person))")
                                }
                            }
                        }
                        if !otherSpeakers.isEmpty {
                            section("MERGE INTO") {
                                Text("Wrong split? Send \(speaker)'s words to another speaker.")
                                    .font(.system(size: 12)).foregroundStyle(Color.skTextFaint)
                                ForEach(otherSpeakers, id: \.self) { other in
                                    Button { choose { onMergeInto(other) } } label: { mergeRow(other) }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("merge-into-\(other)")
                                }
                            }
                        }
                        section("NEW PERSON") {
                            HStack(spacing: 8) {
                                TextField("Full name", text: $newName)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 12).padding(.vertical, 11)
                                    .background(Color.skSurface, in: .rect(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle.sk(10).stroke(Color.skBorder, lineWidth: 1))
                                    .submitLabel(.done)
                                    .onSubmit(addNew)
                                    .accessibilityIdentifier("assign-new-name-field")
                                Button("Add", action: addNew)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(newName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.skTextFaint : .white)
                                    .padding(.horizontal, 14).padding(.vertical, 11)
                                    .background(newName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.skElev : Color.skAccent,
                                                in: .rect(cornerRadius: 10, style: .continuous))
                                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                                    .accessibilityIdentifier("assign-new-name-button")
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Who is \(speaker)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: rows

    private func personRow(_ person: Person) -> some View {
        HStack(spacing: 12) {
            Avatar(name: NamesDisplay.name(person), size: 38)
            Text(NamesDisplay.name(person))
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.skText)
            Spacer()
            if NamesDisplay.isEnrolled(person) { VoiceBars() }
        }
        .padding(.vertical, 9).padding(.horizontal, 6)
        .overlay(Divider().overlay(Color.skBorder), alignment: .bottom)
        .contentShape(Rectangle())
    }

    private func mergeRow(_ other: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.merge").font(.system(size: 14)).foregroundStyle(Color.skAccent)
            Text(other).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.skText)
            Spacer()
        }
        .padding(.vertical, 9).padding(.horizontal, 6)
        .overlay(Divider().overlay(Color.skBorder), alignment: .bottom)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Color.skTextFaint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addNew() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        choose { onNewName(n) }
    }

    /// Run the action then dismiss (defer so the sheet closes after the model mutates).
    private func choose(_ action: () -> Void) { action(); dismiss() }
}
