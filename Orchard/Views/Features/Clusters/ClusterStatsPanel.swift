import SwiftUI

/// Cluster-wide resource view: the node containers' histories summed tick-by-tick
/// (same fold as the system dashboard), rendered in the standard four-metric panel.
/// With a single node this reads as that node's usage; when the k8s plugin grows
/// worker support the same panel becomes the whole-cluster view for free.
struct ClusterStatsPanel: View {
    let cluster: K8sCluster
    @EnvironmentObject var statsService: StatsService

    private var nodeIds: [String] { cluster.nodes.map(\.id) }

    var body: some View {
        ResourceStatsPanel(
            currentStats: currentStats,
            currentSample: history.last,
            history: history,
            cores: cluster.nodes.reduce(0) { $0 + $1.container.configuration.resources.cpus },
            isRunning: cluster.isRunning,
            emptyMessage: "No statistics — the cluster is not running.",
            networkFooter: { EmptyView() },
            diskFooter: { EmptyView() }
        )
    }

    private var history: [StatsSample] {
        aggregate(nodeIds.map { statsService.history.samples(for: StatsKey(id: $0)) })
    }

    /// Headline stats summed across the cluster's nodes, keyed to the cluster name.
    private var currentStats: ContainerStats? {
        let nodeStats = statsService.containerStats.filter { nodeIds.contains($0.id) }
        guard let first = nodeStats.first else { return nil }
        return nodeStats.dropFirst().reduce(first) { acc, s in
            ContainerStats(
                id: cluster.name,
                cpuUsageUsec: acc.cpuUsageUsec + s.cpuUsageUsec,
                memoryUsageBytes: acc.memoryUsageBytes + s.memoryUsageBytes,
                memoryLimitBytes: acc.memoryLimitBytes + s.memoryLimitBytes,
                blockReadBytes: acc.blockReadBytes + s.blockReadBytes,
                blockWriteBytes: acc.blockWriteBytes + s.blockWriteBytes,
                networkRxBytes: acc.networkRxBytes + s.networkRxBytes,
                networkTxBytes: acc.networkTxBytes + s.networkTxBytes,
                numProcesses: acc.numProcesses + s.numProcesses)
        }
    }
}
