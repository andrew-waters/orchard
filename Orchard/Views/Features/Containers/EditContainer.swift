import SwiftUI
import AppKit

struct EditContainerView: View {
    @EnvironmentObject var containerService: ContainerService
    @Environment(\.dismiss) var dismiss
    
    let container: Container
    @State private var config: ContainerRunConfig
    @State private var selectedTab: ConfigTab = .basic
    @State private var isUpdating = false
    
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
    
    init(container: Container) {
        self.container = container
        
        // Extract current configuration from container
        let envVars = container.configuration.initProcess.environment.compactMap { envStr -> ContainerRunConfig.EnvironmentVariable? in
            let components = envStr.split(separator: "=", maxSplits: 1)
            guard components.count == 2 else { return nil }
            return ContainerRunConfig.EnvironmentVariable(
                key: String(components[0]),
                value: String(components[1])
            )
        }
        
        let volumes = container.configuration.mounts.compactMap { mount -> ContainerRunConfig.VolumeMapping? in
            guard mount.type.virtiofs != nil else { return nil }
            let isReadonly = mount.options.contains("ro")
            return ContainerRunConfig.VolumeMapping(
                hostPath: mount.source,
                containerPath: mount.destination,
                readonly: isReadonly
            )
        }
        
        _config = State(initialValue: ContainerRunConfig(
            name: container.configuration.id,
            image: container.configuration.image.reference,
            detached: true,
            removeAfterStop: false,
            environmentVariables: envVars,
            portMappings: [], // Port mappings not available in container config
            volumeMappings: volumes,
            workingDirectory: container.configuration.initProcess.workingDirectory,
            commandOverride: container.configuration.initProcess.arguments.joined(separator: " ")
        ))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Warning banner
            warningBanner
            
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
        .frame(width: 700, height: 650)
    }
    
    private var headerView: some View {
        HStack {
            SwiftUI.Image(systemName: "pencil.circle.fill")
                .font(.title)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Container Configuration")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(container.configuration.id)
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
    
    private var warningBanner: some View {
        HStack(spacing: 12) {
            SwiftUI.Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Container will be recreated")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("The existing container will be deleted and recreated with the new configuration.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
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
    
    // MARK: - Config Views (reuse from RunContainerView)
    
    private var basicConfigView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Container Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField("Enter container name", text: $config.name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true) // Can't change name
                
                Text("Container name cannot be changed")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
            
            Text("Note: Port mappings are not preserved from the original container. Please re-add them.")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.vertical, 8)
            
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
    
    private var footerView: some View {
        HStack {
            if isUpdating {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Recreating container...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Button("Save & Recreate") {
                updateContainer()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(config.name.isEmpty || isUpdating)
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
    
    private func updateContainer() {
        isUpdating = true
        
        Task {
            await containerService.recreateContainer(oldContainerId: container.configuration.id, newConfig: config)
            
            await MainActor.run {
                isUpdating = false
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

#Preview {
    EditContainerView(container: Container(
        status: "stopped",
        configuration: ContainerConfiguration(
            id: "test-container",
            hostname: "test",
            runtimeHandler: "vm",
            initProcess: initProcess(
                terminal: false,
                environment: ["PATH=/usr/bin", "HOME=/root"],
                workingDirectory: "/app",
                arguments: ["nginx", "-g", "daemon off;"],
                executable: "/usr/sbin/nginx",
                user: User(id: nil, raw: nil)
            ),
            mounts: [],
            platform: Platform(os: "linux", architecture: "arm64"),
            image: Image(
                descriptor: ImageDescriptor(mediaType: "application/vnd.oci.image.manifest.v1+json", digest: "sha256:abc123", size: 1000000),
                reference: "docker.io/library/nginx:latest"
            ),
            rosetta: false,
            dns: DNS(nameservers: [], searchDomains: [], options: [], domain: "a.com"),
            resources: Resources(cpus: 2, memoryInBytes: 2147483648),
            labels: nil
        ),
        networks: []
    ))
    .environmentObject(ContainerService())
}

