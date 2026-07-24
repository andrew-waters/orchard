import Foundation

struct StartupSequence: Codable, Equatable {
	var isEnabled = false
	var groups: [StartupGroup] = []

	static let readinessTimeout: TimeInterval = 60

	init(isEnabled: Bool = false, groups: [StartupGroup] = [], steps: [StartupStep]? = nil) {
		self.isEnabled = isEnabled
		if let steps {
			self.groups = [StartupGroup(name: "Startup", containers: steps.map {
				StartupGroupContainer(containerID: $0.containerID, waitForContainerIDs: $0.waitForContainerIDs)
			})]
		} else {
			self.groups = groups
		}
	}

	private enum CodingKeys: String, CodingKey {
		case isEnabled
		case groups
		case steps
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
		if let groups = try container.decodeIfPresent([StartupGroup].self, forKey: .groups) {
			self.groups = groups
		} else if let steps = try container.decodeIfPresent([StartupStep].self, forKey: .steps) {
			groups = [StartupGroup(name: "Startup", containers: steps.map {
				StartupGroupContainer(containerID: $0.containerID, waitForContainerIDs: $0.waitForContainerIDs)
			})]
		} else {
			groups = []
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(isEnabled, forKey: .isEnabled)
		try container.encode(groups, forKey: .groups)
	}

	func validationError(availableContainerIDs: Set<String>? = nil) -> String? {
		var groupIDs = Set<UUID>()
		var containerGroups: [String: UUID] = [:]

		for (groupIndex, group) in groups.enumerated() {
			guard !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
				return "Group \(groupIndex + 1) does not have a name."
			}

			guard groupIDs.insert(group.id).inserted else {
				return "Group \"\(group.name)\" appears more than once."
			}

			for container in group.containers {
				guard !container.containerID.isEmpty else {
					return "Group \"\(group.name)\" has an empty container selection."
				}

				if let availableContainerIDs, !availableContainerIDs.contains(container.containerID) {
					return "Container \"\(container.containerID)\" is not available."
				}

				if let existingGroupID = containerGroups[container.containerID] {
					if existingGroupID == group.id {
						return "Container \"\(container.containerID)\" appears more than once."
					}
					return "Container \"\(container.containerID)\" belongs to more than one group."
				}
				containerGroups[container.containerID] = group.id
			}
		}

		for group in groups {
			var groupDependencies = Set<UUID>()
			for dependencyID in group.waitForGroupIDs {
				guard dependencyID != group.id else {
					return "Group \"\(group.name)\" cannot wait for itself."
				}
				guard groupIDs.contains(dependencyID) else {
					return "Group \"\(group.name)\" waits for a missing group."
				}
				guard groupDependencies.insert(dependencyID).inserted else {
					return "Group \"\(group.name)\" lists the same prerequisite more than once."
				}
			}

			for container in group.containers {
				var dependencies = Set<String>()
				for dependencyID in container.waitForContainerIDs {
					guard dependencyID != container.containerID else {
						return "Container \"\(container.containerID)\" cannot wait for itself."
					}
					guard dependencies.insert(dependencyID).inserted else {
						return "Dependency \"\(dependencyID)\" is listed more than once for \"\(container.containerID)\"."
					}
					guard containerGroups[dependencyID] != nil else {
						return "Container \"\(container.containerID)\" waits for a missing container \"\(dependencyID)\"."
					}
				}
			}
		}

		if hasDependencyCycle(in: groups) {
			return "Startup groups contain a dependency cycle."
		}
		return nil
	}

	func dependencyCycleGroupIDs() -> Set<UUID> {
		Set(dependencyCycleNodes().compactMap { node in
			if case .group(let id) = node { return id }
			return nil
		})
	}

	func dependencyCycleContainerIDs() -> Set<String> {
		Set(dependencyCycleNodes().compactMap { node in
			if case .container(let id) = node { return id }
			return nil
		})
	}

	func wouldCreateGroupDependency(groupID: UUID, dependencyID: UUID) -> Bool {
		var proposedGroups = groups
		guard let index = proposedGroups.firstIndex(where: { $0.id == groupID }) else { return false }
		if !proposedGroups[index].waitForGroupIDs.contains(dependencyID) {
			proposedGroups[index].waitForGroupIDs.append(dependencyID)
		}
		return hasDependencyCycle(in: proposedGroups)
	}

