import SwiftUI

/// Per-container resource view: a master–detail row per metric (current values on the left,
/// the time-series graph on the right). Mounts render beneath the disk stats; network config
/// lives in its own section on the page. Embeds inside the container overview.
struct ContainerStatsPanel: View {
    let container: Container
    @EnvironmentObject var statsService: StatsService

    private var id: String { container.configuration.id }
    private var mounts: [Mount] { container.configuration.mounts }

    var body: some View {
        ResourceStatsPanel(
            currentStats: statsService.containerStats.first { $0.id == id },
            currentSample: statsService.latestSamples[id],
            history: statsService.history.samples(for: StatsKey(id: id)),
            cores: container.configuration.resources.cpus,
            isRunning: container.status.lowercased() == "running",
            emptyMessage: "No statistics — the container is not running.",
            networkFooter: { networkInfoFooter },
            diskFooter: { mountsFooter }
        )
    }

    // MARK: network info (beneath the network graph)

    @ViewBuilder private var networkInfoFooter: some View {
        if !container.networks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Info").font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
                ForEach(container.networks, id: \.hostname) { network in
                    let cleanHostname = network.hostname.hasSuffix(".") ? String(network.hostname.dropLast()) : network.hostname
                    CopyableInfoRow(label: "Hostname", value: cleanHostname, copyValue: cleanHostname)
                    CopyableInfoRow(
                        label: "Address",
                        value: network.address,
                        copyValue: network.address.strippingCIDRSuffix
                    )
                }
            }
        }
    }

    // MARK: mounts (beneath the disk graph)

    @ViewBuilder private var mountsFooter: some View {
        if !mounts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mounts").font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
                ForEach(Array(mounts.enumerated()), id: \.offset) { _, mount in
                    Button {
                        // Navigate to the mount detail view (ContainerMount.id is source->dest).
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NavigateToMount"),
                            object: "\(mount.source)->\(mount.destination)")
                    } label: {
                        Text(mount.destination).font(.subheadline).fontDesign(.monospaced)
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}
