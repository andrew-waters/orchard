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
