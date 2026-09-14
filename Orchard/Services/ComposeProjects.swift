import ComposeModel
import ComposePlanner
import Foundation

/// A compose project as Orchard sees it.
///
/// Containers are the record. A project exists because containers carry its label, whoever
/// created them, which is why a project brought up from the terminal shows here without
/// Orchard having been told anything. The file is extra: Orchard needs one to bring a project
/// up, and does not need one to show it or take it down.
struct ComposeProject: Identifiable, Equatable {
    let name: String
    /// The file Orchard was shown, if it has been shown one.
    let fileURL: URL?
    /// Every container carrying this project's label, running or not.
    let containers: [Container]

    var id: String { name }

    /// Whether Orchard has a file for this project, and so can bring it up.
    var hasFile: Bool { fileURL != nil }

    var runningContainers: [Container] {
        containers.filter { $0.status.lowercased() == "running" }
    }

    var isRunning: Bool { !runningContainers.isEmpty }

    /// Running, partly running, stopped, or nothing created yet.
    var statusText: String {
        if containers.isEmpty { return "Not created" }
        let running = runningContainers.count
        if running == 0 { return "Stopped" }
        if running == containers.count { return "Running" }
        return "\(running) of \(containers.count) running"
    }

    /// Service names taken from the containers' labels, which is all a project found by label
    /// can tell us.
    var serviceNames: [String] {
        Set(containers.compactMap { $0.configuration.labels[ProjectIdentity.serviceLabel] })
            .sorted()
    }

    func container(forService service: String) -> Container? {
        containers.first { $0.configuration.labels[ProjectIdentity.serviceLabel] == service }
    }

    /// Group containers into projects by label, folding in projects Orchard knows a file for
    /// but which have no containers yet. Pure, so the grouping is testable on its own.
    static func group(containers: [Container], records: [ComposeProjectRecord]) -> [ComposeProject] {
        var byProject: [String: [Container]] = [:]
        for container in containers {
            let project = container.configuration.labels[ProjectIdentity.projectLabel] ?? ""
            guard !project.isEmpty else { continue }
            byProject[project, default: []].append(container)
        }
        let recordsByName = Dictionary(records.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Set(byProject.keys).union(recordsByName.keys)
        return names.sorted().map { name in
            ComposeProject(
                name: name,
                fileURL: recordsByName[name].map { URL(fileURLWithPath: $0.path) },
                containers: (byProject[name] ?? []).sorted { $0.configuration.id < $1.configuration.id }
            )
        }
    }
}

extension Container {
    /// The compose project this container belongs to, read off the label a compose front end
    /// stamped on it at create time. `nil` for a container nothing compose-shaped created.
    var composeProjectName: String? {
        let name = configuration.labels[ProjectIdentity.projectLabel] ?? ""
        return name.isEmpty ? nil : name
    }

    /// Which service of that project this container is.
    var composeServiceName: String? {
        let name = configuration.labels[ProjectIdentity.serviceLabel] ?? ""
        return name.isEmpty ? nil : name
    }
}

/// What Orchard remembers about a project between launches.
///
/// Deliberately small: a name, where its file is, and which unhandled keys the user has
/// already been shown. Everything else is read back off the containers or the file itself,
/// because a record that disagreed with them would be worse than no record.
struct ComposeProjectRecord: Codable, Equatable, Identifiable {
    var name: String
    var path: String
    /// Findings the user has seen and accepted. A file that later grows a new unhandled key
    /// is put back in front of them rather than waved through on the strength of an older
    /// answer.
    var acknowledgedFindings: [String]
    var addedAt: Date

    var id: String { name }
    var fileURL: URL { URL(fileURLWithPath: path) }
}

/// The project list on disk, in the same versioned-envelope shape as the build registry.
struct ComposeProjectsPersistence: Sendable {
    let fileURL: URL

    init(fileURL: URL = ComposeProjectsPersistence.defaultURL()) {
        self.fileURL = fileURL
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Orchard", isDirectory: true)
            .appendingPathComponent("compose-projects.json")
    }

    static let currentVersion = 1

    func save(_ records: [ComposeProjectRecord]) throws {
        let data = try JSONEncoder().encode(PersistedFile(version: Self.currentVersion, projects: records))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    /// Best effort: a missing, corrupt or differently versioned file means no known projects,
    /// which costs the user a file picker rather than anything real.
    func load() -> [ComposeProjectRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(PersistedFile.self, from: data),
              file.version == Self.currentVersion else {
            return []
        }
        return file.projects
    }

    private struct PersistedFile: Codable {
        let version: Int
        let projects: [ComposeProjectRecord]
    }
}

/// One execution of a plan, as it happens, so the detail view can show a project coming up
/// rather than a spinner.
struct ComposeRun: Identifiable, Equatable {
    enum Phase: Equatable {
        case running
        case succeeded
        case failed(String)
    }

    struct Step: Identifiable, Equatable {
        enum State: Equatable {
            case pending
            case running
            case done
            case failed(String)
            /// The plan stopped before reaching this step.
            case skipped

            var failureMessage: String? {
                if case .failed(let message) = self { return message }
                return nil
            }
        }

        let id = UUID()
        let summary: String
        /// What this step is doing, in a word, for a row that has no room for a sentence.
        let activity: String
        let service: String?
        /// The network this step acts on, for the steps that act on one rather than a service.
        let network: String?
        var state: State = .pending
        /// Live detail for a step that has something to say while it runs, such as a pull.
        var detail: String?

        init(
            summary: String,
            activity: String,
            service: String? = nil,
            network: String? = nil,
            state: State = .pending,
            detail: String? = nil
        ) {
            self.summary = summary
            self.activity = activity
            self.service = service
            self.network = network
            self.state = state
            self.detail = detail
        }
    }

    let id = UUID()
    let project: String
    /// "up" or "down", for the heading.
    let verb: String
    var steps: [Step]
    var phase: Phase = .running
    let startedAt = Date()

    var isFinished: Bool { phase != .running }
}
