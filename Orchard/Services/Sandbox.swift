import Foundation

/// How Orchard recognises a "sandbox": a workload wired to a local model. Two signals - an
/// explicit label Orchard stamps on the containers it runs against a model, and an env-var
/// heuristic that also catches sandboxes wired up elsewhere. Pure and package-free so the
/// detection logic unit-tests in isolation.
enum SandboxMarker {
    /// Label stamped on containers Orchard runs against a model.
    static let sandboxLabelKey = "com.orchard.sandbox"
    /// Label recording the model endpoint the container was wired to.
    static let endpointLabelKey = "com.orchard.model.endpoint"

    /// Env vars whose presence implies the workload targets a model endpoint.
    static let endpointEnvKeys = ["OPENAI_BASE_URL", "OLLAMA_HOST", "ANTHROPIC_BASE_URL"]

    /// Whether Orchard explicitly marked this workload a sandbox.
    static func hasSandboxLabel(_ labels: [String: String]) -> Bool {
        labels[sandboxLabelKey] == "true"
    }

    /// The model endpoint a workload targets - from its label first, else its env. nil when
    /// there is no signal at all.
    static func modelEndpoint(labels: [String: String], environment: [String]) -> String? {
        if let fromLabel = labels[endpointLabelKey], !fromLabel.isEmpty { return fromLabel }
        for entry in environment {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<eq])
            guard endpointEnvKeys.contains(key) else { continue }
            let value = String(entry[entry.index(after: eq)...])
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// The labels to stamp when Orchard runs a sandbox wired to `endpoint`.
    static func labels(endpoint: String) -> [String: String] {
        [sandboxLabelKey: "true", endpointLabelKey: endpoint]
    }
}

/// A workload recognised as a sandbox - a derived view over a container (or, later, a
/// machine), not a new backend resource.
struct Sandbox: Identifiable, Equatable {
    enum Kind: Equatable {
        case container
        case machine
    }

    /// How we know it's a sandbox: an explicit Orchard label, or only the env-var heuristic.
    enum Source: Equatable {
        case managed
        case detected
    }

    let id: String
    let name: String
    let kind: Kind
    let source: Source
    let modelEndpoint: String?
    let isRunning: Bool
    /// True when the workload is on a host-only (no-egress) network.
    let isIsolated: Bool

    /// Build a sandbox from a container if it shows any sandbox signal, else nil.
    /// `hostOnlyNetworks` is the set of network names with no internet egress.
    static func from(container: Container, hostOnlyNetworks: Set<String>) -> Sandbox? {
        let labels = container.configuration.labels
        let environment = container.configuration.initProcess.environment
        let endpoint = SandboxMarker.modelEndpoint(labels: labels, environment: environment)
        let hasLabel = SandboxMarker.hasSandboxLabel(labels)
        guard hasLabel || endpoint != nil else { return nil }

        let networkName = container.networks.first?.network ?? ""
        return Sandbox(
            id: container.configuration.id,
            name: container.configuration.id,
            kind: .container,
            source: hasLabel ? .managed : .detected,
            modelEndpoint: endpoint,
            isRunning: container.status.lowercased() == "running",
            isIsolated: hostOnlyNetworks.contains(networkName)
        )
    }
}

/// Derive the current sandboxes from the container list, enriched with network isolation.
/// Shared by the Sandboxes view and the sidebar count so they never disagree.
func detectSandboxes(containers: [Container], networks: [ContainerNetwork]) -> [Sandbox] {
    let hostOnly = Set(networks.filter { $0.isHostOnly }.map { $0.id })
    return containers.compactMap { Sandbox.from(container: $0, hostOnlyNetworks: hostOnly) }
}

extension Container {
    /// The model endpoint this container is wired to, if any (from the sandbox label or a
    /// model-endpoint env var).
    var sandboxEndpoint: String? {
        SandboxMarker.modelEndpoint(labels: configuration.labels, environment: configuration.initProcess.environment)
    }

    /// Whether this container is a sandbox - explicitly marked by Orchard or carrying a
    /// model-endpoint env var. Lets the container views flag it, since a sandbox shows in
    /// both the Containers and Sandboxes lists.
    var isSandbox: Bool {
        SandboxMarker.hasSandboxLabel(configuration.labels) || sandboxEndpoint != nil
    }
}
