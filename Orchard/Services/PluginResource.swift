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

    /// The dedicated role the owning plugin assigned ("control-plane", "worker",
    /// "builder"), if any.
    var pluginRole: String? {
        configuration.labels[PluginResourceMarker.roleLabel]
    }

    /// Badge text for a plugin-owned container: the plugin plus its role, so a
    /// kindest/node container reads as "k8s · control-plane" rather than a mystery row.
    var pluginBadgeText: String? {
        guard let plugin = owningPlugin else { return nil }
        guard let role = pluginRole else { return plugin }
        return "\(plugin) · \(role)"
    }
}
