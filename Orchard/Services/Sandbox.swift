import Foundation

/// How Orchard recognises a "sandbox": an isolated workload, defined by what it's kept from
/// rather than by a model. Two signals - the sandbox label, which any app can stamp, and an
/// env-var heuristic that catches workloads wired to a model elsewhere. A model endpoint is
/// one thing a sandbox may have, not what makes it one. Pure and package-free so the
/// detection logic unit-tests in isolation.
///
/// The label contract, which other apps (such as Gannin) follow without depending on Orchard:
///
/// | Label | Meaning |
/// |---|---|
/// | `com.orchard.sandbox=true` | A sandbox. The label alone is enough. |
/// | `com.orchard.sandbox.owner` | The app that manages it. Absent means Orchard's own. |
/// | `com.orchard.sandbox.network` | `nat`, `host-only` or `allowlist`. |
/// | `com.orchard.model.endpoint` | The model endpoint, when it has one. |
enum SandboxMarker {
    /// Label that marks a workload as a sandbox.
    static let sandboxLabelKey = "com.orchard.sandbox"
    /// Label naming the app that made the sandbox and manages its lifecycle.
    static let ownerLabelKey = "com.orchard.sandbox.owner"
    /// Label recording how the sandbox's network is contained.
    static let networkLabelKey = "com.orchard.sandbox.network"
    /// Label recording the model endpoint the container was wired to.
    static let endpointLabelKey = "com.orchard.model.endpoint"

    /// The owner Orchard stamps on the sandboxes it makes. Sandboxes made before the owner
    /// label existed have none, which means the same thing.
    static let orchardOwner = "dev.andon.orchard"

    /// Env vars whose presence implies the workload targets a model endpoint.
    static let endpointEnvKeys = ["OPENAI_BASE_URL", "OLLAMA_HOST", "ANTHROPIC_BASE_URL"]

    /// Whether the workload is explicitly marked a sandbox.
    static func hasSandboxLabel(_ labels: [String: String]) -> Bool {
        labels[sandboxLabelKey] == "true"
    }

    /// The app that manages this sandbox when it isn't Orchard, else nil. An absent or empty
    /// owner is Orchard's, as is Orchard's own identifier.
    static func owner(labels: [String: String]) -> String? {
        guard let owner = labels[ownerLabelKey]?.trimmingCharacters(in: .whitespaces),
              !owner.isEmpty, owner != orchardOwner else { return nil }
        return owner
    }

    /// How the sandbox's network is contained. A container seen on a host-only network is
    /// host-only whatever its label says, since that's observed rather than claimed;
    /// otherwise the label's mode, and NAT when there is no label (or one this build
    /// doesn't know).
    static func networkMode(labels: [String: String], onHostOnlyNetwork: Bool) -> SandboxNetworkMode {
        if onHostOnlyNetwork { return .hostOnly }
        return labels[networkLabelKey].flatMap(SandboxNetworkMode.init(label:)) ?? .nat
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

    /// The labels to stamp when Orchard runs a sandbox wired to `endpoint` on a network
    /// contained as `networkMode`.
    static func labels(endpoint: String, networkMode: SandboxNetworkMode) -> [String: String] {
        [
            sandboxLabelKey: "true",
            ownerLabelKey: orchardOwner,
            networkLabelKey: networkMode.label,
            endpointLabelKey: endpoint,
        ]
    }

    /// The chat API style Orchard can actually drive for this workload, or nil when its
    /// endpoint speaks an API the tester doesn't (e.g. Anthropic, which is a recognised
    /// sandbox signal but not an OpenAI/Ollama chat shape). A label-stamped endpoint is
    /// always OpenAI-style, since that's the only kind Orchard stamps.
    static func chatAPIStyle(labels: [String: String], environment: [String]) -> ModelAPIStyle? {
        if labels[endpointLabelKey] != nil { return .openAI }
        for entry in environment {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            switch String(entry[..<eq]) {
            case "OPENAI_BASE_URL": return .openAI
            case "OLLAMA_HOST": return .ollama
            default: continue
            }
        }
        return nil
    }
}

/// How a sandbox's network is contained, as the `com.orchard.sandbox.network` label says it.
enum SandboxNetworkMode: Equatable {
    /// Open egress through NAT.
    case nat
    /// No egress: reachable from the host only.
    case hostOnly
    /// Egress only to an allow list.
    case allowlist

