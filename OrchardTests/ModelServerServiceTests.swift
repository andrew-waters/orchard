import Testing
import Foundation
@testable import Orchard

// Managed model-server lifecycle: launch, stop, duplicate/validation guards, and the
// crash-vs-intentional-stop distinction. Uses a fake engine + process, so no real servers
// spawn and termination is driven deterministically on the main actor.

@MainActor
private func makeService(_ engine: MockModelServerEngine = MockModelServerEngine())
    -> (service: ModelServerService, engine: MockModelServerEngine, alert: AlertCenter) {
    let alert = AlertCenter()
    let service = ModelServerService(engine: engine, alertCenter: alert)
    return (service, engine, alert)
}

// MARK: - launchArguments (pure)

@Test("Engine args: model, host, and port map to mlx_lm.server flags")
func launchArguments() {
    let args = MLXServerEngine.launchArguments(model: "org/model-4bit", host: "0.0.0.0", port: 8080)
    #expect(args == ["--model", "org/model-4bit", "--host", "0.0.0.0", "--port", "8080"])
}

// MARK: - availability

@Test("Engine availability reflects whether the binary is located")
@MainActor
func engineAvailability() {
    let (present, _, _) = makeService(MockModelServerEngine(binaryPath: "/usr/bin/mlx_lm.server"))
    #expect(present.engineAvailable == true)

    let (absent, _, _) = makeService(MockModelServerEngine(binaryPath: nil))
    #expect(absent.engineAvailable == false)
}

// MARK: - start

@Test("Start: launches the engine with the given config and lists a running server")
@MainActor
func startLaunches() {
    let (service, engine, alert) = makeService()

    let ok = service.start(model: "org/m-4bit", host: "0.0.0.0", port: 8080)

    #expect(ok)
    #expect(engine.launched.count == 1)
    #expect(engine.launched.first?.host == "0.0.0.0")
    #expect(engine.launched.first?.port == 8080)
    #expect(service.servers.count == 1)
    #expect(service.servers.first?.status == .running)
    #expect(service.managedPorts.contains(8080))
    #expect(alert.current == nil)
}

@Test("Start: an empty model is rejected with an alert and no launch")
@MainActor
func startEmptyModel() {
    let (service, engine, alert) = makeService()

    let ok = service.start(model: "   ", host: "0.0.0.0", port: 8080)

    #expect(ok == false)
    #expect(engine.launched.isEmpty)
    #expect(service.servers.isEmpty)
    #expect(alert.current != nil)
}

@Test("Start: a duplicate model+port is rejected without a second launch")
@MainActor
func startDuplicate() {
    let (service, engine, _) = makeService()
    _ = service.start(model: "org/m-4bit", host: "0.0.0.0", port: 8080)

    let second = service.start(model: "org/m-4bit", host: "0.0.0.0", port: 8080)

    #expect(second == false)
    #expect(engine.launched.count == 1)
    #expect(service.servers.count == 1)
}

@Test("Start: a launch failure surfaces an alert and adds no server")
@MainActor
func startLaunchFailure() {
    let engine = MockModelServerEngine()
    engine.launchError = OrchardError.generic("boom")
    let (service, _, alert) = makeService(engine)

    let ok = service.start(model: "org/m-4bit", host: "0.0.0.0", port: 8080)

    #expect(ok == false)
    #expect(service.servers.isEmpty)
    #expect(alert.current != nil)
}

// MARK: - stop / crash

@Test("Stop: terminates the process and removes the server without alerting")
@MainActor
func stopRemoves() {
    let (service, engine, alert) = makeService()
    _ = service.start(model: "org/m-4bit", host: "0.0.0.0", port: 8080)
    let process = engine.processes.first!

    service.stop("org/m-4bit@8080")
    #expect(process.terminated)
    // The process exits in response to terminate(); simulate that.
    process.simulateExit(15)

    #expect(service.servers.isEmpty)
    #expect(alert.current == nil)
}

@Test("Crash: an unexpected exit marks the server failed and alerts")
@MainActor
func crashMarksFailed() {
    let (service, engine, alert) = makeService()
    _ = service.start(model: "org/m-4bit", host: "0.0.0.0", port: 8080)
    let process = engine.processes.first!

    // No stop() call: the process died on its own.
    process.simulateExit(1)

    #expect(service.servers.count == 1)
    #expect(service.servers.first?.status == .failed)
    #expect(alert.current != nil)
}
