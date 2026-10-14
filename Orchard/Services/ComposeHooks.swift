import ComposePlanner
import Foundation

/// What a `post_start` or `pre_stop` hook that went wrong means for a run, and how it reads.
///
/// Ported from the compose plugin (`Runtime.outcome`, `HookFailure`, `HookTranscript` in
/// andrew-waters/compose) so a file behaves the same in Orchard as on the command line. Those
/// live in the plugin's executable target, which nothing can import; when the package exposes
/// them from a library (andrew-waters/orchard#130), this is replaced by the package's.
enum ComposeHooks {
    /// How many of a hook's last output lines a failure message carries.
    static let keptLines = 5

    /// What a hook that went wrong means for the rest of the plan.
    enum Outcome: Equatable {
        /// Say so and go on to the next step.
        case carryOn(warning: String)
        /// Stop the plan with this message.
        case stop(message: String)
    }

    /// The hook as a person would point at it: `post_start[0] in service `web``.
    static func name(of hook: HookOperation) -> String {
        "\(hook.phase.rawValue)[\(hook.index)] in service `\(hook.service)`"
    }

    /// Whatever went wrong, whether the hook exited non-zero or never got going, the plan
    /// decided up front whether it matters.
    ///
    /// - Parameter later: how many steps come after this one, for saying what was not done.
    static func outcome(of hook: HookOperation, failingWith error: any Error, later: Int) -> Outcome {
        let text = (error as? Failure)?.description
            ?? "\(name(of: hook)) could not run: \(error.localizedDescription)"
        guard hook.failureIsFatal else {
            // The container is being stopped either way, so a failed `pre_stop` is worth
            // saying and not worth leaving the container up for.
            return .carryOn(warning: text + "\nCarrying on with the stop.")
        }
        // The container is kept and its hash has not changed, so another up would leave it
        // alone and the hook would not run again.
        return .stop(
            message: text
                + "\n`\(hook.containerName)` was left in place"
                + (later > 0 ? "; \(later) later step(s) were not attempted." : ".")
                + "\nUp keeps a running container, so it will not run this hook again. "
                + "Take the project down and bring it up once it is fixed."
        )
    }

    /// A hook that ran and exited non-zero. Whether that stops the plan is the plan's
    /// decision, carried on the operation, so this only says what happened.
    struct Failure: LocalizedError, CustomStringConvertible {
        let hook: HookOperation
        let status: Int32
        let lastLines: [String]

        var description: String {
            var text = "\(ComposeHooks.name(of: hook)) exited \(status)"
            if !lastLines.isEmpty {
                text += "\nIts last output was:"
                for line in lastLines { text += "\n    \(line)" }
            }
            return text
        }

        var errorDescription: String? { description }
    }

    /// Keeps the end of a hook's output for the message if it fails. Lines arrive from the
    /// backend's output readers, off the main actor.
    final class Transcript: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        private var _latest: String?

        var lastLines: [String] {
            lock.withLock { lines }
        }

        /// The most recent line with something on it, for the step's live detail.
        var latest: String? {
            lock.withLock { _latest }
        }

        func append(_ line: String) {
            lock.withLock {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { _latest = line }
                lines.append(line)
                if lines.count > ComposeHooks.keptLines {
                    lines.removeFirst(lines.count - ComposeHooks.keptLines)
                }
            }
        }
    }
}
