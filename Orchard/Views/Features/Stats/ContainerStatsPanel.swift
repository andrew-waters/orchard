import Charts
import SwiftUI

/// Per-container resource view: current-value cards plus live time-series charts,
/// reading the samples `StatsService` accumulates. Designed to embed inside the container
/// overview (the caller provides the surrounding scroll view and padding).
struct ContainerStatsPanel: View {
    let container: Container
    @EnvironmentObject var statsService: StatsService
    @State private var window: StatsWindow = .fiveMin

    private var id: String { container.configuration.id }
    private var isRunning: Bool { container.status.lowercased() == "running" }
    private var currentStats: ContainerStats? { statsService.containerStats.first { $0.id == id } }
    private var currentSample: StatsSample? { statsService.latestSamples[id] }
    private var history: [StatsSample] { statsService.history.samples(for: StatsKey(id: id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ContainerStatCards(stats: currentStats, sample: currentSample, isRunning: isRunning)

            if isRunning || !history.isEmpty {
                HStack {
                    Spacer()
                    Picker("", selection: $window) {
                        ForEach(StatsWindow.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }

                StatsChartsGrid(
                    samples: history,
                    memoryLimitBytes: currentStats?.memoryLimitBytes ?? currentSample?.memoryLimitBytes ?? 0,
                    windowSeconds: window.seconds
                )
            }
        }
    }
}

// MARK: - Current-value cards

struct ContainerStatCards: View {
    let stats: ContainerStats?
    let sample: StatsSample?
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 16) {
            card("CPU") {
                if let cpu = sample?.cpuPercent, isRunning {
                    primary(String(format: "%.1f%%", cpu))
                    ProgressView(value: min(1, cpu / 100))
                        .tint(.blue)
                } else {
                    placeholder()
                    caption("--")
                }
            }

            card("Memory") {
                if let stats, isRunning {
                    primary(stats.formattedMemoryUsage)
                    ProgressView(value: min(1, stats.memoryUsagePercent / 100))
                        .tint(.purple)
                    caption("\(String(format: "%.1f", stats.memoryUsagePercent))% of \(stats.formattedMemoryLimit)")
                } else {
                    placeholder()
                    caption("--")
                }
            }

            card("Network I/O") {
                if let stats, isRunning {
                    primary("↓ \(stats.formattedNetworkRx)")
                    caption("↑ \(stats.formattedNetworkTx)")
                } else {
                    placeholder(prefix: "↓ ")
                    caption(isRunning ? "↑ --" : "")
                }
            }

            card("Block I/O") {
                if let stats, isRunning {
                    primary("R \(stats.formattedBlockRead)")
                    caption("W \(stats.formattedBlockWrite)")
                } else {
                    placeholder(prefix: "R ")
                    caption(isRunning ? "W --" : "")
                }
            }

            card("Processes") {
                if let stats, isRunning {
                    primary("\(stats.numProcesses)")
                } else {
                    placeholder()
                }
                caption("PIDs")
            }
        }
    }

    // MARK: card chrome

    @ViewBuilder
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func primary(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.semibold)
            .fontDesign(.monospaced)
    }

    private func placeholder(prefix: String = "") -> some View {
        Text(isRunning ? "\(prefix)--" : "Not running")
            .font(.subheadline)
            .fontWeight(.semibold)
            .fontDesign(.monospaced)
            .foregroundColor(.secondary)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontDesign(.monospaced)
            .foregroundColor(.secondary)
    }
}
