import SwiftUI

struct StatsTableView: View {
    let containerStats: [ContainerStats]
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    let emptyStateMessage: String
    let showContainerColumn: Bool

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
                        Text("Container")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("CPU")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(width: 100, alignment: .trailing)

                        Text("Memory")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(width: 140, alignment: .trailing)

                        Text("Network I/O")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(width: 140, alignment: .trailing)

                        Text("Block I/O")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(width: 140, alignment: .trailing)

                        Text("PIDs")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(width: 80, alignment: .trailing)
                    } else {
                        HStack {
                            Text("CPU")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .trailing)

                            Text("Memory")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .trailing)

                            Text("Network I/O")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .trailing)

                            Text("Block I/O")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .trailing)

                            Text("PIDs")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.separatorColor).opacity(0.5))

                Divider()

                // Stats rows
                ForEach(containerStats, id: \.id) { stats in
                    HStack(spacing: 0) {
                        if showContainerColumn {
                            // Container name (clickable)
                            Button(action: {
                                selectedTab = .containers
                                selectedContainer = stats.id
                            }) {
                                HStack {
                                    SwiftUI.Image(systemName: "cube")
                                        .foregroundStyle(.green) // Assume running if we have stats
                                    Text(stats.id)
                                        .foregroundStyle(.blue)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            // CPU Usage (placeholder - would need more calculation)
                            Text("--")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .trailing)

                            // Memory Usage
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(stats.formattedMemoryUsage)")
                                    .font(.system(.caption, design: .monospaced))
                                Text("\(String(format: "%.1f", stats.memoryUsagePercent))%")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 140, alignment: .trailing)

                            // Network I/O (RX / TX)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("↓ \(stats.formattedNetworkRx)")
                                    .font(.system(.caption, design: .monospaced))
                                Text("↑ \(stats.formattedNetworkTx)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 140, alignment: .trailing)

                            // Block I/O (Read / Write)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("R \(stats.formattedBlockRead)")
                                    .font(.system(.caption, design: .monospaced))
                                Text("W \(stats.formattedBlockWrite)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 140, alignment: .trailing)

                            // Number of processes
                            Text("\(stats.numProcesses)")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 80, alignment: .trailing)
                        } else {
                            HStack {
                                // CPU Usage (placeholder - would need more calculation)
                                Text("--")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)

                                // Memory Usage
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(stats.formattedMemoryUsage)")
                                        .font(.system(.caption, design: .monospaced))
                                    Text("\(String(format: "%.1f", stats.memoryUsagePercent))%")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)

                                // Network I/O (RX / TX)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("↓ \(stats.formattedNetworkRx)")
                                        .font(.system(.caption, design: .monospaced))
                                    Text("↑ \(stats.formattedNetworkTx)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)

                                // Block I/O (Read / Write)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("R \(stats.formattedBlockRead)")
                                        .font(.system(.caption, design: .monospaced))
                                    Text("W \(stats.formattedBlockWrite)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)

                                // Number of processes
                                Text("\(stats.numProcesses)")
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.clear)

                    if stats.id != containerStats.last?.id {
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
