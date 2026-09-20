import Foundation
import AppKit

/// Owns user settings: the `container` binary path, the preferred terminal, the shell a
/// container terminal opens with, and the Dock-icon preference.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var customBinaryPath: String?
    @Published var preferredTerminal: TerminalApp = .terminal
    /// What to run inside the container when opening a terminal, flags and all: `sh` by
    /// default, but `bash -l` or `zsh -l` for anyone who wants their rc files read. Stored
    /// as written and passed through, because which shells exist and which flags they take
    /// is a property of the image, not something Orchard can enumerate.
    @Published private(set) var containerShell: String = SettingsStore.defaultContainerShell
    /// Whether the app hides its Dock icon and runs as a menu-bar accessory. Persisted
    /// here; the activation-policy side effect is applied by callers via
    /// `DockIconPolicy` (see that type for why it isn't applied from the setter).
    @Published private(set) var hideDockIcon: Bool = false
    @Published var installedTerminals: [TerminalApp] = [.terminal]

    private let alertCenter: AlertCenter
    /// Backing store for persisted settings. Production uses `.standard`; tests inject an
    /// ephemeral suite so they never read or mutate the real user domain.
    private let defaults: UserDefaults
    /// Credential storage for model-server API keys. Keychain in production; tests
    /// inject the in-memory variant.
    private let secrets: SecretsStore

    private let fallbackBinaryPath = "/usr/local/bin/container"
    private let candidateBinaryPaths: [String] = [
        "/usr/local/bin/container",
        "/opt/homebrew/bin/container",
        "\(NSHomeDirectory())/.nix-profile/bin/container",
        "\(NSHomeDirectory())/.local/bin/container",
    ]
    /// Cache the resolved default so we don't stat up to four candidate paths on every
    /// CLI call. Invalidated when the binary configuration changes.
    private var cachedDefaultBinaryPath: String?
    private var defaultBinaryPath: String {
        if let cached = cachedDefaultBinaryPath { return cached }
        let resolved = candidateBinaryPaths.first(where: { validateBinaryPath($0) }) ?? fallbackBinaryPath
        cachedDefaultBinaryPath = resolved
        return resolved
    }
    private let customBinaryPathKey = "OrchardCustomBinaryPath"
    private let preferredTerminalKey = "OrchardPreferredTerminal"
    private let containerShellKey = "OrchardContainerShell"
    private let modelEndpointsKey = "OrchardModelEndpoints"

    /// `sh` rather than a login shell: it is the one shell a minimal image is likely to
    /// have, which is what makes it a safe default rather than a good one.
    static let defaultContainerShell = "sh"
    /// Static so the app can read the launch policy straight from defaults before any
    /// services are built.
    static let hideDockIconDefaultsKey = "OrchardHideDockIcon"

    var containerBinaryPath: String {
        let path = customBinaryPath ?? defaultBinaryPath
        return validateBinaryPath(path) ? path : defaultBinaryPath
    }

    var isUsingCustomBinary: Bool {
        guard let customPath = customBinaryPath else { return false }
        return customPath != defaultBinaryPath && validateBinaryPath(customPath)
    }

    init(alertCenter: AlertCenter, defaults: UserDefaults = .standard, secrets: SecretsStore = KeychainSecretsStore()) {
        self.secrets = secrets
        self.alertCenter = alertCenter
        self.defaults = defaults
        loadCustomBinaryPath()
        loadPreferredTerminal()
        loadContainerShell()
        loadModelEndpoints()
        hideDockIcon = defaults.bool(forKey: Self.hideDockIconDefaultsKey)
    }

    func setHideDockIcon(_ hidden: Bool) {
        hideDockIcon = hidden
        defaults.set(hidden, forKey: Self.hideDockIconDefaultsKey)
    }

    private func loadCustomBinaryPath() {
        if let savedPath = defaults.string(forKey: customBinaryPathKey), !savedPath.isEmpty {
            customBinaryPath = savedPath
        }
    }

    func setCustomBinaryPath(_ path: String?) {
        customBinaryPath = path
        cachedDefaultBinaryPath = nil   // re-detect on any binary-config change
        if let path = path, !path.isEmpty {
            defaults.set(path, forKey: customBinaryPathKey)
        } else {
            defaults.removeObject(forKey: customBinaryPathKey)
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

        if let savedTerminal = defaults.string(forKey: preferredTerminalKey),
           let terminal = TerminalApp(rawValue: savedTerminal),
           terminal.isInstalled {
            preferredTerminal = terminal
        } else if let firstInstalled = installedTerminals.first {
            preferredTerminal = firstInstalled
        }
    }

    func setPreferredTerminal(_ terminal: TerminalApp) {
        preferredTerminal = terminal
        defaults.set(terminal.rawValue, forKey: preferredTerminalKey)
    }

    private func loadContainerShell() {
        let saved = defaults.string(forKey: containerShellKey)?.trimmingCharacters(in: .whitespaces)
        containerShell = (saved?.isEmpty == false ? saved! : Self.defaultContainerShell)
    }

    /// Set the shell a container terminal opens with. Blank resets to the default rather
    /// than leaving an empty command that would open a terminal onto nothing.
    func setContainerShell(_ shell: String) {
        let trimmed = shell.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            containerShell = Self.defaultContainerShell
            defaults.removeObject(forKey: containerShellKey)
        } else {
            containerShell = trimmed
            defaults.set(trimmed, forKey: containerShellKey)
        }
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
                defaults.removeObject(forKey: customBinaryPathKey)
            }
            return defaultBinaryPath
        }
    }

    // MARK: - Model endpoints

    /// The addresses discovery probes, in list order. Seeded from the built-in defaults on
    /// first run and persisted thereafter, so a user who has edited or switched one off
    /// keeps that across launches (#110).
    @Published private(set) var modelEndpoints: [ModelEndpoint] = ModelEndpoint.builtIns

    private func loadModelEndpoints() {
        guard let data = defaults.data(forKey: modelEndpointsKey),
              let stored = try? JSONDecoder().decode([ModelEndpoint].self, from: data),
              !stored.isEmpty else {
            modelEndpoints = ModelEndpoint.builtIns
            return
        }
        // A built-in added in a later release won't be in an older stored list. Append the
        // newcomers rather than replacing the list, so a release that learns to detect
        // another server doesn't discard the user's edits to the ones they already had.
        let known = Set(stored.map(\.id))
        modelEndpoints = stored + ModelEndpoint.builtIns.filter { !known.contains($0.id) }
    }

    private func persistModelEndpoints() {
        guard let data = try? JSONEncoder().encode(modelEndpoints) else { return }
        defaults.set(data, forKey: modelEndpointsKey)
    }

    /// Replace one endpoint's configuration, matched by id. Unknown ids are ignored rather
    /// than appended: every endpoint originates from this store, so an id it doesn't hold
    /// is stale UI state, not a new endpoint.
    func updateModelEndpoint(_ endpoint: ModelEndpoint) {
        guard let index = modelEndpoints.firstIndex(where: { $0.id == endpoint.id }) else { return }
        guard modelEndpoints[index] != endpoint else { return }
        modelEndpoints[index] = endpoint
        persistModelEndpoints()
    }

    func setModelEndpointEnabled(_ enabled: Bool, id: String) {
        guard var endpoint = modelEndpoints.first(where: { $0.id == id }), endpoint.isEnabled != enabled else { return }
        endpoint.isEnabled = enabled
        updateModelEndpoint(endpoint)
    }

    /// Put a built-in endpoint back on the address it shipped with, leaving its enabled
    /// state alone. A no-op for anything that isn't a built-in.
    func restoreDefaultModelEndpoint(id: String) {
        guard var endpoint = modelEndpoints.first(where: { $0.id == id }),
              let original = endpoint.builtInDefault else { return }
        endpoint.host = original.host
        endpoint.port = original.port
        endpoint.api = original.api
        updateModelEndpoint(endpoint)
    }

    // MARK: - Model provider API keys

    /// Per-endpoint API keys for local model servers (e.g. an oMLX install that generated
    /// one at setup). Keyed by address, the one identity that survives the endpoint list
    /// being reseeded. Stored in the keychain, not UserDefaults - they're credentials, and
    /// the bridge injects them into containers that may be internet-enabled.
    func modelAPIKey(host: String = ModelEndpoint.defaultHost, port: UInt16) -> String? {
        if let key = secrets.secret(for: account(host, port)) { return key }
        // Keys written before endpoints were configurable were accounted by bare port,
        // and every endpoint was on this Mac then. Only a loopback address inherits one:
        // an endpoint the user has re-pointed elsewhere must not carry a credential
        // issued for this machine to someone else's server, which is where it would go
        // next, both as a bearer token on the probe and as OPENAI_API_KEY in a container.
        guard ModelEndpoint.isLoopback(host) else { return nil }
        return secrets.secret(for: String(port))
    }

    private func account(_ host: String, _ port: UInt16) -> String { "\(host):\(port)" }

    /// Throws when the keychain refuses the write, so the caller can say so rather than
    /// leave the user unable to tell a rejected key from a rejected save.
    func setModelAPIKey(_ key: String?, host: String = ModelEndpoint.defaultHost, port: UInt16) throws {
        try secrets.setSecret(key, for: account(host, port))
        // Clearing has to take the legacy account with it, or the fallback read above
        // would resurrect a key the user just removed. Only for a loopback address,
        // matching what that fallback will actually read: clearing a remote endpoint's
        // key has no business deleting a legacy key that belongs to this Mac.
        if key?.isEmpty ?? true, ModelEndpoint.isLoopback(host) {
            try secrets.setSecret(nil, for: String(port))
        }
        objectWillChange.send()
    }

    /// The stored keys for `endpoints`, keyed by endpoint id, for the detection probe.
    func modelAPIKeys(for endpoints: [ModelEndpoint]) -> [String: String] {
        var result: [String: String] = [:]
        for endpoint in endpoints {
            if let key = modelAPIKey(host: endpoint.host, port: endpoint.port) {
                result[endpoint.id] = key
            }
        }
        return result
    }
}
