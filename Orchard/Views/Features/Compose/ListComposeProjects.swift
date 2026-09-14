import AppKit
import ComposeModel
import SwiftUI

struct ComposeProjectsListView: View {
    @EnvironmentObject var composeService: ComposeService
    @EnvironmentObject var containerListService: ContainerListService
    @Binding var searchText: String
    @FocusState var listFocusedTab: TabSelection?

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
            if projects.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { composeService.refreshParses() }
        .sheet(item: $composeService.pendingPreview) { preview in
            ComposeReviewSheet(
                preview: preview,
                isRevision: composeService.records.contains { $0.name == preview.identity.name }
            )
        }
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
