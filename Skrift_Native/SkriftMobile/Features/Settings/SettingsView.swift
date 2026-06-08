import SwiftUI

/// Settings (mockup2): Mac connection + pairing, capture toggles, library
/// (Names & voices, weather key), theme, version. Presented as a sheet from the
/// Memos toolbar; Names + Pair-a-Mac push within its own stack.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("liveTranscription") private var liveTranscription = true
    @AppStorage("conversationDefault") private var conversationDefault = false
    @AppStorage("appTheme") private var appTheme = "dark"
    @AppStorage("weatherAPIKey") private var weatherKey = ""
    @State private var connection = MacConnection.load()
    @State private var showFeedback = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    HStack {
                        Text("Connection")
                        Spacer()
                        if let connection {
                            HStack(spacing: 7) {
                                Circle().fill(Color.skGreen).frame(width: 9, height: 9).shadow(color: .skGreen, radius: 4)
                                Text(connection.host).foregroundStyle(Color.skTextDim)
                            }
                        } else {
                            Text("Not connected").foregroundStyle(Color.skTextFaint)
                        }
                    }
                    NavigationLink {
                        PairMacView()
                    } label: {
                        Text("Pair a Mac")
                    }
                    .accessibilityIdentifier("pair-mac-link")
                }

                Section("Capture") {
                    Toggle("Live transcription", isOn: $liveTranscription)
                        .accessibilityIdentifier("setting-live-transcription")
                    Toggle("Conversation mode default", isOn: $conversationDefault)
                }

                Section("Library") {
                    NavigationLink {
                        NamesListView()
                    } label: {
                        Text("Names & voices")
                    }
                    .accessibilityIdentifier("names-link")
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
                    HStack { Text("Version"); Spacer(); Text("0.1.0").foregroundStyle(Color.skTextDim) }
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
