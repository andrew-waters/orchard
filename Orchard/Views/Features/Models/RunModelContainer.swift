import SwiftUI
import AppKit

/// Spin up a container already wired to a model server, launched from the Models view. Picks
/// the network (surfacing its egress), injects the bridge env vars, and explains — live,
/// against the chosen network — exactly what the container can and cannot reach. The honest
/// isolation story is the point of this sheet, not a footnote.
struct RunModelContainerView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var networkService: NetworkService
    @Environment(\.dismiss) private var dismiss

    /// What we're wiring to (works for both managed and detected servers).
    let providerName: String
    let port: UInt16
    let api: ModelAPIStyle

    @State private var image: String = "alpine:latest"
    @State private var name: String = ""
    /// Empty means the runtime default network.
    @State private var networkID: String = ""
    @State private var isRunning = false

    private var selectedNetwork: ContainerNetwork? {
        let wanted = networkID.isEmpty ? "default" : networkID
        return networkService.networks.first { $0.id == wanted }
    }

    private var baseURL: String? {
        guard let gateway = selectedNetwork?.status.gateway, !gateway.isEmpty else { return nil }
        return ModelBridge.containerBaseURL(gateway: gateway, hostPort: port, api: api)
    }

    private var canRun: Bool {
        !image.trimmingCharacters(in: .whitespaces).isEmpty
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
        .frame(width: 560, height: 620)
        .onAppear {
            if name.isEmpty { name = defaultName() }
        }
        .task { await networkService.load(showLoading: false) }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            SwiftUI.Image(systemName: "play.circle.fill")
                .font(.title)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Run Container Wired to a Model")
                    .font(.headline)
                Text("Bridged to \(providerName) on port \(String(port))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var networkPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Network")
                .font(.subheadline)
                .fontWeight(.medium)
            Picker("Network", selection: $networkID) {
                Text("Default").tag("")
                ForEach(networkService.networks, id: \.id) { network in
                    Text(network.isHostOnly ? "\(network.id) — isolated" : network.id).tag(network.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 280, alignment: .leading)
        }
    }

    @ViewBuilder
    private var endpointPreview: some View {
        if let baseURL {
            VStack(alignment: .leading, spacing: 4) {
                Text("The container will reach the model at")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(baseURL)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("Injected as \(api == .openAI ? "OPENAI_BASE_URL" : "OLLAMA_HOST").")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } else {
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
                Text("This is a host-only network. The container can reach the model over the network gateway but has no route to the internet — nothing to phone home to, no credential to leak.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("This network allows internet access, so the container can reach both the model and the internet. For a sandbox with no egress, use a host-only network — create one with:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("container network create --internal <name>")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Divider()
            Text("Isolation comes from Apple's per-container VM boundary plus the network you choose — Orchard adds none of its own. The model server must be bound to 0.0.0.0 for the container to reach it.")
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
            Button("Run Container") { run() }
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
        return "\(base)-model"
    }

    private func run() {
        guard let baseURL else { return }
        let env = ModelBridge.injectionEnvironment(baseURL: baseURL, api: api)
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
            await containerListService.runContainer(config: config)
            await MainActor.run {
                isRunning = false
                dismiss()
            }
        }
    }
}
