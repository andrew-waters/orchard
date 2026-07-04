import SwiftUI
import AppKit

/// Whether the shared config form is creating a container from an image (`.run`) or
/// editing an existing one (`.edit`). Drives the few places the two flows differ:
/// name editing/validation, the DNS/network pickers, and the ports note.
enum ContainerConfigMode: Equatable {
    case run
    case edit
}

/// The tabbed container-configuration form shared by Run and Edit. Owns the tab UI, the
/// per-tab content, row add/remove, and (run mode) name validation. The host view supplies
/// the config binding and the surrounding chrome (header/warning/footer + the action).
struct ContainerConfigForm: View {
    @Binding var config: ContainerRunConfig
    @Binding var nameValidationError: String?
    let mode: ContainerConfigMode

    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var dnsService: DNSService
    @EnvironmentObject var networkService: NetworkService

    @State private var selectedTab: ConfigTab = .basic

    enum ConfigTab: String, CaseIterable {
        case basic = "Basic"
        case ports = "Ports"
        case volumes = "Volumes"
        case environment = "Environment"
        case advanced = "Advanced"

        var icon: String {
            switch self {
            case .basic: return "gear"
            case .ports: return "network"
            case .volumes: return "externaldrive"
            case .environment: return "rectangle.3.group"
            case .advanced: return "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabPickerView
            Divider()
            ScrollView {
                contentView
                    .padding()
            }
        }
        .task {
            // Run mode populates the DNS/network pickers and defaults to the default domain.
            guard mode == .run else { return }
            await networkService.load(showLoading: false)
            await dnsService.load(showLoading: false)
            if config.dnsDomain.isEmpty,
               let defaultDomain = dnsService.dnsDomains.first(where: { $0.isDefault }) {
                config.dnsDomain = defaultDomain.domain
            }
        }
        .onAppear {
            if mode == .run { validateContainerName() }
        }
    }

