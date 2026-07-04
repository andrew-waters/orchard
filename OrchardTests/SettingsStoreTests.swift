import Testing
import Foundation
@testable import Orchard

// SettingsStore validates paths against the real filesystem (stable system paths only:
// /bin/sh is always an executable file; the container default is never /bin/sh) and
// persists to an injected UserDefaults. Tests back it with a throwaway suite, cleaned up
// after each test, so the host's real `.standard` domain is never read or mutated.

private let binaryKey = "OrchardCustomBinaryPath"
private let terminalKey = "OrchardPreferredTerminal"

/// Run `body` with a `SettingsStore` on a throwaway suite (and the raw suite, for the few
/// tests that pre-seed or re-init). The suite is removed afterwards.
@MainActor
private func withSettingsStore(_ body: (SettingsStore, UserDefaults) -> Void) {
    let name = "OrchardTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    body(SettingsStore(alertCenter: AlertCenter(), defaults: defaults), defaults)
}

// MARK: - validateAndSetCustomBinaryPath

@MainActor
@Test("Binary path: nil clears the custom path and is not treated as custom")
func binaryPathNilClears() {
    withSettingsStore { store, _ in
        #expect(store.validateAndSetCustomBinaryPath(nil) == true)
        #expect(store.customBinaryPath == nil)
        #expect(store.isUsingCustomBinary == false)
    }
}

@MainActor
@Test("Binary path: an empty string is treated as nil")
func binaryPathEmptyIsNil() {
    withSettingsStore { store, _ in
        #expect(store.validateAndSetCustomBinaryPath("") == true)
        #expect(store.customBinaryPath == nil)
    }
}

@MainActor
@Test("Binary path: a nonexistent path is rejected and leaves the custom path unset")
func binaryPathInvalidRejected() {
    withSettingsStore { store, _ in
        #expect(store.validateAndSetCustomBinaryPath("/nonexistent/definitely-not-here") == false)
        #expect(store.customBinaryPath == nil)
    }
}

@MainActor
@Test("Binary path: a valid non-default executable is accepted, used, and persisted")
func binaryPathValidAcceptedAndPersisted() {
    withSettingsStore { store, defaults in
        #expect(store.validateAndSetCustomBinaryPath("/bin/sh") == true)
        #expect(store.customBinaryPath == "/bin/sh")
        #expect(store.isUsingCustomBinary == true)
        #expect(store.containerBinaryPath == "/bin/sh")
        // The one raw-key assertion — pins the persisted key name; other persistence
        // checks below go through a fresh store instead.
        #expect(defaults.string(forKey: binaryKey) == "/bin/sh")
    }
}

@MainActor
@Test("Binary path: reset clears the custom path, and the removal persists to a fresh store")
func binaryPathResetClears() {
    withSettingsStore { store, defaults in
        _ = store.validateAndSetCustomBinaryPath("/bin/sh")

        store.resetToDefaultBinary()

        #expect(store.customBinaryPath == nil)
        #expect(store.isUsingCustomBinary == false)
        // A fresh store must not resurrect the path — proves the key was actually removed.
        let reloaded = SettingsStore(alertCenter: AlertCenter(), defaults: defaults)
        #expect(reloaded.customBinaryPath == nil)
    }
}

@MainActor
@Test("Binary path: an invalid custom path falls back to the default when resolved")
func binaryPathInvalidFallsBack() {
    withSettingsStore { store, _ in
        store.setCustomBinaryPath("/nonexistent/xyz")   // bypasses validation

        #expect(store.containerBinaryPath != "/nonexistent/xyz")   // resolved to default
        #expect(store.isUsingCustomBinary == false)
    }
}

// MARK: - init reads persisted state

@MainActor
@Test("Binary path: a persisted custom path is loaded on init")
func binaryPathLoadedOnInit() {
    withSettingsStore { _, defaults in
        defaults.set("/bin/sh", forKey: binaryKey)

        let store = SettingsStore(alertCenter: AlertCenter(), defaults: defaults)

        #expect(store.customBinaryPath == "/bin/sh")
    }
}

// MARK: - preferred terminal

@MainActor
@Test("Preferred terminal: setting persists to the store")
func preferredTerminalPersists() {
    withSettingsStore { store, defaults in
        store.setPreferredTerminal(.terminal)   // Apple Terminal is always installed

        #expect(store.preferredTerminal == .terminal)
        #expect(defaults.string(forKey: terminalKey) == TerminalApp.terminal.rawValue)
        // No fresh-store round-trip assertion: `.terminal` is the default AND the
        // always-installed first fallback, so a reloaded store returns it whether or not
        // the persisted value is read — the read path can't be falsifiably round-tripped.
    }
}
