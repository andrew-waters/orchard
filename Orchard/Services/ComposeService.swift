import ComposeModel
import ComposeParser
import ComposePlanner
import Foundation

/// A compose file read and understood, ready to be shown to someone before anything is run.
struct ComposeFilePreview: Identifiable {
    /// The file, which is what the review sheet is about.
    var id: String { fileURL.path }

    let fileURL: URL
    let identity: ProjectIdentity
    let file: ComposeFile
    let findings: [Finding]
    let warnings: [InterpolationWarning]

    var serviceNames: [String] { file.orderedServices.map(\.name) }

    /// Findings that change what the services do. These are what the plugin refuses a file
    /// over; here they are what the user is asked about.
    var blockingFindings: [Finding] { findings.filter { $0.severity == .behavioural } }
    var cosmeticFindings: [Finding] { findings.filter { $0.severity == .cosmetic } }
}

/// Owns compose projects: which files Orchard knows about, what they say, and running the
/// plans the package produces.
///
/// Project *state* is not owned here. Projects are derived from the container list by label,
/// the same way clusters are, so the view groups `ContainerListService.containers` through
/// `ComposeProject.group`. What this owns is the file side: the records, the parse of each
/// file, and the execution of a plan.
@MainActor
final class ComposeService: ObservableObject {
    /// Projects Orchard has been shown a file for.
    @Published private(set) var records: [ComposeProjectRecord] = []
    /// The parse of each known project's file, by project name.
    @Published private(set) var parses: [String: ComposeFilePreview] = [:]
    /// The run in progress, or the last one that finished.
    @Published private(set) var run: ComposeRun?
    /// The project the Compose tab is showing. The tab owns its own selection rather than
    /// adding another binding to a layout that already threads a dozen of them.
    @Published var selectedProject: String?
    /// A file that has been chosen and read, waiting for someone to say whether to use it.
    @Published var pendingPreview: ComposeFilePreview?
    /// Projects with an `up` or `down` in flight.
    @Published private(set) var busyProjects: Set<String> = []

    private let backend: ContainerBackend
    private let buildService: ImageBuildService?
    private let alertCenter: AlertCenter
    private let persistence: ComposeProjectsPersistence
    /// Modification dates of the files last parsed, so a file is only re-read when it changes.
    private var parsedAt: [String: Date] = [:]

    /// Refresh the container list after a run. Set by the owner.
    var reloadContainers: () async -> Void = {}
    /// Refresh the network list after a run: `up` and `down` create and remove networks, and
    /// the Networks tab would otherwise show a count that is no longer true. Set by the owner.
    var reloadNetworks: () async -> Void = {}

    init(
        backend: ContainerBackend,
        buildService: ImageBuildService?,
        alertCenter: AlertCenter,
        persistence: ComposeProjectsPersistence = ComposeProjectsPersistence()
    ) {
        self.backend = backend
        self.buildService = buildService
        self.alertCenter = alertCenter
        self.persistence = persistence
        self.records = persistence.load()
    }

    // MARK: - Knowing about files

    /// Read a file without committing to it, for the sheet that asks whether to add it.
    func preview(fileURL: URL) throws -> ComposeFilePreview {
        let result = try ComposeFileParser.parse(contentsOfFile: fileURL.path)
        let identity = ProjectIdentity.resolve(
            file: result.file,
            projectDirectory: fileURL.deletingLastPathComponent().path
        )
        return ComposeFilePreview(
            fileURL: fileURL,
            identity: identity,
            file: result.file,
            findings: result.findings,
            warnings: result.interpolationWarnings
        )
    }

