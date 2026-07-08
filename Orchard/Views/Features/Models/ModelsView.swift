import SwiftUI
import AppKit

/// The "AI" section's landing page. Shows the model servers Orchard manages (with start/stop
/// lifecycle) and any other servers merely detected running on the host, plus how a container
/// reaches each one.
struct ModelsView: View {
    @EnvironmentObject var modelService: ModelService
    @EnvironmentObject var modelServerService: ModelServerService
    @EnvironmentObject var networkService: NetworkService

    @State private var showCreateSheet = false
    @State private var runTarget: RunTarget?
    @State private var testTarget: TestTarget?

    /// A model to launch a container against; drives the run sheet.
    private struct RunTarget: Identifiable {
        let id = UUID()
        let name: String
        let port: UInt16
        let api: ModelAPIStyle
    }

    /// A model to send an ad-hoc prompt to; drives the test sheet.
    private struct TestTarget: Identifiable {
        let id = UUID()
        let name: String
        let port: UInt16
        let api: ModelAPIStyle
        let model: String
    }

    /// Detected providers minus the ones our managed servers already account for (a managed
    /// server also answers detection on its port; showing both would double-count it).
    private var detectedProviders: [ModelProvider] {
        modelService.providers.filter { !modelServerService.managedPorts.contains($0.port) }
    }

    private var isEmpty: Bool {
        modelServerService.servers.isEmpty && detectedProviders.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !modelServerService.engineAvailable {
                    engineGuidance
                }

                if !modelServerService.servers.isEmpty {
                    sectionLabel("Managed by Orchard")
                    ForEach(modelServerService.servers) { server in
                        managedServerCard(server)
                    }
                }

                if !detectedProviders.isEmpty {
                    sectionLabel("Detected")
                    ForEach(detectedProviders) { provider in
                        detectedProviderCard(provider)
                    }
                }

                if isEmpty {
                    emptyState
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await networkService.load(showLoading: false)
            await modelService.load(showLoading: false)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateModelServerView()
        }
        .sheet(item: $runTarget) { target in
            RunModelContainerView(providerName: target.name, port: target.port, api: target.api)
        }
        .sheet(item: $testTarget) { target in
            TestModelPromptView(providerName: target.name, port: target.port, api: target.api, model: target.model)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    SwiftUI.Image(systemName: "sparkles")
                    Text("Local Models")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                Text("AI model servers running on your Mac. Bridge any of them into a container from the container's Environment tab.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { showCreateSheet = true }) {
                Label("New Server", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!modelServerService.engineAvailable)
            .help(modelServerService.engineAvailable ? "Start a new model server" : "mlx_lm.server is not installed")
        }
    }

    private var engineGuidance: some View {
        HStack(alignment: .top, spacing: 10) {
            SwiftUI.Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Server engine not installed")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Install mlx_lm.server to start servers from Orchard:  uv tool install mlx-lm")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            SwiftUI.Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No model servers yet")
                .font(.headline)
            Text("Start one with New Server, or launch Ollama / LM Studio and it will be detected here automatically.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Cards

    private func managedServerCard(_ server: ManagedModelServer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                statusDot(server.status)
                Text(server.model)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                portBadge(server.port)
            }

            labeledRow("On this Mac", "http://\(server.host):\(server.port)/v1")
            if server.reachableFromContainers, let url = containerURL(port: server.port, api: server.api) {
                labeledRow("From containers", url)
            } else if !server.reachableFromContainers {
                Text("Loopback-only — bound to 127.0.0.1, so containers can't reach it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                if server.status == .running {
                    Button(action: { testTarget = TestTarget(name: server.model, port: server.port, api: server.api, model: server.model) }) {
                        Label("Chat…", systemImage: "text.bubble")
                    }
                    Button(action: { runTarget = RunTarget(name: server.model, port: server.port, api: server.api) }) {
                        Label("Run container…", systemImage: "play.circle")
                    }
                }
                Button(role: .destructive, action: { modelServerService.stop(server.id) }) {
                    Label("Stop", systemImage: "stop.fill")
                }
                Button(action: { revealLog(server.logPath) }) {
                    Label("Show Log", systemImage: "doc.text")
                }
                if server.status == .failed {
                    Text("Stopped unexpectedly")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .font(.subheadline)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func detectedProviderCard(_ provider: ModelProvider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SwiftUI.Image(systemName: "cpu")
                Text(provider.kind.displayName)
                    .font(.headline)
                Spacer()
                portBadge(provider.port)
            }

            labeledRow("On this Mac", provider.hostBaseURL)
            if let url = containerURL(port: provider.port, api: provider.api) {
                labeledRow("From containers", url)
            }

            if provider.models.isEmpty {
                Text("No models reported")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Models (\(provider.models.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(provider.models, id: \.self) { model in
                        Text(model)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 2)
            }

            HStack(spacing: 8) {
                Button(action: { testTarget = TestTarget(name: provider.kind.displayName, port: provider.port, api: provider.api, model: provider.models.first ?? "") }) {
                    Label("Chat…", systemImage: "text.bubble")
                }
                Button(action: { runTarget = RunTarget(name: provider.kind.displayName, port: provider.port, api: provider.api) }) {
                    Label("Run container…", systemImage: "play.circle")
                }
            }
            .font(.subheadline)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Bits

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(.secondary.opacity(0.6))
    }

    private func statusDot(_ status: ManagedModelServer.Status) -> some View {
        Circle()
            .fill(status == .running ? Color.green : Color.red)
            .frame(width: 8, height: 8)
    }

    private func portBadge(_ port: UInt16) -> some View {
        Text("port \(String(port))")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
    }

    /// The container-reachable base URL for something on `port`, via the default network's
    /// gateway.
    private func containerURL(port: UInt16, api: ModelAPIStyle) -> String? {
        guard let gateway = networkService.networks.first(where: { $0.id == "default" })?.status.gateway,
              !gateway.isEmpty else { return nil }
        return ModelBridge.containerBaseURL(gateway: gateway, hostPort: port, api: api)
    }

    private func revealLog(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}