    init?(label: String) {
        switch label {
        case "nat": self = .nat
        case "host-only": self = .hostOnly
        case "allowlist": self = .allowlist
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .nat: return "nat"
        case .hostOnly: return "host-only"
        case .allowlist: return "allowlist"
        }
    }

    var displayName: String {
        switch self {
        case .nat: return "NAT"
        case .hostOnly: return "Host-only"
        case .allowlist: return "Allow list"
        }
    }

    /// Short state for a badge or a list row.
    var badgeText: String {
        switch self {
        case .nat: return "Egress open"
        case .hostOnly: return "Isolated"
        case .allowlist: return "Allow list"
        }
    }
}

/// The app that manages a sandbox Orchard didn't make.
struct SandboxOwner: Equatable, Hashable {
    /// The owner label verbatim, such as `dev.andon.gannin`.
    let id: String

    /// Owners Orchard can name: display name and what one of its sandboxes is called.
    private static let known: [String: (name: String, badge: String)] = [
        "dev.andon.gannin": ("Gannin", "Gannin session"),
    ]

    /// The app's name, or its identifier when Orchard doesn't know it.
    var name: String { Self.known[id]?.name ?? id }
    /// Badge text naming the owner, such as "Gannin session".
    var badge: String { Self.known[id]?.badge ?? id }
}

/// A mount as a sandbox shows it: what the workload can see and whether it can write there.
struct SandboxMount: Equatable {
    enum Access: Equatable {
        case readOnly
        case readWrite
        /// A tmpfs, which masks whatever lies beneath it.
        case tmpfs
    }

    let source: String
    let destination: String
    let access: Access

    init(source: String, destination: String, access: Access) {
        self.source = source
        self.destination = destination
        self.access = access
    }

    init(_ mount: Mount) {
        source = mount.source
        destination = mount.destination
        if mount.type.tmpfs != nil {
            access = .tmpfs
        } else {
            access = mount.options.contains("ro") ? .readOnly : .readWrite
        }
    }
}

/// A workload recognised as a sandbox - a derived view over a container (or, later, a
/// machine), not a new backend resource.
struct Sandbox: Identifiable, Equatable {
    enum Kind: Equatable {
        case container
        case machine
    }

    /// How we know it's a sandbox, and who manages it.
    enum Source: Equatable {
        /// Labelled, and made by Orchard.
        case orchard
        /// Labelled, and managed by another app.
        case owned(SandboxOwner)
        /// No label: only the model env-var heuristic.
        case detected
    }

    let id: String
    let name: String
    let kind: Kind
    let source: Source
    let modelEndpoint: String?
    /// The chat API the tester can drive, or nil when there's no endpoint or it isn't
    /// OpenAI/Ollama.
    let chatAPI: ModelAPIStyle?
    let isRunning: Bool
    let networkMode: SandboxNetworkMode
    /// The network the workload is on, or nil when it names none.
    let networkName: String?
    let mounts: [SandboxMount]
    let cpus: Int
    let memoryBytes: Int

    /// The app managing this sandbox when it isn't Orchard.
    var owner: SandboxOwner? {
        if case .owned(let owner) = source { return owner }
        return nil
    }

    /// True when the workload is on a host-only (no-egress) network.
    var isIsolated: Bool { networkMode == .hostOnly }

