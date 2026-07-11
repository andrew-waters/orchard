import SwiftUI
import AppKit

/// Create a sandbox: a container wired to a local model. Reachable two ways - from a model's
/// detail (with that model preselected) or from the Sandboxes tab's New Sandbox button (pick
/// any running model). Picks the network (surfacing its egress), injects the bridge env vars,
/// stamps the sandbox label, and explains the isolation live against the chosen network.
struct RunModelContainerView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var networkService: NetworkService
    @EnvironmentObject var modelService: ModelService
    @EnvironmentObject var modelServerService: ModelServerService
    @Environment(\.dismiss) private var dismiss

    /// A model id (managed server or detected provider) to preselect, or nil to let the user
    /// pick from everything running.
    let preselectedID: String?

    @State private var targetID: String = ""
    @State private var image: String = "alpine:latest"
    @State private var name: String = ""
    /// Empty means the runtime default network.
    @State private var networkID: String = ""
    @State private var isRunning = false

    init(preselectedID: String? = nil) {
        self.preselectedID = preselectedID
    }

    /// A model the sandbox can be wired to.
    private struct Target: Identifiable {
        let id: String
        let name: String
        let port: UInt16
        let api: ModelAPIStyle
    }

    /// Running managed servers plus detected providers (de-duplicated by port).
    private var targets: [Target] {
        let servers = modelServerService.servers.map {
            Target(id: $0.id, name: $0.model, port: $0.port, api: $0.api)
        }
        let managedPorts = modelServerService.managedPorts
        let providers = modelService.providers
            .filter { !managedPorts.contains($0.port) }
            .map { Target(id: $0.id, name: $0.kind.displayName, port: $0.port, api: $0.api) }
        return servers + providers
    }

    private var target: Target? { targets.first { $0.id == targetID } }

    private var selectedNetwork: ContainerNetwork? {
        let wanted = networkID.isEmpty ? "default" : networkID
        return networkService.networks.first { $0.id == wanted }
    }

    private var baseURL: String? {
        guard let target, let gateway = selectedNetwork?.status.gateway, !gateway.isEmpty else { return nil }
        return ModelBridge.containerBaseURL(gateway: gateway, hostPort: target.port, api: target.api)
    }

    private var canRun: Bool {
        target != nil
            && !image.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && baseURL != nil
            && !isRunning
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modelPicker
                    field(title: "Image", placeholder: "alpine:latest", text: $image, mono: true)
                    field(title: "Container name", placeholder: "my-agent", text: $name)
                    networkPicker
                    endpointPreview
                    isolationExplainer
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 660)
        .onAppear {
            if targetID.isEmpty { targetID = preselectedID ?? targets.first?.id ?? "" }
            if name.isEmpty { name = defaultName() }
        }
        .task {
            await networkService.load(showLoading: false)
            await modelService.load(showLoading: false)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            SwiftUI.Image(systemName: "shield.lefthalf.filled")
                .font(.title)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("New Sandbox")
                    .font(.headline)
                Text("A container wired to a local model")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model")
                .font(.subheadline)
                .fontWeight(.medium)
            if targets.isEmpty {
                Text("No model servers running. Start one in Resources → AI Models first.")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Picker("Model", selection: $targetID) {
                    ForEach(targets) { t in
                        Text("\(t.name) · port \(String(t.port))").tag(t.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 320, alignment: .leading)
            }
        }
    }

    private var networkPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Network")
                .font(.subheadline)
                .fontWeight(.medium)
            Picker("Network", selection: $networkID) {
                Text("Default").tag("")
                ForEach(networkService.networks, id: \.id) { network in
                    Text(network.isHostOnly ? "\(network.id) - isolated" : network.id).tag(network.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 280, alignment: .leading)
        }
    }

    @ViewBuilder
    private var endpointPreview: some View {
        if let baseURL, let target {
            VStack(alignment: .leading, spacing: 4) {
                Text("The container will reach the model at")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(baseURL)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("Injected as \(target.api == .openAI ? "OPENAI_BASE_URL" : "OLLAMA_HOST").")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } else if target != nil {
            Text("The selected network has no gateway, so a container can't reach the host. Choose another network.")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }

    /// The honest isolation story, reactive to the chosen network's egress.
    @ViewBuilder
    private var isolationExplainer: some View {
        let hostOnly = selectedNetwork?.isHostOnly ?? false
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SwiftUI.Image(systemName: hostOnly ? "lock.shield" : "exclamationmark.shield")
                    .foregroundColor(hostOnly ? .green : .orange)
                Text(hostOnly ? "Isolated: no internet access" : "Not isolated: internet access is open")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            if hostOnly {
                Text("This is a host-only network. The container can reach the model over the network gateway but has no route to the internet - nothing to phone home to, no credential to leak.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("This network allows internet access, so the container can reach both the model and the internet. For a sandbox with no egress, use a host-only network - create one with:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("container network create --internal <name>")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Divider()
            Text("Isolation comes from Apple's per-container VM boundary plus the network you choose - Orchard adds none of its own. The model server must be bound to 0.0.0.0 for the container to reach it.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background((hostOnly ? Color.green : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            if isRunning {
                ProgressView().scaleEffect(0.8)
                Text("Starting container…").font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Create Sandbox") { run() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canRun)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Helpers

    private func field(title: String, placeholder: String, text: Binding<String>, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(mono ? .system(.body, design: .monospaced) : .body)
        }
    }

    private func defaultName() -> String {
        let base = image
            .replacingOccurrences(of: "docker.io/library/", with: "")
            .replacingOccurrences(of: "docker.io/", with: "")
            .split(separator: ":").first.map(String.init) ?? "container"
        return "\(base)-sandbox"
    }

    private func run() {
        guard let baseURL, let target else { return }
        let env = ModelBridge.injectionEnvironment(baseURL: baseURL, api: target.api)
            .map { ContainerRunConfig.EnvironmentVariable(key: $0.key, value: $0.value) }

        let config = ContainerRunConfig(
            name: name.trimmingCharacters(in: .whitespaces),
            image: image.trimmingCharacters(in: .whitespaces),
            environmentVariables: env,
            network: networkID,
            labels: SandboxMarker.labels(endpoint: baseURL)
        )

        isRunning = true
        Task {
            let ok = await containerListService.runContainer(config: config)
            await MainActor.run {
                isRunning = false
                // runContainer surfaces its own error; keep the sheet open on failure so the
                // user can retry.
                if ok { dismiss() }
            }
        }
    }
}
