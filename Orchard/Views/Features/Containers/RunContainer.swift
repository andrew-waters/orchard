import SwiftUI
import AppKit

struct RunContainerView: View {
    @EnvironmentObject var containerService: ContainerService
    @Environment(\.dismiss) var dismiss

    let imageName: String
    @State private var config: ContainerRunConfig
    @State private var selectedTab: ConfigTab = .basic
    @State private var isRunning = false

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

    init(imageName: String) {
        self.imageName = imageName

        // Generate a default container name from the image
        let cleanName = imageName
            .replacingOccurrences(of: "docker.io/library/", with: "")
            .replacingOccurrences(of: "docker.io/", with: "")
            .split(separator: ":").first.map(String.init) ?? "container"

        _config = State(initialValue: ContainerRunConfig(
            name: cleanName,
            image: imageName
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Tab navigation
            tabPickerView

            Divider()

            // Content
            ScrollView {
                contentView
                    .padding()
            }

            Divider()

            // Footer with action buttons
            footerView
        }
        .frame(width: 700, height: 600)
    }

    private var headerView: some View {
        HStack {
            SwiftUI.Image(systemName: "play.circle.fill")
                .font(.title)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Run Container")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(imageName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                SwiftUI.Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
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

    // MARK: - Basic Configuration

    private var basicConfigView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Container Name")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextField("Enter container name", text: $config.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("DNS Domain")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("DNS Domain", selection: $config.dnsDomain) {
                    Text("None").tag("")
                    ForEach(containerService.dnsDomains, id: \.domain) { domain in
                        Text(domain.domain).tag(domain.domain)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Publish port", isOn: $config.enablePublish)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if config.enablePublish {
                    TextField("[host-ip:]host-port:container-port[/protocol]", text: $config.publishSpec)
                        .textFieldStyle(.roundedBorder)

                    Text("Example: 8080:80, 127.0.0.1:3000:3000/tcp")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

    // MARK: - Ports Configuration

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

            if config.portMappings.isEmpty {
                emptyStateView(
                    icon: "network",
                    title: "No port mappings",
                    message: "Add port mappings to expose container ports to the host"
                )
            } else {
                ForEach(config.portMappings) { mapping in
                    PortMappingRow(
                        mapping: binding(for: mapping),
                        onDelete: { deletePortMapping(mapping) }
                    )
                }
            }

            Spacer()
        }
    }

    // MARK: - Volumes Configuration

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
                ForEach(config.volumeMappings) { mapping in
                    VolumeMappingRow(
                        mapping: binding(for: mapping),
                        onDelete: { deleteVolumeMapping(mapping) }
                    )
                }
            }

            Spacer()
        }
    }

    // MARK: - Environment Configuration

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
                ForEach(config.environmentVariables) { envVar in
                    EnvironmentVariableRow(
                        envVar: binding(for: envVar),
                        onDelete: { deleteEnvironmentVariable(envVar) }
                    )
                }
            }

            Spacer()
        }
    }

    // MARK: - Advanced Configuration

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

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if isRunning {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Starting container...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Run Container") {
                runContainer()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(config.name.isEmpty || isRunning)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
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

    // MARK: - Actions

    private func addPortMapping() {
        config.portMappings.append(ContainerRunConfig.PortMapping(
            hostPort: "",
            containerPort: ""
        ))
    }

    private func deletePortMapping(_ mapping: ContainerRunConfig.PortMapping) {
        config.portMappings.removeAll { $0.id == mapping.id }
    }

    private func addVolumeMapping() {
        config.volumeMappings.append(ContainerRunConfig.VolumeMapping(
            hostPath: "",
            containerPath: ""
        ))
    }

    private func deleteVolumeMapping(_ mapping: ContainerRunConfig.VolumeMapping) {
        config.volumeMappings.removeAll { $0.id == mapping.id }
    }

    private func addEnvironmentVariable() {
        config.environmentVariables.append(ContainerRunConfig.EnvironmentVariable(
            key: "",
            value: ""
        ))
    }

    private func deleteEnvironmentVariable(_ envVar: ContainerRunConfig.EnvironmentVariable) {
        config.environmentVariables.removeAll { $0.id == envVar.id }
    }

    private func runContainer() {
        isRunning = true

        Task {
            await containerService.runContainer(config: config)

            await MainActor.run {
                isRunning = false
                dismiss()
            }
        }
    }

    // MARK: - Binding Helpers

    private func binding(for mapping: ContainerRunConfig.PortMapping) -> Binding<ContainerRunConfig.PortMapping> {
        guard let index = config.portMappings.firstIndex(where: { $0.id == mapping.id }) else {
            fatalError("Port mapping not found")
        }
        return $config.portMappings[index]
    }

    private func binding(for mapping: ContainerRunConfig.VolumeMapping) -> Binding<ContainerRunConfig.VolumeMapping> {
        guard let index = config.volumeMappings.firstIndex(where: { $0.id == mapping.id }) else {
            fatalError("Volume mapping not found")
        }
        return $config.volumeMappings[index]
    }

    private func binding(for envVar: ContainerRunConfig.EnvironmentVariable) -> Binding<ContainerRunConfig.EnvironmentVariable> {
        guard let index = config.environmentVariables.firstIndex(where: { $0.id == envVar.id }) else {
            fatalError("Environment variable not found")
        }
        return $config.environmentVariables[index]
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

#Preview {
    RunContainerView(imageName: "docker.io/library/nginx:latest")
        .environmentObject(ContainerService())
}
