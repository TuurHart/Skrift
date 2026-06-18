import SwiftUI

/// Settings (mockup2): Mac connection + pairing, capture toggles, library
/// (Names & voices, weather key), theme, version. Presented as a sheet from the
/// Memos toolbar; Names + Pair-a-Mac push within its own stack.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("liveTranscription") private var liveTranscription = true
    @AppStorage("appTheme") private var appTheme = "dark"
    @AppStorage("weatherAPIKey") private var weatherKey = ""
    @AppStorage("karaokeTapToSeek") private var karaokeTapToSeek = true
    // Key mirrored by MemoSaver.autoCopySettingKey (default OFF — user-locked).
    @AppStorage("autoCopyTranscript") private var autoCopyTranscript = false
    @State private var connection = MacConnection.load()
    @State private var showFeedback = false
    /// Live reachability of the paired Mac: nil = checking, true = server answered
    /// /health, false = paired but unreachable. The green dot used to show whenever
    /// a pairing was merely SAVED — it lied when the Mac was off / on another
    /// network / a stale port, so memos sat "Waiting" while Settings said connected.
    @State private var reachable: Bool?
    /// Global CloudKit (device↔device) sync activity → the honest "iCloud" status row.
    @ObservedObject private var cloudSync = CloudSyncMonitor.shared

    private var customWordsCount: String {
        let n = CustomVocabularyStore.words().count
        return n == 0 ? "None" : "\(n)"
    }

    private var connectionColor: Color {
        switch reachable {
        case .some(true):  return .skGreen
        case .some(false): return .skRed
        case .none:        return .skTextFaint
        }
    }

    /// Ping the paired Mac's /health so the dot reflects REAL reachability, not just
    /// "a pairing is saved". Re-run on appear (covers returning from Pair-a-Mac).
    private func checkReachability() async {
        guard let connection else { reachable = nil; return }
        reachable = nil
        reachable = await URLSessionMacTransport(connection: connection).health()
    }

    var body: some View {
        NavigationStack {
            Form {
                // The honest GLOBAL sync state (no per-note badge — CloudKit doesn't
                // expose reliable per-row status). "Syncing…" while in flight, else
                // "Up to date".
                Section {
                    HStack {
                        Label("iCloud sync", systemImage: "icloud")
                        Spacer()
                        if cloudSync.isSyncing {
                            ProgressView().controlSize(.mini)
                            Text("Syncing…").foregroundStyle(Color.skTextDim)
                        } else {
                            Text("Up to date").foregroundStyle(Color.skTextDim)
                        }
                    }
                    .accessibilityIdentifier("icloud-status")

                    NavigationLink {
                        SyncedAudiobooksView()
                    } label: {
                        Label("Synced audiobooks", systemImage: "books.vertical")
                    }
                } footer: {
                    Text("Your memos, names, and custom words sync across your devices via iCloud. Audiobooks sync per-book — turn one on from its long-press menu.")
                }

                Section("Mac") {
                    HStack {
                        Text("Connection")
                        Spacer()
                        if let connection {
                            HStack(spacing: 7) {
                                if reachable == nil {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Circle().fill(connectionColor).frame(width: 9, height: 9)
                                        .shadow(color: connectionColor, radius: 4)
                                }
                                Text(reachable == false ? "\(connection.host) · unreachable" : connection.host)
                                    .foregroundStyle(Color.skTextDim)
                            }
                            .accessibilityIdentifier("mac-connection-status")
                        } else {
                            Text("Not connected").foregroundStyle(Color.skTextFaint)
                        }
                    }
                    if reachable == false {
                        Text("Paired, but the Mac isn't answering. Check it's awake, on the same Wi-Fi, and running Skrift — then re-pair if its address changed.")
                            .font(.footnote).foregroundStyle(Color.skTextDim)
                    }
                    NavigationLink {
                        PairMacView()
                    } label: {
                        Text("Pair a Mac")
                    }
                    .accessibilityIdentifier("pair-mac-link")
                }

                Section {
                    Toggle("Live transcription", isOn: $liveTranscription)
                        .accessibilityIdentifier("setting-live-transcription")
                    Toggle("Copy transcript to clipboard", isOn: $autoCopyTranscript)
                        .accessibilityIdentifier("setting-auto-copy-transcript")
                    NavigationLink {
                        CustomWordsView()
                    } label: {
                        HStack {
                            Text("Custom words")
                            Spacer()
                            Text(customWordsCount).foregroundStyle(Color.skTextDim)
                        }
                    }
                    .accessibilityIdentifier("custom-words-link")
                } header: {
                    Text("Capture")
                } footer: {
                    Text("When a transcription finishes, the final transcript is copied to the clipboard automatically. Custom words teach the transcriber names it mis-hears (like “Skrift”).")
                }

                Section {
                    Toggle("Tap words to seek", isOn: $karaokeTapToSeek)
                        .accessibilityIdentifier("setting-tap-to-seek")
                } header: {
                    Text("Playback")
                } footer: {
                    Text("While audio plays, tap a word in the transcript to jump there.")
                }

                Section("Library") {
                    NavigationLink {
                        NamesListView()
                    } label: {
                        Text("Names & voices")
                    }
                    .accessibilityIdentifier("names-link")
                    NavigationLink {
                        ModelsView()
                    } label: {
                        Text("Models")
                    }
                    .accessibilityIdentifier("models-link")
                    NavigationLink {
                        WeatherKeyView(key: $weatherKey)
                    } label: {
                        HStack {
                            Text("Weather API key")
                            Spacer()
                            Text(maskedKey).foregroundStyle(Color.skTextDim)
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appTheme) {
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                        Text("Auto").tag("auto")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Feedback") {
                    Button { showFeedback = true } label: {
                        Label("Send feedback", systemImage: "paperplane")
                    }
                    .accessibilityIdentifier("send-feedback-button")
                }

                Section("About") {
                    // Read from the bundle (was hardcoded "0.1.0" → never reflected the
                    // actual build). Shows "0.1.0 (5)" so you can confirm which build a
                    // device is running — bump CFBundleVersion per install to tell them apart.
                    HStack {
                        Text("Version"); Spacer()
                        Text({
                            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                            let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                            return "\(v) (\(b))"
                        }()).foregroundStyle(Color.skTextDim)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.skBg.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showFeedback) { FeedbackCaptureView() }
            .onAppear { connection = MacConnection.load() }
            // Live health probe so the dot tells the truth (green only when the Mac
            // actually answers). Re-runs when the saved host/port changes (e.g. after
            // re-pairing in Pair-a-Mac).
            .task(id: connection.map { "\($0.host):\($0.port)" }) { await checkReachability() }
        }
    }

    private var maskedKey: String {
        guard !weatherKey.isEmpty else { return "Not set" }
        return "••••••" + String(weatherKey.suffix(2))
    }
}

private struct WeatherKeyView: View {
    @Binding var key: String

    var body: some View {
        Form {
            Section {
                TextField("OpenWeatherMap key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("weather-key-field")
            } footer: {
                Text("Used to tag memos with weather + pressure. Get a free key at openweathermap.org.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.skBg.ignoresSafeArea())
        .navigationTitle("Weather API key")
        .navigationBarTitleDisplayMode(.inline)
    }
}
