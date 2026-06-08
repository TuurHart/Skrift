import MessageUI
import SwiftUI
import UIKit

/// Capture app feedback (ported from Shhhcribble, adapted to Skrift's Transcriber).
/// Flow: dictate (record → on-device transcribe, re-record appends) and/or type a
/// note, optionally paste a screenshot → Send → persist to FeedbackStore + open the
/// mail composer; mark sent on a real send. If Mail isn't set up, the draft is kept.
struct FeedbackCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = FeedbackRecorder()
    @State private var transcript = ""
    @State private var note = ""
    @State private var pastedImage: UIImage?
    @State private var phase: Phase = .idle
    @State private var errorMessage: String?
    @State private var pendingMailItem: FeedbackItem?
    @State private var showNoMailAlert = false

    private let transcriber: any Transcriber = TranscriberFactory.make()

    enum Phase { case idle, recording, transcribing, review }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    recorderRow
                    if let msg = errorMessage {
                        Text(msg).font(.caption).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Speak about what happened, or just type a note below. Transcription stays on-device.")
                }

                if phase == .review || !transcript.isEmpty {
                    Section("Transcript (editable)") {
                        TextField("Transcript", text: $transcript, axis: .vertical)
                            .lineLimit(3...10)
                            .accessibilityIdentifier("feedback-transcript-field")
                    }
                }

                Section("Screenshot (optional)") {
                    if let img = pastedImage {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 200).cornerRadius(8)
                            Button("Remove screenshot", role: .destructive) { pastedImage = nil }.font(.caption)
                        }
                    } else {
                        Button(action: pasteScreenshot) {
                            Label("Paste screenshot from clipboard", systemImage: "doc.on.clipboard")
                        }
                    }
                }

                Section("Note (optional)") {
                    TextField("Anything to add?", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityIdentifier("feedback-note-field")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.skBg.ignoresSafeArea())
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .destructive) { recorder.discard(); dismiss() } label: {
                        Text("Discard").font(.subheadline)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: sendNow) {
                        Label("Send", systemImage: "paperplane.fill").labelStyle(.titleAndIcon).font(.body.weight(.semibold))
                    }
                    .disabled(!canSend)
                    .accessibilityIdentifier("feedback-send-button")
                }
            }
            .sheet(item: $pendingMailItem) { item in
                FeedbackMailComposer(item: item) { sent in
                    sent.forEach { FeedbackStore.shared.markSent($0) }
                    pendingMailItem = nil
                    dismiss()
                }
                .ignoresSafeArea()
            }
            .alert("Mail not available", isPresented: $showNoMailAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Mail isn't set up on this device. Your feedback is saved — set up Mail, then send it from the Feedback list.")
            }
        }
        .interactiveDismissDisabled(phase == .recording || phase == .transcribing)
    }

    private var canSend: Bool {
        guard phase != .recording, phase != .transcribing else { return false }
        return !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recorderRow: some View {
        Button(action: toggleRecord) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(phase == .recording ? Color.red.opacity(0.15) : Color.skAccent.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: phase == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(phase == .recording ? .red : Color.skAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusLine).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if phase == .recording || recorder.elapsed > 0 {
                        Text(formatTime(recorder.elapsed)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if phase == .transcribing { ProgressView().controlSize(.small) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(phase == .transcribing)
        .accessibilityIdentifier("feedback-record-button")
    }

    private var statusLine: String {
        switch phase {
        case .idle: return transcript.isEmpty ? "Tap to record" : "Tap to add more"
        case .recording: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .review: return transcript.isEmpty ? "Done" : "Done — review below"
        }
    }

    private func toggleRecord() {
        switch phase {
        case .recording: stopAndTranscribe()
        case .idle, .review: startRecording()
        case .transcribing: break
        }
    }

    private func startRecording() {
        errorMessage = nil
        do { try recorder.start(); phase = .recording }
        catch { errorMessage = "Couldn't start: \(error.localizedDescription)" }
    }

    private func stopAndTranscribe() {
        recorder.stop()
        guard let url = recorder.finishedFileURL else { errorMessage = "Recording missing."; phase = .idle; return }
        phase = .transcribing
        let existing = transcript
        Task {
            do {
                let result = try await transcriber.transcribe(audioURL: url)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    if existing.isEmpty { transcript = text }
                    else if !text.isEmpty { transcript = existing + " " + text }
                    phase = .review
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Transcribe failed: \(error.localizedDescription). You can still send with a note."
                    phase = .review
                }
            }
            recorder.discard()
        }
    }

    private func pasteScreenshot() {
        if let img = UIPasteboard.general.image { pastedImage = img; errorMessage = nil }
        else { errorMessage = "Clipboard has no image. Take a screenshot, then tap Paste." }
    }

    private func sendNow() {
        let item = pendingMailItem ?? FeedbackStore.shared.save(
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            screenshot: pastedImage,
            durationSeconds: recorder.elapsed
        )
        guard MFMailComposeViewController.canSendMail() else { showNoMailAlert = true; return }
        pendingMailItem = item
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = Int(t); return String(format: "%01d:%02d", total / 60, total % 60)
    }
}