	func wouldCreateContainerDependency(containerID: String, dependencyID: String) -> Bool {
		var proposedGroups = groups
		for groupIndex in proposedGroups.indices {
			guard let containerIndex = proposedGroups[groupIndex].containers.firstIndex(where: { $0.containerID == containerID }) else { continue }
			if !proposedGroups[groupIndex].containers[containerIndex].waitForContainerIDs.contains(dependencyID) {
				proposedGroups[groupIndex].containers[containerIndex].waitForContainerIDs.append(dependencyID)
			}
			return hasDependencyCycle(in: proposedGroups)
		}
		return false
	}

	private enum DependencyNode: Hashable {
		case group(UUID)
		case container(String)
	}

	private func hasDependencyCycle(in groups: [StartupGroup]) -> Bool {
		!dependencyCycleNodes(in: groups).isEmpty
	}

	private func dependencyCycleNodes(in groups: [StartupGroup] = []) -> Set<DependencyNode> {
		let groups = groups.isEmpty ? self.groups : groups
		var dependencies: [DependencyNode: Set<DependencyNode>] = [:]
		for group in groups {
			let groupNode = DependencyNode.group(group.id)
			dependencies[groupNode, default: []].formUnion(group.waitForGroupIDs.map(DependencyNode.group))
			dependencies[groupNode, default: []].formUnion(group.containers.map { .container($0.containerID) })
			for container in group.containers {
				dependencies[.container(container.containerID), default: []].formUnion(
					container.waitForContainerIDs.map(DependencyNode.container))
				dependencies[.container(container.containerID), default: []].formUnion(
					group.waitForGroupIDs.map(DependencyNode.group))
			}
		}

		var visited = Set<DependencyNode>()
		var path: [DependencyNode] = []
		var cycleNodes = Set<DependencyNode>()
		func visit(_ node: DependencyNode) -> Bool {
			if let cycleStart = path.firstIndex(of: node) {
				cycleNodes.formUnion(path[cycleStart...])
				return true
			}
			if visited.contains(node) { return false }
			path.append(node)
			for dependency in dependencies[node, default: []] where visit(dependency) {
				break
			}
			path.removeLast()
			visited.insert(node)
			return false
		}

		for node in dependencies.keys {
			_ = visit(node)
		}
		return cycleNodes
	}
}

struct StartupGroup: Codable, Equatable, Identifiable {
	let id: UUID
	var name: String
	var containers: [StartupGroupContainer]
	var waitForGroupIDs: [UUID]

	init(
		id: UUID = UUID(),
		name: String,
		containers: [StartupGroupContainer] = [],
		waitForGroupIDs: [UUID] = []) {
		self.id = id
		self.name = name
		self.containers = containers
		self.waitForGroupIDs = waitForGroupIDs
	}
}

struct StartupGroupContainer: Codable, Equatable, Identifiable {
	let id: UUID
	var containerID: String
	var waitForContainerIDs: [String]

	init(id: UUID = UUID(), containerID: String, waitForContainerIDs: [String] = []) {
		self.id = id
		self.containerID = containerID
		self.waitForContainerIDs = waitForContainerIDs
	}
}

struct StartupStep: Codable, Equatable, Identifiable {
	let id: UUID
	var containerID: String
	var waitForContainerIDs: [String]

	init(id: UUID = UUID(), containerID: String, waitForContainerID: String? = nil, waitForContainerIDs: [String]? = nil) {
		self.id = id
		self.containerID = containerID
		self.waitForContainerIDs = waitForContainerIDs ?? waitForContainerID.map { [$0] } ?? []
	}
}

enum StartupSequenceRunState: Equatable {
	case idle
	case startingSystem
	case startingGroup(String)
	case starting(String)
	case waiting(String)
	case completed
	case stopping
	case failed(String)

