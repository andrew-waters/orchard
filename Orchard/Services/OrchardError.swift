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

    /// Whether a CLI stderr indicates the resource already exists — treated as an
    /// idempotent success (e.g. the recommended kernel is already installed). Kept here
    /// beside `classifyStartError` so all runtime message-matching lives in one place.
    static func isAlreadyExistsError(_ stderr: String) -> Bool {
        stderr.contains("item with the same name already exists") || stderr.contains("File exists")
    }
}
