import Testing
import Foundation
@testable import Orchard

// SettingsStore persists to UserDefaults.standard and validates paths against the real
// filesystem. To avoid touching the host's real settings, each test snapshots and restores
// the two keys the store owns, and uses stable system paths (/bin/sh is always an
// executable file; the container default is never /bin/sh) for validation.

private let binaryKey = "OrchardCustomBinaryPath"
private let terminalKey = "OrchardPreferredTerminal"

/// Clear the store's UserDefaults keys for the duration of `body`, then restore them.
@MainActor
private func withIsolatedSettingsDefaults(_ body: () -> Void) {
    let d = UserDefaults.standard
    let keys = [binaryKey, terminalKey]
    let saved = keys.map { d.object(forKey: $0) }
    keys.forEach { d.removeObject(forKey: $0) }
    defer {
        for (key, value) in zip(keys, saved) {
            if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
        }
    }
    body()
}

// MARK: - validateAndSetCustomBinaryPath

@MainActor
@Test("Binary path: nil clears the custom path and is not treated as custom")
func binaryPathNilClears() {
    withIsolatedSettingsDefaults {
        let store = SettingsStore(alertCenter: AlertCenter())

        #expect(store.validateAndSetCustomBinaryPath(nil) == true)
        #expect(store.customBinaryPath == nil)
        #expect(store.isUsingCustomBinary == false)
    }
}

@MainActor
@Test("Binary path: an empty string is treated as nil")
func binaryPathEmptyIsNil() {
    withIsolatedSettingsDefaults {
        let store = SettingsStore(alertCenter: AlertCenter())

        #expect(store.validateAndSetCustomBinaryPath("") == true)
        #expect(store.customBinaryPath == nil)
    }
}

@MainActor
@Test("Binary path: a nonexistent path is rejected and leaves the custom path unset")
func binaryPathInvalidRejected() {
    withIsolatedSettingsDefaults {
        let store = SettingsStore(alertCenter: AlertCenter())

        #expect(store.validateAndSetCustomBinaryPath("/nonexistent/definitely-not-here") == false)
        #expect(store.customBinaryPath == nil)
    }
}

@MainActor
@Test("Binary path: a valid non-default executable is accepted, used, and persisted")
func binaryPathValidAcceptedAndPersisted() {
    withIsolatedSettingsDefaults {
        let store = SettingsStore(alertCenter: AlertCenter())

        #expect(store.validateAndSetCustomBinaryPath("/bin/sh") == true)
        #expect(store.customBinaryPath == "/bin/sh")
        #expect(store.isUsingCustomBinary == true)
        #expect(store.containerBinaryPath == "/bin/sh")
        #expect(UserDefaults.standard.string(forKey: binaryKey) == "/bin/sh")
    }
}

@MainActor
@Test("Binary path: reset clears the custom path and removes the persisted key")
func binaryPathResetClears() {
    withIsolatedSettingsDefaults {
        let store = SettingsStore(alertCenter: AlertCenter())
        _ = store.validateAndSetCustomBinaryPath("/bin/sh")

        store.resetToDefaultBinary()

        #expect(store.customBinaryPath == nil)
        #expect(store.isUsingCustomBinary == false)
        #expect(UserDefaults.standard.string(forKey: binaryKey) == nil)
    }
}

@MainActor
@Test("Binary path: an invalid custom path falls back to the default when resolved")
func binaryPathInvalidFallsBack() {
    withIsolatedSettingsDefaults {
        let store = SettingsStore(alertCenter: AlertCenter())
        store.setCustomBinaryPath("/nonexistent/xyz")   // bypasses validation

        #expect(store.containerBinaryPath != "/nonexistent/xyz")   // resolved to default
        #expect(store.isUsingCustomBinary == false)
    }
}

// MARK: - init reads persisted state

@MainActor
@Test("Binary path: a persisted custom path is loaded on init")
func binaryPathLoadedOnInit() {
    withIsolatedSettingsDefaults {
        UserDefaults.standard.set("/bin/sh", forKey: binaryKey)

        let store = SettingsStore(alertCenter: AlertCenter())

        #expect(store.customBinaryPath == "/bin/sh")
    }
}

// MARK: - preferred terminal

@MainActor
@Test("Preferred terminal: setting persists and round-trips through a fresh store")
func preferredTerminalRoundTrips() {
    withIsolatedSettingsDefaults {
        let store = SettingsStore(alertCenter: AlertCenter())
        store.setPreferredTerminal(.terminal)   // Apple Terminal is always installed

        #expect(store.preferredTerminal == .terminal)
        #expect(UserDefaults.standard.string(forKey: terminalKey) == TerminalApp.terminal.rawValue)

        let reloaded = SettingsStore(alertCenter: AlertCenter())
        #expect(reloaded.preferredTerminal == .terminal)
    }
}