	var displayText: String {
		switch self {
		case .idle:
			return "Not run"
		case .startingSystem:
			return "Starting container system…"
		case .startingGroup(let name):
			return "Starting group \(name)…"
		case .starting(let containerID):
			return "Starting \(containerID)…"
		case .waiting(let containerID):
			return "Waiting for \(containerID) to run…"
		case .completed:
			return "Sequence completed"
		case .stopping:
			return "Stopping sequence-owned containers…"
		case .failed(let message):
			return message
		}
	}
}

enum StartupSequenceError: LocalizedError, Equatable {
	case containerNotFound(String)
	case readinessTimeout(String)
	case runtimeFailure(String)

	var errorDescription: String? {
		switch self {
		case .containerNotFound(let message),
			.readinessTimeout(let message),
			.runtimeFailure(let message):
			return message
		}
	}
}

@MainActor
protocol StartupSequenceRuntime: AnyObject {
	func isContainerSystemRunning() async -> Bool
	func startContainerSystem() async throws
	func containerStatuses() async throws -> [String: String]
	func startStartupContainer(_ id: String) async throws
	func stopStartupContainer(_ id: String) async throws
}

@MainActor
final class StartupSequenceRuntimeAdapter: StartupSequenceRuntime {
	private let backend: ContainerBackend
	private let systemService: SystemService
	private let containerListService: ContainerListService

	init(backend: ContainerBackend, systemService: SystemService, containerListService: ContainerListService) {
		self.backend = backend
		self.systemService = systemService
		self.containerListService = containerListService
	}

	func isContainerSystemRunning() async -> Bool {
		if systemService.systemStatus == .running { return true }
		await systemService.checkSystemStatus()
		return systemService.systemStatus == .running
	}

	func startContainerSystem() async throws {
		await systemService.startSystem()
		guard systemService.systemStatus == .running else {
			throw StartupSequenceError.runtimeFailure("The container system could not be started.")
		}
	}

	func containerStatuses() async throws -> [String: String] {
		let containers = try await backend.listContainers()
		containerListService.containers = containers
		return Dictionary(uniqueKeysWithValues: containers.map { ($0.configuration.id, $0.status) })
	}

	func startStartupContainer(_ id: String) async throws {
		try await backend.bootstrapAndStart(id: id)
	}

	func stopStartupContainer(_ id: String) async throws {
		try await backend.stopContainer(id: id)
	}
}

@MainActor
final class StartupSequenceService: ObservableObject {
	@Published private(set) var sequence: StartupSequence
	@Published private(set) var state: StartupSequenceRunState = .idle
	@Published private(set) var sequenceOwnedContainerIDs: [String] = []

	private let runtime: StartupSequenceRuntime
	private let defaults: UserDefaults
	private let readinessTimeout: TimeInterval
	private let sequenceKey = "OrchardStartupSequence"
	private var hasAttemptedAutomaticRun = false
	private var activeRunTask: Task<Void, Never>?
	private var automaticPreparationTask: Task<Bool, Never>?

	init(runtime: StartupSequenceRuntime, defaults: UserDefaults = .standard, readinessTimeout: TimeInterval = StartupSequence.readinessTimeout) {
		self.runtime = runtime
		self.defaults = defaults
		self.readinessTimeout = readinessTimeout
		if let data = defaults.data(forKey: sequenceKey), let savedSequence = try? JSONDecoder().decode(StartupSequence.self, from: data) {
			sequence = savedSequence
		} else {
			sequence = StartupSequence()
		}
	}

	var isRunning: Bool { activeRunTask != nil }

	func updateSequence(_ sequence: StartupSequence) {
		self.sequence = sequence
		persistSequence()
	}

	func persistSequence() {
		guard let data = try? JSONEncoder().encode(sequence) else { return }
		defaults.set(data, forKey: sequenceKey)
	}

	func runIfEnabled(availableContainerIDs: Set<String>) {
		guard sequence.isEnabled, !hasAttemptedAutomaticRun else { return }
		hasAttemptedAutomaticRun = true
		run(availableContainerIDs: availableContainerIDs)
	}

	func prepareForAutomaticRun() async -> Bool {
		guard sequence.isEnabled else { return true }
		if let automaticPreparationTask {
			return await automaticPreparationTask.value
		}

		let task = Task { [weak self] in
			guard let self else { return false }
			guard !(await self.runtime.isContainerSystemRunning()) else { return true }

			self.state = .startingSystem
			do {
				try await self.runtime.startContainerSystem()
				return true
			} catch {
				self.state = .failed(error.localizedDescription)
				return false
			}
		}
		automaticPreparationTask = task

		let result = await task.value
		automaticPreparationTask = nil
		return result
	}

