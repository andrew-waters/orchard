import AppKit
import ComposeModel
import ComposePlanner
import SwiftUI

struct ComposeProjectDetailView: View {
    @EnvironmentObject var composeService: ComposeService
    @EnvironmentObject var containerListService: ContainerListService
    let projectName: String
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?

    private var project: ComposeProject? {
        ComposeProject.group(
            containers: containerListService.containers,
            records: composeService.records
        ).first { $0.name == projectName }
    }

    private var isBusy: Bool { composeService.busyProjects.contains(projectName) }

    /// The run to show: only this project's, and only while it is this project's turn.
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
                                detail: project.fileURL?.path ?? "",
                                action: nil
                            )
                        }
                        unhandledSection(project)
                        if let run { runSection(run) }
                        servicesSection(project)
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

    // MARK: - The run

    private func runSection(_ run: ComposeRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(run.verb == "up" ? "Bringing Up" : "Taking Down")
                    .font(.headline)
                switch run.phase {
                case .running:
                    ProgressView().controlSize(.small)
                case .succeeded:
                    SwiftUI.Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed:
                    SwiftUI.Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
            }
            if run.steps.isEmpty {
                Text("Everything was already up to date.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(run.steps) { step in
                HStack(alignment: .top, spacing: 8) {
                    stepIcon(step.state)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.summary)
                            .font(.callout)
                            .foregroundStyle(step.state == .skipped ? .secondary : .primary)
                        if let detail = stepDetail(step) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func stepDetail(_ step: ComposeRun.Step) -> String? {
        if case .failed(let message) = step.state { return message }
        return step.detail
    }

    @ViewBuilder
    private func stepIcon(_ state: ComposeRun.Step.State) -> some View {
        switch state {
        case .pending:
            SwiftUI.Image(systemName: "circle").foregroundStyle(.secondary).font(.caption)
        case .running:
            ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14, height: 14)
        case .done:
            SwiftUI.Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .failed:
            SwiftUI.Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).font(.caption)
        case .skipped:
            SwiftUI.Image(systemName: "minus.circle").foregroundStyle(.secondary).font(.caption)
        }
    }

    // MARK: - Services

    private func servicesSection(_ project: ComposeProject) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Services")
                .font(.headline)
            ForEach(serviceRows(project), id: \.name) { row in
                serviceRow(row)
            }
        }
    }

    private struct ServiceRow {
        let name: String
        let container: Container?
        let image: String?
        let dependsOn: [String]
    }

    /// Services as the file describes them when Orchard has the file, and as the containers
    /// remember them when it does not.
    private func serviceRows(_ project: ComposeProject) -> [ServiceRow] {
        if let file = composeService.parses[project.name]?.file {
            return file.orderedServices.map { service in
                ServiceRow(
                    name: service.name,
                    container: project.container(forService: service.name),
                    image: service.image,
                    dependsOn: service.dependsOn.sorted()
                )
            }
        }
        return project.serviceNames.map { name in
            ServiceRow(
                name: name,
                container: project.container(forService: name),
                image: project.container(forService: name)?.configuration.image.reference,
                dependsOn: []
            )
        }
    }

    private func serviceRow(_ row: ServiceRow) -> some View {
        let isRunning = row.container?.status.lowercased() == "running"
        return HStack(alignment: .center, spacing: 10) {
            SwiftUI.Image(systemName: "shippingbox")
                .foregroundStyle(isRunning ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.callout.weight(.medium))
                HStack(spacing: 6) {
                    if let image = row.image {
                        Text(image)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !row.dependsOn.isEmpty {
                        Text("after \(row.dependsOn.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let container = row.container {
                Text(container.status.capitalized)
                    .font(.caption)
                    .foregroundStyle(isRunning ? .green : .secondary)
                Button {
                    selectedContainer = container.configuration.id
                    selectedTab = .containers
                } label: {
                    SwiftUI.Image(systemName: "arrow.forward.circle")
                }
                .buttonStyle(.borderless)
                .help("Show this container")
            } else {
                Text("Not created")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Banner

    private func banner(icon: String, tint: Color, title: String, detail: String, action: (() -> Void)?) -> some View {
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
