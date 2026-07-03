import Foundation

/// A single alert to present to the user.
struct AppAlert: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let date: Date
}

/// Owns the app's current user-facing alert. Errors are surfaced here and presented as a
/// native alert; success is conveyed by the UI updating, not by an alert.
@MainActor
final class AlertCenter: ObservableObject {
    @Published var current: AppAlert?

    func error(_ message: String, at date: Date = Date()) {
        current = AppAlert(message: message, date: date)
    }

    func error(_ error: OrchardError, at date: Date = Date()) {
        self.error(error.errorDescription ?? "Something went wrong.", at: date)
    }

    func dismiss() {
        current = nil
    }
}
