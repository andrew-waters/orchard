import SwiftUI
import AppKit

// The AI Models domain (under Resources), in the app's three-column shape: a list of servers
// (middle column) and a detail pane for the selected one (third column).

/// Middle column: managed servers Orchard runs plus other detected providers, with a
/// New Server action.
struct ModelsListView: View {
    @EnvironmentObject var modelService: ModelService
    @EnvironmentObject var modelServerService: ModelServerService
    @Binding var selectedModel: String?

    @State private var showCreateSheet = false

    /// Detected providers minus the ports our managed servers already answer on.
    private var detected: [ModelProvider] {
        modelService.providers.filter { !modelServerService.managedPorts.contains($0.port) }
    }

    private var isEmpty: Bool {
        modelServerService.servers.isEmpty && detected.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Local Models")
                    .font(.headline)
                Spacer()
                Button(action: { showCreateSheet = true }) {
                    SwiftUI.Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(!modelServerService.engineAvailable)
                .help(modelServerService.engineAvailable ? "Start a new model server" : "mlx_lm.server is not installed")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if isEmpty {
                emptyState
            } else {
                List(selection: $selectedModel) {
                    if !modelServerService.servers.isEmpty {
                        Section("Managed by Orchard") {
                            ForEach(modelServerService.servers) { server in
                                ListItemRow(
                                    icon: "cpu",
                                    iconColor: server.status == .running ? .green : .red,
                                    primaryText: server.model,
                                    secondaryLeftText: "port \(String(server.port))",
                                    isSelected: selectedModel == server.id
                                )
                                .tag(server.id)
                            }
                        }
                    }
                    if !detected.isEmpty {
                        Section("Detected") {
                            ForEach(detected) { provider in
                                ListItemRow(
                                    icon: "cpu",
                                    iconColor: .secondary,
                                    primaryText: provider.kind.displayName,
                                    secondaryLeftText: "port \(String(provider.port))",
                                    isSelected: selectedModel == provider.id
                                )
                                .tag(provider.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .task { await modelService.load(showLoading: false) }
        .sheet(isPresented: $showCreateSheet) { CreateModelServerView() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            SwiftUI.Image(systemName: "sparkles")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text("No model servers yet")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("Start one with the + button, or launch Ollama / LM Studio and it will be detected here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if !modelServerService.engineAvailable {
                Text("uv tool install mlx-lm")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 4)
                Link("Setup & troubleshooting guide", destination: URL(string: "https://orchard.andon.dev/ai.html")!)
                    .font(.caption2)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Third column: detail for the selected server or detected provider - endpoints, models,
/// and lifecycle/test actions.
struct ModelDetailView: View {
    @EnvironmentObject var modelService: ModelService
    @EnvironmentObject var modelServerService: ModelServerService
    @EnvironmentObject var networkService: NetworkService
    let selectedModel: String?

    @State private var runTarget: RunTarget?
    @State private var testTarget: TestTarget?

    private struct RunTarget: Identifiable {
        let id = UUID(); let modelID: String
    }
    private struct TestTarget: Identifiable {
        let id = UUID(); let name: String; let port: UInt16; let api: ModelAPIStyle; let model: String
    }

    private var server: ManagedModelServer? {
        modelServerService.servers.first { $0.id == selectedModel }
    }
    private var provider: ModelProvider? {
        modelService.providers.first { $0.id == selectedModel }
    }

    var body: some View {
        Group {
            if let server {
                ScrollView { managedDetail(server).padding(20) }
            } else if let provider {
                ScrollView { detectedDetail(provider).padding(20) }
            } else {
                Text("Select a model")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await networkService.load(showLoading: false) }
        .sheet(item: $runTarget) { t in
            RunModelContainerView(preselectedID: t.modelID)
        }
        .sheet(item: $testTarget) { t in
            TestModelPromptView(providerName: t.name, port: t.port, api: t.api, model: t.model)
        }
    }

    // MARK: - Managed

    private func managedDetail(_ server: ManagedModelServer) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(server.status == .running ? Color.green : Color.red).frame(width: 9, height: 9)
                Text(server.model).font(.title3).fontWeight(.semibold)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                portBadge(server.port)
            }

            labeledRow("On this Mac", "http://\(server.host):\(server.port)/v1")
            if server.reachableFromContainers, let url = containerURL(port: server.port, api: server.api) {
                labeledRow("From containers", url)
            } else if !server.reachableFromContainers {
                Text("Loopback-only - bound to 127.0.0.1, so containers can't reach it.")
                    .font(.caption).foregroundColor(.secondary)
            }

            if server.status == .running {
                HStack(spacing: 8) {
                    Button(action: { testTarget = TestTarget(name: server.model, port: server.port, api: server.api, model: server.model) }) {
                        Label("Chat…", systemImage: "text.bubble")
                    }
                    Button(action: { runTarget = RunTarget(modelID: server.id) }) {
                        Label("New sandbox…", systemImage: "shield.lefthalf.filled")
                    }
                }
                .font(.subheadline)
            }

            HStack(spacing: 8) {
                Button(role: .destructive, action: { modelServerService.stop(server.id) }) {
                    Label("Stop", systemImage: "stop.fill")
                }
                Button(action: { revealLog(server.logPath) }) {
                    Label("Show Log", systemImage: "doc.text")
                }
                if server.status == .failed {
                    Text("Stopped unexpectedly").font(.caption).foregroundColor(.red)
                }
            }
            .font(.subheadline)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Detected

    private func detectedDetail(_ provider: ModelProvider) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SwiftUI.Image(systemName: "cpu")
                Text(provider.kind.displayName).font(.title3).fontWeight(.semibold)
                Spacer()
                portBadge(provider.port)
            }

            labeledRow("On this Mac", provider.hostBaseURL)
            if let url = containerURL(port: provider.port, api: provider.api) {
                labeledRow("From containers", url)
                Text("Reachable from containers only if this server is bound to 0.0.0.0 (some default to 127.0.0.1).")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if provider.models.isEmpty {
                Text("No models reported").font(.caption).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Models (\(provider.models.count))").font(.caption).foregroundColor(.secondary)
                    ForEach(provider.models, id: \.self) { model in
                        Text(model).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: { testTarget = TestTarget(name: provider.kind.displayName, port: provider.port, api: provider.api, model: provider.models.first ?? "") }) {
                    Label("Chat…", systemImage: "text.bubble")
                }
                Button(action: { runTarget = RunTarget(modelID: provider.id) }) {
                    Label("New sandbox…", systemImage: "shield.lefthalf.filled")
                }
            }
            .font(.subheadline)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bits

    private func portBadge(_ port: UInt16) -> some View {
        Text("port \(String(port))")
            .font(.caption).foregroundColor(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 120, alignment: .leading)
            Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Spacer()
        }
    }

    private func containerURL(port: UInt16, api: ModelAPIStyle) -> String? {
        guard let gateway = networkService.networks.first(where: { $0.id == "default" })?.status.gateway,
              !gateway.isEmpty else { return nil }
        return ModelBridge.containerBaseURL(gateway: gateway, hostPort: port, api: api)
    }

    private func revealLog(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}
