import Foundation

struct AlertButton: Identifiable, Equatable {
    let text: String
    let url: URL?
    
    var id: String { text + (url?.absoluteString ?? "") }
}

/// A single alert to present to the user.
struct AppAlert: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let date: Date
    let extraButtons: [AlertButton]
}

/// Where an error came from, which decides whether it's allowed to interrupt the user.
enum AlertSource {
    /// A user-initiated action (button press, explicit refresh). May present a modal.
    case user
    /// A background poll / auto-refresh. Never presents a modal and never dismisses one.
    case background
}

/// Owns the app's current user-facing alert. Errors from *user* actions are presented as a
/// native modal; errors from *background* polls are logged only — otherwise the 1–5s
/// refresh timers would storm modals and dismiss ones the user is mid-read. Success is
/// conveyed by the UI updating, not by an alert.
@MainActor
final class AlertCenter: ObservableObject {
    @Published var current: AppAlert?
    /// The alert a pending `dismiss()` will clear. Deliberately not `@Published`: it is set
    /// from inside SwiftUI's view update, where publishing is what `dismiss()` avoids.
    private var dismissingID: UUID?

    /// Whether an alert should be on screen. Drives the alert's `isPresented` binding, and goes
    /// false as soon as `dismiss()` is called rather than when its deferred clear lands, so a
    /// re-render in between cannot present the dismissed alert again.
    var isPresenting: Bool {
        guard let current else { return false }
        return current.id != dismissingID
    }

    func error(_ message: String, source: AlertSource = .user, alertButtons: [AlertButton] = []) {
        guard source == .user else {
            Log.ui.debug("suppressed background alert: \(message)")
            return
        }
        current = AppAlert(message: message, date: Date(), extraButtons: alertButtons)
    }

    func error(_ error: OrchardError, source: AlertSource = .user) {
        self.error(error.errorDescription ?? "Something went wrong.", source: source)
    }

    @discardableResult
    func dismiss() -> Task<Void, Never> {
        // Called from the alert's isPresented binding while SwiftUI is still applying that
        // alert's own presentation update, so publishing synchronously here trips "Publishing
        // changes from within view updates". Hopping through a Task defers it past that update.
        // The returned Task lets callers (tests) await the actual completion instead of guessing
        // at scheduling order.
        let dismissedID = current?.id
        dismissingID = dismissedID
        return Task { [weak self] in
            guard let self, dismissedID != nil, self.current?.id == dismissedID else { return }
            self.current = nil
        }
    }
}
