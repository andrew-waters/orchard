import Testing
@testable import Orchard

@Test("Plugin marker: k8s node labels resolve plugin, role, and badge text")
func pluginLabelsResolve() throws {
    let node = try makeContainer(
        id: "k8s-dev", status: "running",
        labels: [
            "com.apple.container.plugin": "k8s",
            "com.apple.container.resource.role": "control-plane",
        ])
    #expect(node.owningPlugin == "k8s")
    #expect(node.pluginRole == "control-plane")
    #expect(node.pluginBadgeText == "k8s · control-plane")
}

@Test("Plugin marker: a plugin label without a role badges as the plugin alone")
func pluginWithoutRole() throws {
    let container = try makeContainer(
        id: "helper", status: "running",
        labels: ["com.apple.container.plugin": "k8s"])
    #expect(container.pluginBadgeText == "k8s")
    #expect(container.pluginRole == nil)
}

@Test("Plugin marker: unlabeled containers get no badge")
func unlabeledContainer() throws {
    let container = try makeContainer(id: "web", status: "running")
    #expect(container.owningPlugin == nil)
    #expect(container.pluginBadgeText == nil)
}

@Test("Plugin marker: a bare role label (e.g. builder) does not badge without an owner")
func roleWithoutPlugin() throws {
    let container = try makeContainer(
        id: "buildkit", status: "running",
        labels: ["com.apple.container.resource.role": "builder"])
    #expect(container.pluginBadgeText == nil)
    #expect(container.pluginRole == "builder")
}
