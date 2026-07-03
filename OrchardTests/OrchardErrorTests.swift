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