    /// Read a chosen file and hold it for review. Parse failures are errors here rather than
    /// findings: a file that cannot be read is not a project.
    func beginAdd(fileURL: URL) {
        do {
            pendingPreview = try preview(fileURL: fileURL)
        } catch let error as ParseError {
            alertCenter.error("\(fileURL.lastPathComponent):\(error.description)")
        } catch {
            alertCenter.error("Could not read \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func clearPendingPreview() {
        pendingPreview = nil
    }

    /// Remember a project, along with the findings the user has just been shown.
    func add(_ preview: ComposeFilePreview) {
        let record = ComposeProjectRecord(
            name: preview.identity.name,
            path: preview.fileURL.path,
            acknowledgedFindings: preview.findings.map(\.id).sorted(),
            addedAt: Date()
        )
        records.removeAll { $0.name == record.name }
        records.append(record)
        records.sort { $0.name < $1.name }
        parses[record.name] = preview
        parsedAt[record.name] = modificationDate(of: preview.fileURL)
        persist()
    }

    /// Record that the user has seen this project's current findings, so the project stops
    /// asking and goes back to merely saying.
    func acknowledgeFindings(for name: String) {
        guard let index = records.firstIndex(where: { $0.name == name }) else { return }
        records[index].acknowledgedFindings = (parses[name]?.findings.map(\.id) ?? []).sorted()
        persist()
    }

    /// Forget a project's file. The containers are left exactly as they are: forgetting is
    /// not a synonym for `down`, and pretending otherwise would lose someone's database.
    func forget(_ name: String) {
        records.removeAll { $0.name == name }
        parses[name] = nil
        parsedAt[name] = nil
        persist()
    }

    /// Re-read any known file that has changed on disk. Cheap enough to call whenever the
    /// Compose tab appears: it stats each file and parses only what has moved on.
    func refreshParses() {
        for record in records {
            let modified = modificationDate(of: record.fileURL)
            if let modified, parsedAt[record.name] == modified, parses[record.name] != nil { continue }
            parsedAt[record.name] = modified
            parses[record.name] = try? preview(fileURL: record.fileURL)
        }
    }

    func findings(for name: String) -> [Finding] {
        parses[name]?.findings ?? []
    }

    /// Findings this project has that the user has not been shown yet, which is how a file
    /// that grew a `restart:` since it was added gets asked about again.
    func unacknowledgedFindings(for name: String) -> [Finding] {
        guard let record = records.first(where: { $0.name == name }) else { return findings(for: name) }
        let seen = Set(record.acknowledgedFindings)
        return findings(for: name).filter { !seen.contains($0.id) }
    }

    /// Whether the file is still where it was. A project whose file has been moved or deleted
    /// can still be inspected and taken down; it just cannot be brought up.
    func fileIsMissing(for project: ComposeProject) -> Bool {
        guard let url = project.fileURL else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func persist() {
        do {
            try persistence.save(records)
        } catch {
            Log.containers.error("Could not save compose projects: \(error.localizedDescription)")
        }
    }

    // MARK: - Running plans

    func up(project: ComposeProject, options: UpOptions = UpOptions()) async {
        guard let preview = parses[project.name] else {
            alertCenter.error("Orchard has no compose file for `\(project.name)`.")
            return
        }
        await runPlan(project: project.name, verb: "up") { state in
            try Planner.up(file: preview.file, project: preview.identity, state: state, options: options)
        }
    }

    /// Take a project down, with or without a file.
    ///
    /// A project found only by its labels still comes down: the services and their order are
    /// read back off the containers. Stopping in the wrong order is a worse outcome than
    /// refusing, so a known file is used when there is one.
    func down(project: ComposeProject, options: DownOptions = DownOptions()) async {
        let file = parses[project.name]?.file ?? Self.fileFromLabels(project)
        let identity = parses[project.name]?.identity ?? ProjectIdentity(name: project.name)
        await runPlan(project: project.name, verb: "down") { state in
            try Planner.down(file: file, project: identity, state: state, options: options)
        }
    }

    /// The minimum compose file that describes a project nobody has shown us: one service per
    /// labelled container, no dependencies, no images. Enough for `down`, which only needs
    /// names and an order.
    nonisolated static func fileFromLabels(_ project: ComposeProject) -> ComposeFile {
        var file = ComposeFile()
        for name in project.serviceNames {
            file.services[name] = ComposeModel.Service(name: name)
        }
        return file
    }

    private func runPlan(
        project: String,
        verb: String,
        makePlan: (CurrentState) throws -> Plan
    ) async {
        guard !busyProjects.contains(project) else { return }
        busyProjects.insert(project)
        defer { busyProjects.remove(project) }
        alertCenter.dismiss()

        let state: CurrentState
        do {
            state = try await snapshot()
        } catch {
            alertCenter.error("Could not read the current state: \(error.localizedDescription)")
            return
        }

        let plan: Plan
        do {
            plan = try makePlan(state)
        } catch let error as PlanError {
            // Everything the planner refuses, it refuses before anything is created, so this
            // is safe to surface as plainly as it is written.
            alertCenter.error(error.description)
            return
        } catch {
            alertCenter.error("Could not work out what to do: \(error.localizedDescription)")
            return
        }

        guard !plan.operations.isEmpty else {
            run = ComposeRun(project: project, verb: verb, steps: [], phase: .succeeded)
            return
        }

        await execute(plan, project: project, verb: verb)
        await reloadContainers()
        await reloadNetworks()
    }

    /// Everything the planner needs to know, read fresh rather than from the polled list: a
    /// plan made against a stale snapshot would create what already exists.
    private func snapshot() async throws -> CurrentState {
        async let containers = backend.listContainers()
        async let networks = backend.listNetworks()
        async let images = backend.listImages()
        return CurrentState(
            containers: try await containers.map(Self.containerState(of:)),
            networks: try await networks.map { NetworkState(name: $0.id, labels: $0.config.labels) },
            images: try await images.map(\.reference)
        )
    }

    /// `ContainerState` is a name ContainerizationOCI also uses, hence the qualification.
    nonisolated static func containerState(of container: Container) -> ComposePlanner.ContainerState {
        ComposePlanner.ContainerState(
            name: container.configuration.id,
            labels: container.configuration.labels,
            isRunning: container.status.lowercased() == "running",
            publishedHostPorts: container.configuration.publishedPorts.compactMap {
                UInt16(exactly: $0.hostPort)
            },
            networkName: container.configuration.networkName
        )
    }

    private func execute(_ plan: Plan, project: String, verb: String) async {
        var live = ComposeRun(
            project: project,
            verb: verb,
            steps: plan.operations.map { ComposeRun.Step(summary: $0.summary, service: $0.service) }
        )
        run = live

        // Orchard's create call also starts the container it creates, so the start the plan
        // asks for next would be a second start of something already running.
        var alreadyStarted: Set<String> = []

        for (index, operation) in plan.operations.enumerated() {
            live.steps[index].state = .running
            run = live
            do {
                try await perform(operation, stepIndex: index, alreadyStarted: &alreadyStarted)
                live.steps[index].state = .done
                live.steps[index].detail = run?.steps[index].detail
                run = live
            } catch {
                let message = error.localizedDescription
                live.steps[index].state = .failed(message)
                for later in (index + 1)..<live.steps.count {
                    live.steps[later].state = .skipped
                }
                live.phase = .failed(message)
                run = live
                alertCenter.error("\(operation.summary) failed: \(message)")
                await reloadContainers()
                await reloadNetworks()
                return
            }
        }

        live.phase = .succeeded
        run = live
    }

    private func perform(
        _ operation: ComposePlanner.Operation,
        stepIndex: Int,
        alreadyStarted: inout Set<String>
    ) async throws {
        switch operation {
        case .createNetwork(let network):
            try await backend.createNetwork(name: network.name, subnet: nil, labels: network.labels)
        case .removeNetwork(let network):
            try await backend.deleteNetwork(id: network.name)
        case .pullImage(let pull):
            try await backend.pullImage(reference: pull.imageReference) { [weak self] metrics in
                Task { @MainActor [weak self] in
                    self?.updateDetail(at: stepIndex, to: Self.pullDetail(metrics))
                }
            }
        case .buildImage(let build):
            try await self.build(build)
        case .createContainer(let create):
            let created = try Self.ensureBindSources(of: create)
            if !created.isEmpty {
                updateDetail(at: stepIndex, to: "created \(created.joined(separator: ", "))")
            }
            try await backend.createContainer(Self.createSpec(from: create))
            alreadyStarted.insert(create.containerName)
        case .startContainer(let reference):
            guard !alreadyStarted.contains(reference.containerName) else { return }
            try await backend.bootstrapAndStart(id: reference.containerName)
        case .stopContainer(let reference):
            try await backend.stopContainer(id: reference.containerName)
        case .removeContainer(let reference):
            try await backend.deleteContainer(id: reference.containerName, force: true)
        }
    }

    private func updateDetail(at index: Int, to detail: String?) {
        guard var live = run, live.steps.indices.contains(index) else { return }
        guard live.steps[index].detail != detail else { return }
        live.steps[index].detail = detail
        run = live
    }

    nonisolated static func pullDetail(_ metrics: ImagePullMetrics) -> String? {
        guard metrics.totalBytes > 0 else {
            return metrics.phase.isEmpty ? nil : metrics.phase
        }
        let percent = Int((Double(metrics.bytesDownloaded) / Double(metrics.totalBytes) * 100).rounded())
        let phase = metrics.phase.isEmpty ? "Pulling" : metrics.phase
        return "\(phase) \(min(percent, 100))%"
    }

    /// Builds go through the same service the Images tab uses, so a compose build shows up in
    /// the Builds tab with its BuildKit log like any other.
    private func build(_ operation: BuildOperation) async throws {
        guard let buildService else {
            throw ComposeRunError("this build cannot run: no build service")
        }
        let dockerfile = operation.dockerfile.map { path -> String in
            path.hasPrefix("/") ? path : (operation.context as NSString).appendingPathComponent(path)
        } ?? (operation.context as NSString).appendingPathComponent("Dockerfile")

        let id = buildService.startBuild(
            ImageBuildService.Request(
                dockerfile: dockerfile,
                contextDir: operation.context,
                tag: operation.imageReference,
                // Every container on this stack is a linux/arm64 guest, which is why a
                // compose file's `platform` is reported and ignored rather than passed on.
                arch: "arm64",
                noCache: false,
                buildArgs: operation.arguments.isEmpty ? nil : operation.arguments,
                target: operation.target
            )
        )
        await buildService.wait(for: id)
        switch buildService.build(id: id)?.phase {
        case .succeeded:
            return
        case .failed(let message):
            throw ComposeRunError(message)
        case .cancelled:
            throw ComposeRunError("the build was cancelled")
        default:
            throw ComposeRunError("the build did not finish")
        }
    }

    /// Create the host directories a service binds that are not there yet, which is what
    /// compose does and what a file writing `./data/public:/data` expects.
    ///
    /// Without this the runtime is handed a mount whose source does not exist, and the failure
    /// arrives much later and much less clearly, as a container that will not bootstrap with
    /// `errno 2`.
    ///
    /// - Returns: the paths that had to be created, so the step can say so.
    @discardableResult
    nonisolated static func ensureBindSources(of operation: CreateOperation) throws -> [String] {
        var created: [String] = []
        for mount in operation.mounts where !FileManager.default.fileExists(atPath: mount.hostPath) {
            do {
                try FileManager.default.createDirectory(
                    atPath: mount.hostPath,
                    withIntermediateDirectories: true
                )
            } catch {
                throw ComposeRunError(
                    "`\(mount.hostPath)` is mounted at `\(mount.containerPath)` and could not "
                        + "be created: \(error.localizedDescription)"
                )
            }
            created.append(mount.hostPath)
        }
        return created
    }

    /// A create operation in the shape Orchard's own create call takes.
    nonisolated static func createSpec(from operation: CreateOperation) -> ContainerCreateSpec {
        ContainerCreateSpec(
            id: operation.containerName,
            imageRef: operation.imageReference,
            environment: operation.environment,
            workingDirectory: operation.workingDirectory ?? "",
            commandOverride: operation.command,
            volumes: operation.mounts.map {
                .init(hostPath: $0.hostPath, containerPath: $0.containerPath, readonly: $0.readOnly)
            },
            publishedPorts: operation.ports.map {
                .init(
                    hostPort: $0.hostPort,
                    containerPort: $0.containerPort,
                    transportProtocol: $0.networkProtocol,
                    hostAddress: $0.hostAddress
                )
            },
            dnsDomain: "",
            networkName: operation.networkName,
            autoRemove: false,
            // A compose file that says nothing about resources gets the same defaults as a
            // container created through the Run form, rather than something invented here.
            cpus: operation.cpus.map { max(1, Int($0.rounded(.up))) } ?? ContainerRunConfig.defaultCPUs,
            memoryBytes: operation.memoryBytes ?? ContainerRunConfig.defaultMemoryBytes,
            labels: operation.labels
        )
    }
}

/// A failure inside a run, already written for a person.
struct ComposeRunError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
