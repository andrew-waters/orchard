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

    func load(showLoading: Bool = true) async {
        if showLoading {
            await MainActor.run {
                isStatsLoading = true
                self.alertCenter.dismiss()
            }
        }

        let runningContainers = containerList.containers.filter { $0.status == "running" }

        var allStats: [ContainerStats] = []
        var failedContainers: [String] = []
        for container in runningContainers {
            do {
                let stats = try await backend.stats(id: container.configuration.id)
                allStats.append(stats)
            } catch {
                failedContainers.append(container.configuration.id)
                Log.containers.error("Failed to load stats for container \(container.configuration.id): \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            self.containerStats = allStats
            self.isStatsLoading = false
            // Only surface an error if every running container failed (one broken
            // container shouldn't blank the page) AND this was user-initiated — the 1s
            // poll must not storm modals. StatsView shows a passive inline panel instead.
            if showLoading
                && !runningContainers.isEmpty
                && failedContainers.count == runningContainers.count {
                self.alertCenter.error("Unable to read container stats. Check that the container service is running.")
            }
        }
    }

    /// Whether the stats page should show its passive "unavailable" panel: there are
    /// running containers but no stats came back. Drives non-modal UI in StatsView.
    var statsUnavailable: Bool {
        !containerList.containers.filter { $0.status == "running" }.isEmpty && containerStats.isEmpty
    }
}
