import SwiftUI

/// Edit a machine's boot configuration (CPUs, memory, home-mount, nested virtualization,
/// custom kernel). These take effect only on the next boot — for a running machine we offer
/// "Apply & Restart" to stop→apply→boot in one action, which the CLI makes you do by hand.
struct EditMachineView: View {
    let machine: Machine
    @EnvironmentObject var machineService: MachineService
    @Environment(\.dismiss) private var dismiss

    @State private var cpus: Int
    @State private var memoryGiB: Int
    @State private var homeMount: MachineHomeMount
    @State private var virtualization: Bool
    @State private var kernelPath: String
    @State private var validationError: String?
    /// Which action is in flight, so the buttons can show progress and disable.
    @State private var pending: PendingAction?

    enum PendingAction { case apply, restart }

    private let hostCores = ProcessInfo.processInfo.processorCount
    private let hostGiB = max(1, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))

    init(machine: Machine) {
        self.machine = machine
        _cpus = State(initialValue: machine.cpus)
        _memoryGiB = State(initialValue: max(1, machine.memoryBytes / 1_073_741_824))
        _homeMount = State(initialValue: MachineHomeMount(rawValue: machine.homeMount) ?? .rw)
        _virtualization = State(initialValue: machine.virtualization)
        _kernelPath = State(initialValue: machine.kernelPath ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        field(title: "CPUs") {
                            NumericStepperField(value: $cpus, range: 1...max(hostCores, cpus))
                        }
                        field(title: "Memory (GB)") {
                            NumericStepperField(value: $memoryGiB, range: 1...max(hostGiB, memoryGiB), unit: "GB")
                        }
                    }

                    field(title: "Home Directory Mount") {
                        Picker("", selection: $homeMount) {
                            ForEach(MachineHomeMount.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Toggle("Enable nested virtualization", isOn: $virtualization)

                    field(title: "Custom Kernel (Optional)") {
                        TextField("/path/to/vmlinux", text: $kernelPath).textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 8) {
                        SwiftUI.Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text(machine.isRunning
                             ? "Changes take effect after a restart. Use “Apply & Restart” to apply now."
                             : "Changes take effect the next time this machine boots.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let validationError {
                        Text(validationError).font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }

            footer
        }
        .frame(width: 500, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("Edit \(machine.id)").font(.title2).fontWeight(.semibold)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .bottom)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(pending != nil)
            if machine.isRunning {
                Button(pending == .apply ? "Applying…" : "Apply") { apply(restartNow: false) }
                    .buttonStyle(.bordered)
                    .disabled(pending != nil)
                Button(pending == .restart ? "Restarting…" : "Apply & Restart") { apply(restartNow: true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pending != nil)
            } else {
                Button(pending == .apply ? "Applying…" : "Apply") { apply(restartNow: false) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pending != nil)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .top)
    }

    @ViewBuilder
    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func apply(restartNow: Bool) {
        guard pending == nil else { return }
        guard cpus > 0 else {
            validationError = "CPUs must be a positive number."
            return
        }
        guard memoryGiB >= 1 else {
            validationError = "Memory must be at least 1 GB."
            return
        }
        validationError = nil

        let config = MachineConfigSpec(
            cpus: cpus,
            memoryGiB: memoryGiB,
            homeMount: homeMount.rawValue,
            virtualization: virtualization,
            kernelPath: kernelPath.trimmingCharacters(in: .whitespaces).isEmpty ? nil : kernelPath.trimmingCharacters(in: .whitespaces)
        )

        pending = restartNow ? .restart : .apply
        Task {
            let ok = await machineService.applyConfig(config, to: machine.id, restartNow: restartNow)
            await MainActor.run {
                pending = nil
                if ok { dismiss() }
            }
        }
    }
}
