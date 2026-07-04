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

    func openTerminal(for containerId: String, shell: String = "sh") {
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
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalApp.ghostty.bundleIdentifier) else {
            Log.ui.error("❌ Ghostty application not found")
            alertCenter.error("Ghostty application not found")
            return
        }

        // Use 'open -na' to always open a new window, even if Ghostty is already running.
        // Pass the command via 'sh -c' to avoid Ghostty's argument parsing issues.
        let fullCommand = "'\(containerBinary)' exec -it '\(containerId)' \(shell)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-na", appURL.path, "--args", "-e", "sh", "-c", fullCommand]

        do {
            try process.run()
            Log.ui.debug("✓ Ghostty opened successfully")
        } catch {
            Log.ui.error("❌ Failed to open Ghostty: \(error.localizedDescription)")
            alertCenter.error("Failed to open Ghostty: \(error.localizedDescription)")
        }
    }

    private func executeAppleScript(_ script: String) {
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        let result = appleScript?.executeAndReturnError(&error)

        if let error = error {
            Log.ui.error("❌ AppleScript error: \(String(describing: error))")
            alertCenter.error("Failed to open terminal: \(String(describing: error))")
        } else if let result = result {
            Log.ui.debug("✓ AppleScript executed: \(String(describing: result))")
        }
    }
}
