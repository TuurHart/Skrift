import SwiftUI

/// Settings → Capture → Custom words: the vocabulary-boost list. Words added
/// here are CTC-spotted + rescored into every finished transcription
/// (`VocabularyBooster`), fixing names Parakeet mis-hears ("Skrift", products,
/// people). First use downloads a ~100 MB spotter model.
struct CustomWordsView: View {
    @State private var words: [String] = CustomVocabularyStore.words()
    @State private var newWord: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Add a word or name…", text: $newWord)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .onSubmit(addWord)
                        .accessibilityIdentifier("custom-word-field")
                    Button {
                        addWord()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.skAccent)
                    }
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("custom-word-add")
                }
            } footer: {
                Text("The transcriber listens for these words and corrects near-misses (“skrift” → “Skrift”). Spelled exactly as you want them written. The first transcription after adding words downloads a ~100 MB model.")
            }

            if !words.isEmpty {
                Section("Words") {
                    ForEach(words, id: \.self) { word in
                        Text(word)
                    }
                    .onDelete { offsets in
                        words.remove(atOffsets: offsets)
                        CustomVocabularyStore.save(words)
                    }
                }
            }
        }
        .navigationTitle("Custom words")
        .navigationBarTitleDisplayMode(.inline)
        // Re-read from the store on every appearance — the `@State` initial value is only
        // evaluated once, so if this view is kept alive and revisited it would otherwise
        // show stale state. (The store itself uses UserDefaults.standard and persists.)
        .onAppear { words = CustomVocabularyStore.words() }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !words.contains(where: { $0.lowercased() == trimmed.lowercased() }) else {
            newWord = ""
            return
        }
        words.append(trimmed)
        CustomVocabularyStore.save(words)
        newWord = ""
        fieldFocused = true   // keep the keyboard for rapid entry
    }
}
