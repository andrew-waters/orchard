import Testing
import Foundation
@testable import Orchard

// Sandbox detection: the label and env-var signals, owner and network mode, endpoint
// resolution, the labels Orchard stamps, and the confirmation before acting on a sandbox
// another app manages. Pure logic, so no fixtures beyond dictionaries, env arrays and
// decoded containers.

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

@Test("Stamped labels carry the marker, Orchard as owner, the network mode and the endpoint")
func stampedLabels() {
    let labels = SandboxMarker.labels(endpoint: "http://192.168.128.1:8080/v1", networkMode: .hostOnly)
    #expect(labels[SandboxMarker.sandboxLabelKey] == "true")
    #expect(labels[SandboxMarker.ownerLabelKey] == "dev.andon.orchard")
    #expect(labels[SandboxMarker.networkLabelKey] == "host-only")
    #expect(labels[SandboxMarker.endpointLabelKey] == "http://192.168.128.1:8080/v1")
    // Round-trips through detection.
    #expect(SandboxMarker.hasSandboxLabel(labels))
    #expect(SandboxMarker.owner(labels: labels) == nil)
    #expect(SandboxMarker.networkMode(labels: labels, onHostOnlyNetwork: false) == .hostOnly)
    #expect(SandboxMarker.modelEndpoint(labels: labels, environment: []) == "http://192.168.128.1:8080/v1")
}

@Test("Owner: another app's ID is an owner; absent, empty and Orchard's own are not")
func sandboxOwnerLabel() {
    #expect(SandboxMarker.owner(labels: [SandboxMarker.ownerLabelKey: "dev.andon.gannin"]) == "dev.andon.gannin")
    #expect(SandboxMarker.owner(labels: [:]) == nil)
    #expect(SandboxMarker.owner(labels: [SandboxMarker.ownerLabelKey: ""]) == nil)
    #expect(SandboxMarker.owner(labels: [SandboxMarker.ownerLabelKey: "dev.andon.orchard"]) == nil)
}

@Test("Owner: a known owner is named, an unknown one shows its ID")
func sandboxOwnerNames() {
    let gannin = SandboxOwner(id: "dev.andon.gannin")
    #expect(gannin.name == "Gannin")
    #expect(gannin.badge == "Gannin session")
    let other = SandboxOwner(id: "com.example.agent")
    #expect(other.name == "com.example.agent")
    #expect(other.badge == "com.example.agent")
}

@Test("Network mode: from the label, NAT without one, and a host-only network wins")
func sandboxNetworkMode() {
    let key = SandboxMarker.networkLabelKey
    #expect(SandboxMarker.networkMode(labels: [key: "nat"], onHostOnlyNetwork: false) == .nat)
    #expect(SandboxMarker.networkMode(labels: [key: "host-only"], onHostOnlyNetwork: false) == .hostOnly)
    #expect(SandboxMarker.networkMode(labels: [key: "allowlist"], onHostOnlyNetwork: false) == .allowlist)
    #expect(SandboxMarker.networkMode(labels: [:], onHostOnlyNetwork: false) == .nat)
    #expect(SandboxMarker.networkMode(labels: [key: "bridged"], onHostOnlyNetwork: false) == .nat)
    #expect(SandboxMarker.networkMode(labels: [key: "nat"], onHostOnlyNetwork: true) == .hostOnly)
}

@Test("Sandbox: the label alone makes one, with no endpoint and no tester")
func sandboxLabelOnly() throws {
    let container = try makeContainer(id: "plain", status: "running", labels: [SandboxMarker.sandboxLabelKey: "true"])
    let sandbox = try #require(Sandbox.from(container: container, hostOnlyNetworks: []))
    #expect(sandbox.source == .orchard)
    #expect(sandbox.modelEndpoint == nil)
    #expect(sandbox.chatAPI == nil)
    #expect(sandbox.networkMode == .nat)
    #expect(container.isSandbox)
}

@Test("Sandbox: the label with an endpoint offers the tester")
func sandboxLabelWithEndpoint() throws {
    let container = try makeContainer(
        id: "wired", status: "running",
        labels: SandboxMarker.labels(endpoint: "http://192.168.64.1:8080/v1", networkMode: .nat)
    )
    let sandbox = try #require(Sandbox.from(container: container, hostOnlyNetworks: []))
    #expect(sandbox.source == .orchard)
    #expect(sandbox.modelEndpoint == "http://192.168.64.1:8080/v1")
    #expect(sandbox.chatAPI == .openAI)
}

@Test("Sandbox: a model env var alone is detected; nothing at all is not a sandbox")
func sandboxEnvironmentOnly() throws {
    let detected = try makeContainer(id: "agent", status: "running", environment: ["OLLAMA_HOST=http://g:11434"])
    let sandbox = try #require(Sandbox.from(container: detected, hostOnlyNetworks: []))
    #expect(sandbox.source == .detected)
    #expect(sandbox.chatAPI == .ollama)
    #expect(detected.sandboxOwner == nil)

    let plain = try makeContainer(id: "web", status: "running")
    #expect(Sandbox.from(container: plain, hostOnlyNetworks: []) == nil)
}

