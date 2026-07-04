import Testing
import Foundation
import ContainerResource
import ContainerizationOCI
import ContainerAPIClient
@testable import Orchard

// Pure mapping from the upstream `container` framework types to Orchard's own models.
// No mocks, no async — construct an input value, assert the mapped output.

// MARK: - mapContainerStats

// KNOWN-ISSUE (2026-07-04): nil (unknown/unlimited) is coalesced to 0 and is therefore
// indistinguishable from a real 0 downstream — the UI renders an unknown/unlimited memory
// limit as 0%. This test documents the current coalescing, not an endorsement of it; a
// future fix should preserve optionality.
@Test("Stats mapping: nil counters coalesce to 0 (see KNOWN-ISSUE)")
func statsMappingNilCoalesces() {
    let raw = ContainerResource.ContainerStats(
        id: "web", memoryUsageBytes: nil, memoryLimitBytes: nil, cpuUsageUsec: nil,
        networkRxBytes: nil, networkTxBytes: nil, blockReadBytes: nil,
        blockWriteBytes: nil, numProcesses: nil
    )

    let mapped = mapContainerStats(raw)

    #expect(mapped.id == "web")
    #expect(mapped.cpuUsageUsec == 0)
    #expect(mapped.memoryUsageBytes == 0)
    #expect(mapped.memoryLimitBytes == 0)
    #expect(mapped.blockReadBytes == 0)
    #expect(mapped.blockWriteBytes == 0)
    #expect(mapped.networkRxBytes == 0)
    #expect(mapped.networkTxBytes == 0)
    #expect(mapped.numProcesses == 0)
}

@Test("Stats mapping: populated UInt64 counters carry through as Int")
func statsMappingPopulated() {
    let raw = ContainerResource.ContainerStats(
        id: "db", memoryUsageBytes: 2048, memoryLimitBytes: 8192, cpuUsageUsec: 12345,
        networkRxBytes: 111, networkTxBytes: 222, blockReadBytes: 333,
        blockWriteBytes: 444, numProcesses: 7
    )

    let mapped = mapContainerStats(raw)

    #expect(mapped.id == "db")
    #expect(mapped.cpuUsageUsec == 12345)
    #expect(mapped.memoryUsageBytes == 2048)
    #expect(mapped.memoryLimitBytes == 8192)
    #expect(mapped.networkRxBytes == 111)
    #expect(mapped.networkTxBytes == 222)
    #expect(mapped.blockReadBytes == 333)
    #expect(mapped.blockWriteBytes == 444)
    #expect(mapped.numProcesses == 7)
}

// MARK: - mapResources

@Test("Resources mapping: cpus and UInt64 memory carry through as Int")
func resourcesMapping() {
    var resources = ContainerResource.ContainerConfiguration.Resources()
    resources.cpus = 3
    resources.memoryInBytes = 4096

    let mapped = mapResources(resources)

    #expect(mapped.cpus == 3)
    #expect(mapped.memoryInBytes == 4096)
}

// MARK: - mapPlatform

@Test("Platform mapping: os and architecture are stringified from the input")
func platformMapping() {
    let platform = ContainerizationOCI.Platform(arch: "arm64", os: "linux", variant: "v8")

    let mapped = mapPlatform(platform)

    #expect(mapped.os == "linux")
    #expect(mapped.architecture == "arm64")
    // NB: mapPlatform hardcodes variant to nil even though Orchard.Platform has the field —
    // see the KNOWN-ISSUE on mapPlatform. Not asserted here (a constant can't be falsified).
}

// MARK: - mapProcessConfiguration (the user-enum switch — actual branching)

@Test("Process mapping: an id-based user maps to a UserID with uid/gid, no raw")
func processMappingUserID() {
    let process = ProcessConfiguration(
        executable: "/bin/sh", arguments: [], environment: [],
        user: .id(uid: 501, gid: 20)
    )

    let mapped = mapProcessConfiguration(process)

    #expect(mapped.user.id?.uid == 501)
    #expect(mapped.user.id?.gid == 20)
    #expect(mapped.user.raw == nil)
    #expect(mapped.executable == "/bin/sh")
}

@Test("Process mapping: a raw user maps to UserRaw, no id")
func processMappingRawUser() {
    let process = ProcessConfiguration(
        executable: "/bin/sh", arguments: [], environment: [],
        user: .raw(userString: "root:root")
    )

    let mapped = mapProcessConfiguration(process)

    #expect(mapped.user.raw?.userString == "root:root")
    #expect(mapped.user.id == nil)
}

// MARK: - mapDNSConfiguration

@Test("DNS mapping: nil configuration maps to an empty DNS (the guard branch)")
func dnsMappingNil() {
    let mapped = mapDNSConfiguration(nil)

    #expect(mapped.nameservers.isEmpty)
    #expect(mapped.searchDomains.isEmpty)
    #expect(mapped.options.isEmpty)
    #expect(mapped.domain == nil)
}

@Test("DNS mapping: populated configuration carries every field through")
func dnsMappingPopulated() {
    let dns = ContainerResource.ContainerConfiguration.DNSConfiguration(
        nameservers: ["1.1.1.1", "8.8.8.8"],
        domain: "test",
        searchDomains: ["svc.local"],
        options: ["ndots:2"]
    )

    let mapped = mapDNSConfiguration(dns)

    #expect(mapped.nameservers == ["1.1.1.1", "8.8.8.8"])
    #expect(mapped.domain == "test")
    #expect(mapped.searchDomains == ["svc.local"])
    #expect(mapped.options == ["ndots:2"])
}

// MARK: - mapDiskUsageStats / mapResourceUsage

@Test("Disk usage mapping: per-section counts carry through with widened integers")
func diskUsageMapping() {
    let usage = DiskUsageStats(
        images: ResourceUsage(total: 10, active: 4, sizeInBytes: 5000, reclaimable: 1000),
        containers: ResourceUsage(total: 3, active: 3, sizeInBytes: 200, reclaimable: 0),
        volumes: ResourceUsage(total: 1, active: 0, sizeInBytes: 50, reclaimable: 50)
    )

    let mapped = mapDiskUsageStats(usage)

    #expect(mapped.images.total == 10)
    #expect(mapped.images.active == 4)
    #expect(mapped.images.sizeInBytes == 5000)
    #expect(mapped.images.reclaimable == 1000)
    #expect(mapped.containers.total == 3)
    #expect(mapped.volumes.sizeInBytes == 50)
    #expect(mapped.volumes.reclaimable == 50)
}
