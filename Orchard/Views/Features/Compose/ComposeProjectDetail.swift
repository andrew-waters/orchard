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
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if composeService.fileIsMissing(for: project) {
                            banner(
                                icon: "questionmark.folder",
                                tint: .orange,
                                title: "The compose file is not where it was",
                                detail: project.fileURL?.path ?? ""
                            )
                        }
                        unhandledSection(project)
                        containersSection(project)
                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
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

    // MARK: - What is not being honoured

    private var findings: [Finding] {
        composeService.findings(for: projectName)
    }

    private var hasUnreviewedChanges: Bool {
        !composeService.unacknowledgedFindings(for: projectName).isEmpty
    }

    @ViewBuilder
    private func unhandledSection(_ project: ComposeProject) -> some View {
        let behavioural = findings.filter { $0.severity == .behavioural }
        let cosmetic = findings.filter { $0.severity == .cosmetic }
        if !behavioural.isEmpty || !cosmetic.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Not Honoured")
                        .font(.headline)
                    Spacer()
                    if hasUnreviewedChanges {
                        Button("Review Changes") { reviewCurrentFile() }
                            .controlSize(.small)
                    }
                }
                if hasUnreviewedChanges {
                    Text("This file has changed since it was added and now asks for something new.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                // Shown for as long as the project exists, not just at the point of adding it:
                // nobody remembers three weeks later what they accepted, and the containers
                // cannot tell them.
                ForEach(behavioural + cosmetic) { finding in
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
                note: { note(forService: $0.composeServiceName) },
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
                note: note(forService: service) ?? ContainerTable.Note("Not created")
            )
        }
    }

    /// What the run in progress is doing to a service, if anything.
    private func note(forService service: String?) -> ContainerTable.Note? {
        guard let service, let run else { return nil }
        if let step = run.steps.last(where: { $0.service == service && $0.state == .running }) {
            return ContainerTable.Note(step.detail.map { "\(step.activity) \($0)" } ?? "\(step.activity)…")
        }
        if run.steps.contains(where: { $0.service == service && $0.state.failureMessage != nil }) {
            return ContainerTable.Note("Failed", isError: true)
        }
        return nil
    }

    // MARK: - Networks

    /// The networks the stack wants, which the container table has no column for and which a
    /// plan creates and removes like anything else.
    ///
    /// There is no DNS equivalent: a compose file's `dns:` key is not honoured, and compose has
    /// no concept that maps onto a DNS domain, so there would be nothing true to show.
    @ViewBuilder
    private func networksSection(_ project: ComposeProject) -> some View {
        let names = networkNames(project)
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Networks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(names, id: \.self) { name in
                    HStack(spacing: 8) {
                        SwiftUI.Image(systemName: "arrow.down.left.arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(name) {
                            selectedNetwork = name
                            selectedTab = .networks
                        }
                        .buttonStyle(.link)
                        if let note = networkNote(name) {
                            Text(note.text)
                                .font(.caption)
                                .foregroundStyle(note.isError ? Color.red : Color.secondary)
                        }
                        Spacer()
                    }
                }
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

    private func networkNote(_ name: String) -> ContainerTable.Note? {
        if let run, let step = run.steps.last(where: { $0.network == name && $0.state == .running }) {
            return ContainerTable.Note("\(step.activity)…")
        }
        if networkService.networks.contains(where: { $0.id == name }) { return nil }
        return ContainerTable.Note("Not created")
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
