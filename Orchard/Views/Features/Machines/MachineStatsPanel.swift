import SwiftUI

/// Per-machine resource view — the same four-metric panel as containers, fed from the
/// machine's backing-container stats via `StatsService`'s machine accessors.
struct MachineStatsPanel: View {
    let machine: Machine
    @EnvironmentObject var statsService: StatsService

    var body: some View {
        ResourceStatsPanel(
            currentStats: statsService.machineRawStats(machine.id),
            currentSample: statsService.machineSample(machine.id),
            history: statsService.machineHistory(machine.id),
            cores: machine.cpus,
            isRunning: machine.isRunning,
            emptyMessage: "No statistics — the machine is not running.",
            networkFooter: { networkFooter },
            diskFooter: { EmptyView() }
        )
    }

    @ViewBuilder private var networkFooter: some View {
        if let ip = machine.ipAddress, !ip.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Info").font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
                CopyableInfoRow(label: "IP Address", value: ip, copyValue: ip)
            }
        }
    }
}
