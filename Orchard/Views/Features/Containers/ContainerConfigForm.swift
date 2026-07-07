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
    @EnvironmentObject var modelService: ModelService

    @State private var selectedTab: ConfigTab = .basic
    /// The detected model provider the user chose to bridge into this container, by
    /// `ModelProvider.id`. Empty means "none" — the bridge section is opt-in.
    @State private var bridgeProviderID: String = ""

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
            await modelService.load(showLoading: false)
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
            if mode == .run {
                modelBridgeSection
                Divider()
            }

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

    // MARK: - Model bridge (run mode)

    /// Lets the user wire this new container to a model server running on the host. The
    /// endpoint is computed from the target network's gateway (how a container reaches the
    /// host) and injected as standard client env vars. Opt-in and additive — it only
    /// appends to the environment when the user asks.
    @ViewBuilder
    private var modelBridgeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SwiftUI.Image(systemName: "cpu")
                Text("Local Model Bridge")
                    .font(.headline)
            }

            Text("Wire this container to an AI model server running on your Mac. The container reaches it over its network gateway — no host networking to hand-configure.")
                .font(.caption)
                .foregroundColor(.secondary)

            if modelService.providers.isEmpty {
                Text("No local model servers detected. Start one bound to 0.0.0.0 (Ollama, LM Studio, or an MLX server) and it will appear here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            } else {
                Picker("Expose to model", selection: $bridgeProviderID) {
                    Text("None").tag("")
                    ForEach(modelService.providers) { provider in
                        Text("\(provider.kind.displayName) · port \(String(provider.port))").tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 300, alignment: .leading)

                if let provider = bridgeProvider {
                    if let env = bridgeEnvironment, let baseURL = bridgeBaseURL(provider) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Container reaches it at")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(baseURL)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)

                            Button(action: { injectBridge(env) }) {
                                Label("Add \(env.count) variable\(env.count == 1 ? "" : "s") to Environment",
                                      systemImage: "plus.circle.fill")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 2)

                            Text("Requires the server to listen on 0.0.0.0, not 127.0.0.1, so the container can reach it.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    } else {
                        Text("The selected network has no gateway, so a container can't reach the host. Pick a different network on the Basic tab.")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    /// The provider currently chosen in the bridge picker, if any.
    private var bridgeProvider: ModelProvider? {
        modelService.providers.first { $0.id == bridgeProviderID }
    }

    /// The network this container will attach to; an empty selection means the runtime's
    /// default network, whose id is `default`.
    private var targetNetwork: ContainerNetwork? {
        let wanted = config.network.isEmpty ? "default" : config.network
        return networkService.networks.first { $0.id == wanted }
    }

    /// The env-var pairs to inject for the chosen provider on the target network, or nil
    /// when either is missing (or the network has no gateway).
    private var bridgeEnvironment: [(key: String, value: String)]? {
        guard let provider = bridgeProvider, let network = targetNetwork else { return nil }
        return modelService.bridgeEnvironment(for: provider, on: network)
    }

    /// The container-reachable base URL shown as a preview, mirroring what will be injected.
    private func bridgeBaseURL(_ provider: ModelProvider) -> String? {
        guard let gateway = targetNetwork?.status.gateway, !gateway.isEmpty else { return nil }
        return ModelBridge.containerBaseURL(gateway: gateway, hostPort: provider.port, api: provider.api)
    }

    /// Append the bridge variables, replacing any existing entries with the same key so
    /// re-injecting after a provider/network change stays consistent.
    private func injectBridge(_ env: [(key: String, value: String)]) {
        for pair in env {
            config.environmentVariables.removeAll { $0.key == pair.key }
            config.environmentVariables.append(ContainerRunConfig.EnvironmentVariable(key: pair.key, value: pair.value))
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
