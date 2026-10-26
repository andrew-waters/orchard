import Testing
import Foundation
@testable import Orchard

// MARK: - ContainerPlatform.resolve (#147)

@Test("Platform: a requested platform the image offers is used")
func resolveRequested() throws {
    let platform = try ContainerPlatform.resolve(
        requested: "linux/amd64", candidates: ["linux/arm64", "linux/amd64"], host: "linux/arm64"
    )
    #expect(platform == "linux/amd64")
}

@Test("Platform: a requested platform the image does not offer is refused, naming what it does")
func resolveRequestedMissing() {
    let error = #expect(throws: ContainerPlatform.ResolutionError.self) {
        try ContainerPlatform.resolve(requested: "linux/amd64", candidates: ["linux/arm64"], host: "linux/arm64")
    }
    #expect(error?.message.contains("linux/arm64") == true)
}

@Test("Platform: Automatic runs a single-platform image as that platform")
func resolveSingleCandidate() throws {
    #expect(try ContainerPlatform.resolve(requested: nil, candidates: ["linux/amd64"], host: "linux/arm64") == "linux/amd64")
    // An empty request is Automatic too: it is what the form sends.
    #expect(try ContainerPlatform.resolve(requested: "", candidates: ["linux/amd64"], host: "linux/arm64") == "linux/amd64")
}

@Test("Platform: Automatic picks the host's among several")
func resolveHostAmongSeveral() throws {
    let platform = try ContainerPlatform.resolve(
        requested: nil, candidates: ["linux/amd64", "linux/arm64", "linux/arm/v7"], host: "linux/arm64"
    )
    #expect(platform == "linux/arm64")
}

@Test("Platform: several without the host's cannot be chosen between automatically")
func resolveSeveralWithoutHost() {
    #expect(throws: ContainerPlatform.ResolutionError.self) {
        try ContainerPlatform.resolve(requested: nil, candidates: ["linux/amd64", "linux/s390x"], host: "linux/arm64")
    }
}

@Test("Platform: unreadable candidates fall back to the request, or the host's")
func resolveUnknownCandidates() throws {
    #expect(try ContainerPlatform.resolve(requested: nil, candidates: [], host: "linux/arm64") == "linux/arm64")
    #expect(try ContainerPlatform.resolve(requested: "linux/amd64", candidates: [], host: "linux/arm64") == "linux/amd64")
}

@Test("Platform: Rosetta is needed for amd64 on an arm64 host only")
func rosettaRule() {
    #expect(ContainerPlatform.needsRosetta("linux/amd64", hostArchitecture: "arm64"))
    #expect(!ContainerPlatform.needsRosetta("linux/arm64", hostArchitecture: "arm64"))
    #expect(!ContainerPlatform.needsRosetta("linux/amd64", hostArchitecture: "amd64"))
    #expect(!ContainerPlatform.needsRosetta("", hostArchitecture: "arm64"))
}

@Test("Platform: description leaves out arm64's v8 and keeps other variants")
func platformDescription() {
    #expect(Platform(os: "linux", architecture: "arm64", variant: "v8").description == "linux/arm64")
    #expect(Platform(os: "linux", architecture: "arm64", variant: nil).description == "linux/arm64")
    #expect(Platform(os: "linux", architecture: "arm", variant: "v7").description == "linux/arm/v7")
    #expect(Platform(os: "linux", architecture: "amd64", variant: nil).description == "linux/amd64")
}

// MARK: - Carrying the choice to the create spec

@MainActor
@Test("Spec: a chosen platform is carried; Automatic sends none")
func specPlatform() async {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)
    var config = ContainerRunConfig(name: "intel", image: "nginx")
    config.platform = "linux/amd64"
    await service.containerListService.runContainer(config: config)
    await service.containerListService.runContainer(config: ContainerRunConfig(name: "auto", image: "nginx"))

    #expect(backend.createdSpecs.first { $0.id == "intel" }?.platform == "linux/amd64")
    #expect(backend.createdSpecs.first { $0.id == "auto" }?.platform == nil)
}

// MARK: - RosettaService

@MainActor
@Test("Rosetta: a successful install refreshes availability")
func rosettaInstallRefreshes() async {
    let installed = LockedFlag()
    let service = RosettaService(
        probe: { installed.value ? .installed : .notInstalled },
        installer: { installed.set() }
    )
    #expect(service.availability == .notInstalled)
    await service.install()
    #expect(service.availability == .installed)
    #expect(service.installError == nil)
}

@MainActor
@Test("Rosetta: a failed install says so, with the command to do it by hand")
func rosettaInstallFails() async {
    let service = RosettaService(
        probe: { .notInstalled },
        installer: { throw OrchardError.generic("declined") }
    )
    await service.install()
    #expect(service.availability == .notInstalled)
    #expect(service.installError?.contains("softwareupdate --install-rosetta") == true)
    #expect(service.isInstalling == false)
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}
