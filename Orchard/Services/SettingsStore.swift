import Foundation
import AppKit

/// Owns user settings: the `container` binary path and the preferred terminal.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var customBinaryPath: String?
    @Published var preferredTerminal: TerminalApp = .terminal
    @Published var installedTerminals: [TerminalApp] = [.terminal]

    private let alertCenter: AlertCenter

    private let fallbackBinaryPath = "/usr/local/bin/container"
    private let candidateBinaryPaths: [String] = [
        "/usr/local/bin/container",
        "/opt/homebrew/bin/container",
        "\(NSHomeDirectory())/.nix-profile/bin/container",
        "\(NSHomeDirectory())/.local/bin/container",
    ]
    private var defaultBinaryPath: String {
        candidateBinaryPaths.first(where: { validateBinaryPath($0) }) ?? fallbackBinaryPath
    }
    private let customBinaryPathKey = "OrchardCustomBinaryPath"
    private let preferredTerminalKey = "OrchardPreferredTerminal"

    var containerBinaryPath: String {
        let path = customBinaryPath ?? defaultBinaryPath
        return validateBinaryPath(path) ? path : defaultBinaryPath
    }

    var isUsingCustomBinary: Bool {
        guard let customPath = customBinaryPath else { return false }
        return customPath != defaultBinaryPath && validateBinaryPath(customPath)
    }

    init(alertCenter: AlertCenter) {
        self.alertCenter = alertCenter
        loadCustomBinaryPath()
        loadPreferredTerminal()
    }

    private func loadCustomBinaryPath() {
        let userDefaults = UserDefaults.standard
        if let savedPath = userDefaults.string(forKey: customBinaryPathKey), !savedPath.isEmpty {
            customBinaryPath = savedPath
        }
    }

    func setCustomBinaryPath(_ path: String?) {
        customBinaryPath = path
        let userDefaults = UserDefaults.standard
        if let path = path, !path.isEmpty {
            userDefaults.set(path, forKey: customBinaryPathKey)
        } else {
            userDefaults.removeObject(forKey: customBinaryPathKey)
        }
    }

    func resetToDefaultBinary() {
        setCustomBinaryPath(nil)
    }

    func validateAndSetCustomBinaryPath(_ path: String?) -> Bool {
        guard let path = path, !path.isEmpty else {
            setCustomBinaryPath(nil)
            return true
        }

        if validateBinaryPath(path) {
            // If the selected path is the same as default, treat it as default
            if path == defaultBinaryPath {
                setCustomBinaryPath(nil)
            } else {
                setCustomBinaryPath(path)
            }
            return true
        } else {
            return false
        }
    }

    private func loadPreferredTerminal() {
        installedTerminals = TerminalApp.installedTerminals

        let userDefaults = UserDefaults.standard
        if let savedTerminal = userDefaults.string(forKey: preferredTerminalKey),
           let terminal = TerminalApp(rawValue: savedTerminal),
           terminal.isInstalled {
            preferredTerminal = terminal
        } else if let firstInstalled = installedTerminals.first {
            preferredTerminal = firstInstalled
        }
    }

    func setPreferredTerminal(_ terminal: TerminalApp) {
        preferredTerminal = terminal
        let userDefaults = UserDefaults.standard
        userDefaults.set(terminal.rawValue, forKey: preferredTerminalKey)
    }

    private func validateBinaryPath(_ path: String) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }

        guard fileManager.isExecutableFile(atPath: path) else {
            return false
        }

        return true
    }

    /// The binary path to use, falling back to the default (and clearing an invalid
    /// custom path) if the current one is unusable.
    func safeContainerBinaryPath() -> String {
        let currentPath = customBinaryPath ?? defaultBinaryPath

        if validateBinaryPath(currentPath) {
            return currentPath
        } else {
            if customBinaryPath != nil {
                let fallback = defaultBinaryPath
                DispatchQueue.main.async {
                    self.customBinaryPath = nil
                    self.alertCenter.error("Invalid binary path detected. Reset to default: \(fallback)")
                }
                UserDefaults.standard.removeObject(forKey: customBinaryPathKey)
            }
            return defaultBinaryPath
        }
    }
}
