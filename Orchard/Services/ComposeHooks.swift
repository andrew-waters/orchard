import ComposePlanner
import Foundation

/// How a `post_start` or `pre_stop` hook that went wrong reads in Orchard.
///
/// The rules are compose's, shared with the plugin: `HookOperation.outcome(laterSteps:)` says
/// whether the plan carries on, `HookFailure` carries what happened and `HookTranscript` keeps
/// the end of the output. Only the wording is Orchard's, written for a run row and an alert
/// rather than a terminal.
enum ComposeHooks {
    /// How many of a hook's last output lines a failure message carries. Fewer than the
    /// plugin's twenty: the message is shown on a row and in an alert.
    static let keptLines = 5

    /// How a hook that went wrong is reported.
    enum Report: Equatable {
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
    static func report(of hook: HookOperation, failingWith error: any Error, later: Int) -> Report {
        let failure = error as? HookFailure ?? HookFailure(hook: hook, reason: .couldNotStart(error))
        let text = describe(failure)
        switch hook.outcome(laterSteps: later) {
        case .carryOn:
            return .carryOn(warning: text + "\nCarrying on with the stop.")
        case .stop(let laterSteps, let container):
            return .stop(
                message: text
                    + "\n`\(container)` was left in place"
                    + (laterSteps > 0 ? "; \(laterSteps) later step(s) were not attempted." : ".")
                    + "\nUp keeps a running container, so it will not run this hook again. "
                    + "Take the project down and bring it up once it is fixed."
            )
        }
    }

    /// The failure in Orchard's words: the hook, then its exit status and last output, or why
    /// it could not run.
    static func describe(_ failure: HookFailure) -> String {
        switch failure.reason {
        case .couldNotStart(let error):
            return "\(name(of: failure.hook)) could not run: \(error.localizedDescription)"
        case .exited(let status):
            var text = "\(name(of: failure.hook)) exited \(status)"
            if !failure.lastLines.isEmpty {
                text += "\nIts last output was:"
                for line in failure.lastLines { text += "\n    \(line)" }
            }
            return text
        }
    }
}
