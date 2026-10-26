import ContainerizationOCI
import Foundation

// MARK: - Choosing the platform a container runs as (#147)

/// The platform this Mac runs containers as without translation: `linux/arm64` on Apple
/// silicon. Written the way `ContainerizationOCI.Platform.description` writes one, which is
/// the form every platform string in Orchard takes.
let hostContainerPlatform = "linux/\(hostContainerArchitecture)"

extension Orchard.Platform {
    /// `os/arch`, or `os/arch/variant`, in the form `ContainerizationOCI.Platform.description`
    /// uses: arm64's `v8` is its only variant and is left out, so a container's platform
    /// compares equal to the one an image lists.
    var description: String {
        if let variant, !variant.isEmpty, !(architecture == "arm64" && variant == "v8") {
            return "\(os)/\(architecture)/\(variant)"
        }
        return "\(os)/\(architecture)"
    }
}

enum ContainerPlatform {
    /// What went wrong choosing a platform, written for a person.
    struct ResolutionError: LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
    }

    /// The architecture part of `os/arch[/variant]`, or nil when there is none.
    /// `platform` written the way the runtime writes one, which is how image platforms come
    /// back: `linux/arm64/v8` is `linux/arm64`, `linux/x86_64` is `linux/amd64`. Nil when it is
    /// not a platform at all.
    static func normalized(_ platform: String) -> String? {
        (try? ContainerizationOCI.Platform(from: platform))?.description
    }

    static func architecture(of platform: String) -> String? {
        let parts = platform.split(separator: "/")
        return parts.count >= 2 ? String(parts[1]) : nil
    }

    /// Whether a container of this platform runs under Rosetta. The rule is the CLI's: an
    /// amd64 container on an arm64 host. Anything else either runs natively or not at all.
    static func needsRosetta(_ platform: String, hostArchitecture: String = hostContainerArchitecture) -> Bool {
        hostArchitecture == "arm64" && architecture(of: platform) == "amd64"
    }

    /// The platform to create a container as, chosen the way `container run` chooses one from
    /// 1.6.1 (`PlatformResolver`).
    ///
    /// - A requested platform is used, and has to be one the image offers.
    /// - Otherwise an image with one platform runs as that one, and an image with several runs
    ///   as the host's.
    /// - An empty `candidates` means the image's platforms could not be read (an older runtime
    ///   and an image that is not here yet). The request, or the host's platform, is used and
    ///   the fetch says whether the image has it, which is how Orchard behaved before.
    static func resolve(
        requested: String?,
        candidates: [String],
        host: String = hostContainerPlatform
    ) throws -> String {
        // Compared as parsed platforms, as upstream does, so an alias or arm64's redundant v8
        // in a compose file matches what the image lists, and Rosetta is decided on the
        // normalised architecture.
        var requested = requested.flatMap { $0.isEmpty ? nil : $0 }
        if let raw = requested {
            guard let normalized = normalized(raw) else {
                throw ResolutionError(message: "\(raw) is not a platform. Write it as os/arch, such as linux/amd64.")
            }
            requested = normalized
        }
        guard !candidates.isEmpty else { return requested ?? host }

        if let requested {
            guard candidates.contains(requested) else {
                throw ResolutionError(
                    message: "The image has no \(requested) variant. It offers \(candidates.joined(separator: ", "))."
                )
            }
            return requested
        }
        if candidates.count == 1 { return candidates[0] }
        guard candidates.contains(host) else {
            throw ResolutionError(
                message: "The image offers \(candidates.joined(separator: ", ")) but not \(host), so one has to be chosen."
            )
        }
        return host
    }
}
