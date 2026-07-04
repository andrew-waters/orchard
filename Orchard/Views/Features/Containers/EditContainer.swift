import SwiftUI
import AppKit

struct EditContainerView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @Environment(\.dismiss) var dismiss

    let container: Container
    @State private var config: ContainerRunConfig
    @State private var isUpdating = false

    init(container: Container) {
        self.container = container

        // Extract current configuration from the container.
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
            return ContainerRunConfig.VolumeMapping(
                hostPath: mount.source,
                containerPath: mount.destination,
                readonly: mount.options.contains("ro")
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
            headerView
            Divider()
            warningBanner
            Divider()
            ContainerConfigForm(config: $config, nameValidationError: .constant(nil), mode: .edit)
            Divider()
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

    private func updateContainer() {
        isUpdating = true
        Task {
            await containerListService.recreateContainer(oldContainerId: container.configuration.id, newConfig: config)
            await MainActor.run {
                isUpdating = false
                dismiss()
            }
        }
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
                user: User(id: UserID(gid: 0, uid: 0), raw: UserRaw(userString: "root")),
                rlimits: [],
                supplementalGroups: []
            ),
            mounts: [],
            platform: Platform(os: "linux", architecture: "arm64", variant: nil),
            image: Image(
                descriptor: ImageDescriptor(mediaType: "application/vnd.oci.image.manifest.v1+json", digest: "sha256:abc123", size: 1000000),
                reference: "docker.io/library/nginx:latest"
            ),
            rosetta: false,
            dns: DNS(nameservers: [], searchDomains: [], options: [], domain: "a.com"),
            resources: Resources(cpus: 2, memoryInBytes: 2147483648),
            labels: [:],
            publishedPorts: [],
            publishedSockets: nil,
            ssh: nil,
            virtualization: nil,
            sysctls: [:]
        ),
        networks: []
    ))
    .injectServices(AppServices())
}
