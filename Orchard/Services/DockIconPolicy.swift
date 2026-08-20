import AppKit

/// Applies the Dock-icon preference by switching the app's activation policy at runtime:
/// `.accessory` hides the Dock icon (and removes the app from the Cmd-Tab switcher) while
/// the menu-bar extra keeps the app reachable; `.regular` restores it. Runtime policy
/// switching means the preference needs no relaunch, unlike `LSUIElement`.
///
/// Deliberately not a `SettingsStore` side effect: the store runs in unit tests on
/// ephemeral defaults, and flipping the test runner's activation policy from a setter
/// would be a nasty surprise. Callers (launch and the Settings toggle) apply it
/// explicitly instead.
@MainActor
enum DockIconPolicy {
    static func apply(hidden: Bool) {
        // NSApplication.shared, not the NSApp global: at the launch call site (App.init)
        // AppKit hasn't created the application object yet, so NSApp - an implicitly
        // unwrapped optional - is still nil and would crash. Accessing .shared creates it.
        let app = NSApplication.shared
        app.setActivationPolicy(hidden ? .accessory : .regular)
        if !hidden {
            // Returning to .regular needs an explicit activation for the Dock icon and
            // main menu to come back reliably - a long-standing AppKit quirk.
            app.activate(ignoringOtherApps: true)
        }
    }
}
