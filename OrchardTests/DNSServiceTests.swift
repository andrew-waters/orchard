import Foundation
import Testing
@testable import Orchard

@MainActor
@Test("DNS load: a failed `dns ls` leaves existing domains intact and clears the spinner")
func dnsLoadFailureKeepsDomains() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 1, stdout: nil, stderr: "boom") }
    let service = makeService(runner: runner)
    service.dnsService.dnsDomains = [DNSDomain(domain: "keep.test", isDefault: true)]

    await service.dnsService.load(showLoading: true)

    #expect(service.dnsService.dnsDomains == [DNSDomain(domain: "keep.test", isDefault: true)])  // not blanked
    #expect(service.dnsService.isDNSLoading == false)                                            // spinner cleared
    #expect(service.alertCenter.current != nil)                                       // user-initiated → alert
}

@MainActor
@Test("DNS load: nil stdout clears the spinner (no infinite loading)")
func dnsLoadNilStdoutClearsSpinner() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 0, stdout: nil, stderr: nil) }
    let service = makeService(runner: runner)

    await service.dnsService.load(showLoading: true)

    #expect(service.dnsService.isDNSLoading == false)
}

// MARK: - Localhost redirect

@MainActor
@Test("DNS create: a localhost address is passed as --localhost")
func dnsCreateWithLocalhost() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)

    await service.dnsService.create("host.test", localhost: "203.0.113.1")

    #expect(runner.calls.contains(["system", "dns", "create", "host.test", "--localhost", "203.0.113.1"]))
}

@MainActor
@Test("DNS create: no localhost address leaves the flag off")
func dnsCreateWithoutLocalhost() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)

    await service.dnsService.create("plain.test")

    #expect(runner.calls.contains(["system", "dns", "create", "plain.test"]))
}

@MainActor
@Test("DNS load: a domain's localhost redirect is read from its resolver file")
func dnsLoadReadsLocalhostRedirect() async throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DNSServiceTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    // What `container system dns create host.test --localhost 203.0.113.1` writes.
    try """
        domain host.test
        search host.test
        nameserver 127.0.0.1
        port 1053
        options localhost:203.0.113.1
        """.write(to: dir.appendingPathComponent("containerization.host.test"), atomically: true, encoding: .utf8)
    try """
        domain plain.test
        search plain.test
        nameserver 127.0.0.1
        port 2053

        """.write(to: dir.appendingPathComponent("containerization.plain.test"), atomically: true, encoding: .utf8)

    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 0, stdout: #"["host.test","plain.test","gone.test"]"#, stderr: nil) }
    let service = makeService(runner: runner)
    service.dnsService.resolverDirectory = dir

    await service.dnsService.load(showLoading: false)

    #expect(service.dnsService.dnsDomains == [
        DNSDomain(domain: "host.test", localhostRedirect: "203.0.113.1"),
        DNSDomain(domain: "plain.test"),
        DNSDomain(domain: "gone.test"),   // no resolver file: no redirect, not an error
    ])
}

// MARK: - Default domain (#116)

@MainActor
@Test("DNS default: Make Default stores the preference and runs no command")
func dnsSetDefaultStoresPreference() {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    service.dnsService.dnsDomains = [DNSDomain(domain: "a.test", isDefault: true), DNSDomain(domain: "b.test")]
    let callsBefore = runner.calls.count

    service.dnsService.setDefault("b.test")

    #expect(runner.calls.count == callsBefore)   // `container system property set` no longer exists
    #expect(service.settings.defaultDNSDomain == "b.test")
    #expect(service.dnsService.dnsDomains == [DNSDomain(domain: "a.test"), DNSDomain(domain: "b.test", isDefault: true)])
}

