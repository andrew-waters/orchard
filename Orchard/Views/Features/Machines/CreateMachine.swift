import SwiftUI

/// Create a container machine. Mirrors the `container machine create` options: image, name,
/// CPUs, memory (default = half of host RAM), home-mount mode, the machine's account (1.6.0),
/// nested virtualization, an optional custom kernel, set-default, and create-without-boot.
struct CreateMachineView: View {
    @EnvironmentObject var machineService: MachineService
    @EnvironmentObject var systemService: SystemService
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
    // Account fields start empty: an empty one is left to the runtime's host-user default, so
    // only what the user typed is sent. The placeholders show those defaults.
    @State private var showAccount = false
    @State private var accountUser: String = ""
    @State private var accountUID: String = ""
    @State private var accountGID: String = ""
    @State private var accountHome: String = ""
    private let hostUser = NSUserName()
    private let hostUID = getuid()
    private let hostGID = getgid()
    @State private var validationError: String?

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

                    if supportsUserAccount {
                        accountGroup
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

    // Upstream's machine docs: the home folder is mounted at the same path, and root in the
    // machine (passwordless sudo) writes to it with your macOS user's permissions.
    private var homeMountCaption: String {
        switch homeMount {
        case .rw: return "Your Mac home folder is mounted at the same path. Anything in the machine, including root through passwordless sudo, can change your files with your permissions."
        case .ro: return "Your Mac home folder is mounted at the same path, read-only. The machine can read everything in it but not change it."
        case .none: return "Your Mac home folder is not mounted into the machine."
        }
    }

    // MARK: - Account

    private var supportsUserAccount: Bool {
        MachineService.supportsUserAccount(containerVersion: systemService.containerVersion)
    }

    /// Upstream defaults the home to `/home/<user>`, so the placeholder follows a typed user.
    private var homePlaceholder: String {
        let user = accountUser.trimmingCharacters(in: .whitespaces)
        return "/home/\(user.isEmpty ? hostUser : user)"
    }

    private var accountGroup: some View {
        DisclosureGroup("Account", isExpanded: $showAccount) {
            VStack(alignment: .leading, spacing: 20) {
                Text("The Linux account the machine creates, which commands in the machine run as. Leave a field empty to use your Mac user's. The account can't be changed after the machine is created.\n\nThe user, UID and home directory must not already exist in the image (such as ubuntu, UID 1000 or /root), or the machine can't set up the account when it boots.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                field(title: "User", caption: "A user name, such as dev.") {
                    TextField(hostUser, text: $accountUser)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(alignment: .top, spacing: 16) {
                    field(title: "UID", caption: "The account's user ID.") {
                        TextField("\(hostUID)", text: $accountUID)
                            .textFieldStyle(.roundedBorder)
                    }
                    field(title: "GID", caption: "The account's group ID.") {
                        TextField("\(hostGID)", text: $accountGID)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                field(title: "Home Directory", caption: "The account's home inside the machine. Your Mac home folder, if mounted, stays at its own path.") {
                    TextField(homePlaceholder, text: $accountHome)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.top, 8)
        }
    }

    private var header: some View {
        HStack {
            Text("Create Machine").font(.title2).fontWeight(.semibold)
            Spacer()
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
        var account = MachineAccountSpec()
        if supportsUserAccount {
            do {
                account = try MachineAccountSpec(
                    userText: accountUser, uidText: accountUID, gidText: accountGID, homeText: accountHome)
            } catch {
                validationError = error.localizedDescription
                showAccount = true
                return
            }
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
            noBoot: !boot,
            account: account
        )

        Task {
            let created = await machineService.create(spec)
            if created { await MainActor.run { dismiss() } }
        }
    }
}
