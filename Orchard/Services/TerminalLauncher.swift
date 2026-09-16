import Foundation
import AppKit

/// Opens a container shell in the user's preferred terminal. Holds no published state;
/// conforms to `ObservableObject` only so it can be injected via `@EnvironmentObject`.
@MainActor
final class TerminalLauncher: ObservableObject {
    private let settings: SettingsStore
    private let alertCenter: AlertCenter

    init(settings: SettingsStore, alertCenter: AlertCenter) {
        self.settings = settings
        self.alertCenter = alertCenter
    }

    /// Open a shell in a container.
    ///
    /// `shell` defaults to whatever the user configured, flags and all, so someone who wants
    /// their rc files read can ask for `bash -l` once and have every terminal honour it
    /// (#107). Passing a value explicitly overrides the setting, which is what the bash
    /// action below does.
    func openTerminal(for containerId: String, shell: String? = nil) {
        let shell = shell ?? settings.containerShell
        let containerBinary = settings.safeContainerBinaryPath()
        let fullCommand = "'\(containerBinary)' exec -it '\(containerId)' \(shell)"

        Log.ui.debug("Opening terminal — terminal: \(self.settings.preferredTerminal.displayName), command: \(fullCommand)")

        switch settings.preferredTerminal {
        case .terminal:
            openInTerminalApp(command: fullCommand)
        case .iterm2:
            openInITerm2(command: fullCommand)
        case .ghostty:
            openInGhostty(containerBinary: containerBinary, containerId: containerId, shell: shell)
        }
    }

    func openTerminalWithBash(for containerId: String) {
        openTerminal(for: containerId, shell: "bash")
    }

    /// Open the user's preferred terminal running an arbitrary shell command (e.g. a
    /// kubectl session preconfigured for a cluster).
    func openTerminal(runningCommand command: String) {
        Log.ui.debug("Opening terminal — terminal: \(self.settings.preferredTerminal.displayName), command: \(command)")

        switch settings.preferredTerminal {
        case .terminal:
            openInTerminalApp(command: command)
        case .iterm2:
            openInITerm2(command: command)
        case .ghostty:
            openInGhostty(command: command)
        }
    }

    // MARK: - Terminal-specific openers

    private func openInTerminalApp(command: String) {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """

        executeAppleScript(script)
    }

    private func openInITerm2(command: String) {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application id "com.googlecode.iterm2"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text "\(escapedCommand)"
            end tell
        end tell
        """

        executeAppleScript(script)
    }

    private func openInGhostty(containerBinary: String, containerId: String, shell: String) {
        openInGhostty(command: "'\(containerBinary)' exec -it '\(containerId)' \(shell)")
    }

    /// Ghostty ships a scripting dictionary (1.3 and later), so it is driven the same way
    /// Terminal.app and iTerm2 are rather than through `open`.
    ///
    /// This used to run `open -na`, which could only ever produce a new window: `-n` starts a
    /// *separate instance* of Ghostty, and a window in one instance can never join a window in
    /// another. It also left a second Ghostty running for every container opened (#107).
    ///
    /// Whether the terminal arrives as a tab or a window follows the system-wide "Prefer tabs
    /// when opening documents" setting rather than a preference of Orchard's own: the user has
    /// already answered this question once, for every app, and a second answer here could only
    /// agree with it or contradict it.
    private func openInGhostty(command fullCommand: String) {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalApp.ghostty.bundleIdentifier) != nil else {
            Log.ui.error("❌ Ghostty application not found")
            alertCenter.error("Ghostty application not found")
            return
        }

        let escapedCommand = fullCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // `front window` is only asked for once a window is known to exist: with none open,
        // Ghostty has no front window to put a tab in.
        let script = """
        tell application id "\(TerminalApp.ghostty.bundleIdentifier)"
            activate
            set cfg to new surface configuration
            set command of cfg to "\(escapedCommand)"
            if \(prefersTabs) and (count of windows) > 0 then
                new tab in front window with configuration cfg
            else
                new window with configuration cfg
            end if
        end tell
        """

        executeAppleScript(script)
    }

    /// The system-wide "Prefer tabs when opening documents" setting, from System Settings ›
    /// Desktop & Dock. Unset means macOS's own default, `fullscreen`, which is not "always".
    private var prefersTabs: Bool {
        UserDefaults.standard.string(forKey: "AppleWindowTabbingMode") == "always"
    }

    private func executeAppleScript(_ script: String) {
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        let result = appleScript?.executeAndReturnError(&error)

        if let error = error {
            Log.ui.error("❌ AppleScript error: \(String(describing: error))")
            alertCenter.error(Self.userMessage(for: error))
        } else if let result = result {
            Log.ui.debug("✓ AppleScript executed: \(String(describing: result))")
        }
    }

    /// Translates an `NSAppleScript` error dictionary into something actionable.
    /// Automation refusals (errAEEventNotPermitted / errAEPrivilegeError) get pointed
    /// at System Settings instead of dumping the raw error dictionary (#64).
    nonisolated static func userMessage(for error: NSDictionary) -> String {
        let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
        let appName = (error[NSAppleScript.errorAppName] as? String) ?? "your terminal app"

        switch code {
        case -1743, -10004: // errAEEventNotPermitted, errAEPrivilegeError
            return """
            Orchard isn't authorized to control \(appName). \
            Allow it under System Settings → Privacy & Security → Automation → Orchard, \
            then try again.
            """
        case -600, -609: // procNotFound, connectionInvalid
            return "\(appName) isn't running and couldn't be launched. Open it once manually, then try again."
        default:
            // Never dump the raw error dictionary at the user; the full details are
            // already logged. Fall back to a stable message carrying the error code.
            let message = (error[NSAppleScript.errorBriefMessage] as? String)
                ?? (error[NSAppleScript.errorMessage] as? String)
                ?? "An unknown AppleScript error occurred (code \(code))."
            return "Failed to open terminal: \(message)"
        }
    }
}
