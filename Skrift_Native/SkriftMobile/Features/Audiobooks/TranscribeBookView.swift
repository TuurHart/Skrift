import SwiftUI

/// Wave-2 text-capture: the "Transcribe book" sheet (player ⋯ menu). Drives
/// `BookTranscriptionJob.shared` and shows live progress + a REAL per-device
/// estimate (the job measures its own throughput — no placeholder). Copy per
/// design `text-capture-DESIGN.md` §12/§13: the load-bearing reassurance
/// ("keep listening — capture already works for the done parts") is the lede;
/// the bar + % are secondary; "runs on battery (best overnight on a charger)",
/// "resumes if interrupted", "leave any time — keeps running".
struct TranscribeBookView: View {
    let book: Audiobook
    @ObservedObject private var job = BookTranscriptionJob.shared
    @Environment(\.dismiss) private var dismiss

    /// True when this sheet's book is the one the job is working on.
    private var isThisBook: Bool { job.activeBookID == book.id }
    private var pct: Int { Int((job.progress * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    lede
                    progressBlock
                    guidance
                }
                .padding(.horizontal, Theme.Space.margin)
                .padding(.top, 6)
            }
            controls
        }
        .background(Color.skBg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("transcribe-book")
        // Show the REAL saved % the moment the sheet opens (a partly-transcribed
        // book reads its frontier from the sidecar) — not 0-until-Start.
        .task { job.reflectSavedProgress(for: book) }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Transcribe this book")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.skText)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.skTextDim)
                    .frame(width: 28, height: 28)
                    .background(Color.skElev, in: .circle)
            }
            .accessibilityIdentifier("transcribe-book-close")
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 16).padding(.bottom, 10)
    }

    // MARK: - Lede (the load-bearing reassurance)

    private var lede: some View {
        Text(job.progress >= 0.999
             ? "Done — capture is now instant anywhere in this book."
             : "Keep listening — capture already works for the parts that are done.")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.skText)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Progress

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.skBorder).frame(height: 6)
                    Capsule().fill(Color.skAccent)
                        .frame(width: max(6, geo.size.width * job.progress), height: 6)
                }
            }
            .frame(height: 6)
            .accessibilityIdentifier("transcribe-book-progress")

            HStack {
                Text("\(pct)% transcribed")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.skTextDim)
                Spacer()
                if let estimate = estimateText {
                    Text(estimate)
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.skTextFaint)
                }
            }
        }
        .padding(.top, 2)
    }

    /// REAL estimate from the job's measured throughput. "≈ 12 min left" while
    /// running, "≈ 8 min per hour of audio" otherwise. nil (→ no number shown)
    /// until a per-device rate exists — never a fabricated figure.
    private var estimateText: String? {
        // Nothing to estimate once fully transcribed.
        guard let rtf = job.measuredRTF, rtf > 0, job.progress < 0.999 else { return nil }
        // "≈ N min left" whenever there's audio still to do (running OR a paused/
        // reopened partial run) — uses the reflected saved progress.
        if let eta = job.estimatedRemainingSeconds(for: book), eta > 1 {
            return "≈ \(Self.shortDuration(eta)) left"
        }
        return String(format: "≈ %.0f min per hour", 60.0 / rtf)
    }

    // MARK: - Guidance

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 9) {
            row("bolt.fill", "Runs on battery — best overnight on a charger for a full book.")
            row("arrow.clockwise", "Resumes where it left off if interrupted.")
            row("rectangle.portrait.and.arrow.right", "Leave any time — it keeps running.")
            if job.phase == .pausedUnplugged {
                row("battery.25", "Paused to save battery (low charge or Low Power Mode). Resumes automatically.", tint: .skAmber)
            }
            if case .failed(let why) = job.phase {
                row("exclamationmark.triangle", "Stopped: \(why)", tint: .skAmber)
            }
        }
        .padding(.top, 2)
    }

    private func row(_ icon: String, _ text: String, tint: Color = .skTextDim) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(tint).frame(width: 18)
            Text(text).font(.system(size: 12.5)).foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 8) {
            if job.progress >= 0.999 {
                // Fully transcribed — nothing to start/resume (gate on PROGRESS, not
                // phase/isThisBook: the job clears activeBookID when it finishes, and
                // a re-opened already-done book is .idle — both must read as "done").
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 15))
                    Text("Fully transcribed").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.skAccent)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .accessibilityIdentifier("transcribe-book-done")
            } else {
                switch job.phase {
                case .running where isThisBook:
                    secondaryButton("Pause", id: "transcribe-book-pause") { job.pauseByUser() }
                case .pausedByUser where isThisBook:
                    primaryButton("Resume", id: "transcribe-book-resume") { job.resumeByUser() }
                case .pausedUnplugged where isThisBook:
                    secondaryButton("Pause", id: "transcribe-book-pause") { job.pauseByUser() }
                default:
                    primaryButton(job.progress > 0.001 ? "Resume transcribing" : "Start transcribing",
                                  id: "transcribe-book-start") { job.start(book: book) }
                }
            }
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 10).padding(.bottom, 20)
    }

    private func primaryButton(_ title: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Color.skAccent, in: .rect(cornerRadius: 14, style: .continuous))
        }
        .accessibilityIdentifier(id)
    }

    private func secondaryButton(_ title: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.skText)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Color.skElev, in: .rect(cornerRadius: 14, style: .continuous))
        }
        .accessibilityIdentifier(id)
    }

    /// "12 min" / "1 h 20 min" / "45 s".
    static func shortDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        let m = s / 60, h = m / 60
        if h > 0 { return "\(h) h \(m % 60) min" }
        return "\(m) min"
    }
}
