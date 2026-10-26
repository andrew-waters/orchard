import AppKit

/// Applies the Dock-icon preference by switching the app's activation policy at runtime.
/// With the icon hidden, Orchard is `.regular` while any of its windows is open, so it has
/// its menu bar, full screen and a place in Cmd-Tab, and `.accessory` once the last one
/// closes, leaving only the menu-bar extra (#142). An accessory app gets no menu bar of its
/// own, so staying `.accessory` with a window open left the previous app's menu showing.
/// Runtime policy switching means the preference needs no relaunch, unlike `LSUIElement`.
///
/// Deliberately not a `SettingsStore` side effect: the store runs in unit tests on
/// ephemeral defaults, and flipping the test runner's activation policy from a setter
/// would be a nasty surprise. Callers (launch and the Settings toggle) apply it
/// explicitly instead.
@MainActor
enum DockIconPolicy {
    private static var hidden = false
    private static var observers: [NSObjectProtocol] = []

    static func apply(hidden: Bool) {
        self.hidden = hidden
        if hidden { startObserving() } else { stopObserving() }
        update()
    }

    /// Re-evaluates the policy whenever a window comes forward or closes. Key covers a
    /// window opening, being clicked or being restored from the Dock.
    private static func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { update() }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
                // The closing window is still on screen when this fires, so leave it out.
                let closing = note.object as? NSWindow
                MainActor.assumeIsolated { update(excluding: closing) }
            },
        ]
    }

    private static func stopObserving() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private static func update(excluding closing: NSWindow? = nil) {
        // NSApplication.shared, not the NSApp global: at the launch call site (App.init)
        // AppKit hasn't created the application object yet, so NSApp - an implicitly
        // unwrapped optional - is still nil and would crash. Accessing .shared creates it.
        let app = NSApplication.shared
        let regular = !hidden || app.windows.contains { $0 !== closing && isAppWindow($0) }
        let policy: NSApplication.ActivationPolicy = regular ? .regular : .accessory
        guard app.activationPolicy() != policy else { return }
        app.setActivationPolicy(policy)
        if regular {
            // Returning to .regular needs an explicit activation for the Dock icon and
            // main menu to come back reliably - a long-standing AppKit quirk.
            app.activate(ignoringOtherApps: true)
        }
    }

    /// A main, logs or Settings window that is open, minimised included. Panels, the
    /// menu-bar extra's among them, and untitled utility windows don't keep the Dock icon.
    private static func isAppWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel)
            && window.styleMask.contains(.titled)
            && (window.isVisible || window.isMiniaturized)
    }
}
