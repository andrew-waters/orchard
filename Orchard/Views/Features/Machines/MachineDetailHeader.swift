import SwiftUI

// MARK: - Machine Detail Header
struct MachineDetailHeader: View {
    let machine: Machine
    @EnvironmentObject var machineService: MachineService
    @Environment(\.openWindow) private var openWindow
    @State private var showEditConfiguration = false
    /// Which lifecycle action is in flight, so its button shows progress and all disable.
    @State private var pending: PendingAction?

    enum PendingAction { case start, stop, setDefault, delete }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(machine.id)
                        .font(.title2)
                        .fontWeight(.semibold)
                    if machine.isDefault {
                        Text("DEFAULT")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .cornerRadius(4)
                    }
                }
                Text(machine.status.capitalized)
                    .font(.caption)
                    .foregroundStyle(machine.isRunning ? .green : .secondary)
            }
            Spacer()

            HStack(spacing: 12) {
                if machine.isStopped {
                    Button(pending == .start ? "Starting…" : "Start") {
                        run(.start) { await machineService.boot(machine.id) }
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .disabled(pending != nil)
                }
                if machine.isRunning {
                    Button(pending == .stop ? "Stopping…" : "Stop") {
                        run(.stop) { await machineService.stop(machine.id) }
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .disabled(pending != nil)
                }

                Button("Edit Configuration") {
                    showEditConfiguration = true
                }
                .buttonStyle(BorderedButtonStyle())
                .disabled(pending != nil)

                Button(pending == .setDefault ? "Setting…" : "Set Default") {
                    run(.setDefault) { await machineService.setDefault(machine.id) }
                }
                .buttonStyle(BorderedButtonStyle())
                .disabled(machine.isDefault || pending != nil)

                Button(pending == .delete ? "Deleting…" : "Delete", role: .destructive) {
                    confirmMachineDeletion()
                }
                .buttonStyle(BorderedButtonStyle())
                .disabled(pending != nil)

                Button("Logs") {
                    openWindow(id: "logs", value: LogTarget.machine(machine.id))
                }
                .buttonStyle(BorderedButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .sheet(isPresented: $showEditConfiguration) {
            EditMachineView(machine: machine)
        }
    }

    /// Run a lifecycle action with an in-flight state so its button shows progress and the
    /// others disable until it completes. Guards against overlapping actions.
    private func run(_ action: PendingAction, _ op: @escaping () async -> Void) {
        guard pending == nil else { return }
        pending = action
        Task {
            await op()
            await MainActor.run { pending = nil }
        }
    }

    private func confirmMachineDeletion() {
        let alert = NSAlert()
        alert.messageText = "Delete Machine"
        alert.informativeText = "Are you sure you want to delete '\(machine.id)'? This permanently removes the machine and its persistent storage."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            run(.delete) { await machineService.delete(machine.id) }
        }
    }
}
