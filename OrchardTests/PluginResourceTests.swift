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

@Test("Plugin marker: a combined role label reads as both roles")
func pluginCombinedRoles() throws {
    // What `container k8s create` actually stamps on a single-node cluster from 1.4.1: the one
    // node is the control plane and a worker, so the label names both.
    let node = try makeContainer(
        id: "k8s-dev", status: "running",
        labels: [
            "com.apple.container.plugin": "k8s",
            "com.apple.container.resource.role": "control-plane,worker",
        ])
    #expect(node.pluginRoles == ["control-plane", "worker"])
    #expect(node.pluginRole == "control-plane,worker")   // verbatim, for copying
    // A badge has room for one role, and the control plane is the half worth showing.
    #expect(node.pluginPrimaryRole == "control-plane")
    #expect(node.pluginBadgeText == "k8s · control-plane")
    // The detail header has room for all of them, spaced to read.
    #expect(node.pluginRoleDisplay == "control-plane, worker")
}

@Test("Plugin marker: an unrecognised role still leads with something")
func pluginUnknownRole() throws {
    let node = try makeContainer(
        id: "odd", status: "running",
        labels: [
            "com.apple.container.plugin": "k8s",
            "com.apple.container.resource.role": "etcd,gateway",
        ])
    #expect(node.pluginPrimaryRole == "etcd")          // first named, since none is known
    #expect(node.pluginBadgeText == "k8s · etcd")
    #expect(node.pluginRoleDisplay == "etcd, gateway")

    // A worker-only node leads with worker rather than reaching for a control plane.
    let worker = try makeContainer(
        id: "k8s-dev-worker-1", status: "running",
        labels: ["com.apple.container.resource.role": "worker"])
    #expect(worker.pluginPrimaryRole == "worker")
    #expect(worker.pluginRoleDisplay == "worker")
}

@Test("Plugin marker: role parsing tolerates spacing and an absent label")
func pluginRolesParsing() throws {
    let spaced = try makeContainer(
        id: "k8s-dev", status: "running",
        labels: ["com.apple.container.resource.role": " control-plane , worker "])
    #expect(spaced.pluginRoles == ["control-plane", "worker"])

    let single = try makeContainer(
        id: "k8s-worker-1", status: "running",
        labels: ["com.apple.container.resource.role": "worker"])
    #expect(single.pluginRoles == ["worker"])

    #expect(try makeContainer(id: "web", status: "running").pluginRoles.isEmpty)
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