@Test("Sandbox: another app's owner makes it owned, and only with the sandbox label")
func sandboxOwned() throws {
    let owned = try makeContainer(id: "session", status: "running", labels: [
        SandboxMarker.sandboxLabelKey: "true",
        SandboxMarker.ownerLabelKey: "dev.andon.gannin",
        SandboxMarker.networkLabelKey: "nat",
    ])
    let sandbox = try #require(Sandbox.from(container: owned, hostOnlyNetworks: []))
    #expect(sandbox.source == .owned(SandboxOwner(id: "dev.andon.gannin")))
    #expect(sandbox.owner?.name == "Gannin")
    #expect(owned.sandboxOwner == SandboxOwner(id: "dev.andon.gannin"))

    let unlabelled = try makeContainer(id: "other", status: "running", labels: [SandboxMarker.ownerLabelKey: "dev.andon.gannin"])
    #expect(unlabelled.sandboxOwner == nil)
}

@Test("Sandbox: mounts, CPU, memory and a stopped container's network carry over")
func sandboxContainment() throws {
    let mounts = """
    [
      { "type": { "virtiofs": {} }, "source": "/Users/me/harness", "options": ["ro"], "destination": "/harness" },
      { "type": { "virtiofs": {} }, "source": "/Users/me/work", "options": [], "destination": "/work" },
      { "type": { "tmpfs": {} }, "source": "", "options": [], "destination": "/harness/sessions" }
    ]
    """
    let container = try makeContainer(
        id: "session", status: "stopped",
        labels: [SandboxMarker.sandboxLabelKey: "true"],
        cpus: 4, memoryInBytes: 8 * 1024 * 1024 * 1024,
        mountsJSON: mounts, networkName: "isolated"
    )
    let sandbox = try #require(Sandbox.from(container: container, hostOnlyNetworks: ["isolated"]))
    #expect(sandbox.mounts == [
        SandboxMount(source: "/Users/me/harness", destination: "/harness", access: .readOnly),
        SandboxMount(source: "/Users/me/work", destination: "/work", access: .readWrite),
        SandboxMount(source: "", destination: "/harness/sessions", access: .tmpfs),
    ])
    #expect(sandbox.cpus == 4)
    #expect(sandbox.memoryBytes == 8 * 1024 * 1024 * 1024)
    // Stopped, so no live attachment: the configured network still says it's host-only.
    #expect(sandbox.networkName == "isolated")
    #expect(sandbox.networkMode == .hostOnly)
}

@Test("Owned confirmation: none for ordinary containers or Orchard's sandboxes")
func ownedConfirmationNone() throws {
    let plain = try makeContainer(id: "web", status: "running")
    let ours = try makeContainer(id: "ours", status: "running", labels: [
        SandboxMarker.sandboxLabelKey: "true", SandboxMarker.ownerLabelKey: "dev.andon.orchard",
    ])
    #expect(OwnedSandboxConfirmation.make(.stop, containers: [plain, ours], perform: {}) == nil)
}

@Test("Owned confirmation: one owned sandbox is named with its owner")
func ownedConfirmationSingle() throws {
    let session = try makeContainer(id: "gannin-122", status: "running", labels: [
        SandboxMarker.sandboxLabelKey: "true", SandboxMarker.ownerLabelKey: "dev.andon.gannin",
    ])
    let confirmation = try #require(OwnedSandboxConfirmation.make(.stop, containers: [session], perform: {}))
    #expect(confirmation.title == "Stop a sandbox Gannin manages?")
    #expect(confirmation.confirmTitle == "Stop")
    #expect(confirmation.message.contains("gannin-122 (Gannin session)"))
    #expect(confirmation.message.contains("Stopping it here"))
}

@Test("Owned confirmation: a mixed bulk set counts only the owned sandboxes, across owners")
func ownedConfirmationBulk() throws {
    let plain = try makeContainer(id: "web", status: "stopped")
    let first = try makeContainer(id: "gannin-1", status: "stopped", labels: [
        SandboxMarker.sandboxLabelKey: "true", SandboxMarker.ownerLabelKey: "dev.andon.gannin",
    ])
    let second = try makeContainer(id: "gannin-2", status: "stopped", labels: [
        SandboxMarker.sandboxLabelKey: "true", SandboxMarker.ownerLabelKey: "dev.andon.gannin",
    ])
    let sameOwner = try #require(OwnedSandboxConfirmation.make(.remove, containers: [plain, first, second], perform: {}))
    #expect(sameOwner.title == "Remove 2 sandboxes Gannin manages?")
    #expect(!sameOwner.message.contains("web"))

    let other = try makeContainer(id: "agent", status: "stopped", labels: [
        SandboxMarker.sandboxLabelKey: "true", SandboxMarker.ownerLabelKey: "com.example.agent",
    ])
    let twoOwners = try #require(OwnedSandboxConfirmation.make(.forceStop, containers: [first, other], perform: {}))
    #expect(twoOwners.title == "Force Stop 2 sandboxes Gannin and com.example.agent manage?")
}
