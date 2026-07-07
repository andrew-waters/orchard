import Testing
import Foundation
@testable import Orchard

// MachineService load, lifecycle transitions, and error surfacing. The mock mutates its
// stored machines on each lifecycle call, so a post-action `load()` (which the service does
// internally) reflects the transition — the same contract as the live daemon.
//
// Alert copy is not asserted (same stance as the other service suites); a fired alert is
// detected structurally via `AlertCenter.current`.

@MainActor
private func makeMachineService(_ backend: MockMachineBackend = MockMachineBackend())
    -> (service: MachineService, alert: AlertCenter) {
    let alert = AlertCenter()
    let service = MachineService(backend: backend, alertCenter: alert)
    return (service, alert)
}

// MARK: - load

@Test("Machines load: success publishes the list and clears loading, no alert")
@MainActor
func machinesLoadSuccess() async {
    let backend = MockMachineBackend()
    backend.machines = [makeMachine(id: "m-a", isDefault: true), makeMachine(id: "m-b", status: "stopped")]
    let (service, alert) = makeMachineService(backend)

    await service.load()

    #expect(service.machines.count == 2)
    #expect(service.isLoading == false)
    #expect(service.apiUnavailable == false)
    #expect(alert.current == nil)
}

@Test("Machines load: machineApiUnavailable sets the flag, empties the list, and does not alert")
@MainActor
func machinesLoadApiUnavailable() async {
    let backend = MockMachineBackend()
    backend.machines = [makeMachine(id: "m-a")]
    backend.listError = OrchardError.machineApiUnavailable
    let (service, alert) = makeMachineService(backend)

    await service.load()

    #expect(service.apiUnavailable == true)
    #expect(service.machines.isEmpty)
    #expect(service.isLoading == false)
    #expect(alert.current == nil)
}

@Test("Machines load: a generic user-initiated failure alerts and clears loading")
@MainActor
func machinesLoadGenericErrorAlerts() async {
    let backend = MockMachineBackend()
    backend.listError = makeError("boom")
    let (service, alert) = makeMachineService(backend)

    await service.load(showLoading: true)

    #expect(alert.current != nil)
    #expect(service.isLoading == false)
    #expect(service.apiUnavailable == false)
}

@Test("Machines load: a background failure (showLoading false) does not alert")
@MainActor
func machinesLoadBackgroundErrorSilent() async {
    let backend = MockMachineBackend()
    backend.listError = makeError("boom")
    let (service, alert) = makeMachineService(backend)

    await service.load(showLoading: false)

    #expect(alert.current == nil)
}

// MARK: - lifecycle transitions

@Test("Machines boot: a stopped machine transitions to running and is recorded")
@MainActor
func machinesBootTransition() async {
    let backend = MockMachineBackend()
    backend.machines = [makeMachine(id: "m-a", status: "stopped")]
    let (service, alert) = makeMachineService(backend)
    await service.load()

    await service.boot("m-a")

    #expect(backend.bootedIds == ["m-a"])
    #expect(service.machines.first?.status == "running")
    #expect(alert.current == nil)
}

@Test("Machines stop: a running machine transitions to stopped")
@MainActor
func machinesStopTransition() async {
    let backend = MockMachineBackend()
    backend.machines = [makeMachine(id: "m-a", status: "running")]
    let (service, _) = makeMachineService(backend)
    await service.load()

    await service.stop("m-a")

    #expect(backend.stoppedIds == ["m-a"])
    #expect(service.machines.first?.status == "stopped")
}

@Test("Machines delete: removes the machine from the published list")
@MainActor
func machinesDeleteRemoves() async {
    let backend = MockMachineBackend()
    backend.machines = [makeMachine(id: "m-a"), makeMachine(id: "m-b")]
    let (service, _) = makeMachineService(backend)
    await service.load()

    await service.delete("m-a")

    #expect(backend.deletedIds == ["m-a"])
    #expect(service.machines.map(\.id) == ["m-b"])
}

@Test("Machines setDefault: moves the default badge to the chosen machine")
@MainActor
func machinesSetDefaultFlips() async {
    let backend = MockMachineBackend()
    backend.machines = [makeMachine(id: "m-a", isDefault: true), makeMachine(id: "m-b", isDefault: false)]
    let (service, _) = makeMachineService(backend)
    await service.load()

    await service.setDefault("m-b")

    #expect(backend.setDefaultIds == ["m-b"])
    #expect(service.machines.first(where: { $0.id == "m-a" })?.isDefault == false)
    #expect(service.machines.first(where: { $0.id == "m-b" })?.isDefault == true)
}

@Test("Machines boot: a failure alerts and leaves state untouched")
@MainActor
func machinesBootFailureAlerts() async {
    let backend = MockMachineBackend()
    backend.machines = [makeMachine(id: "m-a", status: "stopped")]
    backend.bootError = makeError("cannot boot")
    let (service, alert) = makeMachineService(backend)
    await service.load()

    await service.boot("m-a")

    #expect(alert.current != nil)
    #expect(service.machines.first?.status == "stopped")
}

// MARK: - create

private func makeCreateSpec(name: String = "dev-box", noBoot: Bool = false, setDefault: Bool = false) -> MachineCreateSpec {
    MachineCreateSpec(name: name, imageRef: "docker.io/library/fedora:41", cpus: 4, memoryGiB: 4,
                      homeMount: "rw", virtualization: false, kernelPath: nil, setDefault: setDefault, noBoot: noBoot)
}

