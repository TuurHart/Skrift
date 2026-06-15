import BackgroundTasks
import Foundation

/// Lets the whole-book transcribe continue in the BACKGROUND (app closed) — best
/// overnight on a charger. Best-effort by design: iOS grants BGProcessingTask time
/// generously while charging, but the ~1 GB ASR model can be jetsammed mid-run. The job
/// saves every chunk atomically, so a kill just resumes from the saved frontier next
/// time — nothing is lost, and FOREGROUND transcription is unaffected. If the OS denies
/// or never runs the task, the only consequence is "no overnight progress" (benign).
///
/// Wiring: `register()` once at launch (before the scene connects), `scheduleIfNeeded()`
/// when the app backgrounds with a transcribe in flight. Requires `processing` in
/// `UIBackgroundModes` + `taskID` in `BGTaskSchedulerPermittedIdentifiers` (project.yml).
enum BookBackgroundScheduler {
    /// App-internal identifier (NOT the bundle id) so it's identical across Debug/Release.
    static let taskID = "com.skrift.booktranscribe"
    private static let pendingKey = "pendingBookTranscribeID"

    /// Register the launch handler. MUST be called before the app finishes launching
    /// (SwiftUI `App.init`). No-op in the sim/UI-test path (no ANE → nothing to resume).
    static func register() {
        guard LaunchFlags.seedTranscript == nil else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: .main) { task in
            guard let task = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
            MainActor.assumeIsolated { handle(task) }   // using:.main → already on the main actor
        }
    }

    /// Submit a background request IF a book is mid-transcription. Call when the app
    /// backgrounds. `requiresExternalPower` matches the user's "best overnight, charging"
    /// choice — iOS schedules it during a charge (typically overnight).
    @MainActor static func scheduleIfNeeded() {
        let job = BookTranscriptionJob.shared
        guard let bookID = job.activeBookID, job.isRunningOrPaused else { return }
        UserDefaults.standard.set(bookID.uuidString, forKey: pendingKey)
        let request = BGProcessingTaskRequest(identifier: taskID)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        do {
            try BGTaskScheduler.shared.submit(request)
            DevLog.log("bookbg: scheduled background transcribe for \(bookID)")
        } catch {
            DevLog.log("bookbg: submit failed \(error)")
        }
    }

    @MainActor private static func handle(_ task: BGProcessingTask) {
        DevLog.log("bookbg: handler woke")
        let job = BookTranscriptionJob.shared
        guard let idStr = UserDefaults.standard.string(forKey: pendingKey),
              let bookID = UUID(uuidString: idStr),
              let book = AudiobookLibraryStore.shared.book(id: bookID) else {
            task.setTaskCompleted(success: true); return
        }

        // Guard against double-completion (expiration vs natural finish); both paths hop
        // through the main actor, so the flag is race-free.
        var done = false
        func complete(_ ok: Bool) {
            guard !done else { return }
            done = true
            task.setTaskCompleted(success: ok)
        }

        // iOS calls this when our window runs out: pause (the last chunk is already
        // saved), ask for another window, and report incomplete.
        task.expirationHandler = {
            Task { @MainActor in
                job.pauseByUser()
                scheduleIfNeeded()
                DevLog.log("bookbg: window expired — paused, rescheduled")
                complete(false)
            }
        }

        job.start(book: book)
        // Poll for the book finishing; the expirationHandler ends us first if time runs out.
        Task { @MainActor in
            while !done, job.activeBookID == bookID, job.phase != .finished {
                try? await Task.sleep(for: .seconds(2))
            }
            DevLog.log("bookbg: book finished or stopped — handler done")
            complete(true)
        }
    }
}
