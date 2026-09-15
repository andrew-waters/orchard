import Foundation

/// System-defined label keys for resources owned by container plugins, mirroring
/// ResourceLabelKeys in apple/container. The k8s plugin, for example, stamps its node
/// containers with plugin "k8s" and roles "control-plane"/"worker".
enum PluginResourceMarker {
    static let pluginLabel = "com.apple.container.plugin"
    static let roleLabel = "com.apple.container.resource.role"
}

extension Container {
    /// The container plugin that owns this container (e.g. "k8s"), if any.
    var owningPlugin: String? {
        configuration.labels[PluginResourceMarker.pluginLabel]
    }

    /// The role label verbatim, for display. May name more than one role: see `pluginRoles`.
    var pluginRole: String? {
        configuration.labels[PluginResourceMarker.roleLabel]
    }

    /// The roles the owning plugin assigned, as a list. The label is not always a single
    /// value: container 1.4.1 stamps a single-node Kubernetes cluster `control-plane,worker`,
    /// because the one node is both. Comparing the label to "control-plane" therefore misses
    /// exactly the cluster shape `container k8s create` produces by default, so anything
    /// deciding what a node *is* asks this rather than matching the raw string.
    var pluginRoles: [String] {
        (pluginRole ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The one role to lead with where only one fits, such as a list badge. A node that is
    /// both control plane and worker is, for the purpose of recognising it in a list, the
    /// control plane. An unfamiliar combination falls back to whichever role is named first,
    /// so a role this build has never heard of still reads as something.
    var pluginPrimaryRole: String? {
        let roles = pluginRoles
        for known in ["control-plane", "worker", "builder"] where roles.contains(known) {
            return known
        }
        return roles.first
    }

    /// Every role, spaced for reading, for somewhere with room to say all of them. The label
    /// itself packs them without spaces ("control-plane,worker").
    var pluginRoleDisplay: String? {
        let roles = pluginRoles
        return roles.isEmpty ? nil : roles.joined(separator: ", ")
    }

    /// Badge text for a plugin-owned container: the plugin plus its role, so a kindest/node
    /// container reads as "k8s · control-plane" rather than a mystery row. Uses the primary
    /// role, because a badge has no room for a list and the control plane is the useful half.
    var pluginBadgeText: String? {
        guard let plugin = owningPlugin else { return nil }
        guard let role = pluginPrimaryRole else { return plugin }
        return "\(plugin) · \(role)"
    }
}
