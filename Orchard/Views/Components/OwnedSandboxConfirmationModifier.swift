import SwiftUI

extension View {
    /// Presents an `OwnedSandboxConfirmation` while `confirmation` is set, running its action
    /// only when confirmed.
    func ownedSandboxConfirmation(_ confirmation: Binding<OwnedSandboxConfirmation?>) -> some View {
        alert(
            confirmation.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { confirmation.wrappedValue != nil },
                set: { if !$0 { confirmation.wrappedValue = nil } }
            ),
            presenting: confirmation.wrappedValue
        ) { pending in
            Button("Cancel", role: .cancel) { }
            Button(pending.confirmTitle, role: .destructive) { pending.perform() }
        } message: { pending in
            Text(pending.message)
        }
    }
}

extension OwnedSandboxConfirmation {
    /// Run `perform` straight away when none of `containers` is a sandbox another app
    /// manages; otherwise put the confirmation in `pending` for the view to present.
    @MainActor
    static func run(
        _ action: Action,
        containers: [Container],
        pending: Binding<OwnedSandboxConfirmation?>,
        perform: @escaping () -> Void
    ) {
        if let confirmation = make(action, containers: containers, perform: perform) {
            pending.wrappedValue = confirmation
        } else {
            perform()
        }
    }
}