@Test("Machines create: success records the spec, adds the machine, and does not alert")
@MainActor
func machinesCreateSuccess() async {
    let backend = MockMachineBackend()
    let (service, alert) = makeMachineService(backend)

    let ok = await service.create(makeCreateSpec(name: "dev-box"))

    #expect(ok)
    #expect(backend.createdSpecs.map(\.name) == ["dev-box"])
    #expect(service.machines.contains { $0.id == "dev-box" })
    #expect(service.isCreating == false)
    #expect(alert.current == nil)
}

@Test("Machines create: a failure alerts and returns false")
@MainActor
func machinesCreateFailure() async {
    let backend = MockMachineBackend()
    backend.createError = makeError("image not found")
    let (service, alert) = makeMachineService(backend)

    let ok = await service.create(makeCreateSpec())

    #expect(!ok)
    #expect(alert.current != nil)
    #expect(service.isCreating == false)
}

// MARK: - applyConfig (edit + restart orchestration)

private func makeConfigSpec(cpus: Int = 2, memoryGiB: Int = 2) -> MachineConfigSpec {
    MachineConfigSpec(cpus: cpus, memoryGiB: memoryGiB, homeMount: "ro", virtualization: false, kernelPath: nil)
}

@Test("Machines edit: apply without restart sets config and does not stop/boot")
@MainActor
func machinesApplyConfigNoRestart() async {
    let backend = MockMachineBackend()
    backend.machines = [makeMachine(id: "m-a", status: "running")]
    let (service, alert) = makeMachineService(backend)
    await service.load()

    let ok = await service.applyConfig(makeConfigSpec(cpus: 8), to: "m-a", restartNow: false)

    #expect(ok)
    #expect(backend.setConfigCalls.map(\.id) == ["m-a"])
    #expect(backend.setConfigCalls.first?.config.cpus == 8)
    #expect(backend.stoppedIds.isEmpty)
    #expect(backend.bootedIds.isEmpty)
    #expect(alert.current == nil)
}

@Test("Machines edit: apply with restart sets config then stops and boots")
@MainActor
func machinesApplyConfigRestart() async {
    let backend = MockMachineBackend()
    backend.machines = [makeMachine(id: "m-a", status: "running")]
    let (service, _) = makeMachineService(backend)
    await service.load()

    let ok = await service.applyConfig(makeConfigSpec(), to: "m-a", restartNow: true)

    #expect(ok)
    #expect(backend.setConfigCalls.map(\.id) == ["m-a"])
    #expect(backend.stoppedIds == ["m-a"])
    #expect(backend.bootedIds == ["m-a"])
}

@Test("Machines edit: a setConfig failure alerts and returns false")
@MainActor
func machinesApplyConfigFailure() async {
    let backend = MockMachineBackend()
    backend.machines = [makeMachine(id: "m-a", status: "running")]
    backend.setConfigError = makeError("bad config")
    let (service, alert) = makeMachineService(backend)
    await service.load()

    let ok = await service.applyConfig(makeConfigSpec(), to: "m-a", restartNow: true)

    #expect(!ok)
    #expect(alert.current != nil)
    #expect(backend.bootedIds.isEmpty)
}

// MARK: - fetchLogs

@Test("Machine logs: stdio handle (index 0) is read into lines")
@MainActor
func machineLogsStdio() async throws {
    let backend = MockMachineBackend()
    backend.logs = [pipeHandle(with: "hello\nworld\n")]
    let (service, _) = makeMachineService(backend)

    let lines = try await service.fetchLogs(id: "m-a")

    #expect(lines.prefix(2) == ["hello", "world"])
}

@Test("Machine logs: boot flag selects the second handle")
@MainActor
func machineLogsBoot() async throws {
    let backend = MockMachineBackend()
    backend.logs = [pipeHandle(with: "stdio\n"), pipeHandle(with: "boot-line\n")]
    let (service, _) = makeMachineService(backend)

    let lines = try await service.fetchLogs(id: "m-a", boot: true)

    #expect(lines.first == "boot-line")
}

// MARK: - Stats sampling

@Test("Stats: a running machine is sampled through its backing container, keyed on the machine id")
@MainActor
func statsSamplesMachineViaBackingContainer() async {
    let backend = MockContainerBackend()
    // Return stats for whatever id is asked (the backing container id).
    backend.statsHandler = { id in
        Orchard.ContainerStats(id: id, cpuUsageUsec: 1000, memoryUsageBytes: 100, memoryLimitBytes: 1000,
                               blockReadBytes: 0, blockWriteBytes: 0, networkRxBytes: 0, networkTxBytes: 0, numProcesses: 3)
    }
    let alert = AlertCenter()
    let containerList = ContainerListService(backend: backend, alertCenter: alert, pollInterval: 0)
    let stats = StatsService(backend: backend, alertCenter: alert, containerList: containerList)
    stats.machineStatTargets = { [(machineId: "m-a", backingId: "m-a-abc123", cpus: 4)] }

    await stats.load(showLoading: false)

    // Exposed under the bare machine id, not the backing container id.
    #expect(stats.machineStats.map(\.id) == ["m-a"])
    #expect(stats.machineRawStats("m-a")?.memoryUsageBytes == 100)
    // And it did not leak into the container-facing array.
    #expect(stats.containerStats.isEmpty)
}

/// A readable `FileHandle` pre-filled with `text` (write end closed), so `readDataToEndOfFile`
/// returns exactly `text` — models a machine log fd without touching a real daemon.
private func pipeHandle(with text: String) -> FileHandle {
    let pipe = Pipe()
    pipe.fileHandleForWriting.write(Data(text.utf8))
    try? pipe.fileHandleForWriting.close()
    return pipe.fileHandleForReading
}
