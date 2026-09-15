import Foundation

/// Typed errors surfaced to the user. User-facing copy lives in `errorDescription`.
enum OrchardError: Error, LocalizedError, Equatable {
    case binaryNotFound(searched: [String])
    case cliFailed(command: String, exitCode: Int32, stderr: String?)
    case decodeFailed(what: String, preview: String)
    case xpcUnavailable
    case containerNotFound(id: String)
    case containerInTransition(id: String)
    case recoveryFailed(id: String)
    case searchFailed
    case noEntrypoint
    /// The container machine API server (a separate Mach service from the main daemon) is
    /// unreachable — typically an older `container` install without machine support.
    case machineApiUnavailable
    /// The daemon refused a reclaim because the container isn't running.
    case containerNotRunning(id: String)
    /// The daemon accepted the reclaim but the guest reported the filesystem trim as
    /// unsupported. See `classifyCleanError` for why this is its own case. Carries the
    /// id because a multi-selection reclaim can fail per container.
    case trimUnsupported(id: String)
    /// `container k8s create` aborted while preparing its node. Carries its own case because
    /// the CLI's message names a step that succeeded rather than the one that failed, so the
    /// raw text is actively misleading (see `K8sKernelAdvisor`). `staleKernel` is the default
    /// kernel's name when it predates nftables and is therefore the cause.
    case k8sNodePrepFailed(cluster: String, staleKernel: String?)
    /// An error we haven't classified; carries the original message verbatim.
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let searched):
            return "The container binary could not be found. Searched: \(searched.joined(separator: ", "))."
        case .cliFailed(let command, let exitCode, let stderr):
            let detail = stderr?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let detail, !detail.isEmpty {
                return "\(command) failed: \(detail)"
            }
            return "\(command) failed (exit \(exitCode))."
        case .decodeFailed(let what, _):
            return "Could not read \(what): the container service returned an unexpected response."
        case .xpcUnavailable:
            return "The container service is unavailable. Make sure it is running."
        case .containerNotFound(let id):
            return "Container \(id) was not found."
        case .containerInTransition(let id):
            return "Container \(id) is changing state. Try again in a moment."
        case .recoveryFailed(let id):
            return "Container \(id) was automatically removed and could not be recovered. Its original configuration may be lost."
        case .searchFailed:
            return "Image search failed. Check your connection and try again."
        case .noEntrypoint:
            return "No entrypoint or command specified for the container."
        case .machineApiUnavailable:
            return "Container machines are unavailable. Update your `container` install (1.0 or later) to use machines."
        case .containerNotRunning(let id):
            return "Container \(id) is not running. Only a running container can reclaim disk space."
        case .trimUnsupported(let id):
            return "Apple container reported the filesystem trim as unsupported, so no space was reclaimed on \(id). This needs a container release that can trim a container's root filesystem; 1.4.1 cannot."
        case .k8sNodePrepFailed(let cluster, let staleKernel):
            if let staleKernel {
                return "Preparing the node for '\(cluster)' failed because the guest kernel \(staleKernel) was built without nftables, which cluster creation needs. Upgrading Apple container does not replace an existing kernel, so this install kept an older one. Install the recommended kernel and try again."
            }
            return "Preparing the node for '\(cluster)' failed. Apple container reports the output of the last step that succeeded instead of the one that failed, so its own message names a sysctl that worked. The usual cause is a guest kernel built without nftables, which installing the recommended kernel fixes."
        case .generic(let message):
            return message
        }
    }
}

extension OrchardError {
    /// Classify a raw error thrown while starting/bootstrapping a container. The runtime
    /// reports these as opaque messages, so this is where the message-string matching is
    /// pinned against the supported container version — one place, unit-tested.
    static func classifyStartError(_ error: Error, id: String) -> OrchardError {
        let message = error.localizedDescription
        if message.contains("not found") {
            return .containerNotFound(id: id)
        }
        if message.contains("shuttingDown")
            || message.contains("invalidState")
            || message.contains("expected to be in created state") {
            return .containerInTransition(id: id)
        }
        return .generic(message)
    }

    /// Classify a raw error thrown while reclaiming a container's disk space. The daemon
    /// nests the guest's failure three layers deep ("failed to clean container" wrapping
    /// "failed to clean mounts in <id>: /" wrapping "filesystemOperation trim failed"),
    /// which is unreadable in an alert.
    ///
    /// As of container 1.4.1 the trim always fails on a container's root filesystem: the
    /// guest's FITRIM ioctl returns EOPNOTSUPP even though the block device backing the
    /// rootfs advertises discard, and the daemon adds "/" to the target list for every
    /// container that isn't read-only. So `.trimUnsupported` is the expected outcome
    /// today, not an edge case, and says so rather than blaming the user's setup.
    static func classifyCleanError(_ error: Error, id: String) -> OrchardError {
        let message = error.localizedDescription
        if message.contains("trim failed") || message.contains("filesystemOperation") {
            return .trimUnsupported(id: id)
        }
        if message.contains("not running") {
            return .containerNotRunning(id: id)
        }
        return .generic(message)
    }

    /// Whether a CLI stderr indicates the resource already exists — treated as an
    /// idempotent success (e.g. the recommended kernel is already installed). Kept here
    /// beside `classifyStartError` so all runtime message-matching lives in one place.
    static func isAlreadyExistsError(_ stderr: String) -> Bool {
        stderr.contains("item with the same name already exists") || stderr.contains("File exists")
    }
}
