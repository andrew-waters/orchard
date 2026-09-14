import Testing
import Foundation
@testable import Orchard

private func error(_ message: String) -> NSError {
    NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

@Test("Start error: 'not found' classifies as containerNotFound")
func startErrorNotFound() {
    #expect(OrchardError.classifyStartError(error("container xyz not found"), id: "xyz") == .containerNotFound(id: "xyz"))
}

@Test("Start error: transition messages classify as containerInTransition")
func startErrorTransition() {
    for message in ["state is shuttingDown", "invalidState", "expected to be in created state"] {
        #expect(OrchardError.classifyStartError(error(message), id: "abc") == .containerInTransition(id: "abc"))
    }
}

@Test("Start error: anything else is generic and preserves the message")
func startErrorGeneric() {
    #expect(OrchardError.classifyStartError(error("disk full"), id: "abc") == .generic("disk full"))
}

@Test("Clean error: the nested trim failure classifies as trimUnsupported")
func cleanErrorTrimUnsupported() {
    // The exact chain container 1.4.1 returns for a running container, daemon wrapping
    // included.
    let nested = "failed to clean container (cause: \"failed to clean container db "
        + "(cause: \"failed to clean mounts in db: / (internalError: "
        + "\"filesystemOperation trim failed\")\")\")"
    #expect(OrchardError.classifyCleanError(error(nested), id: "db") == .trimUnsupported(id: "db"))
    #expect(OrchardError.classifyCleanError(error("filesystemOperation"), id: "db") == .trimUnsupported(id: "db"))
    // A multi-selection reclaim alerts per container, so the copy has to name which one.
    #expect(OrchardError.trimUnsupported(id: "db").errorDescription?.contains("db") == true)
}

@Test("Clean error: a stopped container classifies as containerNotRunning")
func cleanErrorNotRunning() {
    #expect(OrchardError.classifyCleanError(error("container is not running"), id: "db")
        == .containerNotRunning(id: "db"))
}

@Test("Clean error: anything else is generic and preserves the message")
func cleanErrorGeneric() {
    #expect(OrchardError.classifyCleanError(error("disk full"), id: "db") == .generic("disk full"))
}

@Test("isAlreadyExistsError: recognizes the idempotent-install messages")
func alreadyExistsClassifier() {
    #expect(OrchardError.isAlreadyExistsError("item with the same name already exists") == true)
    #expect(OrchardError.isAlreadyExistsError("mkdir: File exists") == true)
    #expect(OrchardError.isAlreadyExistsError("permission denied") == false)
}

@Test("Error copy: cases produce user-facing descriptions")
func errorCopy() {
    #expect(OrchardError.xpcUnavailable.errorDescription?.isEmpty == false)
    #expect(OrchardError.noEntrypoint.errorDescription == "No entrypoint or command specified for the container.")
    #expect(OrchardError.containerNotFound(id: "web").errorDescription?.contains("web") == true)
}

@Test("cliFailed: uses stderr when present, else the exit code")
func cliFailedCopy() {
    let withStderr = OrchardError.cliFailed(command: "builder start", exitCode: 1, stderr: "daemon down")
    #expect(withStderr.errorDescription == "builder start failed: daemon down")

    let noStderr = OrchardError.cliFailed(command: "builder start", exitCode: 2, stderr: nil)
    #expect(noStderr.errorDescription == "builder start failed (exit 2).")
}

@Test("isContainerServiceUnavailable: matches common XPC outage messages")
func containerServiceUnavailableClassifier() {
    for message in [
        "The connection was invalidated.",
        "Connection invalid",
        "XPC connection interrupted",
        "Couldn’t communicate with a helper application.",
        "Couldn't communicate with a helper application.",
        "Could not communicate with the helper",
        "The service could not be opened",
        "No such XPC service",
    ] {
        #expect(isContainerServiceUnavailable(error(message)) == true, "expected match for: \(message)")
    }
    #expect(isContainerServiceUnavailable(error("disk full")) == false)
}

@Test("mapContainerError: rewrites XPC outages to xpcUnavailable, passes others through")
func mapContainerErrorRewritesXPC() {
    let mapped = mapContainerError(error("The connection was invalidated."))
    #expect((mapped as? OrchardError) == .xpcUnavailable)

    let other = mapContainerError(error("disk full"))
    #expect(other.localizedDescription == "disk full")
}

@Test("isContainerVersionMismatch: matches undecodable health-check replies, not outages")
func containerVersionMismatchClassifier() {
    for message in [
        "internalError: \"failed to decode apiServerBuild in health check\"",
        "failed to decode apiServerAppName in health check",
        "Failed to decode appRoot in health check",
    ] {
        #expect(isContainerVersionMismatch(error(message)) == true, "expected match for: \(message)")
    }
    #expect(isContainerVersionMismatch(error("The connection was invalidated.")) == false)
    #expect(isContainerVersionMismatch(error("failed to decode container list")) == false)
    #expect(isContainerVersionMismatch(error("disk full")) == false)
}