    private var tabPickerView: some View {
        HStack(spacing: 0) {
            ForEach(ConfigTab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func tabButton(for tab: ConfigTab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 6) {
                SwiftUI.Image(systemName: tab.icon)
                    .font(.subheadline)
                Text(tab.rawValue)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .basic:
            basicConfigView
        case .ports:
            portsConfigView
        case .volumes:
            volumesConfigView
        case .environment:
            environmentConfigView
        case .advanced:
            advancedConfigView
        }
    }

    // MARK: - Basic

    private var basicConfigView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Container Name")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextField("Enter container name", text: $config.name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(mode == .edit)   // name is the identity; can't change on edit
                    .onChange(of: config.name) {
                        if mode == .run { validateContainerName() }
                    }

                if mode == .edit {
                    Text("Container name cannot be changed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let nameValidationError {
                    Text(nameValidationError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 2)
                }
            }

            if mode == .run {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DNS Domain")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("DNS Domain", selection: $config.dnsDomain) {
                        Text("None").tag("")
                        ForEach(dnsService.dnsDomains, id: \.domain) { domain in
                            Text(domain.domain).tag(domain.domain)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200, alignment: .leading)

                    if !config.dnsDomain.isEmpty {
                        Text("Selected: \(config.dnsDomain)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Network")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("Network", selection: $config.network) {
                        Text("Default").tag("")
                        ForEach(networkService.networks, id: \.id) { network in
                            Text(network.id).tag(network.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Run in detached mode (background)", isOn: $config.detached)
                    .font(.subheadline)

                Toggle("Remove container after it stops", isOn: $config.removeAfterStop)
                    .font(.subheadline)
            }

            Spacer()
        }
    }

    // MARK: - Ports

    private var portsConfigView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Port Mappings")
                    .font(.headline)

                Spacer()

                Button(action: addPortMapping) {
                    HStack(spacing: 4) {
                        SwiftUI.Image(systemName: "plus.circle.fill")
                        Text("Add Port")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
            }

            if mode == .edit {
                Text("Note: Port mappings are not preserved from the original container. Please re-add them.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.vertical, 8)
            }

            if config.portMappings.isEmpty {
                emptyStateView(
                    icon: "network",
                    title: "No port mappings",
                    message: "Add port mappings to expose container ports to the host"
                )
            } else {
                ForEach($config.portMappings) { $mapping in
                    PortMappingRow(
                        mapping: $mapping,
                        onDelete: { deletePortMapping(mapping) }
                    )
                }
            }

            Spacer()
        }
    }

    // MARK: - Volumes

    private var volumesConfigView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Volume Mounts")
                    .font(.headline)

                Spacer()

                Button(action: addVolumeMapping) {
                    HStack(spacing: 4) {
                        SwiftUI.Image(systemName: "plus.circle.fill")
                        Text("Add Volume")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
            }

            if config.volumeMappings.isEmpty {
                emptyStateView(
                    icon: "externaldrive",
                    title: "No volume mounts",
                    message: "Add volume mounts to persist data or share files with the container"
                )
            } else {
                ForEach($config.volumeMappings) { $mapping in
                    VolumeMappingRow(
                        mapping: $mapping,
                        onDelete: { deleteVolumeMapping(mapping) }
                    )
                }
            }

            Spacer()
        }
    }

    // MARK: - Environment

    private var environmentConfigView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Environment Variables")
                    .font(.headline)

                Spacer()

                Button(action: addEnvironmentVariable) {
                    HStack(spacing: 4) {
                        SwiftUI.Image(systemName: "plus.circle.fill")
                        Text("Add Variable")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
            }

            if config.environmentVariables.isEmpty {
                emptyStateView(
                    icon: "rectangle.3.group",
                    title: "No environment variables",
                    message: "Add environment variables to configure the container"
                )
            } else {
                ForEach($config.environmentVariables) { $envVar in
                    EnvironmentVariableRow(
                        envVar: $envVar,
                        onDelete: { deleteEnvironmentVariable(envVar) }
                    )
                }
            }

            Spacer()
        }
    }

    // MARK: - Advanced

    private var advancedConfigView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Working Directory")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextField("/path/in/container", text: $config.workingDirectory)
                    .textFieldStyle(.roundedBorder)

                Text("Override the default working directory inside the container")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Command Override")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextField("command arg1 arg2", text: $config.commandOverride)
                    .textFieldStyle(.roundedBorder)

                Text("Override the default command/entrypoint")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Helper Views

    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            SwiftUI.Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Row mutations

    private func addPortMapping() {
        config.portMappings.append(ContainerRunConfig.PortMapping(hostPort: "", containerPort: ""))
    }

    private func deletePortMapping(_ mapping: ContainerRunConfig.PortMapping) {
        config.portMappings.removeAll { $0.id == mapping.id }
    }

    private func addVolumeMapping() {
        config.volumeMappings.append(ContainerRunConfig.VolumeMapping(hostPath: "", containerPath: ""))
    }

    private func deleteVolumeMapping(_ mapping: ContainerRunConfig.VolumeMapping) {
        config.volumeMappings.removeAll { $0.id == mapping.id }
    }

    private func addEnvironmentVariable() {
        config.environmentVariables.append(ContainerRunConfig.EnvironmentVariable(key: "", value: ""))
    }

    private func deleteEnvironmentVariable(_ envVar: ContainerRunConfig.EnvironmentVariable) {
        config.environmentVariables.removeAll { $0.id == envVar.id }
    }

    // MARK: - Name validation (run mode)

    func validateContainerName() {
        nameValidationError = Self.validationError(for: config.name, existing: containerListService.containers)
    }

    /// Pure validation: Docker naming rules + length + uniqueness. Returns the error copy,
    /// or nil if valid.
    static func validationError(for name: String, existing: [Container]) -> String? {
        guard !name.isEmpty else { return nil }

        let namePattern = /^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/
        if name.wholeMatch(of: namePattern) == nil {
            return "Container name can only contain letters, numbers, underscores, periods and dashes. Must start with a letter or number."
        }
        if name.count > 63 {
            return "Container name must be 63 characters or less"
        }
        if existing.contains(where: { $0.configuration.id == name }) {
            return "A container with this name already exists"
        }
        return nil
    }
}

// MARK: - Row Components

struct PortMappingRow: View {
    @Binding var mapping: ContainerRunConfig.PortMapping
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Host Port", text: $mapping.hostPort)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)

            SwiftUI.Image(systemName: "arrow.right")
                .foregroundColor(.secondary)

            TextField("Container Port", text: $mapping.containerPort)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)

            Picker("", selection: $mapping.transportProtocol) {
                Text("TCP").tag("tcp")
                Text("UDP").tag("udp")
            }
            .frame(width: 80)

            Spacer()

            Button(action: onDelete) {
                SwiftUI.Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct VolumeMappingRow: View {
    @Binding var mapping: ContainerRunConfig.VolumeMapping
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                TextField("Host Path", text: $mapping.hostPath)
                    .textFieldStyle(.roundedBorder)

                SwiftUI.Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                TextField("Container Path", text: $mapping.containerPath)
                    .textFieldStyle(.roundedBorder)

                Button(action: onDelete) {
                    SwiftUI.Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Toggle("Read-only", isOn: $mapping.readonly)
                    .font(.caption)
                Spacer()
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct EnvironmentVariableRow: View {
    @Binding var envVar: ContainerRunConfig.EnvironmentVariable
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("KEY", text: $envVar.key)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 150)

            Text("=")
                .foregroundColor(.secondary)

            TextField("value", text: $envVar.value)
                .textFieldStyle(.roundedBorder)

            Button(action: onDelete) {
                SwiftUI.Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
