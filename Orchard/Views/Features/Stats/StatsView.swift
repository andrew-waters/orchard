import SwiftUI

struct StatsView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?


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

            // Error message if any
            if let errorMessage = containerService.errorMessage, !errorMessage.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SwiftUI.Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Stats Unavailable")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                    }

                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if errorMessage.contains("container stats") || errorMessage.contains("Plugin") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Possible solutions:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("• Update your container runtime to the latest version")
                            Text("• Check if container stats plugin is available")
                            Text("• Ensure containers are running before checking stats")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
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
            }
        }
    }
}

#Preview {
    StatsView(
        selectedTab: .constant(.stats),
        selectedContainer: .constant(nil)
    )
    .environmentObject(ContainerService())
}
