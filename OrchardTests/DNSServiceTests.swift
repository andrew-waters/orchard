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