    /// Build a sandbox from a container if it shows any sandbox signal, else nil.
    /// `hostOnlyNetworks` is the set of network names with no internet egress.
    static func from(container: Container, hostOnlyNetworks: Set<String>) -> Sandbox? {
        let labels = container.configuration.labels
        let environment = container.configuration.initProcess.environment
        let endpoint = SandboxMarker.modelEndpoint(labels: labels, environment: environment)
        let hasLabel = SandboxMarker.hasSandboxLabel(labels)
        guard hasLabel || endpoint != nil else { return nil }

        let source: Source
        if !hasLabel {
            source = .detected
        } else if let owner = SandboxMarker.owner(labels: labels) {
            source = .owned(SandboxOwner(id: owner))
        } else {
            source = .orchard
        }

        let networkName = container.attachedNetworkName
        return Sandbox(
            id: container.configuration.id,
            name: container.configuration.id,
            kind: .container,
            source: source,
            modelEndpoint: endpoint,
            chatAPI: endpoint == nil ? nil : SandboxMarker.chatAPIStyle(labels: labels, environment: environment),
            isRunning: container.status.lowercased() == "running",
            networkMode: SandboxMarker.networkMode(
                labels: labels,
                onHostOnlyNetwork: networkName.map(hostOnlyNetworks.contains) ?? false
            ),
            networkName: networkName,
            mounts: container.configuration.mounts.map(SandboxMount.init),
            cpus: container.configuration.resources.cpus,
            memoryBytes: container.configuration.resources.memoryInBytes
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

    /// Whether this container is a sandbox - labelled one, or carrying a model-endpoint env
    /// var. Lets the container views flag it, since a sandbox shows in both the Containers
    /// and Sandboxes lists.
    var isSandbox: Bool {
        SandboxMarker.hasSandboxLabel(configuration.labels) || sandboxEndpoint != nil
    }

    /// The app managing this sandbox when it isn't Orchard, else nil (including when the
    /// container isn't a labelled sandbox at all).
    var sandboxOwner: SandboxOwner? {
        guard SandboxMarker.hasSandboxLabel(configuration.labels),
              let owner = SandboxMarker.owner(labels: configuration.labels) else { return nil }
        return SandboxOwner(id: owner)
    }

    /// The network the container is on: its live attachment while running, else the one it
    /// is configured to join, since `networks` is empty while it's stopped.
    var attachedNetworkName: String? {
        if let live = networks.first?.network, !live.isEmpty { return live }
        if let configured = configuration.networkName, !configured.isEmpty { return configured }
        return nil
    }
}

/// A confirmation to show before stopping or removing containers that include a sandbox
/// another app manages, so Orchard doesn't pull a container out from under a running
/// session. Pure, so the wording unit-tests; the views present it with
/// `ownedSandboxConfirmation(_:)`.
struct OwnedSandboxConfirmation: Identifiable {
    enum Action: Equatable {
        case stop
        case forceStop
        case remove

        var title: String {
            switch self {
            case .stop: return "Stop"
            case .forceStop: return "Force Stop"
            case .remove: return "Remove"
            }
        }

        fileprivate var gerund: String {
            switch self {
            case .stop: return "Stopping"
            case .forceStop: return "Force stopping"
            case .remove: return "Removing"
            }
        }
    }

    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let perform: () -> Void

    init(title: String, message: String, confirmTitle: String, perform: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.perform = perform
    }

    /// The confirmation for acting on `containers`, or nil when none of them is a sandbox
    /// another app manages, in which case the caller acts straight away.
    static func make(_ action: Action, containers: [Container], perform: @escaping () -> Void) -> OwnedSandboxConfirmation? {
        guard let warning = warning(action, containers: containers) else { return nil }
        return OwnedSandboxConfirmation(
            title: warning.title,
            message: warning.message,
            confirmTitle: action.title,
            perform: perform
        )
    }

    /// The title and message warning about the owned sandboxes among `containers`, for a
    /// view that already confirms the action and only needs to add the warning.
    static func warning(_ action: Action, containers: [Container]) -> (title: String, message: String)? {
        let owned = containers.compactMap { c in c.sandboxOwner.map { (id: c.configuration.id, owner: $0) } }
        guard !owned.isEmpty else { return nil }

        var owners: [SandboxOwner] = []
        for entry in owned where !owners.contains(entry.owner) { owners.append(entry.owner) }
        let ownerNames = owners.map(\.name).joined(separator: " and ")
        let manages = owners.count == 1 ? "manages" : "manage"
        let single = owned.count == 1

        let title = single
            ? "\(action.title) a sandbox \(ownerNames) \(manages)?"
            : "\(action.title) \(owned.count) sandboxes \(ownerNames) \(manages)?"
        let names = owned.map { "\($0.id) (\($0.owner.badge))" }.joined(separator: "\n")
        let pronoun = single ? "it" : "them"
        let message = "\(names)\n\n\(ownerNames) \(manages) \(single ? "this sandbox" : "these sandboxes"). "
            + "\(action.gerund) \(pronoun) here can interrupt work in progress, and \(ownerNames) may not expect it."
        return (title, message)
    }
}
