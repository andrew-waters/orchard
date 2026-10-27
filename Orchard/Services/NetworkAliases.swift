import Foundation

/// Whether the installed container takes DNS aliases on a network attachment. They arrived in
/// 1.6.0 (apple/container#2390).
func supportsNetworkAliases(containerVersion: String?) -> Bool {
    isContainerVersion(containerVersion, atLeast: [1, 6])
}

/// The names a container answers to on a network, worked out the way `container run` does
/// (container 1.6.0, `Utility.getAttachmentConfigurations` and `qualifyAliases`). Only the
/// shape of the names is handled here; the runtime checks every rule and its errors are shown
/// as they are.
enum NetworkAliases {
    /// The attachment hostname for a container: `<id>.<domain>.` when the id has no dot and
    /// there is a domain, `<id>.` when the id already has a dot, otherwise the bare id.
    static func hostname(id: String, domain: String) -> String {
        if id.contains(".") { return "\(id)." }
        return domain.isEmpty ? id : "\(id).\(domain)."
    }

    /// The form's rows as aliases: trimmed, with empty rows dropped.
    static func entered(_ rows: [String]) -> [String] {
        rows.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Aliases in the runtime's normalised form, with the domain added to a name that has no
    /// dot (for a subtree alias, the name after its leading dot). Lowercase, without a
    /// trailing dot. Without a domain a dotless name is left as it is, and the runtime says
    /// it needs one.
    static func qualify(_ aliases: [String], domain: String) -> [String] {
        aliases.map { alias in
            var name = alias.lowercased()
            if name.hasSuffix(".") { name.removeLast() }
            let isSubtree = name.hasPrefix(".")
            let base = isSubtree ? String(name.dropFirst()) : name
            guard !base.contains("."), !domain.isEmpty else { return name }
            return "\(isSubtree ? "." : "")\(base).\(domain.lowercased())"
        }
    }

    /// How an alias reads in the app: a subtree alias `.gateway.test` as `*.gateway.test`.
    static func display(_ alias: String) -> String {
        alias.hasPrefix(".") ? "*\(alias)" : alias
    }

    /// The names a search should find a container by: each alias, and for a subtree alias the
    /// name it sits below, so `gateway.test` finds the container that answers below it.
    static func searchTerms(_ aliases: [String]) -> [String] {
        aliases.map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
    }

    /// Whether an alias falls under a DNS domain: the domain itself or a name below it.
    static func alias(_ alias: String, isIn domain: String) -> Bool {
        let name = alias.hasPrefix(".") ? String(alias.dropFirst()) : alias
        let domain = domain.lowercased()
        return name == domain || name.hasSuffix(".\(domain)")
    }
}