@MainActor
@Test("DNS default: the Orchard preference beats the daemon's dns.domain")
func dnsDefaultPreferenceBeatsDaemon() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 0, stdout: #"["a.test","b.test"]"#, stderr: nil) }
    let service = makeService(runner: runner)
    service.dnsService.daemonDefaultDomain = { "a.test" }
    service.settings.setDefaultDNSDomain("b.test")

    await service.dnsService.load(showLoading: false)

    #expect(service.dnsService.defaultDomain == "b.test")
    #expect(service.dnsService.dnsDomains == [DNSDomain(domain: "a.test"), DNSDomain(domain: "b.test", isDefault: true)])
}

@MainActor
@Test("DNS default: with no preference the daemon's dns.domain is the default")
func dnsDefaultFallsBackToDaemon() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 0, stdout: #"["a.test","b.test"]"#, stderr: nil) }
    let service = makeService(runner: runner)
    service.dnsService.daemonDefaultDomain = { "a.test" }

    await service.dnsService.load(showLoading: false)
    #expect(service.dnsService.dnsDomains == [DNSDomain(domain: "a.test", isDefault: true), DNSDomain(domain: "b.test")])

    // Choosing none in Settings goes back to the daemon's.
    service.dnsService.setDefault("b.test")
    service.dnsService.setDefault(nil)
    #expect(service.settings.defaultDNSDomain == nil)
    #expect(service.dnsService.defaultDomain == "a.test")
}

@MainActor
@Test("DNS default: a chosen domain that no longer exists is forgotten on load")
func dnsDefaultClearedWhenDomainGone() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 0, stdout: #"["a.test"]"#, stderr: nil) }
    let service = makeService(runner: runner)
    service.dnsService.daemonDefaultDomain = { "a.test" }
    service.settings.setDefaultDNSDomain("gone.test")

    await service.dnsService.load(showLoading: false)

    #expect(service.settings.defaultDNSDomain == nil)
    #expect(service.dnsService.dnsDomains == [DNSDomain(domain: "a.test", isDefault: true)])
}

@MainActor
@Test("DNS default: a failed list leaves the chosen default alone")
func dnsDefaultKeptWhenListFails() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 1, stdout: nil, stderr: "boom") }
    let service = makeService(runner: runner)
    service.settings.setDefaultDNSDomain("b.test")

    await service.dnsService.load(showLoading: false)

    #expect(service.settings.defaultDNSDomain == "b.test")
}

// MARK: - [container.dns] defaults (container 1.7.1)

private func dnsSpec(
    domain: String = "", nameservers: [String] = [], search: [String] = [], options: [String] = [],
    fallback: String? = nil
) -> ContainerCreateSpec {
    var spec = ContainerCreateSpec(
        id: "web", imageRef: "nginx", environment: [], workingDirectory: "",
        commandOverride: [], volumes: [], publishedPorts: [], dnsDomain: domain,
        networkName: "", autoRemove: false, cpus: 1, memoryBytes: 1 << 30)
    spec.dnsNameservers = nameservers
    spec.dnsSearchDomains = search
    spec.dnsOptions = options
    spec.fallbackDNSDomain = fallback
    return spec
}

private let configDefaults = ContainerDNSDefaults(
    domain: "corp.test", nameservers: ["10.0.0.53"], searchDomains: ["corp.test"], options: ["ndots:2"])

private func resolve(_ spec: ContainerCreateSpec, _ defaults: ContainerDNSDefaults = ContainerDNSDefaults(), host: String? = nil) -> ResolvedContainerDNS {
    resolveContainerDNS(spec, defaults: defaults, hostDomain: host, defaultNameservers: ["1.1.1.1"])
}

@Test("DNS resolve: with no defaults, an empty spec still gets a configuration, with nothing in it")
func resolveNoDefaults() {
    #expect(resolve(dnsSpec()) == ResolvedContainerDNS(nameservers: [], domain: nil, searchDomains: [], options: []))
}

