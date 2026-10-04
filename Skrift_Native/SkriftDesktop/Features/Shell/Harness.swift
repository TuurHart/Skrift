#if DEBUG
import Foundation

/// What every headless `-flag` entry point in `RunFile` shares: argument lookup, a logger,
/// and a runner that cannot leave the process alive.
///
/// The runner exists because a headless run is a Task that has to end in `exit()`. A `try`
/// with no catch inside that Task swallows the throw, `exit()` is never reached, and the
/// process carries on as a GUI app (`-ratetorow` did exactly that). `main` / `background`
/// catch, print `>>> ERROR: …` and exit 1; a body that returns normally exits 0. A body may
/// still `exit(n)` itself for a verdict (PASS/FAIL).
enum Harness {
    nonisolated static var args: [String] { LaunchArgs.all }

    /// `-flag` is present.
    nonisolated static func has(_ flag: String) -> Bool { LaunchArgs.has(flag) }

    /// The one argument after `-flag`.
    nonisolated static func value(_ flag: String) -> String? { LaunchArgs.value(after: flag) }

    /// The `n` arguments after `-flag` (`-ratefile <ids> <rating>` is n = 2).
    nonisolated static func values(_ flag: String, count n: Int) -> [String]? {
        LaunchArgs.values(after: flag, count: n)
    }

    /// stderr: where every harness but the two vault ones prints.
    nonisolated static func log(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }

    /// stdout: `-vaultexport` prints its tree there so a caller can pipe it.
    nonisolated static func logOut(_ s: String) {
        FileHandle.standardOutput.write(Data((s + "\n").utf8))
    }

    /// Run `body` on the main actor (the SwiftData main contexts, `@MainActor` stores), then exit.
    nonisolated static func main(_ body: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do { try await body() } catch { fail(error) }
            exit(0)
        }
    }

    /// Run `body` off the main actor (the ASR engines: FluidAudio posts completions to main,
    /// so main must stay free), then exit.
    nonisolated static func background(_ body: @escaping @Sendable () async throws -> Void) {
        Task.detached(priority: .userInitiated) {
            do { try await body() } catch { fail(error) }
            exit(0)
        }
    }

    nonisolated private static func fail(_ error: Error) -> Never {
        log(">>> ERROR: \(error)")
        exit(1)
    }
}
#endif
