import Foundation
import Testing
import ContainerResource
@testable import Orchard

// DNS aliases on a network attachment (#134): the version gate, the names worked out the way
// `container run` does, and the path from the form to the create spec and back. The runtime's
// own checks are exercised by hand against 1.6.x.

@Test("Aliases are offered from container 1.6.0")
func networkAliasesVersionGate() {
    #expect(supportsNetworkAliases(containerVersion: "1.6.0"))
    #expect(supportsNetworkAliases(containerVersion: "1.6.1"))
    #expect(!supportsNetworkAliases(containerVersion: "1.5.0"))
    #expect(!supportsNetworkAliases(containerVersion: nil))
}

@Test("The hostname gets the domain as `container run` gives it")
func attachmentHostname() {
    #expect(NetworkAliases.hostname(id: "gateway", domain: "test") == "gateway.test.")
    #expect(NetworkAliases.hostname(id: "gateway", domain: "") == "gateway")
    #expect(NetworkAliases.hostname(id: "gateway.example.com", domain: "test") == "gateway.example.com.")
}

@Test("A name without a dot gets the domain; a subtree alias gets it after its leading dot")
func aliasQualification() {
    #expect(NetworkAliases.qualify(["api", ".gateway"], domain: "test") == ["api.test", ".gateway.test"])
    #expect(NetworkAliases.qualify(["api.example.com", ".example.com"], domain: "test") == ["api.example.com", ".example.com"])
    #expect(NetworkAliases.qualify(["API.Example.Com."], domain: "test") == ["api.example.com"])
    // Already qualified names are left alone, so a recreate qualifying stored aliases changes nothing.
    #expect(NetworkAliases.qualify(["api.test", ".gateway.test"], domain: "test") == ["api.test", ".gateway.test"])
    // With no domain a bare name goes as it is, for the runtime to explain.
    #expect(NetworkAliases.qualify(["api"], domain: "") == ["api"])
}

@Test("Empty and whitespace-only rows are dropped and the rest trimmed")
func aliasRows() {
    var config = ContainerRunConfig(name: "gateway", image: "nginx")
    config.networkAliases = [.init(name: " api "), .init(name: "   "), .init(name: ""), .init(name: ".gateway")]
    #expect(config.effectiveNetworkAliases == ["api", ".gateway"])
}

@Test("A subtree alias reads with a star, and searches by the name it sits below")
func aliasDisplayAndSearch() {
    #expect(NetworkAliases.display(".gateway.test") == "*.gateway.test")
    #expect(NetworkAliases.display("api.test") == "api.test")
    #expect(NetworkAliases.searchTerms(["api.test", ".gateway.test"]) == ["api.test", "gateway.test"])
}

@Test("An alias is in a domain when it is the domain or below it, by label")
func aliasInDomain() {
    #expect(NetworkAliases.alias("api.test", isIn: "test"))
    #expect(NetworkAliases.alias(".gateway.test", isIn: "test"))
    #expect(NetworkAliases.alias(".gateway.test", isIn: "gateway.test"))
    #expect(!NetworkAliases.alias("api.mytest", isIn: "test"))
}

@MainActor
@Test("Spec: the form's aliases reach the create spec as entered")
func specCarriesNetworkAliases() async {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)
    var config = ContainerRunConfig(name: "gateway", image: "nginx")
    config.dnsDomain = "test"
    config.networkAliases = [.init(name: "api"), .init(name: " "), .init(name: ".gateway")]
    await service.containerListService.runContainer(config: config)

    let spec = backend.createdSpecs.first
    #expect(spec?.networkAliases == ["api", ".gateway"])
    #expect(spec?.dnsDomain == "test")
}

@Test("Mapping: each attachment's aliases by network, leaving out those without")
func networkAliasesMapping() {
    let attachments = [
        AttachmentConfiguration(network: "default", options: AttachmentOptions(hostname: "gateway.test.", aliases: ["api.test", ".gateway.test"])),
        AttachmentConfiguration(network: "backend", options: AttachmentOptions(hostname: "gateway")),
    ]
    #expect(mapNetworkAliases(attachments) == ["default": ["api.test", ".gateway.test"]])
    #expect(mapNetworkAliases([attachments[1]]) == nil)
}

@Test("A stored container's aliases come back as rows for the network it is on")
func primaryNetworkAliasRows() throws {
    let container = try makeContainer(
        id: "gateway", status: "stopped", networkName: "default",
        networkAliases: ["default": ["api.test", ".gateway.test"], "backend": ["db.test"]]
    )
    #expect(container.configuration.primaryNetworkAliasRows.map(\.name) == ["api.test", ".gateway.test"])
    #expect(container.configuration.allNetworkAliases == ["db.test", "api.test", ".gateway.test"])

    let plain = try makeContainer(id: "web", status: "stopped", networkName: "default")
    #expect(plain.configuration.networkAliases == nil)
    #expect(plain.configuration.primaryNetworkAliasRows.isEmpty)
}

@MainActor
@Test("Edit keeps the network, DNS domain and aliases for the recreate")
func editPrefillsNetworkAndAliases() throws {
    let container = try makeContainer(
        id: "gateway", status: "stopped", networkName: "backend",
        networkAliases: ["backend": ["api.test"]]
    )
    let config = EditContainerView.initialConfig(for: container)
    #expect(config.network == "backend")
    #expect(config.effectiveNetworkAliases == ["api.test"])
}
