import SwiftUI
import AppKit

struct ClusterDetailView: View {
    @EnvironmentObject var clusterService: ClusterService
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var terminalLauncher: TerminalLauncher
    let clusterName: String
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?

    @State private var showLoadImageSheet = false
    @State private var showDeleteConfirmation = false
    /// Set briefly after a successful write-config so the button confirms in place.
    @State private var kubeconfigWritten = false
    @State private var copiedPath = false

    private var cluster: K8sCluster? {
        K8sCluster.group(containers: containerListService.containers)
            .first(where: { $0.name == clusterName })
    }

    var body: some View {
        if let cluster {
            VStack(spacing: 0) {
                header(cluster)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        kubectlCard(cluster)
                        nodesSection(cluster)
                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showLoadImageSheet) {
                LoadImageSheet(clusterName: cluster.name)
            }
            .confirmationDialog(
                "Delete '\(cluster.name)'? This permanently removes the cluster's node containers and any workloads running on them.",
                isPresented: $showDeleteConfirmation
            ) {
                Button("Delete Cluster", role: .destructive) {
                    Task { await clusterService.delete(name: cluster.name) }
                }
            }
        } else {
            Text("Cluster not found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    private func header(_ cluster: K8sCluster) -> some View {
        let busy = clusterService.busyClusters.contains(cluster.name)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(cluster.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Circle()
                        .fill(cluster.isRunning ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .help(cluster.status.capitalized)
                }
                Text(cluster.nodes.count == 1 ? "Kubernetes cluster · 1 node" : "Kubernetes cluster · \(cluster.nodes.count) nodes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()

            HStack(spacing: 12) {
                if busy {
                    ProgressView().controlSize(.small)
                }
                if !cluster.isRunning {
                    Button("Start") {
                        Task { await clusterService.start(name: cluster.name) }
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .disabled(busy)
                }
                if cluster.isRunning {
                    Button("Terminal (kubectl)") {
                        terminalLauncher.openTerminal(runningCommand: ClusterService.kubectlTerminalCommand(cluster: cluster.name))
                    }
                    .buttonStyle(BorderedButtonStyle())

                    Button("Load Image…") { showLoadImageSheet = true }
                        .buttonStyle(BorderedButtonStyle())
                        .disabled(clusterService.isLoadingImage)
                }
                Button("Delete") { showDeleteConfirmation = true }
                    .buttonStyle(BorderedButtonStyle())
                    .tint(.red)
                    .disabled(busy)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - kubectl access

    private func kubectlCard(_ cluster: K8sCluster) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("kubectl Access")
                .font(.headline)

            Text("`container k8s write-config` merges this cluster's context (named `\(cluster.name)`) into your kubeconfig.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(kubeconfigWritten ? "Kubeconfig Written ✓" : "Write Kubeconfig") {
                    Task {
                        if await clusterService.writeConfig(cluster: cluster.name) {
                            kubeconfigWritten = true
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            kubeconfigWritten = false
                        }
                    }
                }
                .disabled(kubeconfigWritten)

                Button(copiedPath ? "Copied ✓" : "Copy Kubeconfig Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ClusterService.kubeconfigPath, forType: .string)
                    copiedPath = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        copiedPath = false
                    }
                }

                Text(ClusterService.kubeconfigPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Nodes

    private func nodesSection(_ cluster: K8sCluster) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nodes")
                .font(.headline)

            VStack(spacing: 0) {
                nodesHeader

                Divider()

                ForEach(cluster.nodes) { node in
                    nodeRow(node)
                    if node.id != cluster.nodes.last?.id {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            singleNodeBanner
        }
    }

    /// Honest about the current ceiling: the k8s plugin creates single-node clusters;
    /// worker provisioning is in development upstream (#87). Same banner style as the
    /// machine detail's init-system warning.
    private var singleNodeBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            SwiftUI.Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Single-node clusters only")
                    .font(.subheadline).fontWeight(.medium)
                Text("Apple container's k8s plugin can't add worker nodes yet, so every cluster is one control-plane node that also runs workloads. Worker nodes will appear in this table once the plugin supports adding them.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var nodesHeader: some View {
        HStack(spacing: 0) {
            headerCell("Node").frame(maxWidth: .infinity, alignment: .leading)
            headerCell("Role").frame(width: 110, alignment: .leading)
            headerCell("Status").frame(width: 80, alignment: .leading)
            headerCell("IP").frame(width: 120, alignment: .leading)
            headerCell("CPUs").frame(width: 50, alignment: .trailing)
            headerCell("Memory").frame(width: 80, alignment: .trailing)
            headerCell("Ports").frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.separatorColor).opacity(0.5))
    }

    private func headerCell(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.medium)
    }

    private func nodeRow(_ node: K8sClusterNode) -> some View {
        let ports = node.container.configuration.publishedPorts
            .map { "\($0.hostPort)→\($0.containerPort)" }
            .joined(separator: ", ")
        return HStack(spacing: 0) {
            // Node name jumps to the backing container, like ContainerTable rows.
            Button(action: {
                selectedTab = .containers
                selectedContainer = node.id
            }) {
                HStack {
                    SwiftUI.Image(systemName: "cube")
                        .foregroundStyle(node.isRunning ? .green : .gray)
                    Text(node.id)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Show this node in Containers")

            Group {
                if let role = node.role {
                    Text(role)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, alignment: .leading)

            Text(node.container.status.capitalized)
                .foregroundStyle(node.isRunning ? .primary : .secondary)
                .frame(width: 80, alignment: .leading)

            Text(node.address?.strippingCIDRSuffix ?? "—")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(width: 120, alignment: .leading)

            Text("\(node.container.configuration.resources.cpus)")
                .font(.system(.body, design: .monospaced))
                .frame(width: 50, alignment: .trailing)

            Text(ByteFormat.memory(node.container.configuration.resources.memoryInBytes))
                .font(.system(.body, design: .monospaced))
                .frame(width: 80, alignment: .trailing)

            Text(ports.isEmpty ? "—" : ports)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Load image sheet

/// Load one of Orchard's local images into the cluster's containerd, so cluster
/// workloads can reference images built or pulled outside the cluster.
private struct LoadImageSheet: View {
    @EnvironmentObject var clusterService: ClusterService
    @EnvironmentObject var imageService: ImageService
    @Environment(\.dismiss) private var dismiss
    let clusterName: String

    @State private var selectedReference: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Load Image into '\(clusterName)'")
                    .font(.title3).fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .bottom)

            VStack(alignment: .leading, spacing: 8) {
                if imageService.images.isEmpty {
                    Text("No local images. Pull or build an image first.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("The image is exported from the local store and imported into the cluster nodes' containerd, so pods can use it without a registry.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Image", selection: $selectedReference) {
                        ForEach(imageService.images, id: \.reference) { image in
                            Text(image.reference).tag(image.reference)
                        }
                    }
                    .labelsHidden()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                if clusterService.isLoadingImage {
                    ProgressView().controlSize(.small)
                    Text("Loading image…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Load Image") { load() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedReference.isEmpty || clusterService.isLoadingImage)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .top)
        }
        .frame(width: 460, height: 260)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if selectedReference.isEmpty {
                selectedReference = imageService.images.first?.reference ?? ""
            }
        }
    }

    private func load() {
        Task {
            let loaded = await clusterService.loadImage(cluster: clusterName, reference: selectedReference)
            if loaded { await MainActor.run { dismiss() } }
        }
    }
}
