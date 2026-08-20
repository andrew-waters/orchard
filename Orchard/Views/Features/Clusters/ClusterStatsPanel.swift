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

    /// Headline stats are exact for a single node; a multi-node cluster falls back to
    /// the aggregated sample (ContainerStats isn't meaningfully summable across nodes).
    private var currentStats: ContainerStats? {
        guard nodeIds.count == 1, let id = nodeIds.first else { return nil }
        return statsService.containerStats.first { $0.id == id }
    }
}
