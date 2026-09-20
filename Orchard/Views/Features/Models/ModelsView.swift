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
    @FocusState var listFocusedTab: TabSelection?

    @State private var showCreateSheet = false

    /// Detected providers minus the ports our managed servers already answer on.
    private var detected: [ModelProvider] {
        modelService.providers.filter { !modelServerService.managedPorts.contains($0.port) }
    }

    /// Endpoints the user has switched off. They are never probed, so they can't turn up
    /// under Detected - without a row of their own there would be no way back on (#110).
    private var notProbed: [ModelEndpoint] {
        modelService.endpoints.filter { !$0.isEnabled }
    }

    /// Endpoints being probed that nothing is answering on, limited to the ones the user
    /// configured. A built-in on its shipped address stays quiet, because "you aren't
    /// running Ollama" is not news; one that has been re-pointed has to stay on screen,
    /// or a mistyped address would remove the endpoint from the panel and take the means
    /// of fixing it along with it.
    private var notAnswering: [ModelEndpoint] {
        let answering = Set(modelService.providers.map(\.id))
        return modelService.endpoints.filter {
            $0.isEnabled && $0.isUserConfigured && !answering.contains($0.id)
        }
    }

    private var isEmpty: Bool {
        modelServerService.servers.isEmpty && detected.isEmpty && notProbed.isEmpty && notAnswering.isEmpty
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
                    if !notAnswering.isEmpty {
                        Section("Not answering") {
                            ForEach(notAnswering) { endpoint in
                                ListItemRow(
                                    icon: "questionmark.circle",
                                    iconColor: .secondary,
                                    primaryText: endpoint.displayName,
                                    secondaryLeftText: "port \(String(endpoint.port))",
                                    isSelected: selectedModel == endpoint.id
                                )
                                .tag(endpoint.id)
                            }
                        }
                    }
                    if !notProbed.isEmpty {
                        Section("Not probed") {
                            ForEach(notProbed) { endpoint in
                                ListItemRow(
                                    icon: "pause.circle",
                                    iconColor: .secondary,
                                    primaryText: endpoint.displayName,
                                    secondaryLeftText: "port \(String(endpoint.port))",
                                    isSelected: selectedModel == endpoint.id
                                )
                                .tag(endpoint.id)
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .focused($listFocusedTab, equals: .models)
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
    /// Draft key for unlocking a 401-locked provider; cleared on a successful save.
    @State private var apiKeyDraft = ""
    /// What the last key save actually did. Rendered verbatim, because a save that
    /// silently did nothing was indistinguishable from one that worked (#110).
    @State private var apiKeyStatus: APIKeyStatus?
    /// Editable copy of the selected endpoint's address, reseeded whenever the selection
    /// moves so a half-typed host never lands on a different endpoint.
    @State private var addressDraft: AddressDraft?
    @State private var addressError: String?

    private struct RunTarget: Identifiable {
        let id = UUID(); let modelID: String
    }
    private struct TestTarget: Identifiable {
        let id = UUID(); let name: String; let host: String; let port: UInt16; let api: ModelAPIStyle; let model: String
    }

    private enum APIKeyStatus: Equatable {
        case saved
        case cleared
        case failed(String)
    }

    private struct AddressDraft: Equatable {
        var endpointID: String
        var host: String
        var port: String

        init(_ endpoint: ModelEndpoint) {
            endpointID = endpoint.id
            host = endpoint.host
            port = String(endpoint.port)
        }
    }

    private var server: ManagedModelServer? {
        modelServerService.servers.first { $0.id == selectedModel }
    }
    private var provider: ModelProvider? {
        modelService.providers.first { $0.id == selectedModel }
    }
    /// The configured endpoint behind the selection. A detected provider's id *is* its
    /// endpoint id, so this resolves for both a responding provider and one switched off.
    private var endpoint: ModelEndpoint? {
        modelService.endpoints.first { $0.id == selectedModel }
    }

    var body: some View {
        Group {
            if let server {
                ScrollView { managedDetail(server).padding(20) }
            } else if let provider {
                ScrollView { detectedDetail(provider).padding(20) }
            } else if let endpoint {
                ScrollView { endpointDetail(endpoint).padding(20) }
            } else {
                Text("Select a model")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await networkService.load(showLoading: false) }
        // Runs on appear and on every selection change, which is exactly when the drafts
        // and the last save's outcome stop belonging to what's on screen.
        .task(id: selectedModel) { resetDrafts() }
        .sheet(item: $runTarget) { t in
            RunModelContainerView(preselectedID: t.modelID)
        }
        .sheet(item: $testTarget) { t in
            TestModelPromptView(providerName: t.name, host: t.host, port: t.port, api: t.api, model: t.model)
        }
    }

    private func resetDrafts() {
        apiKeyDraft = ""
        apiKeyStatus = nil
        addressError = nil
        addressDraft = endpoint.map(AddressDraft.init)
    }

    // MARK: - Managed

    private func managedDetail(_ server: ManagedModelServer) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(server.status == .running ? Color.green : Color.red).frame(width: 9, height: 9)
                Text(server.model).font(.title3).fontWeight(.semibold)
                    .lineLimit(1).truncationMode(.middle)
                portBadge(server.port)
                Spacer()
                // Actions live top-right, consistent with the other detail headers.
                HStack(spacing: 8) {
                    if server.status == .running {
                        Button(action: { testTarget = TestTarget(name: server.model, host: server.host, port: server.port, api: server.api, model: server.model) }) {
                            Label("Chat…", systemImage: "text.bubble")
                        }
                        Button(action: { runTarget = RunTarget(modelID: server.id) }) {
                            Label("New sandbox…", systemImage: "shield.lefthalf.filled")
                        }
                    }
                    Button(role: .destructive, action: { modelServerService.stop(server.id) }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    Button(action: { revealLog(server.logPath) }) {
                        Label("Show Log", systemImage: "doc.text")
                    }
                }
                .font(.subheadline)
            }

            labeledRow("On this Mac", "http://\(server.host):\(server.port)/v1")
            if server.reachableFromContainers, let url = containerURL(port: server.port, api: server.api) {
                labeledRow("From containers", url)
            } else if !server.reachableFromContainers {
                Text("Loopback-only - bound to 127.0.0.1, so containers can't reach it.")
                    .font(.caption).foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
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
                portBadge(provider.port)
                Spacer()
                HStack(spacing: 8) {
                    if !provider.requiresAPIKey {
                        Button(action: { testTarget = TestTarget(name: provider.kind.displayName, host: provider.host, port: provider.port, api: provider.api, model: provider.models.first ?? "") }) {
                            Label("Chat…", systemImage: "text.bubble")
                        }
                        Button(action: { runTarget = RunTarget(modelID: provider.id) }) {
                            Label("New sandbox…", systemImage: "shield.lefthalf.filled")
                        }
                    }
                    if endpoint != nil {
                        Button(action: { setProbing(false, id: provider.id) }) {
                            Label("Stop probing", systemImage: "pause.circle")
                        }
                        .help("Stop Orchard contacting this address. It stays in the list under Not probed.")
                    }
                }
                .font(.subheadline)
            }

            labeledRow("On this Mac", provider.hostBaseURL)
            if let url = containerURL(provider) {
                labeledRow("From containers", url)
                if provider.isLoopback {
                    Text("Reachable from containers only if this server is bound to 0.0.0.0 (some default to 127.0.0.1).")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if let endpoint {
                addressEditor(endpoint)
            }

            if provider.requiresAPIKey, let endpoint {
                lockedKeyEditor(endpoint)
            } else if let endpoint, modelService.hasAPIKey(host: endpoint.host, port: endpoint.port) {
                storedKeyRow(endpoint)
            }

            if !provider.requiresAPIKey {
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
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Not probed

    /// Detail for an endpoint that is switched off, or that is on but isn't answering.
    /// Either way there is no provider to describe, so the pane is the address plus the
    /// way back.
    private func endpointDetail(_ endpoint: ModelEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SwiftUI.Image(systemName: endpoint.isEnabled ? "cpu" : "pause.circle")
                Text(endpoint.displayName).font(.title3).fontWeight(.semibold)
                portBadge(endpoint.port)
                Spacer()
                Button(action: { setProbing(!endpoint.isEnabled, id: endpoint.id) }) {
                    Label(endpoint.isEnabled ? "Stop probing" : "Resume probing",
                          systemImage: endpoint.isEnabled ? "pause.circle" : "play.circle")
                }
                .font(.subheadline)
            }

            Text(endpoint.isEnabled
                 ? "Nothing is answering at this address. It stays in the list so you can re-point it or switch it off."
                 : "Orchard is not contacting this address. Nothing here is probed, so a server running on it won't be detected.")
                .font(.caption)
                .foregroundColor(.secondary)

            addressEditor(endpoint)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Endpoint address

    private func addressEditor(_ endpoint: ModelEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Address Orchard probes").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 6) {
                TextField("Host", text: draftHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                Text(":").foregroundColor(.secondary)
                TextField("Port", text: draftPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Save") { saveAddress(endpoint) }
                    .disabled(!addressChanged(from: endpoint))
                if endpoint.isEdited {
                    Button("Restore default") {
                        Task {
                            await modelService.restoreDefaultEndpoint(id: endpoint.id)
                            resetDrafts()
                        }
                    }
                }
            }
            .font(.subheadline)

            if let addressError {
                Text(addressError).font(.caption2).foregroundColor(.orange)
            } else {
                Text("Discovery requests \(endpoint.probeBaseURL)\(endpoint.listPath). Change it if your server listens elsewhere.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var draftHost: Binding<String> {
        Binding(get: { addressDraft?.host ?? "" }, set: { addressDraft?.host = $0 })
    }

    private var draftPort: Binding<String> {
        Binding(get: { addressDraft?.port ?? "" }, set: { addressDraft?.port = $0 })
    }

    private func addressChanged(from endpoint: ModelEndpoint) -> Bool {
        guard let addressDraft else { return false }
        return addressDraft.host != endpoint.host || addressDraft.port != String(endpoint.port)
    }

    /// Validate and apply the address draft. Port 0 is rejected alongside non-numbers and
    /// anything over 65535: it parses, but nothing listens there.
    private func saveAddress(_ endpoint: ModelEndpoint) {
        guard let draft = addressDraft else { return }
        let host = draft.host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else {
            addressError = "Enter a host, for example 127.0.0.1."
            return
        }
        guard let port = UInt16(draft.port.trimmingCharacters(in: .whitespaces)), port > 0 else {
            addressError = "Enter a port between 1 and 65535."
            return
        }
        addressError = nil
        var updated = endpoint
        updated.host = host
        updated.port = port
        Task {
            await modelService.updateEndpoint(updated)
            resetDrafts()
        }
    }

    private func setProbing(_ enabled: Bool, id: String) {
        Task { await modelService.setEndpointEnabled(enabled, id: id) }
    }

    // MARK: - API keys

    private func lockedKeyEditor(_ endpoint: ModelEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("API key required", systemImage: "lock")
                .font(.caption)
                .foregroundColor(.orange)
            Text("This server rejected the probe with 401 or 403. Paste its API key to list models and chat.")
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                SecureField("API key", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Button("Save") { saveAPIKey(apiKeyDraft, endpoint: endpoint) }
                    .disabled(apiKeyDraft.isEmpty)
            }
            keyStatusText(stillLocked: true)
        }
    }

    /// Shown once a key is stored and the server is answering, so the key is visible as a
    /// thing that exists and can be taken away again.
    private func storedKeyRow(_ endpoint: ModelEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("API key stored in your keychain", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Remove") { saveAPIKey("", endpoint: endpoint) }
                    .font(.caption)
            }
            keyStatusText(stillLocked: false)
        }
    }

    /// The outcome of the last save. The "saved but still locked" case is the one that
    /// matters: previously it looked identical to no save happening at all.
    @ViewBuilder
    private func keyStatusText(stillLocked: Bool) -> some View {
        switch apiKeyStatus {
        case .failed(let message):
            Text(message).font(.caption2).foregroundColor(.orange)
        case .saved where stillLocked:
            Text("Key saved to your keychain, but the server still rejected the probe. Check the key, or stop probing this address so Orchard leaves it alone.")
                .font(.caption2)
                .foregroundColor(.orange)
        case .saved:
            Text("Key saved to your keychain.").font(.caption2).foregroundColor(.secondary)
        case .cleared:
            Text("Key removed from your keychain.").font(.caption2).foregroundColor(.secondary)
        case nil:
            EmptyView()
        }
    }

    private func saveAPIKey(_ key: String, endpoint: ModelEndpoint) {
        Task {
            do {
                try await modelService.setAPIKey(key, host: endpoint.host, port: endpoint.port)
                apiKeyDraft = ""
                apiKeyStatus = key.isEmpty ? .cleared : .saved
            } catch {
                // The draft is deliberately left alone: retyping a key someone has just
                // pasted, because the keychain refused it, is a poor apology.
                apiKeyStatus = .failed(error.localizedDescription)
            }
        }
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

    /// As above, but honouring an endpoint the user has pointed at another machine: that
    /// address is already routable from a container, so it needs no gateway at all.
    private func containerURL(_ provider: ModelProvider) -> String? {
        guard let network = networkService.networks.first(where: { $0.id == "default" }) else { return nil }
        return modelService.containerBaseURL(for: provider, on: network)
    }

    private func revealLog(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}
