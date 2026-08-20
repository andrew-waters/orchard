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

    func dismiss() {
        current = nil
    }
}
