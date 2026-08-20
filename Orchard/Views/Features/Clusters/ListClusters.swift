import SwiftUI
import AppKit

struct ClustersListView: View {
    @EnvironmentObject var clusterService: ClusterService
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var terminalLauncher: TerminalLauncher
    @Binding var selectedCluster: String?
    @Binding var lastSelectedCluster: String?
    @Binding var searchText: String
    @Binding var showCreateClusterSheet: Bool
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
        .task {
            // Node containers surface through the regular container refresh; the only
            // thing to probe is whether the CLI plugin exists for lifecycle actions.
            await clusterService.probePluginAvailability()
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

    private var clustersListView: some View {
        List(selection: $selectedCluster) {
            ForEach(filteredClusters) { cluster in
                ClusterRowView(
                    cluster: cluster,
                    isSelected: selectedCluster == cluster.name,
                    isBusy: clusterService.busyClusters.contains(cluster.name)
                )
                .contextMenu {
                    contextMenu(for: cluster)
                }
                .tag(cluster.name)
            }
        }
        .listStyle(PlainListStyle())
        .animation(.easeInOut(duration: 0.3), value: containerListService.containers)
        .focused($listFocusedTab, equals: .clusters)
        .onChange(of: selectedCluster) { _, newValue in
            lastSelectedCluster = newValue
        }
    }

    @ViewBuilder
    private func contextMenu(for cluster: K8sCluster) -> some View {
        let busy = clusterService.busyClusters.contains(cluster.name)
        if !cluster.isRunning {
            Button("Start Cluster") {
                Task { await clusterService.start(name: cluster.name) }
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

        var body: some View {
            let nodeCount = cluster.nodes.count
            ListItemRow(
                icon: "helm",
                iconColor: cluster.isRunning ? .green : .secondary,
                primaryText: cluster.name,
                secondaryLeftText: nodeCount == 1 ? "1 node" : "\(nodeCount) nodes",
                secondaryRightText: isBusy ? "Working…" : cluster.status.capitalized,
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
