import SwiftUI

struct MachinesListView: View {
    @EnvironmentObject var machineService: MachineService
    @Binding var selectedMachine: String?
    @Binding var lastSelectedMachine: String?
    @Binding var searchText: String
    @Binding var showAddMachineSheet: Bool
    @FocusState var listFocusedTab: TabSelection?

    private var filteredMachines: [Machine] {
        guard !searchText.isEmpty else { return machineService.machines }
        let query = searchText.lowercased()
        return machineService.machines.filter { $0.id.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            contentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddMachineSheet) {
            CreateMachineView()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if machineService.apiUnavailable {
            unavailableStateView
        } else if machineService.isLoading && machineService.machines.isEmpty {
            loadingView
        } else if machineService.machines.isEmpty {
            emptyStateView
        } else {
            machinesListView
        }
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
                .padding()
            Text("Loading machines...")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack {
            SwiftUI.Image(systemName: "cpu")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            Text("No Machines")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Create a container machine to get started")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Create Machine") { showAddMachineSheet = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableStateView: some View {
        VStack(spacing: 6) {
            SwiftUI.Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("Machines Unavailable")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Update your `container` install (1.0 or later) to use machines.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var machinesListView: some View {
        List(selection: $selectedMachine) {
            ForEach(filteredMachines, id: \.id) { machine in
                MachineRowView(machine: machine, isSelected: selectedMachine == machine.id)
                    .contextMenu {
                        if machine.isStopped {
                            Button("Start Machine") {
                                Task { await machineService.boot(machine.id) }
                            }
                        }
                        if machine.isRunning {
                            Button("Stop Machine") {
                                Task { await machineService.stop(machine.id) }
                            }
                        }
                        if !machine.isDefault {
                            Button("Set as Default") {
                                Task { await machineService.setDefault(machine.id) }
                            }
                        }
                        Divider()
                        Button("Delete Machine", role: .destructive) {
                            confirmMachineDeletion(machine)
                        }
                    }
                    .tag(machine.id)
            }
        }
        .listStyle(PlainListStyle())
        .animation(.easeInOut(duration: 0.3), value: machineService.machines)
        .focused($listFocusedTab, equals: .machines)
        .onChange(of: selectedMachine) { _, newValue in
            lastSelectedMachine = newValue
        }
    }

    private struct MachineRowView: View {
        let machine: Machine
        let isSelected: Bool

        var body: some View {
            let primary = machine.isDefault ? "\(machine.id)  ★" : machine.id
            ListItemRow(
                icon: "cpu",
                iconColor: machine.isRunning ? .green : .secondary,
                primaryText: primary,
                secondaryLeftText: machine.status.capitalized,
                secondaryRightText: machine.ipAddress ?? "—",
                isSelected: isSelected
            )
        }
    }

    private func confirmMachineDeletion(_ machine: Machine) {
        let alert = NSAlert()
        alert.messageText = "Delete Machine"
        alert.informativeText = "Are you sure you want to delete '\(machine.id)'? This permanently removes the machine and its persistent storage."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            Task { await machineService.delete(machine.id) }
        }
    }
}
