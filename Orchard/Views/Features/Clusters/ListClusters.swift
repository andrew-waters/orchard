import SwiftUI
import AppKit

struct ClustersListView: View {
    /// A row in the list: a cluster, or one of its nodes listed under it. A control plane's id
    /// is its cluster's name, so the two need telling apart.
    private enum Row: Hashable {
        case cluster(String)
        case node(cluster: String, id: String)
    }

    @EnvironmentObject var clusterService: ClusterService
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var terminalLauncher: TerminalLauncher
    @Binding var selectedCluster: String?
    @Binding var lastSelectedCluster: String?
    @Binding var searchText: String
    @Binding var showCreateClusterSheet: Bool
    @State private var recreateSettings: ClusterRecreateSettings?
    @FocusState var listFocusedTab: TabSelection?

    private var clusters: [K8sCluster] {
        K8sCluster.group(containers: containerListService.containers)
    }

    private var filteredClusters: [K8sCluster] {
        guard !searchText.isEmpty else { return clusters }
        let query = searchText.lowercased()
        return clusters.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            contentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showCreateClusterSheet) {
            CreateClusterView()
        }
        .sheet(item: $recreateSettings) { settings in
            CreateClusterView(recreating: settings)
        }
        .task {
            // Node containers surface through the regular container refresh; the only
            // thing to probe is whether the CLI plugin exists for lifecycle actions.
            await clusterService.probePluginAvailability()
        }
        .task {
            // Clusters created with no CNI wait for the user to install one. Checked while the
            // list is on screen, which it is beside a cluster's detail; ends with the view.
            while !Task.isCancelled {
                await clusterService.refreshCNIReadiness(of: clusters)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if clusterService.pluginAvailability == .missingPlugin {
            // Authoritative even if labelled node containers linger (e.g. after a
            // downgrade): every lifecycle action would fail without the plugin.
            pluginMissingStateView
        } else if !clusters.isEmpty {
            clustersListView
        } else {
            emptyStateView
        }
    }

    private var emptyStateView: some View {
        VStack {
            SwiftUI.Image(systemName: "helm")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            Text("No Clusters")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Create a local Kubernetes cluster to get started")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Create Cluster") { showCreateClusterSheet = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
                .disabled(clusterService.pluginAvailability != .available)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Guardrail for installs without the k8s plugin (container releases before 1.2.2).
    private var pluginMissingStateView: some View {
        VStack(spacing: 6) {
            SwiftUI.Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("Kubernetes Plugin Not Installed")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Local Kubernetes clusters need the `k8s` plugin that ships with Apple container 1.2.2 or later. Update your `container` install to use clusters.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Button("View upgrade instructions") {
                if let url = URL(string: "https://github.com/apple/container?tab=readme-ov-file#install-or-upgrade") {
                    NSWorkspace.shared.open(url)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The list's selection, kept as the cluster plus `ClusterService.selectedNode`.
    private var selection: Binding<Row?> {
        Binding(
            get: {
                guard let selectedCluster else { return nil }
                if let node = clusterService.selectedNode { return .node(cluster: selectedCluster, id: node) }
                return .cluster(selectedCluster)
            },
            set: { row in
                switch row {
                case .cluster(let name):
                    clusterService.selectedNode = nil
                    selectedCluster = name
                case .node(let cluster, let id):
                    clusterService.selectedNode = id
                    selectedCluster = cluster
                case nil:
                    clusterService.selectedNode = nil
                    selectedCluster = nil
                }
            })
    }

    private var clustersListView: some View {
        List(selection: selection) {
            ForEach(filteredClusters) { cluster in
                let isExpanded = clusterService.expandedClusters.contains(cluster.name)
                HStack(spacing: 4) {
                    disclosureButton(for: cluster, isExpanded: isExpanded)
                    ClusterRowView(
                        cluster: cluster,
                        isSelected: selectedCluster == cluster.name && clusterService.selectedNode == nil,
                        isBusy: clusterService.busyClusters.contains(cluster.name),
                        isAwaitingCNI: clusterService.awaitingCNI.contains(cluster.name)
                    )
                }
                .contextMenu {
                    contextMenu(for: cluster)
                }
                .tag(Row.cluster(cluster.name))

                if isExpanded {
                    ForEach(cluster.nodes) { node in
                        NodeRowView(
                            node: node,
                            isSelected: selectedCluster == cluster.name && clusterService.selectedNode == node.id
                        )
                        .padding(.leading, 24)
                        .tag(Row.node(cluster: cluster.name, id: node.id))
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
        .animation(.easeInOut(duration: 0.3), value: containerListService.containers)
        .focused($listFocusedTab, equals: .clusters)
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in handleArrow(press.key) }
        .onChange(of: selectedCluster) { _, newValue in
            lastSelectedCluster = newValue
            // Another view (a cross-link, the command palette) picked a cluster: show it, not a
            // node left selected from a different one.
            if let node = clusterService.selectedNode,
               !clusters.contains(where: { $0.name == newValue && $0.nodes.contains { $0.id == node } }) {
                clusterService.selectedNode = nil
            }
        }
        .onChange(of: containerListService.containers) { _, _ in
            // A node that has gone falls back to its cluster.
            if let node = clusterService.selectedNode,
               !clusters.contains(where: { $0.nodes.contains { $0.id == node } }) {
                clusterService.selectedNode = nil
            }
        }
    }

    /// A chevron for a cluster with workers. A single-node cluster gets the same width of
    /// space, so every cluster's name lines up.
    @ViewBuilder
    private func disclosureButton(for cluster: K8sCluster, isExpanded: Bool) -> some View {
        if cluster.nodes.count > 1 {
            Button {
                setExpanded(!isExpanded, cluster: cluster.name)
            } label: {
                SwiftUI.Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide nodes" : "Show nodes")
        } else {
            Color.clear.frame(width: 14, height: 14)
        }
    }

    private func setExpanded(_ expanded: Bool, cluster name: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expanded {
                clusterService.expandedClusters.insert(name)
            } else {
                clusterService.expandedClusters.remove(name)
                // A node hidden by the collapse hands the selection back to its cluster.
                if selectedCluster == name { clusterService.selectedNode = nil }
            }
        }
    }

    /// Left and right arrows, as in a Finder outline: right expands a cluster, then steps
    /// into its first node; left steps from a node back to its cluster, then collapses it.
    private func handleArrow(_ key: KeyEquivalent) -> KeyPress.Result {
        guard let name = selectedCluster,
              let cluster = filteredClusters.first(where: { $0.name == name }),
              cluster.nodes.count > 1
        else { return .ignored }
        let isExpanded = clusterService.expandedClusters.contains(name)
        switch key {
        case .rightArrow:
            guard clusterService.selectedNode == nil else { return .ignored }
            if isExpanded {
                clusterService.selectedNode = cluster.nodes.first?.id
            } else {
                setExpanded(true, cluster: name)
            }
            return .handled
        case .leftArrow:
            if clusterService.selectedNode != nil {
                clusterService.selectedNode = nil
            } else if isExpanded {
                setExpanded(false, cluster: name)
            } else {
                return .ignored
            }
            return .handled
        default:
            return .ignored
        }
    }

    @ViewBuilder
    private func contextMenu(for cluster: K8sCluster) -> some View {
        let busy = clusterService.busyClusters.contains(cluster.name)
        if !cluster.isRunning {
            Button("Recreate Cluster…") {
                Task { recreateSettings = await clusterService.prepareRecreate(cluster) }
            }
            .disabled(busy)
        }
        Button("Write Kubeconfig") {
            Task { await clusterService.writeConfig(cluster: cluster.name) }
        }
        Button("Copy Kubeconfig Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ClusterService.kubeconfigPath, forType: .string)
        }
        Button("Terminal (kubectl)") {
            terminalLauncher.openTerminal(runningCommand: ClusterService.kubectlTerminalCommand(cluster: cluster.name))
        }
        Divider()
        Button("Delete Cluster", role: .destructive) {
            confirmClusterDeletion(cluster)
        }
        .disabled(busy)
    }

    private struct ClusterRowView: View {
        let cluster: K8sCluster
        let isSelected: Bool
        let isBusy: Bool
        let isAwaitingCNI: Bool

        var body: some View {
            let nodeCount = cluster.nodes.count
            ListItemRow(
                icon: "helm",
                iconColor: isAwaitingCNI ? .orange : cluster.isRunning ? .green : .secondary,
                primaryText: cluster.name,
                secondaryLeftText: nodeCount == 1 ? "1 node" : "\(nodeCount) nodes",
                secondaryRightText: isBusy ? "Working…" : isAwaitingCNI ? "Waiting for CNI" : cluster.status.capitalized,
                isSelected: isSelected
            )
        }
    }

    private struct NodeRowView: View {
        let node: K8sClusterNode
        let isSelected: Bool

        var body: some View {
            ListItemRow(
                icon: "cube",
                iconColor: node.isRunning ? .green : .secondary,
                primaryText: node.id,
                secondaryLeftText: node.container.pluginRoleDisplay,
                secondaryRightText: node.container.status.capitalized,
                isSelected: isSelected
            )
        }
    }

    private func confirmClusterDeletion(_ cluster: K8sCluster) {
        let alert = NSAlert()
        alert.messageText = "Delete Cluster"
        alert.informativeText = "Are you sure you want to delete '\(cluster.name)'? This permanently removes the cluster's node containers and any workloads running on them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            Task { await clusterService.delete(name: cluster.name) }
        }
    }
}
