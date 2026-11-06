import SwiftUI
import AppKit

extension EnvironmentValues {
    /// Whether the window hosting this view is in full screen. Set by `tracksWindowFullScreen()`.
    ///
    /// The main window's columns lay their headers into the title bar row, which is transparent
    /// in a window. In full screen AppKit draws the title bar and toolbar as a strip over that
    /// row, so layouts read this to keep their headers below it (#167).
    @Entry var isWindowFullScreen: Bool = false
}

extension View {
    /// Follows the hosting window in and out of full screen and publishes it as
    /// `isWindowFullScreen` to this view's hierarchy.
    func tracksWindowFullScreen() -> some View {
        modifier(WindowFullScreenTracker())
    }
}

private struct WindowFullScreenTracker: ViewModifier {
    @State private var window: NSWindow?
    @State private var isFullScreen = false

    func body(content: Content) -> some View {
        content
            .environment(\.isWindowFullScreen, isFullScreen)
            .background(WindowAccessor { resolved in
                guard resolved !== window else { return }
                window = resolved
                // A window restored straight into full screen sends no notification.
                isFullScreen = resolved?.styleMask.contains(.fullScreen) ?? false
            })
            // The "will" notifications, so the layout changes with the transition rather than
            // jumping once it has finished. Each window has its own tracker, so only this
            // window's notifications count.
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { note in
                if let window, note.object as? NSWindow === window { isFullScreen = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { note in
                if let window, note.object as? NSWindow === window { isFullScreen = false }
            }
    }
}
