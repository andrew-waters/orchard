import SwiftUI

// The Sandboxes domain (under Compute), in the app's three-column shape: a list of sandbox
// containers (middle column) and a detail pane for the selected one (third column). A
// sandbox is a derived view over an isolated container, with or without a model.

/// Middle column: containers recognised as sandboxes (labelled, or detected via a
/// model-endpoint env var), grouped by who manages them.
struct SandboxesListView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var networkService: NetworkService
    @Binding var selectedSandbox: String?
    @FocusState var listFocusedTab: TabSelection?

    @State private var showNewSandbox = false

    private var sandboxes: [Sandbox] {
        detectSandboxes(containers: containerListService.containers, networks: networkService.networks)
    }
    private var orchard: [Sandbox] { sandboxes.filter { $0.source == .orchard } }
    private var detected: [Sandbox] { sandboxes.filter { $0.source == .detected } }
    /// Sandboxes other apps manage, one group per owner, ordered by the owner's name.
    private var owned: [(owner: SandboxOwner, sandboxes: [Sandbox])] {
        Dictionary(grouping: sandboxes.compactMap { s in s.owner.map { ($0, s) } }, by: \.0)
            .map { (owner: $0.key, sandboxes: $0.value.map(\.1)) }
            .sorted { $0.owner.name.localizedStandardCompare($1.owner.name) == .orderedAscending }
    }

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
                    if !orchard.isEmpty {
                        Section("Orchard") {
                            ForEach(orchard) { sandboxRow($0) }
                        }
                    }
                    ForEach(owned, id: \.owner) { group in
                        Section(group.owner.name) {
                            ForEach(group.sandboxes) { sandboxRow($0) }
                        }
                    }
                    if !detected.isEmpty {
                        Section("Detected") {
                            ForEach(detected) { sandboxRow($0) }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .focused($listFocusedTab, equals: .sandboxes)
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
            secondaryLeftText: sandbox.networkMode.badgeText,
            isSelected: selectedSandbox == sandbox.id,
            ownerBadge: sandbox.owner?.badge
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
            Text("A sandbox is a container kept from your files, keys and network. Use the + button to create one wired to a running model, or label a container com.orchard.sandbox=true. It appears here with how it's contained.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Third column: detail for the selected sandbox - how it's contained (owner, network,
/// resources, mounts), its model endpoint when it has one, and the agent-runner controls
/// (chat, terminal, stop, delete).
struct SandboxDetailView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var networkService: NetworkService
    @EnvironmentObject var terminalLauncher: TerminalLauncher
    let selectedSandbox: String?

    @State private var chatTarget: ChatTarget?
    @State private var pendingConfirmation: OwnedSandboxConfirmation?

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
        .ownedSandboxConfirmation($pendingConfirmation)
    }

    private func detail(_ sandbox: Sandbox) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(sandbox.isRunning ? Color.green : Color.secondary).frame(width: 9, height: 9)
                SwiftUI.Image(systemName: sandbox.kind == .container ? "cube" : "cpu")
                Text(sandbox.name).font(.title3).fontWeight(.semibold)
                    .lineLimit(1).truncationMode(.middle)
                networkBadge(sandbox.networkMode)
                if let owner = sandbox.owner {
                    ownerBadge(owner)
                }
                Spacer()
                // Actions live top-right, consistent with the other detail headers.
                HStack(spacing: 8) {
                    if sandbox.isRunning {
                        if let target = chatTargetFor(sandbox) {
                            Button(action: { chatTarget = target }) {
                                Label("Chat…", systemImage: "text.bubble")
                            }
                        }
                        Button(action: { terminalLauncher.openTerminal(for: sandbox.id) }) {
                            Label("Open Terminal", systemImage: "terminal")
                        }
                        Button(role: .destructive, action: { stop(sandbox) }) {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    } else {
                        Button(role: .destructive, action: { delete(sandbox) }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .font(.subheadline)
            }

            labeledRow("Managed by", managedBy(sandbox.source))
            labeledRow("Network", networkDescription(sandbox))
            labeledRow("CPU", "\(sandbox.cpus) \(sandbox.cpus == 1 ? "core" : "cores")")
            labeledRow("Memory", ByteFormat.string(sandbox.memoryBytes))
            if let endpoint = sandbox.modelEndpoint {
                labeledRow("Model endpoint", endpoint)
            }

            if !sandbox.mounts.isEmpty {
                Divider()
                Text("Mounts").font(.subheadline).fontWeight(.medium)
                ForEach(Array(sandbox.mounts.enumerated()), id: \.offset) { _, mount in
                    mountRow(mount)
                }
            }

            Divider()
            Text(networkCaption(sandbox.networkMode))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stop(_ sandbox: Sandbox) {
        OwnedSandboxConfirmation.run(.stop, containers: containers(for: sandbox), pending: $pendingConfirmation) {
            Task { await containerListService.stopContainer(sandbox.id) }
        }
    }

    /// Delete always asks: there's no undo, and a sandbox another app manages says so.
    private func delete(_ sandbox: Sandbox) {
        let perform: () -> Void = { Task { await containerListService.removeContainer(sandbox.id) } }
        if let owned = OwnedSandboxConfirmation.make(.remove, containers: containers(for: sandbox), perform: perform) {
            pendingConfirmation = owned
        } else {
            pendingConfirmation = OwnedSandboxConfirmation(
                title: "Delete Sandbox?",
                message: "Are you sure you want to delete '\(sandbox.name)'? This action cannot be undone.",
                confirmTitle: "Delete",
                perform: perform
            )
        }
    }

    private func containers(for sandbox: Sandbox) -> [Container] {
        containerListService.containers.filter { $0.configuration.id == sandbox.id }
    }

    private func managedBy(_ source: Sandbox.Source) -> String {
        switch source {
        case .orchard: return "Orchard"
        case .owned(let owner): return owner.name == owner.id ? owner.id : "\(owner.name) (\(owner.id))"
        case .detected: return "Unknown (detected from a model env var)"
        }
    }

    private func networkDescription(_ sandbox: Sandbox) -> String {
        guard let network = sandbox.networkName else { return sandbox.networkMode.displayName }
        return "\(sandbox.networkMode.displayName) on \(network)"
    }

    private func networkCaption(_ mode: SandboxNetworkMode) -> String {
        switch mode {
        case .hostOnly:
            return "This container is on a host-only network: it can reach the host, including any model served there, but has no internet access."
        case .allowlist:
            return "This container's egress is limited to an allow list kept by the app that manages it."
        case .nat:
            return "This container's network allows internet access. For a no-egress sandbox, use a host-only network."
        }
    }

    private func networkBadge(_ mode: SandboxNetworkMode) -> some View {
        let color: Color = mode == .nat ? .orange : .green
        return HStack(spacing: 4) {
            SwiftUI.Image(systemName: mode == .nat ? "exclamationmark.shield" : "lock.shield")
            Text(mode.badgeText)
        }
        .font(.caption)
        .foregroundColor(color)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func ownerBadge(_ owner: SandboxOwner) -> some View {
        Text(owner.badge)
            .font(.caption)
            .foregroundColor(.purple)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Color.purple.opacity(0.12), in: Capsule())
            .help("\(owner.name) manages this sandbox")
    }

    private func mountRow(_ mount: SandboxMount) -> some View {
        let access: String
        switch mount.access {
        case .readOnly: access = "read-only"
        case .readWrite: access = "read-write"
        case .tmpfs: access = "tmpfs (masked)"
        }
        return HStack(alignment: .top, spacing: 8) {
            Text(access).font(.caption)
                .foregroundColor(mount.access == .readWrite ? .orange : .secondary)
                .frame(width: 120, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(mount.destination).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                if !mount.source.isEmpty {
                    Text(mount.source).font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary).textSelection(.enabled)
                }
            }
            Spacer()
        }
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 120, alignment: .leading)
            Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Spacer()
        }
    }

    private func chatTargetFor(_ sandbox: Sandbox) -> ChatTarget? {
        // Only offer chat for endpoints the tester speaks (OpenAI/Ollama); Anthropic-style
        // sandboxes are recognised but not chattable here, and sandboxes with no model have
        // nothing to chat to.
        guard let endpoint = sandbox.modelEndpoint,
              let api = sandbox.chatAPI,
              let url = URL(string: endpoint),
              let port = url.port, port > 0, port <= 65535 else { return nil }
        return ChatTarget(name: sandbox.name, port: UInt16(port), api: api)
    }
}
