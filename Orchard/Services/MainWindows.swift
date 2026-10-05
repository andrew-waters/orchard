import AppKit

/// The app's main windows, so the menu bar can bring one forward instead of opening another.
///
/// `openWindow(id: "main")` always creates a window for a `WindowGroup`, even when one is
/// already open. The group stays a `WindowGroup` because more than one main window is
/// allowed (File > New Window); this is only what "Open Orchard" consults first.
@MainActor
enum MainWindows {
    /// Weak, so a window SwiftUI tears down drops out on its own.
    private static let windows = NSHashTable<NSWindow>.weakObjects()

    static func register(_ window: NSWindow) {
        windows.add(window)
    }

    /// Bring the frontmost open main window forward, restoring it if it is minimised.
    /// Returns false when there is none to show, and the caller should open one.
    @discardableResult
    static func bringToFront() -> Bool {
        // A hidden app reports its windows as not visible, which would read as closed.
        if NSApp.isHidden { NSApp.unhide(nil) }

        let registered = windows.allObjects
        // A closed window can outlive its close, so only one still on screen or in the Dock counts.
        let open = registered.filter { $0.isVisible || $0.isMiniaturized }
        let window = NSApp.orderedWindows.first { open.contains($0) } ?? open.first
        guard let window else { return false }

        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        return true
    }
}
