import Foundation
import Testing
@testable import Orchard

@MainActor
private final class StartupRuntimeStub: StartupSequenceRuntime {
	var systemRunning = false
	var statuses: [String: String]
	var startSystemCount = 0
	var startedContainerIDs: [String] = []
	var stoppedContainerIDs: [String] = []
	var containersBecomeRunning = true

	init(statuses: [String: String]) {
		self.statuses = statuses
	}

	func isContainerSystemRunning() async -> Bool {
		systemRunning
	}

	func startContainerSystem() async throws {
		startSystemCount += 1
		systemRunning = true
	}

	func containerStatuses() async throws -> [String: String] {
		statuses
	}

	func startStartupContainer(_ id: String) async throws {
		startedContainerIDs.append(id)
		if containersBecomeRunning {
			statuses[id] = "running"
		}
	}

	func stopStartupContainer(_ id: String) async throws {
		stoppedContainerIDs.append(id)
	}
}

@MainActor
struct StartupSequenceServiceTests {
	@Test func persistsSequenceConfiguration() {
		let suiteName = "OrchardStartupSequenceTests-\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let runtime = StartupRuntimeStub(statuses: [:])
		let service = StartupSequenceService(runtime: runtime, defaults: defaults)
		let sequence = StartupSequence(
			isEnabled: true,
			steps: [
				StartupStep(containerID: "a"),
				StartupStep(containerID: "b", waitForContainerID: "a")
			])

		service.updateSequence(sequence)
		let reloaded = StartupSequenceService(runtime: runtime, defaults: defaults)

		#expect(reloaded.sequence == sequence)
	}

	@Test func rejectsDuplicatesButAllowsOutOfOrderDependencies() {
		let duplicate = StartupSequence(steps: [
			StartupStep(containerID: "a"),
			StartupStep(containerID: "a")
		])
		#expect(duplicate.validationError() == "Container \"a\" appears more than once.")

		let outOfOrder = StartupSequence(steps: [
			StartupStep(containerID: "b", waitForContainerID: "a"),
			StartupStep(containerID: "a")
		])
		#expect(outOfOrder.validationError() == nil)
	}

	@Test func runsDependentGroupsAfterAllPrerequisiteContainersAreReady() async {
		let backendID = UUID()
		let frontendID = UUID()
		let runtime = StartupRuntimeStub(statuses: ["mysql": "stopped", "php8": "stopped", "nginx": "stopped"])
		let suiteName = "OrchardStartupSequenceTests-\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let service = StartupSequenceService(runtime: runtime, defaults: defaults)
		service.updateSequence(StartupSequence(groups: [
			StartupGroup(
				id: backendID,
				name: "Backend",
				containers: [
					StartupGroupContainer(containerID: "mysql"),
					StartupGroupContainer(containerID: "php8")
				]),
			StartupGroup(
				id: frontendID,
				name: "Frontend",
				containers: [StartupGroupContainer(containerID: "nginx")],
				waitForGroupIDs: [backendID])
		]))

		service.run(availableContainerIDs: ["mysql", "php8", "nginx"])
		await waitForRunToFinish(service)

		#expect(service.state == .completed)
		#expect(Set(runtime.startedContainerIDs) == Set(["mysql", "php8", "nginx"]))
	}

	@Test func allowsContainerToWaitForContainerInAnotherGroup() async {
		let websitesID = UUID()
		let servicesID = UUID()
		let sequence = StartupSequence(groups: [
			StartupGroup(
				id: websitesID,
				name: "Websites",
				containers: [StartupGroupContainer(containerID: "mysql")]),
			StartupGroup(
				id: servicesID,
				name: "Services",
				containers: [
					StartupGroupContainer(containerID: "mosquitto"),
					StartupGroupContainer(containerID: "nodered", waitForContainerIDs: ["mosquitto", "mysql"])]),
		])
		#expect(sequence.validationError() == nil)

		let runtime = StartupRuntimeStub(statuses: ["mysql": "stopped", "mosquitto": "stopped", "nodered": "stopped"])
		let suiteName = "OrchardStartupSequenceTests-\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let service = StartupSequenceService(runtime: runtime, defaults: defaults)
		service.updateSequence(sequence)
		service.run(availableContainerIDs: ["mysql", "mosquitto", "nodered"])
		await waitForRunToFinish(service)

		#expect(service.state == .completed)
		#expect(Set(runtime.startedContainerIDs) == Set(["mysql", "mosquitto", "nodered"]))
	}

	@Test func rejectsCrossGroupDependencyDeadlocks() {
		let groupAID = UUID()
		let groupBID = UUID()
		let sequence = StartupSequence(groups: [
			StartupGroup(
				id: groupAID,
				name: "A",
				containers: [StartupGroupContainer(containerID: "a")],
				waitForGroupIDs: [groupBID]),
			StartupGroup(
				id: groupBID,
				name: "B",
				containers: [StartupGroupContainer(containerID: "b", waitForContainerIDs: ["a"])])
		])

		#expect(sequence.validationError() == "Startup groups contain a dependency cycle.")
	}

	@Test func startsInOrderAndStopsOnlyOwnedContainersInReverseOrder() async {
		let runtime = StartupRuntimeStub(statuses: ["a": "stopped", "b": "running", "c": "stopped", "nginx": "stopped"])
		let suiteName = "OrchardStartupSequenceTests-\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let service = StartupSequenceService(runtime: runtime, defaults: defaults)
		service.updateSequence(StartupSequence(steps: [
			StartupStep(containerID: "a"),
			StartupStep(containerID: "b", waitForContainerID: "a"),
			StartupStep(containerID: "c", waitForContainerID: "b"),
			StartupStep(containerID: "nginx", waitForContainerIDs: ["a", "c"])
		]))

		service.run(availableContainerIDs: ["a", "b", "c", "nginx"])
		await waitForRunToFinish(service)

		#expect(runtime.startSystemCount == 1)
		#expect(Set(runtime.startedContainerIDs) == Set(["a", "c", "nginx"]))
		#expect(service.state == .completed)

		let startedOrder = runtime.startedContainerIDs
		await service.stopSequenceOwnedContainers()

		#expect(runtime.stoppedContainerIDs == Array(startedOrder.reversed()))
	}

	@Test func abortsWhenStartedContainerNeverBecomesReady() async {
		let runtime = StartupRuntimeStub(statuses: ["a": "stopped"])
		runtime.containersBecomeRunning = false
		let suiteName = "OrchardStartupSequenceTests-\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let service = StartupSequenceService(
			runtime: runtime,
			defaults: defaults,
			readinessTimeout: 0.02)
		service.updateSequence(StartupSequence(steps: [StartupStep(containerID: "a")]))

		service.run(availableContainerIDs: ["a"])
		await waitForRunToFinish(service)

		guard case .failed(let message) = service.state else {
			Issue.record("Expected a failed startup sequence")
			return
		}
		#expect(message.contains("Timed out waiting for a"))
		#expect(runtime.startedContainerIDs == ["a"])
		#expect(service.sequenceOwnedContainerIDs == ["a"])
	}

	private func waitForRunToFinish(_ service: StartupSequenceService) async {
		while service.isRunning {
			do {
				try await Task.sleep(for: .milliseconds(10))
			} catch {
				return
			}
		}
	}
}
