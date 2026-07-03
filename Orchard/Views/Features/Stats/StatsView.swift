import SwiftUI

struct StatsView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    @State private var statsTimer: Timer?

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
            // Header
            HStack {
                Text("Stats")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Stats table
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // System Disk Usage Section
                    SystemDiskUsageView()

                    Text("Container Utilisation")
                        .font(.headline)
                        .foregroundColor(.primary)

                    // Container Stats Table
                    StatsTableView(
                        containerStats: containerService.containerStats,
                        selectedTab: $selectedTab,
                        selectedContainer: $selectedContainer,
                        emptyStateMessage: emptyMessage,
                        showContainerColumn: true
                    )
                }
                .padding(16)
            }
        }
        .onAppear {
            Task {
                await containerService.loadContainerStats()
                await containerService.loadSystemDiskUsage()
            }
            startStatsTimer()
        }
        .onDisappear {
            stopStatsTimer()
        }
    }

    private func startStatsTimer() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                await containerService.loadContainerStats(showLoading: false)
                await containerService.loadSystemDiskUsage(showLoading: false)
            }
        }
    }

    private func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
    }
}

// MARK: - System Disk Usage View

struct SystemDiskUsageView: View {
    @EnvironmentObject var containerService: ContainerService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Disk Usage")
                .font(.headline)
                .foregroundColor(.primary)

            if let diskUsage = containerService.systemDiskUsage {
                HStack(spacing: 16) {
                    // Containers
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Containers")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(diskUsage.containers.formattedSize)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                        Text("\(diskUsage.containers.active)/\(diskUsage.containers.total)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Images
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Images")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(diskUsage.images.formattedSize)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                        Text("\(diskUsage.images.active)/\(diskUsage.images.total)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Volumes
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Volumes")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(diskUsage.volumes.formattedSize)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                        Text("\(diskUsage.volumes.active)/\(diskUsage.volumes.total)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Reclaimable
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reclaimable")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(diskUsage.formattedTotalReclaimable)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                            .foregroundColor(.orange)
                        Text("Space")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            } else {
                HStack(spacing: 16) {
                    // Containers placeholder
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Containers")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Images placeholder
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Images")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Volumes placeholder
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Volumes")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Reclaimable placeholder
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reclaimable")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                            .foregroundColor(.secondary)
                        Text("Space")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}



#Preview {
    StatsView(
        selectedTab: .constant(.stats),
        selectedContainer: .constant(nil)
    )
    .environmentObject(ContainerService())
}
