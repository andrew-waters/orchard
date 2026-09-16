import AppKit
import ComposeModel
import SwiftUI

struct ComposeProjectsListView: View {
    @EnvironmentObject var composeService: ComposeService
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var composePluginService: ComposePluginService
    @Binding var searchText: String
    @FocusState var listFocusedTab: TabSelection?
    @State private var showingPluginInstaller = false

    private var projects: [ComposeProject] {
        ComposeProject.group(
            containers: containerListService.containers,
            records: composeService.records
        )
    }

    private var filteredProjects: [ComposeProject] {
        guard !searchText.isEmpty else { return projects }
        let query = searchText.lowercased()
        return projects.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if composePluginService.isMissing {
                pluginBanner
            }
            if projects.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { composeService.refreshParses() }
        .task {
            // Looked for when the tab is opened rather than polled: it only changes when
            // someone installs it, or when container's installer clears the plugin directory.
            await composePluginService.refresh()
        }
        .sheet(isPresented: $showingPluginInstaller) {
            InstallComposePluginSheet()
        }
        .sheet(item: $composeService.pendingPreview) { preview in
            ComposeReviewSheet(
                preview: preview,
                isRevision: composeService.records.contains { $0.name == preview.identity.name }
            )
        }
    }

    /// Says the CLI plugin is not installed, and offers to fetch it.
    ///
    /// Blue rather than orange on purpose: nothing is wrong. Every project in this list works
    /// without the plugin, because the window links the planner and runs plans over XPC. This
    /// is an offer, and it is worth making because container's own installer clears the plugin
    /// directory on every upgrade (apple/container#1617), so it goes missing again through
    /// nobody's fault.
    private var pluginBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            SwiftUI.Image(systemName: "terminal")
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("container compose is not installed")
                    .font(.callout.weight(.medium))
                Text("Projects here work without it. The command in a terminal does not.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            }

            Spacer()

            Button("Install") { showingPluginInstaller = true }
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    private var emptyState: some View {
        VStack {
            SwiftUI.Image(systemName: "square.stack.3d.up")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            Text("No Projects")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Add a compose file, or bring one up from the terminal and it will show here")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Button("Add Project") { ComposeAddFlow.present(service: composeService) }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List(selection: $composeService.selectedProject) {
            ForEach(filteredProjects) { project in
                ComposeProjectRow(
                    project: project,
                    serviceCount: serviceCount(for: project),
                    isSelected: composeService.selectedProject == project.name,
                    isBusy: composeService.busyProjects.contains(project.name),
                    unhandledCount: composeService.findings(for: project.name)
                        .filter { $0.severity == .behavioural }.count
                )
                .contextMenu { contextMenu(for: project) }
                .tag(project.name)
            }
        }
        .listStyle(PlainListStyle())
        .animation(.easeInOut(duration: 0.3), value: containerListService.containers)
        .focused($listFocusedTab, equals: .compose)
    }

    /// The file's services when Orchard has the file, the containers' labels when it does not.
    private func serviceCount(for project: ComposeProject) -> Int {
        composeService.parses[project.name]?.file.services.count ?? project.serviceNames.count
    }

    @ViewBuilder
    private func contextMenu(for project: ComposeProject) -> some View {
        let busy = composeService.busyProjects.contains(project.name)
        if project.hasFile {
            Button("Up") { Task { await composeService.up(project: project) } }
                .disabled(busy)
        }
        Button("Down") { Task { await composeService.down(project: project) } }
            .disabled(busy || project.containers.isEmpty)
        if let url = project.fileURL {
            Divider()
            Button("Reveal Compose File") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Copy File Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
            Divider()
            Button("Forget Project", role: .destructive) {
                confirmForget(project)
            }
        }
    }

    /// Forgetting is not `down`. Say so, because the two are easy to confuse and only one of
    /// them is reversible by clicking the other button.
    private func confirmForget(_ project: ComposeProject) {
        let alert = NSAlert()
        alert.messageText = "Forget '\(project.name)'?"
        alert.informativeText = """
            Orchard will stop tracking this compose file. The project's containers are left \
            exactly as they are, running or not, and the project will still appear here for as \
            long as they exist.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Forget")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            composeService.forget(project.name)
        }
    }

    private struct ComposeProjectRow: View {
        let project: ComposeProject
        let serviceCount: Int
        let isSelected: Bool
        let isBusy: Bool
        let unhandledCount: Int

        var body: some View {
            let services = serviceCount
            ListItemRow(
                icon: "square.stack.3d.up",
                iconColor: project.isRunning ? .green : .secondary,
                primaryText: project.name,
                secondaryLeftText: services == 1 ? "1 service" : "\(services) services",
                secondaryRightText: isBusy ? "Working…" : project.statusText,
                isSelected: isSelected,
                warningBadge: unhandledCount > 0 ? "\(unhandledCount) unhandled" : nil
            )
        }
    }
}
