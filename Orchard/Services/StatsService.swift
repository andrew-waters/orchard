import Foundation

/// Owns per-container resource stats. Reads the running containers from the container
/// list (owned by `ContainerListService`) and fetches stats for each.
@MainActor
final class StatsService: ObservableObject {
    @Published var containerStats: [ContainerStats] = []
    @Published var isStatsLoading = false

    private let backend: ContainerBackend
    private let alertCenter: AlertCenter
    private let containerList: ContainerListService

    init(backend: ContainerBackend, alertCenter: AlertCenter, containerList: ContainerListService) {
        self.backend = backend
        self.alertCenter = alertCenter
        self.containerList = containerList
    }

    private var isRefreshing = false

    func load(showLoading: Bool = true) async {
        // The 1s poll must not pile up overlapping loads if one runs slow.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if showLoading {
            isStatsLoading = true
            alertCenter.dismiss()
        }

        let runningIds = containerList.containers.filter { $0.status == "running" }.map { $0.configuration.id }
        let backend = self.backend

        // Fetch every container's stats concurrently rather than serially.
        let results: [ContainerStats] = await withTaskGroup(of: ContainerStats?.self) { group in
            for id in runningIds {
                group.addTask { try? await backend.stats(id: id) }
            }
            var collected: [ContainerStats] = []
            for await case let stats? in group {
                collected.append(stats)
            }
            return collected
        }

        containerStats = results
        isStatsLoading = false
        // Alert only when every running container failed (results empty) AND the load was
        // user-initiated — the 1s poll stays silent; StatsView shows a passive panel.
        if showLoading && !runningIds.isEmpty && results.isEmpty {
            alertCenter.error("Unable to read container stats. Check that the container service is running.")
        }
    }

    /// Whether the stats page should show its passive "unavailable" panel: there are
    /// running containers but no stats came back. Drives non-modal UI in StatsView.
    var statsUnavailable: Bool {
        !containerList.containers.filter { $0.status == "running" }.isEmpty && containerStats.isEmpty
    }
}
