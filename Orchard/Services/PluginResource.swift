import Foundation

/// System-defined label keys for resources owned by container plugins, mirroring
/// ResourceLabelKeys in apple/container. The cluster plugin, for example, stamps its node
/// containers with plugin "cluster" ("k8s" before 1.6.1) and roles "control-plane"/"worker".
enum PluginResourceMarker {
    static let pluginLabel = "com.apple.container.plugin"
    static let roleLabel = "com.apple.container.resource.role"
}

extension Container {
    /// The container plugin that owns this container (e.g. "cluster"), if any.
    var owningPlugin: String? {
        configuration.labels[PluginResourceMarker.pluginLabel]
    }

    /// A Kubernetes cluster node, under the plugin's `cluster` label or its pre-1.6.1 `k8s`.
    /// Since container 1.5.0 there is no supported way to start one again once stopped
    /// (`k8s start` is gone, and a plain start skips the node boot, readiness wait and
    /// kubeconfig write it did), so Start is replaced by Recreate.
    var isK8sNode: Bool {
        owningPlugin.map(K8sCluster.pluginNames.contains) ?? false
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

// MARK: - Cluster nodes act with their cluster

/// Stopping, killing, restarting or deleting one node of a cluster on its own breaks the
/// cluster's kubeadm state, so Orchard leaves those to the cluster. Container 1.7.1 hides nodes
/// from the CLI's `stop`, `kill`, `delete` and `prune` for the same reason
/// (apple/container#2462), but Orchard drives the runtime over XPC and skips that filter, so it
/// applies its own, on every version. Logs, exec, stats and export still work on a node.
extension Container {
    /// Why Stop, Kill and Delete are off for this container, or nil when they aren't.
    var clusterNodeActionHelp: String? {
        guard isK8sNode else { return nil }
        let cluster = K8sCluster.clusterName(for: self) ?? configuration.id
        return "Part of cluster \(cluster). Stopping or deleting one node breaks the cluster, so stop or delete \(cluster) from Clusters instead."
    }
}

extension Sequence where Element == Container {
    /// These containers less any cluster node, for bulk actions and their counts.
    var excludingClusterNodes: [Container] {
        filter { !$0.isK8sNode }
    }
}