@Test("DNS resolve: a spec that sets nothing gets every [container.dns] default")
func resolveDefaultsOnly() {
    #expect(resolve(dnsSpec(), configDefaults, host: "host.test") == ResolvedContainerDNS(
        nameservers: ["10.0.0.53"], domain: "corp.test", searchDomains: ["corp.test"], options: ["ndots:2"]))
}

@Test("DNS resolve: each field set in Orchard wins over its default, and the rest still default")
func resolveOrchardFieldWins() {
    let resolved = resolve(dnsSpec(domain: "test", nameservers: ["9.9.9.9"]), configDefaults, host: "host.test")
    #expect(resolved == ResolvedContainerDNS(
        nameservers: ["9.9.9.9"], domain: "test", searchDomains: ["corp.test"], options: ["ndots:2"]))
    #expect(resolve(dnsSpec(search: ["a.test"], options: ["rotate"]), configDefaults).searchDomains == ["a.test"])
    #expect(resolve(dnsSpec(search: ["a.test"], options: ["rotate"]), configDefaults).options == ["rotate"])
}

@Test("DNS resolve: the domain goes own, [container.dns], Orchard's fallback, then [dns].domain")
func resolveDomainOrder() {
    #expect(resolve(dnsSpec(domain: "own", fallback: "orchard"), configDefaults, host: "host").domain == "own")
    #expect(resolve(dnsSpec(fallback: "orchard"), configDefaults, host: "host").domain == "corp.test")
    #expect(resolve(dnsSpec(fallback: "orchard"), ContainerDNSDefaults(), host: "host").domain == "orchard")
    #expect(resolve(dnsSpec(), ContainerDNSDefaults(), host: "host").domain == "host")
    #expect(resolve(dnsSpec(), ContainerDNSDefaults(domain: ""), host: "").domain == nil)
}

@Test("DNS resolve: a domain set in Orchard brings the default nameservers only when nothing names any")
func resolveDefaultNameservers() {
    #expect(resolve(dnsSpec(domain: "test")).nameservers == ["1.1.1.1"])
    #expect(resolve(dnsSpec(domain: "test"), configDefaults).nameservers == ["10.0.0.53"])
    // A domain that only defaulted keeps the network's own nameserver, as before.
    #expect(resolve(dnsSpec(fallback: "orchard")).nameservers.isEmpty)
    #expect(resolve(dnsSpec(), ContainerDNSDefaults(domain: "corp.test")).nameservers.isEmpty)
}

@MainActor
@Test("DNS default: [container.dns].domain beats the Orchard preference, which beats [dns].domain")
func dnsDefaultContainerConfigFirst() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 0, stdout: #"["a.test","b.test","c.test"]"#, stderr: nil) }
    let service = makeService(runner: runner)
    service.dnsService.daemonDefaultDomain = { "a.test" }
    service.dnsService.readContainerDNSDefaults = { ContainerDNSDefaults(domain: "c.test", nameservers: ["10.0.0.53"]) }
    service.settings.setDefaultDNSDomain("b.test")

    await service.dnsService.load(showLoading: false)

    #expect(service.dnsService.containerDNSDefaults.nameservers == ["10.0.0.53"])
    #expect(service.dnsService.defaultDomain == "c.test")
    #expect(service.dnsService.unsetDomainFallback == "c.test")
    #expect(service.dnsService.dnsDomains.first(where: \.isDefault)?.domain == "c.test")
}

@MainActor
@Test("DNS default: an unreadable config.toml keeps the defaults read before")
func dnsDefaultsKeptWhenUnreadable() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 0, stdout: #"["a.test"]"#, stderr: nil) }
    let service = makeService(runner: runner)
    service.dnsService.readContainerDNSDefaults = { ContainerDNSDefaults(domain: "c.test") }
    await service.dnsService.load(showLoading: false)
    service.dnsService.readContainerDNSDefaults = { throw OrchardError.generic("unreadable") }

    await service.dnsService.load(showLoading: false)

    #expect(service.dnsService.containerDefaultDomain == "c.test")
}
