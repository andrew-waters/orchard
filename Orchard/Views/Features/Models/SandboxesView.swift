import SwiftUI

// The Sandboxes domain (under Compute), in the app's three-column shape: a list of sandbox
// containers (middle column) and a detail pane for the selected one (third column). A
// sandbox is a derived view over a container wired to a local model.

/// Middle column: containers recognised as sandboxes (Orchard-labelled or detected via a
/// model-endpoint env var).
struct SandboxesListView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var networkService: NetworkService
    @Binding var selectedSandbox: String?

    @State private var showNewSandbox = false

    private var sandboxes: [Sandbox] {
        detectSandboxes(containers: containerListService.containers, networks: networkService.networks)
    }
    private var managed: [Sandbox] { sandboxes.filter { $0.source == .managed } }
    private var detected: [Sandbox] { sandboxes.filter { $0.source == .detected } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sandboxes").font(.headline)
                Spacer()
                Button(action: { showNewSandbox = true }) {
                    SwiftUI.Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Create a new sandbox")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if sandboxes.isEmpty {
                emptyState
            } else {
                List(selection: $selectedSandbox) {
                    if !managed.isEmpty {
                        Section("Wired by Orchard") {
                            ForEach(managed) { sandboxRow($0) }
                        }
                    }
                    if !detected.isEmpty {
                        Section("Detected") {
                            ForEach(detected) { sandboxRow($0) }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .task { await networkService.load(showLoading: false) }
        .sheet(isPresented: $showNewSandbox) { RunModelContainerView() }
    }

    private func sandboxRow(_ sandbox: Sandbox) -> some View {
        ListItemRow(
            icon: sandbox.kind == .container ? "cube" : "cpu",
            iconColor: sandbox.isRunning ? .green : .secondary,
            primaryText: sandbox.name,
            secondaryLeftText: sandbox.isIsolated ? "Isolated" : "Egress open",
            isSelected: selectedSandbox == sandbox.id
        )
        .tag(sandbox.id)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            SwiftUI.Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text("No sandboxes yet")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("Use the + button to create one wired to a running model, or start a sandbox from a model's detail. It appears here with its endpoint and isolation.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Third column: detail for the selected sandbox - endpoint, isolation, and the
/// agent-runner controls (chat, terminal, kill switch).
struct SandboxDetailView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var networkService: NetworkService
    @EnvironmentObject var terminalLauncher: TerminalLauncher
    let selectedSandbox: String?

    @State private var chatTarget: ChatTarget?

    private struct ChatTarget: Identifiable {
        let id = UUID(); let name: String; let port: UInt16; let api: ModelAPIStyle
    }

    private var sandbox: Sandbox? {
        detectSandboxes(containers: containerListService.containers, networks: networkService.networks)
            .first { $0.id == selectedSandbox }
    }

    var body: some View {
        Group {
            if let sandbox {
                ScrollView { detail(sandbox).padding(20) }
            } else {
                Text("Select a sandbox")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $chatTarget) { t in
            TestModelPromptView(providerName: t.name, port: t.port, api: t.api, model: "")
        }
    }

    private func detail(_ sandbox: Sandbox) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(sandbox.isRunning ? Color.green : Color.secondary).frame(width: 9, height: 9)
                SwiftUI.Image(systemName: sandbox.kind == .container ? "cube" : "cpu")
                Text(sandbox.name).font(.title3).fontWeight(.semibold)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                isolationBadge(sandbox.isIsolated)
            }

            if let endpoint = sandbox.modelEndpoint {
                labeledRow("Model endpoint", endpoint)
            }
            labeledRow("Source", sandbox.source == .managed ? "Wired by Orchard" : "Detected (env var)")

            if sandbox.isRunning {
                HStack(spacing: 8) {
                    if let target = chatTargetFor(sandbox) {
                        Button(action: { chatTarget = target }) {
                            Label("Chat…", systemImage: "text.bubble")
                        }
                    }
                    Button(action: { terminalLauncher.openTerminal(for: sandbox.id) }) {
                        Label("Open Terminal", systemImage: "terminal")
                    }
                    Button(role: .destructive, action: {
                        Task { await containerListService.stopContainer(sandbox.id) }
                    }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }
                .font(.subheadline)
            }

            Divider()
            Text(sandbox.isIsolated
                 ? "This container is on a host-only network: it can reach the model but has no internet access."
                 : "This container's network allows internet access. For a no-egress sandbox, use a host-only network.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isolationBadge(_ isolated: Bool) -> some View {
        HStack(spacing: 4) {
            SwiftUI.Image(systemName: isolated ? "lock.shield" : "exclamationmark.shield")
            Text(isolated ? "Isolated" : "Egress open")
        }
        .font(.caption)
        .foregroundColor(isolated ? .green : .orange)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background((isolated ? Color.green : Color.orange).opacity(0.12), in: Capsule())
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 120, alignment: .leading)
            Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Spacer()
        }
    }

    private func chatTargetFor(_ sandbox: Sandbox) -> ChatTarget? {
        guard let endpoint = sandbox.modelEndpoint,
              let url = URL(string: endpoint),
              let port = url.port, port > 0, port <= 65535 else { return nil }
        let api: ModelAPIStyle = endpoint.contains("/v1") ? .openAI : .ollama
        return ChatTarget(name: sandbox.name, port: UInt16(port), api: api)
    }
}
