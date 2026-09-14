import AppKit
import ComposeModel
import ComposePlanner
import SwiftUI

struct ComposeProjectDetailView: View {
    @EnvironmentObject var composeService: ComposeService
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var networkService: NetworkService
    let projectName: String
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    @Binding var selectedNetwork: String?

    private var project: ComposeProject? {
        ComposeProject.group(
            containers: containerListService.containers,
            records: composeService.records
        ).first { $0.name == projectName }
    }

    /// The two halves of a project: what it is doing, and what it asked for and will not get.
    /// Separate because the second is a list that can run to a dozen lines on a real file and
    /// was pushing the first off the top of the pane.
    private enum ProjectTab: String, CaseIterable {
        case running = "Running"
        case problems = "Problems"
    }

    @State private var tab: ProjectTab = .running

    private var isBusy: Bool { composeService.busyProjects.contains(projectName) }

    /// The run to show, which is only ever this project's.
    private var run: ComposeRun? {
        guard let run = composeService.run, run.project == projectName else { return nil }
        return run
    }

    var body: some View {
        if let project {
            VStack(spacing: 0) {
                header(project)
                tabStrip(project)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch tab {
                        case .running:
                            containersSection(project)
                        case .problems:
                            problemsTab(project)
                        }
                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
            .id(projectName)
            .onAppear { composeService.refreshParses() }
        } else {
            Text("Project not found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    private func header(_ project: ComposeProject) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(isBusy ? "Working…" : project.statusText)
                        .font(.caption)
                        .foregroundStyle(project.isRunning ? .green : .secondary)
                }
                if let url = project.fileURL {
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("Found by label. Add its compose file to bring it up from here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            actions(project)
        }
        .padding()
    }

    @ViewBuilder
    private func actions(_ project: ComposeProject) -> some View {
        HStack(spacing: 8) {
            if project.hasFile {
                Button {
                    Task { await composeService.up(project: project) }
                } label: {
                    Label("Up", systemImage: "play.fill")
                }
                .disabled(isBusy || composeService.fileIsMissing(for: project) || hasUnreviewedChanges)
                .help(hasUnreviewedChanges ? "Review what this file now asks for first" : "Create and start the services")
            } else {
                Button {
                    ComposeAddFlow.present(service: composeService)
                } label: {
                    Label("Add Compose File", systemImage: "doc.badge.plus")
                }
            }
            Button {
                Task { await composeService.down(project: project) }
            } label: {
                Label("Down", systemImage: "stop.fill")
            }
            .disabled(isBusy || project.containers.isEmpty)
            .help("Stop and remove this project's containers")
        }
    }

    // MARK: - Tabs

    private func tabStrip(_ project: ComposeProject) -> some View {
        HStack {
            Picker("", selection: $tab) {
                ForEach(ProjectTab.allCases, id: \.self) { candidate in
                    Text(tabTitle(candidate, project: project)).tag(candidate)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("compose-tabs")
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private func tabTitle(_ candidate: ProjectTab, project: ComposeProject) -> String {
        guard candidate == .problems else { return candidate.rawValue }
        let count = problemCount(project)
        return count > 0 ? "\(candidate.rawValue) (\(count))" : candidate.rawValue
    }

    /// What the count on the tab means: things that change what the services do. Cosmetic
    /// findings are listed on the tab but not counted, or the number would say "nine
    /// problems" about a file whose only real problem is one.
    private func problemCount(_ project: ComposeProject) -> Int {
        findings.filter { $0.severity == .behavioural }.count
            + (composeService.fileIsMissing(for: project) ? 1 : 0)
    }

    @ViewBuilder
    private func problemsTab(_ project: ComposeProject) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if composeService.fileIsMissing(for: project) {
                banner(
                    icon: "questionmark.folder",
                    tint: .orange,
                    title: "The compose file is not where it was",
                    detail: project.fileURL?.path ?? ""
                )
            }
            if findings.isEmpty, !composeService.fileIsMissing(for: project) {
                Label(
                    project.hasFile
                        ? "Everything in this file is supported."
                        : "Orchard has no compose file for this project, so there is nothing to check.",
                    systemImage: project.hasFile ? "checkmark.circle" : "questionmark.circle"
                )
                .foregroundStyle(project.hasFile ? .green : .secondary)
            }
            unhandledSection(project)
        }
    }

    // MARK: - What is not being honoured

    private var findings: [Finding] {
        composeService.findings(for: projectName)
    }

    private var hasUnreviewedChanges: Bool {
        !composeService.unacknowledgedFindings(for: projectName).isEmpty
    }

    /// Keys nobody has ever defined. Checked first: the parser marks them unsupported for
    /// want of a better case, and they are not a runtime limitation, they are a typo.
    private var unknownKeys: [Finding] {
        findings.filter { $0.kind == .unknownKey }
    }

    /// Things the runtime underneath cannot do, whoever asks it.
    private var runtimeBlocked: [Finding] {
        findings.filter { $0.kind != .unknownKey && $0.support.needsRuntimeSupport }
    }

    /// Things this could do and has not built yet.
    private var notBuiltYet: [Finding] {
        findings.filter { $0.kind != .unknownKey && $0.support.isDeferred }
    }

    @ViewBuilder
    private func unhandledSection(_ project: ComposeProject) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if hasUnreviewedChanges {
                HStack(alignment: .top, spacing: 10) {
                    SwiftUI.Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("This file has changed since it was added and now asks for something new.")
                        .font(.callout)
                    Spacer()
                    Button("Review Changes") { reviewCurrentFile() }
                        .controlSize(.small)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
            }

            // Grouped by what is actually in the way, because the three are not the same kind
            // of news and a single list reads as though all of it were this project's doing.
            findingGroup(
                title: "Not possible on this runtime",
                note: "Apple's container runtime has no equivalent, so nothing built on it can "
                    + "honour these. They will work here when the runtime does.",
                findings: runtimeBlocked
            )
            findingGroup(
                title: "Not implemented yet",
                note: "Nothing about the runtime prevents these. They are simply not built yet.",
                findings: notBuiltYet
            )
            findingGroup(
                title: "Not a compose key",
                note: "No version of the Compose Specification defines these, so they are as "
                    + "likely to be a typo as anything else.",
                findings: unknownKeys
            )
        }
    }

    @ViewBuilder
    private func findingGroup(title: String, note: String, findings: [Finding]) -> some View {
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Behavioural first: a key that changes what the services do outranks one that
                // changes nothing anybody can see.
                ForEach(findings.sorted { $0.severity > $1.severity }) { finding in
                    HStack(alignment: .top, spacing: 8) {
                        SwiftUI.Image(
                            systemName: finding.severity == .behavioural
                                ? "exclamationmark.triangle.fill" : "minus.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(finding.severity == .behavioural ? Color.orange : Color.secondary)
                        .padding(.top, 2)
                        Text(finding.message)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func reviewCurrentFile() {
        guard let url = project?.fileURL else { return }
        composeService.beginAdd(fileURL: url)
    }

    // MARK: - Containers

    /// Everything the stack wants, in one table: the containers that exist, the ones that do
    /// not yet, and what is happening to each while a plan runs. A separate list of steps said
    /// the same thing twice and cost the height to say it.
    private func containersSection(_ project: ComposeProject) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Containers")
                    .font(.headline)
                if let run, run.phase == .running {
                    ProgressView().controlSize(.small)
                    Text(run.verb == "up" ? "Bringing up" : "Taking down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let failure = runFailure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ContainerTable(
                containers: orderedContainers(project),
                placeholders: placeholders(project),
                // What a plan is doing to this service right now, falling back to the
                // container's own state when nothing is happening to it.
                note: {
                    note(forService: $0.composeServiceName)
                        ?? ResourceTable.Note($0.status.capitalized)
                },
                selectedTab: $selectedTab,
                selectedContainer: $selectedContainer,
                emptyStateMessage: project.hasFile
                    ? "Nothing created yet. Bring the project up to create its containers."
                    : "This project has no containers."
            )
            networksSection(project)
        }
    }

    /// The message from a run that stopped, kept visible after the alert has gone.
    private var runFailure: String? {
        guard let run, case .failed(let message) = run.phase else { return nil }
        return message
    }

    /// Services in the order the planner would start them, so the table reads the way the
    /// stack comes up rather than alphabetically.
    private func serviceOrder(_ project: ComposeProject) -> [String] {
        guard let file = composeService.parses[project.name]?.file else { return project.serviceNames }
        if let graph = try? DependencyGraph(services: file.services) {
            return graph.startOrder
        }
        return file.orderedServices.map(\.name)
    }

    private func orderedContainers(_ project: ComposeProject) -> [Container] {
        let order = serviceOrder(project)
        return project.containers.sorted { first, second in
            let firstIndex = order.firstIndex(of: first.composeServiceName ?? "") ?? Int.max
            let secondIndex = order.firstIndex(of: second.composeServiceName ?? "") ?? Int.max
            if firstIndex != secondIndex { return firstIndex < secondIndex }
            return first.configuration.id < second.configuration.id
        }
    }

    /// A row for every service the file declares that has no container, named the way the
    /// planner will name it so the row does not move once it exists.
    private func placeholders(_ project: ComposeProject) -> [ContainerTable.Placeholder] {
        guard let parse = composeService.parses[project.name] else { return [] }
        return serviceOrder(project).compactMap { service in
            guard project.container(forService: service) == nil else { return nil }
            let name = parse.file.services[service]
                .map { parse.identity.containerName(for: $0) } ?? service
            return ContainerTable.Placeholder(
                name: name,
                note: note(forService: service) ?? ResourceTable.Note("Not created")
            )
        }
    }

    /// What the run in progress is doing to a service, if anything.
    private func note(forService service: String?) -> ResourceTable.Note? {
        guard let service, let run else { return nil }
        if let step = run.steps.last(where: { $0.service == service && $0.state == .running }) {
            return ResourceTable.Note(step.detail.map { "\(step.activity) \($0)" } ?? "\(step.activity)…")
        }
        if run.steps.contains(where: { $0.service == service && $0.state.failureMessage != nil }) {
            return ResourceTable.Note("Failed", isError: true)
        }
        return nil
    }

    // MARK: - Networks

    /// The networks the stack wants, in the same table as its containers, because they are
    /// created and removed by the same plan and a footnote would not say so.
    ///
    /// There is no DNS equivalent: a compose file's `dns:` key is not honoured, and compose
    /// has no concept that maps onto a DNS domain, so there would be nothing true to show.
    @ViewBuilder
    private func networksSection(_ project: ComposeProject) -> some View {
        let names = networkNames(project)
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Networks")
                    .font(.headline)
                NetworkTable(
                    networks: networkService.networks.filter { names.contains($0.id) },
                    placeholders: names
                        .filter { name in !networkService.networks.contains { $0.id == name } }
                        .map {
                            NetworkTable.Placeholder(
                                name: $0,
                                note: networkNote($0) ?? ResourceTable.Note("Not created")
                            )
                        },
                    note: { networkNote($0.id) ?? ResourceTable.Note($0.state.capitalized) },
                    selectedTab: $selectedTab,
                    selectedNetwork: $selectedNetwork,
                    emptyStateMessage: "This project uses no networks."
                )
            }
        }
    }

    private func networkNames(_ project: ComposeProject) -> [String] {
        if let parse = composeService.parses[project.name] {
            return Set(
                Planner.networkNames(in: parse.file, project: parse.identity).values.compactMap { $0 }
            ).sorted()
        }
        return Set(project.containers.compactMap { $0.configuration.networkName }).sorted()
    }

    /// What the run in progress is doing to a network, if anything.
    private func networkNote(_ name: String) -> ResourceTable.Note? {
        guard let run,
              let step = run.steps.last(where: { $0.network == name && $0.state == .running })
        else { return nil }
        return ResourceTable.Note("\(step.activity)…")
    }

    // MARK: - Banner

    private func banner(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SwiftUI.Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1)))
    }
}