	func run(availableContainerIDs: Set<String>) {
		guard activeRunTask == nil else { return }
		activeRunTask = Task { [weak self] in
			guard let self else { return }
			await self.execute(availableContainerIDs: availableContainerIDs)
			self.activeRunTask = nil
		}
	}

	func stopSequenceOwnedContainers() async {
		let runTask = activeRunTask
		runTask?.cancel()
		if let runTask { await runTask.value }
		activeRunTask = nil
		guard !sequenceOwnedContainerIDs.isEmpty else { return }

		state = .stopping
		for id in sequenceOwnedContainerIDs.reversed() {
			guard !Task.isCancelled else { break }
			do {
				try await runtime.stopStartupContainer(id)
			} catch {
				state = .failed("Failed to stop \(id): \(error.localizedDescription)")
			}
		}
		sequenceOwnedContainerIDs.removeAll()
		if case .stopping = state { state = .idle }
	}

	private func execute(availableContainerIDs: Set<String>) async {
		if let validationError = sequence.validationError(availableContainerIDs: availableContainerIDs) {
			state = .failed(validationError)
			return
		}

		do {
			if !(await runtime.isContainerSystemRunning()) {
				state = .startingSystem
				try await runtime.startContainerSystem()
			}

			var completedGroups = Set<UUID>()
			while completedGroups.count < sequence.groups.count {
				try Task.checkCancellation()
				let eligibleGroups = sequence.groups.filter {
					!completedGroups.contains($0.id) && Set($0.waitForGroupIDs).isSubset(of: completedGroups)
				}
				guard !eligibleGroups.isEmpty else {
					throw StartupSequenceError.runtimeFailure("Startup groups could not be ordered.")
				}

				try await withThrowingTaskGroup(of: UUID.self) { groupTasks in
					for group in eligibleGroups {
						groupTasks.addTask { [weak self] in
							guard let self else { throw CancellationError() }
							try await self.execute(group)
							return group.id
						}
					}
					for try await groupID in groupTasks {
						completedGroups.insert(groupID)
					}
				}
			}

			state = .completed
		} catch is CancellationError {
			state = .idle
		} catch {
			state = .failed(error.localizedDescription)
		}
	}

	private func execute(_ group: StartupGroup) async throws {
		state = .startingGroup(group.name)
		try await withThrowingTaskGroup(of: Void.self) { containerTasks in
			for container in group.containers {
				containerTasks.addTask { [weak self] in
					guard let self else { throw CancellationError() }
					try await self.execute(container)
				}
			}
			for try await _ in containerTasks { }
		}
	}

	private func execute(_ container: StartupGroupContainer) async throws {
		for dependency in container.waitForContainerIDs {
			try await waitUntilRunning(dependency)
		}

		let statuses = try await runtime.containerStatuses()
		guard let status = statuses[container.containerID] else {
			throw StartupSequenceError.containerNotFound(container.containerID)
		}

		if status.lowercased() == "running" {
			return
		}

		state = .starting(container.containerID)
		try await runtime.startStartupContainer(container.containerID)
		if !sequenceOwnedContainerIDs.contains(container.containerID) {
			sequenceOwnedContainerIDs.append(container.containerID)
		}
		try await waitUntilRunning(container.containerID)
	}

	private func waitUntilRunning(_ id: String) async throws {
		let deadline = Date().addingTimeInterval(readinessTimeout)
		while Date() < deadline {
			try Task.checkCancellation()
			let statuses = try await runtime.containerStatuses()
			if statuses[id]?.lowercased() == "running" { return }
			state = .waiting(id)
			let remainingMilliseconds = Int(max(1, min(500, deadline.timeIntervalSinceNow * 1_000)))
			try await Task.sleep(for: .milliseconds(remainingMilliseconds))
		}
		throw StartupSequenceError.readinessTimeout("Timed out waiting for \(id) to become running.")
	}
}
