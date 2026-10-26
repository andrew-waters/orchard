import AppKit

/// When Orchard shows its Dock icon. Hiding it means running as an accessory app, which
/// macOS gives no menu bar of its own and no proper full screen, so `whileWindowsOpen` is
/// the middle ground: a regular app while a window is open, menu-bar-only otherwise (#142).
enum DockIconMode: String, CaseIterable, Identifiable {
    case always
    case whileWindowsOpen
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: return "Always"
        case .whileWindowsOpen: return "While a Window Is Open"
        case .never: return "Never"
        }
    }

    /// Static so the app can read the launch policy straight from defaults before any
    /// services are built.
    static let defaultsKey = "OrchardDockIconMode"
    /// The Hide Dock icon toggle this replaced. Read only to carry an old choice over.
    static let legacyHiddenDefaultsKey = "OrchardHideDockIcon"

    /// The stored mode. A Hide Dock icon toggle left on before the modes existed becomes
    /// `whileWindowsOpen`, so nobody upgrades into the stuck state #142 reported.
    static func stored(in defaults: UserDefaults) -> DockIconMode {
        if let raw = defaults.string(forKey: defaultsKey), let mode = DockIconMode(rawValue: raw) {
            return mode
        }
        return defaults.bool(forKey: legacyHiddenDefaultsKey) ? .whileWindowsOpen : .always
    }
}

/// Applies the Dock-icon preference by switching the app's activation policy at runtime:
/// `.regular` shows the Dock icon, `.accessory` hides it (and removes the app from the
/// Cmd-Tab switcher and its main menu from the menu bar) while the menu-bar extra keeps
/// the app reachable. In `whileWindowsOpen` the policy follows Orchard's windows, so
/// they get their menu bar and full screen. Runtime policy switching means the
/// preference needs no relaunch, unlike `LSUIElement`.
///
/// Deliberately not a `SettingsStore` side effect: the store runs in unit tests on
/// ephemeral defaults, and flipping the test runner's activation policy from a setter
/// would be a nasty surprise. Callers (launch and the Settings picker) apply it
/// explicitly instead.
@MainActor
enum DockIconPolicy {
    private static var mode: DockIconMode = .always
    private static var observers: [NSObjectProtocol] = []
    private static var launchObserver: NSObjectProtocol?

    static func apply(_ mode: DockIconMode) {
        self.mode = mode
        if mode == .whileWindowsOpen { startObserving() } else { stopObserving() }
        update()
    }

    /// The launch-time apply, from App.init. Never applies straight away, so no window
    /// shows with a Dock icon. While a Window Is Open waits for launch to finish: no
    /// window exists yet, so evaluating now would drop to .accessory only for the main
    /// window to bring the icon back. After launch, one opened stays .regular and none
    /// leaves Orchard menu-bar-only.
    static func applyAtLaunch(_ mode: DockIconMode) {
        guard mode == .whileWindowsOpen else { return apply(mode) }
        self.mode = mode
        startObserving()
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                launchObserver.map(NotificationCenter.default.removeObserver)
                launchObserver = nil
                // One more hop: SwiftUI puts its first window on screen just after this.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { update() }
                }
            }
        }
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
        let regular: Bool
        switch mode {
        case .always: regular = true
        case .never: regular = false
        case .whileWindowsOpen:
            // A hidden app (Cmd-H) reports its windows as not visible. They're still open,
            // and the Dock icon is how they come back.
            regular = app.isHidden || app.windows.contains { $0 !== closing && isAppWindow($0) }
        }
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
