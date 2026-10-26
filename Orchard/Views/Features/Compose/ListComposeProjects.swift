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
    /// Whether the sheet is replacing an installed plugin. Fixed when the button is pressed,
    /// because the offer itself goes away as soon as the install starts.
    @State private var pluginSheetIsUpdate = false

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
            } else if let update = composePluginService.update {
                updateBanner(update)
            }
            if projects.isEmpty {
                emptyState
            } else {
                list
            }
            if composePluginService.isInstalled {
                pluginFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { composeService.refreshParses() }
        .task {
            // Looked for when the tab is opened rather than polled: it only changes when
            // someone installs it, or when container's installer clears the plugin directory.
            // The release lookup happens here too, once per visit, so the tab never polls
            // GitHub and a failed lookup simply leaves nothing to offer.
            await composePluginService.refresh()
            await composePluginService.checkForUpdate()
        }
        .sheet(isPresented: $showingPluginInstaller) {
            InstallComposePluginSheet(isUpdate: pluginSheetIsUpdate)
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
        banner(
            title: "container compose is not installed",
            detail: "Projects here work without it. The command in a terminal does not.",
            action: "Install",
            isUpdate: false
        )
    }

    /// Says the installed plugin is behind, and offers the newer one.
    ///
    /// The reason it matters is the window and the terminal disagreeing about the same file:
    /// Orchard plans with the package it links, and an older plugin may ignore a key that
    /// package honours (a 0.6.0 plugin ignores `platform:`, #155).
    private func updateBanner(_ update: ComposePluginService.Update) -> some View {
        let installed = composePluginService.installedVersion ?? ""
        let consequence = "The terminal may not handle a file the way this window does."
        switch update {
        case .newerRelease(let latest):
            return banner(
                title: "container compose \(latest) is available",
                detail: "\(installed) is installed. \(consequence)",
                action: "Update",
                isUpdate: true
            )
        case .olderThanOrchard:
            return banner(
                title: "container compose \(installed) is older than Orchard's",
                detail: consequence,
                action: "Update",
                isUpdate: true
            )
        }
    }

    private func banner(title: String, detail: String, action: String, isUpdate: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SwiftUI.Image(systemName: "terminal")
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            }

            Spacer()

            Button(action) {
                pluginSheetIsUpdate = isUpdate
                showingPluginInstaller = true
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    /// The installed plugin's version, quietly, so it can be checked at a glance without a
    /// terminal. Shown whether or not an update is known, including offline.
    private var pluginFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Text(composePluginService.installedVersion.map { "container compose \($0)" } ?? "container compose")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
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
        // Adding a project that sorts first inserts it at the top while selecting it, and
        // the list then kept the new row at the default height, half hidden under the next.
        .environment(\.defaultMinListRowHeight, ListItemRow.twoLineHeight)
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
