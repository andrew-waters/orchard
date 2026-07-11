import Testing
import Foundation
@testable import Orchard

// Sandbox detection: the label and env-var signals, endpoint resolution, and the label
// Orchard stamps. Pure logic, so no fixtures beyond dictionaries and env arrays.

@Test("Sandbox label: only the exact marker counts")
func sandboxLabel() {
    #expect(SandboxMarker.hasSandboxLabel([SandboxMarker.sandboxLabelKey: "true"]))
    #expect(!SandboxMarker.hasSandboxLabel([SandboxMarker.sandboxLabelKey: "false"]))
    #expect(!SandboxMarker.hasSandboxLabel([:]))
}

@Test("Endpoint: label takes precedence over env")
func endpointFromLabel() {
    let labels = [SandboxMarker.endpointLabelKey: "http://192.168.66.1:8080/v1"]
    let env = ["OPENAI_BASE_URL=http://other:1234/v1"]
    #expect(SandboxMarker.modelEndpoint(labels: labels, environment: env) == "http://192.168.66.1:8080/v1")
}

@Test("Endpoint: falls back to a recognised env var")
func endpointFromEnv() {
    #expect(SandboxMarker.modelEndpoint(labels: [:], environment: ["PATH=/usr/bin", "OPENAI_BASE_URL=http://g:8080/v1"])
            == "http://g:8080/v1")
    #expect(SandboxMarker.modelEndpoint(labels: [:], environment: ["OLLAMA_HOST=http://g:11434"])
            == "http://g:11434")
}

@Test("Endpoint: no signal yields nil")
func endpointNone() {
    #expect(SandboxMarker.modelEndpoint(labels: [:], environment: ["PATH=/usr/bin", "HOME=/root"]) == nil)
    // An empty value is not a signal.
    #expect(SandboxMarker.modelEndpoint(labels: [:], environment: ["OPENAI_BASE_URL="]) == nil)
}

@Test("Stamped labels carry the marker and the endpoint")
func stampedLabels() {
    let labels = SandboxMarker.labels(endpoint: "http://192.168.128.1:8080/v1")
    #expect(labels[SandboxMarker.sandboxLabelKey] == "true")
    #expect(labels[SandboxMarker.endpointLabelKey] == "http://192.168.128.1:8080/v1")
    // Round-trips through detection.
    #expect(SandboxMarker.hasSandboxLabel(labels))
    #expect(SandboxMarker.modelEndpoint(labels: labels, environment: []) == "http://192.168.128.1:8080/v1")
}
