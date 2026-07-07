import SwiftUI

/// Create a container machine. Mirrors the `container machine create` options: image, name,
/// CPUs, memory (default = half of host RAM), home-mount mode, nested virtualization, an
/// optional custom kernel, set-default, and create-without-boot.
struct CreateMachineView: View {
    @EnvironmentObject var machineService: MachineService
    @Environment(\.dismiss) private var dismiss

    @State private var image: String = ""
    @State private var name: String = ""
    // Pre-filled with the runtime's defaults (≈ half the host) and bounded by host capacity.
    @State private var cpus: Int = max(ProcessInfo.processInfo.processorCount / 2, 1)
    @State private var memoryGiB: Int = max(Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) / 2, 1)

    private let hostCores = ProcessInfo.processInfo.processorCount
    private let hostGiB = max(1, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))
    @State private var homeMount: MachineHomeMount = .rw
    @State private var virtualization: Bool = false
    @State private var kernelPath: String = ""
    @State private var setDefault: Bool = false
    @State private var boot: Bool = true
    @State private var validationError: String?

    enum MachineHomeMount: String, CaseIterable, Identifiable {
        case rw, ro, none
        var id: String { rawValue }
        var label: String {
            switch self {
            case .rw: return "Read/Write"
            case .ro: return "Read-Only"
            case .none: return "None"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    field(title: "Image", caption: "A machine boots the image's init system (systemd/openrc) as PID 1 at /sbin/init. Stock images (ubuntu, alpine, nginx, …) have no init and will boot then immediately stop.") {
                        TextField("e.g., geerlingguy/docker-ubuntu2204-ansible", text: $image)
                            .textFieldStyle(.roundedBorder)
                    }

                    if MachineImageAdvisor.likelyLacksInit(image.trimmingCharacters(in: .whitespaces)) {
                        initWarning
                    }

                    field(title: "Name", caption: "Lowercase letters, digits, and hyphens.") {
                        TextField("e.g., dev-box", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(alignment: .top, spacing: 16) {
                        field(title: "CPUs", caption: "Cores allocated (host has \(hostCores)).") {
                            NumericStepperField(value: $cpus, range: 1...hostCores)
                        }
                        field(title: "Memory (GB)", caption: "RAM allocated (host has \(hostGiB) GB).") {
                            NumericStepperField(value: $memoryGiB, range: 1...hostGiB, unit: "GB")
                        }
                    }

                    field(title: "Home Directory Mount", caption: homeMountCaption) {
                        Picker("", selection: $homeMount) {
                            ForEach(MachineHomeMount.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Enable nested virtualization", isOn: $virtualization)
                        Text("Requires Apple silicon M3 or later, macOS 15+, and a CONFIG_KVM kernel.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    field(title: "Custom Kernel (Optional)", caption: "Path to a kernel binary (e.g. vmlinux). Leave empty for the system default.") {
                        TextField("/path/to/vmlinux", text: $kernelPath)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Set as default machine", isOn: $setDefault)
                    Toggle("Boot after creating", isOn: $boot)

                    if let validationError {
                        Text(validationError)
                            .font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }

            footer
        }
        .frame(width: 520, height: 640)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var initWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            SwiftUI.Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("This image likely has no init system")
                    .font(.subheadline).fontWeight(.medium)
                Text("It will probably boot and then immediately stop. Use an init-enabled image — e.g. geerlingguy/docker-ubuntu2204-ansible, or an image with systemd/openrc as /sbin/init.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var homeMountCaption: String {
        switch homeMount {
        case .rw: return "The machine gets full read/write access to your home directory."
        case .ro: return "The machine can read but not modify your home directory."
        case .none: return "Your home directory is not mounted into the machine."
        }
    }

    private var header: some View {
        HStack {
            Text("Create Machine").font(.title2).fontWeight(.semibold)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .bottom)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(machineService.isCreating ? "Creating…" : "Create Machine") { create() }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate || machineService.isCreating)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .top)
    }

    @ViewBuilder
    private func field<Content: View>(title: String, caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canCreate: Bool {
        !image.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func create() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedImage = image.trimmingCharacters(in: .whitespaces)

        // Machine names follow the same rule as the runtime: start/end alphanumeric, lowercase
        // letters/digits/hyphens only. Validate here for a fast, clear message.
        let pattern = "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"
        guard trimmedName.range(of: pattern, options: .regularExpression) != nil else {
            validationError = "Invalid name. Use lowercase letters, digits, and hyphens (must start and end alphanumeric)."
            return
        }
        validationError = nil

        let spec = MachineCreateSpec(
            name: trimmedName,
            imageRef: trimmedImage,
            cpus: cpus,
            memoryGiB: memoryGiB,
            homeMount: homeMount.rawValue,
            virtualization: virtualization,
            kernelPath: kernelPath.trimmingCharacters(in: .whitespaces).isEmpty ? nil : kernelPath.trimmingCharacters(in: .whitespaces),
            setDefault: setDefault,
            noBoot: !boot
        )

        Task {
            let created = await machineService.create(spec)
            if created { await MainActor.run { dismiss() } }
        }
    }
}
