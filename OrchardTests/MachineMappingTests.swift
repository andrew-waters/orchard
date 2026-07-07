import Testing
import Foundation
import MachineAPIClient
import ContainerResource
import ContainerPersistence
import ContainerizationOCI
@testable import Orchard

// Pure mapping from the machine client's `MachineSnapshot` to Orchard's `Machine`. Inputs are
// constructed to mirror the M0 spike captures: a running alpine machine (rw home, 4cpu/4G)
// and a stopped one (which the daemon returns with ipAddress/startedDate/containerId absent).

private func makeSnapshot(
    id: String,
    status: RuntimeStatus,
    running: Bool
) throws -> MachineSnapshot {
    let image = ImageDescription(
        reference: "docker.io/library/alpine:3.22",
        descriptor: Descriptor(
            mediaType: "application/vnd.oci.image.index.v1+json",
            digest: "sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce",
            size: 9218
        )
    )
    let configuration = try MachineConfiguration(
        id: id,
        image: image,
        platform: ContainerizationOCI.Platform(arch: "arm64", os: "linux"),
        userSetup: UserSetup(username: "aw", uid: 501, gid: 20)
    )
    let bootConfig = try MachineConfig(
        cpus: 4,
        memory: try MemorySize("4gb"),
        homeMount: .rw,
        virtualization: false,
        kernelPath: nil
    )
    return MachineSnapshot(
        configuration: configuration,
        status: status,
        bootConfig: bootConfig,
        startedDate: running ? Date(timeIntervalSince1970: 1_751_888_677) : nil,
        createdDate: Date(timeIntervalSince1970: 1_751_888_675),
        containerId: running ? "\(id)-13ab40" : nil,
        ipAddress: running ? "192.168.66.7" : nil,
        diskSize: 78_659_584,
        initialized: true
    )
}

@Test("Machine mapping: a running snapshot carries every field through, isDefault from the caller")
func mapMachineRunning() throws {
    let snapshot = try makeSnapshot(id: "orchard-m0-a", status: .running, running: true)

    let machine = mapMachine(snapshot, isDefault: true)

    #expect(machine.id == "orchard-m0-a")
    #expect(machine.status == "running")
    #expect(machine.isDefault == true)
    #expect(machine.cpus == 4)
    #expect(machine.memoryBytes == 4_294_967_296)
    #expect(machine.diskSizeBytes == 78_659_584)
    #expect(machine.homeMount == "rw")
    #expect(machine.virtualization == false)
    #expect(machine.kernelPath == nil)
    #expect(machine.imageReference == "docker.io/library/alpine:3.22")
    #expect(machine.platform.os == "linux")
    #expect(machine.platform.architecture == "arm64")
    #expect(machine.ipAddress == "192.168.66.7")
    #expect(machine.containerId == "orchard-m0-a-13ab40")
    #expect(machine.initialized == true)
    #expect(machine.userSetup?.username == "aw")
    #expect(machine.userSetup?.uid == 501)
    #expect(machine.userSetup?.gid == 20)
}

@Test("Machine mapping: a stopped snapshot leaves ip/started/containerId nil and isDefault false")
func mapMachineStopped() throws {
    let snapshot = try makeSnapshot(id: "orchard-m0-b", status: .stopped, running: false)

    let machine = mapMachine(snapshot, isDefault: false)

    #expect(machine.status == "stopped")
    #expect(machine.isDefault == false)
    #expect(machine.ipAddress == nil)
    #expect(machine.startedDate == nil)
    #expect(machine.containerId == nil)
    #expect(machine.isStopped == true)
    #expect(machine.isRunning == false)
}
