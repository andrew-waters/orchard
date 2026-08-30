import SwiftUI

/// The Builds tab's middle column: every build Orchard has started, current
/// and restored from previous launches, newest first. Only builds Orchard
/// itself started can be listed - apple/container's builder shim exposes no
/// host-reachable BuildKit history.
struct BuildsListView: View {
    @EnvironmentObject var buildService: ImageBuildService
    @Binding var selectedBuild: UUID?
    @Binding var searchText: String
    @Binding var showBuildImage: Bool
    @FocusState var listFocusedTab: TabSelection?

    var body: some View {
        Group {
            if buildService.builds.isEmpty {
                VStack(spacing: 8) {
                    Text("No builds recorded")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Build an image from a Dockerfile with the hammer button")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedBuild) {
                    ForEach(filteredBuilds) { build in
                        buildRow(for: build)
                    }
                }
                .listStyle(PlainListStyle())
                .animation(.easeInOut(duration: 0.3), value: buildService.builds)
                .focused($listFocusedTab, equals: .builds)
            }
        }
        .sheet(isPresented: $showBuildImage) {
            BuildImageView()
        }
        // selectTab only auto-selects on tab entry; reconcile when the registry
        // changes underneath an open tab (first build started while the list
        // was empty, or the selected record was removed). Keyed on ids so the
        // per-line transcript appends don't trigger comparisons of whole
        // records.
        .onChange(of: buildService.builds.map(\.id)) { _, ids in
            if selectedBuild == nil || !ids.contains(where: { $0 == selectedBuild }) {
                selectedBuild = ids.first
            }
        }
    }

    private var filteredBuilds: [ImageBuild] {
        guard !searchText.isEmpty else { return buildService.builds }
        let search = searchText.lowercased()
        return buildService.builds.filter { $0.tag.lowercased().contains(search) }
    }

    private func buildRow(for build: ImageBuild) -> some View {
        ListItemRow(
            icon: BuildPhaseStyle.icon(build.phase),
            iconColor: BuildPhaseStyle.color(build.phase),
            primaryText: build.tag,
            secondaryLeftText: build.startedAt.formatted(date: .abbreviated, time: .shortened),
            secondaryRightText: BuildPhaseStyle.durationText(build.duration),
            isSelected: selectedBuild == build.id
        )
        .contentShape(Rectangle())
        .contextMenu {
            if build.phase == .building {
                Button("Cancel Build") {
                    buildService.cancel(build.id)
                }
            } else {
                Button("Remove Record", role: .destructive) {
                    if selectedBuild == build.id {
                        selectedBuild = nil
                    }
                    buildService.remove(build.id)
                }
            }
        }
        .tag(build.id)
    }
}

/// Shared presentation for a build phase across the list and detail views.
enum BuildPhaseStyle {
    static func icon(_ phase: ImageBuild.Phase) -> String {
        switch phase {
        case .building: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .cancelled: return "slash.circle"
        case .interrupted: return "questionmark.circle"
        }
    }

    static func color(_ phase: ImageBuild.Phase) -> Color {
        switch phase {
        case .building: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        case .interrupted: return .orange
        }
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}
