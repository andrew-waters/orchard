import SwiftUI

enum StatsSortColumn: String {
    case container, cpu, memory, network, block, pids
}

/// Recent history per metric for one container's row sparklines.
struct RowSparklines {
    var cpu: [Double] = []
    var memory: [Double] = []
    var network: [Double] = []
    var disk: [Double] = []
}

struct StatsTableView: View {
    let containerStats: [ContainerStats]
    /// Latest derived sample per container id — supplies real CPU% (raw stats can't).
    var latestSamples: [String: StatsSample] = [:]
    /// Recent per-metric history per container id — drives the per-row sparklines.
    var sparklines: [String: RowSparklines] = [:]
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    let emptyStateMessage: String
    let showContainerColumn: Bool
    /// Row identity presentation + navigation, so the same table serves containers and machines.
    var nameColumnTitle: String = "Container"
    var rowIcon: String = "cube"
    var rowIconColor: Color = .green
    /// Invoked when a row's name is clicked. Defaults to selecting the container.
    var onSelectRow: ((String) -> Void)? = nil

    @AppStorage("statsSortColumn") private var sortColumn: StatsSortColumn = .container
    @AppStorage("statsSortAscending") private var sortAscending: Bool = true

    private var sortedStats: [ContainerStats] {
        let ascending = sortAscending
        return containerStats.sorted { a, b in
            let result: Bool
            switch sortColumn {
            case .container:
                result = a.id.localizedCaseInsensitiveCompare(b.id) == .orderedAscending
            case .cpu:
                // Sort by current load, not lifetime CPU-seconds. No sample yet sorts low.
                result = (latestSamples[a.id]?.cpuPercent ?? -1) < (latestSamples[b.id]?.cpuPercent ?? -1)
            case .memory:
                result = a.memoryUsageBytes < b.memoryUsageBytes
            case .network:
                result = (a.networkRxBytes + a.networkTxBytes) < (b.networkRxBytes + b.networkTxBytes)
            case .block:
                result = (a.blockReadBytes + a.blockWriteBytes) < (b.blockReadBytes + b.blockWriteBytes)
            case .pids:
                result = a.numProcesses < b.numProcesses
            }
            return ascending ? result : !result
        }
    }

    /// Real CPU% from the latest sample, or "collecting" placeholder until two reads exist.
    @ViewBuilder
    private func cpuValue(for id: String) -> some View {
        if let pct = latestSamples[id]?.cpuPercent {
            Text(String(format: "%.1f%%", pct))
                .font(.system(.body, design: .monospaced))
        } else {
            Text("--")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func toggleSort(_ column: StatsSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
    }

    @ViewBuilder
    private func columnHeader(_ title: String, column: StatsSortColumn, width: CGFloat? = nil, alignment: Alignment = .trailing) -> some View {
        let button = Button(action: { toggleSort(column) }) {
            HStack(spacing: 2) {
                if alignment == .leading {
                    Text(title)
                    if sortColumn == column {
                        SwiftUI.Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                    }
                    Spacer()
                } else {
                    Spacer()
                    Text(title)
                    if sortColumn == column {
                        SwiftUI.Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                    }
                }
            }
            .font(.subheadline)
            .fontWeight(.medium)
        }
        .buttonStyle(.plain)

        if let width = width {
            button.frame(width: width, alignment: alignment)
        } else {
            button.frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    var body: some View {
        if containerStats.isEmpty {
            HStack {
                SwiftUI.Image(systemName: "chart.bar")
                    .foregroundStyle(.secondary)
                Text(emptyStateMessage)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        } else {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    if showContainerColumn {
                        columnHeader(nameColumnTitle, column: .container, alignment: .leading)
                        columnHeader("CPU", column: .cpu, width: 120)
                        columnHeader("Memory", column: .memory, width: 150)
                        columnHeader("Network I/O", column: .network, width: 150)
                        columnHeader("Block I/O", column: .block, width: 150)
                        columnHeader("PIDs", column: .pids, width: 70)
                    } else {
                        HStack {
                            columnHeader("CPU", column: .cpu)
                            columnHeader("Memory", column: .memory)
                            columnHeader("Network I/O", column: .network)
                            columnHeader("Block I/O", column: .block)
                            columnHeader("PIDs", column: .pids)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.separatorColor).opacity(0.5))

                Divider()

                // Stats rows
                ForEach(sortedStats, id: \.id) { stats in
                    HStack(spacing: 0) {
                        if showContainerColumn {
                            // Resource name (clickable)
                            Button(action: {
                                if let onSelectRow {
                                    onSelectRow(stats.id)
                                } else {
                                    selectedTab = .containers
                                    selectedContainer = stats.id
                                }
                            }) {
                                HStack {
                                    SwiftUI.Image(systemName: rowIcon)
                                        .foregroundStyle(rowIconColor)
                                    Text(stats.id)
                                        .foregroundStyle(.blue)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .trailing, spacing: 3) {
                                cpuValue(for: stats.id)
                                Sparkline(values: sparklines[stats.id]?.cpu ?? [], color: .blue, maxValue: 100)
                            }
                            .frame(width: 120, alignment: .trailing)

                            VStack(alignment: .trailing, spacing: 3) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(stats.formattedMemoryUsage)")
                                        .font(.system(.caption, design: .monospaced))
                                    Text("\(String(format: "%.1f", stats.memoryUsagePercent))%")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Sparkline(values: sparklines[stats.id]?.memory ?? [], color: .purple, maxValue: 100)
                            }
                            .frame(width: 150, alignment: .trailing)

                            VStack(alignment: .trailing, spacing: 3) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\u{2193} \(stats.formattedNetworkRx)")
                                        .font(.system(.caption, design: .monospaced))
                                    Text("\u{2191} \(stats.formattedNetworkTx)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Sparkline(values: sparklines[stats.id]?.network ?? [], color: .green)
                            }
                            .frame(width: 150, alignment: .trailing)

                            VStack(alignment: .trailing, spacing: 3) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("R \(stats.formattedBlockRead)")
                                        .font(.system(.caption, design: .monospaced))
                                    Text("W \(stats.formattedBlockWrite)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Sparkline(values: sparklines[stats.id]?.disk ?? [], color: .teal)
                            }
                            .frame(width: 150, alignment: .trailing)

                            Text("\(stats.numProcesses)")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 70, alignment: .trailing)
                        } else {
                            HStack {
                                cpuValue(for: stats.id)
                                    .frame(maxWidth: .infinity, alignment: .trailing)

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(stats.formattedMemoryUsage)")
                                        .font(.system(.caption, design: .monospaced))
                                    Text("\(String(format: "%.1f", stats.memoryUsagePercent))%")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\u{2193} \(stats.formattedNetworkRx)")
                                        .font(.system(.caption, design: .monospaced))
                                    Text("\u{2191} \(stats.formattedNetworkTx)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("R \(stats.formattedBlockRead)")
                                        .font(.system(.caption, design: .monospaced))
                                    Text("W \(stats.formattedBlockWrite)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)

                                Text("\(stats.numProcesses)")
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.clear)

                    if stats.id != sortedStats.last?.id {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}
