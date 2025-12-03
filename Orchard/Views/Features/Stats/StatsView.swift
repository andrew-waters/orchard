import SwiftUI

struct StatsView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    @State private var refreshTimer: Timer?

    private var emptyMessage: String {
        if containerService.isStatsLoading {
            return "Loading container statistics..."
        } else if containerService.containerStats.isEmpty {
            return "No running containers or stats unavailable"
        }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with refresh controls
            HStack {
                Text("Container Statistics")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                // Refresh controls
                HStack(spacing: 12) {
                    if containerService.isStatsLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }

                    Button("Refresh") {
                        Task {
                            await containerService.loadContainerStats()
                        }
                    }
                    .disabled(containerService.isStatsLoading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Error message if any
            if let errorMessage = containerService.errorMessage, !errorMessage.isEmpty {
                HStack {
                    SwiftUI.Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Stats table
            ScrollView {
                VStack(spacing: 16) {
                    // Temporary simple stats display until StatsTable compilation is fixed
                    VStack(alignment: .leading, spacing: 8) {
                        if containerService.containerStats.isEmpty {
                            HStack {
                                SwiftUI.Image(systemName: "chart.bar")
                                    .foregroundStyle(.secondary)
                                Text(emptyMessage)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(containerService.containerStats, id: \.id) { stats in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(stats.id)
                                        .font(.headline)
                                    Text("Memory: \(stats.formattedMemoryUsage) (\(String(format: "%.1f", stats.memoryUsagePercent))%)")
                                    Text("Network: ↓\(stats.formattedNetworkRx) ↑\(stats.formattedNetworkTx)")
                                    Text("Processes: \(stats.numProcesses)")
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }

                    // Additional info section
                    if !containerService.containerStats.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Statistics Info")
                                    .font(.headline)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Memory usage shows current consumption and percentage of limit")
                                Text("• Network I/O shows total bytes received (↓) and transmitted (↑)")
                                Text("• Block I/O shows total bytes read (R) and written (W)")
                                Text("• PIDs shows the number of processes running in the container")
                                Text("• Statistics are updated when you refresh or navigate to this tab")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            startAutoRefresh()
            Task {
                await containerService.loadContainerStats()
            }
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task {
                await containerService.loadContainerStats(showLoading: false)
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

#Preview {
    StatsView(
        selectedTab: .constant(.stats),
        selectedContainer: .constant(nil)
    )
    .environmentObject(ContainerService())
}
