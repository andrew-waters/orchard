import Testing
import Foundation
@testable import Orchard

// Tests for the pure CLI/HTTP parsers in CLIParsers.swift. The `Builder` success path
// requires a large nested JSON fixture and is exercised separately; here we cover the
// branches that don't need it.

// MARK: - parseBuilderStatus

@Test("Builder status: non-JSON and empty output means no builder")
func builderStatusNotRunning() {
    for stdout in ["builder is not running", "No builder found", "", "null", "[]", "  \n "] {
        guard case .notRunning = parseBuilderStatus(stdout: stdout) else {
            Issue.record("expected .notRunning for \(stdout.debugDescription)")
            continue
        }
    }
}

@Test("Builder status: undecodable JSON reports a decode failure with a preview")
func builderStatusDecodeFailure() {
    guard case .decodeFailure(let preview) = parseBuilderStatus(stdout: "{ this is not valid builder json") else {
        Issue.record("expected .decodeFailure")
        return
    }
    #expect(!preview.isEmpty)
}

@Test("Builder status: a valid single-builder JSON object decodes")
func builderStatusSingleObject() {
    guard case .builders(let builders) = parseBuilderStatus(stdout: makeBuilderStatusJSON(status: "running")) else {
        Issue.record("expected .builders")
        return
    }
    #expect(builders.count == 1)
    #expect(builders.first?.status == "running")
    #expect(builders.first?.configuration.id == "buildkit")
}

@Test("Builder status: a JSON array of builders decodes")
func builderStatusArray() {
    let arrayJSON = "[\(makeBuilderStatusJSON(status: "running"))]"
    guard case .builders(let builders) = parseBuilderStatus(stdout: arrayJSON) else {
        Issue.record("expected .builders")
        return
    }
    #expect(builders.count == 1)
}

// MARK: - parseDNSDomains

@Test("DNS domains: parses the array and marks the default")
func dnsDomainsParsed() {
    let domains = parseDNSDomains(json: #"["alpha.test","beta.test"]"#, defaultDomain: "beta.test")
    #expect(domains == [
        DNSDomain(domain: "alpha.test", isDefault: false),
        DNSDomain(domain: "beta.test", isDefault: true),
    ])
}

@Test("DNS domains: malformed JSON yields an empty list, not a crash")
func dnsDomainsMalformed() {
    #expect(parseDNSDomains(json: "not json", defaultDomain: nil).isEmpty)
}

// MARK: - parseSystemProperties

@Test("System properties: decodes the array format, typing bool/string and null")
func systemPropertiesParsed() {
    // Shape matches `container system property list --format=json`: an array of
    // {id, type, value, description}, with value as a JSON bool, string, or null.
    let json = """
    [
      { "id": "build.rosetta", "type": "Bool", "value": true, "description": "Use Rosetta." },
      { "id": "dns.domain", "type": "String", "value": "test", "description": "Local DNS domain." },
      { "id": "build.cpus", "type": "String", "value": null, "description": "Builder CPUs." },
      { "id": "image.builder", "type": "String", "value": "ghcr.io/example/builder:latest", "description": "" }
    ]
    """
    let props = parseSystemProperties(json: json)
    func prop(_ id: String) -> SystemProperty? { props.first { $0.id == id } }

    // A JSON bool typed as .bool
    #expect(prop("build.rosetta")?.type == .bool)
    #expect(prop("build.rosetta")?.value == "true")
    // A plain string value
    #expect(prop("dns.domain")?.value == "test")
    // null becomes the *undefined* sentinel
    #expect(prop("build.cpus")?.value == "*undefined*")
    #expect(prop("build.cpus")?.isUndefined == true)
    // description carries through
    #expect(prop("dns.domain")?.description == "Local DNS domain.")
    #expect(prop("image.builder")?.value == "ghcr.io/example/builder:latest")
}

@Test("System properties: decodes the container 1.0+ nested-object format")
func systemPropertiesNestedObject() {
    // Shape matches `container system property list --format=json` on container 1.0+:
    // a nested object keyed by category, with no per-property type/description.
    let json = """
    {
      "build": { "cpus": 2, "image": "ghcr.io/example/builder:0.12.0", "rosetta": true },
      "dns": {},
      "kernel": { "binaryPath": "opt/kata/vmlinux", "url": "https://example.com/kernel.tar" },
      "registry": { "domain": "docker.io" },
      "vminit": { "image": "ghcr.io/example/vminit:0.35.0" }
    }
    """
    let props = parseSystemProperties(json: json)
    func prop(_ id: String) -> SystemProperty? { props.first { $0.id == id } }

    // JSON booleans are typed .bool (and not confused with numbers).
    #expect(prop("build.rosetta")?.type == .bool)
    #expect(prop("build.rosetta")?.value == "true")
    // Numbers render as strings, typed .string.
    #expect(prop("build.cpus")?.type == .string)
    #expect(prop("build.cpus")?.value == "2")
    // Category keys flatten to dotted ids the panes look up.
    #expect(prop("kernel.binaryPath")?.value == "opt/kata/vmlinux")
    #expect(prop("registry.domain")?.value == "docker.io")
    // Legacy category keys remap to the ids the app expects.
    #expect(prop("image.builder")?.value == "ghcr.io/example/builder:0.12.0")
    #expect(prop("image.init")?.value == "ghcr.io/example/vminit:0.35.0")
    #expect(prop("build.image") == nil)
    // An empty category contributes nothing.
    #expect(prop("dns.domain") == nil)
}

@Test("System properties: malformed / empty JSON yields an empty list, not a crash")
func systemPropertiesMalformed() {
    #expect(parseSystemProperties(json: "not json").isEmpty)
    #expect(parseSystemProperties(json: "{}").isEmpty)
    #expect(parseSystemProperties(json: "[]").isEmpty)
}

@Test("System properties: skips entries without an id and remaps legacy aliases")
func systemPropertiesMalformedEntriesAndAliases() {
    let json = """
    [
      { "type": "String", "value": "orphan", "description": "no id, must be skipped" },
      { "id": "build.image", "type": "String", "value": "ghcr.io/example/builder:1", "description": "" },
      { "id": "vminit.image", "type": "String", "value": "ghcr.io/example/vminit:1", "description": "" }
    ]
    """
    let props = parseSystemProperties(json: json)
    func prop(_ id: String) -> SystemProperty? { props.first { $0.id == id } }

    // The entry missing `id` is dropped by compactMap, leaving only the two aliased ones.
    #expect(props.count == 2)
    // Legacy ids remap to their current names.
    #expect(prop("image.builder")?.value == "ghcr.io/example/builder:1")
    #expect(prop("image.init")?.value == "ghcr.io/example/vminit:1")
    #expect(prop("build.image") == nil)
    #expect(prop("vminit.image") == nil)
}

// MARK: - parseDockerHubSearch

@Test("Docker Hub search: official vs namespaced names get the right registry prefix")
func dockerHubSearchParsed() {
    let json = """
    { "results": [
        { "repo_name": "nginx", "is_official": true, "star_count": 100, "short_description": "web server" },
        { "repo_name": "bitnami/redis", "is_official": false, "star_count": 50 }
    ] }
    """
    let results = parseDockerHubSearch(data: Data(json.utf8))
    #expect(results.count == 2)

    let official = results[0]
    #expect(official.name == "docker.io/library/nginx")
    #expect(official.isOfficial == true)
    #expect(official.starCount == 100)
    #expect(official.description == "web server")

    let namespaced = results[1]
    #expect(namespaced.name == "docker.io/bitnami/redis")
    #expect(namespaced.isOfficial == false)
    #expect(namespaced.description == nil)
}

// MARK: - resolveProcessArguments

@Test("Process args: entrypoint alone is used when there is no cmd or override")
func processArgsEntrypointOnly() {
    #expect(resolveProcessArguments(imageEntrypoint: ["/bin/app"], imageCmd: nil, override: []) == ["/bin/app"])
}

@Test("Process args: cmd is appended to entrypoint when there is no override")
func processArgsEntrypointPlusCmd() {
    #expect(resolveProcessArguments(imageEntrypoint: ["/bin/app"], imageCmd: ["--serve"], override: []) == ["/bin/app", "--serve"])
}

@Test("Process args: cmd alone is used when there is no entrypoint or override")
func processArgsCmdOnly() {
    #expect(resolveProcessArguments(imageEntrypoint: nil, imageCmd: ["sh"], override: []) == ["sh"])
}

@Test("Process args: override replaces cmd but keeps the entrypoint prefix")
func processArgsOverrideWithEntrypoint() {
    #expect(resolveProcessArguments(imageEntrypoint: ["/bin/app"], imageCmd: ["--serve"], override: ["--debug"]) == ["/bin/app", "--debug"])
}

@Test("Process args: override alone is used when there is no entrypoint")
func processArgsOverrideOnly() {
    #expect(resolveProcessArguments(imageEntrypoint: nil, imageCmd: ["sh"], override: ["bash"]) == ["bash"])
}

@Test("Process args: empty everything yields no arguments")
func processArgsEmpty() {
    #expect(resolveProcessArguments(imageEntrypoint: nil, imageCmd: nil, override: []).isEmpty)
}

// MARK: - MachineBackingContainer.isMachine

@Test("Machine filter: the plugin=machine label marks a machine backing container")
func machineFilterMatchesRealLabel() {
    // Captured verbatim in the M0 spike from `container inspect` of a machine's backing container.
    #expect(MachineBackingContainer.isMachine(labels: ["com.apple.container.plugin": "machine"]))
}

@Test("Machine filter: a container with no labels is not a machine")
func machineFilterEmptyLabels() {
    #expect(!MachineBackingContainer.isMachine(labels: [:]))
}

@Test("Machine filter: the plugin key with a non-machine value is not a machine")
func machineFilterOtherPluginValue() {
    #expect(!MachineBackingContainer.isMachine(labels: ["com.apple.container.plugin": "builder"]))
}

@Test("Machine filter: unrelated labels are not a machine")
func machineFilterUnrelatedLabels() {
    #expect(!MachineBackingContainer.isMachine(labels: ["com.example.team": "platform"]))
}

// MARK: - MachineImageAdvisor.likelyLacksInit

@Test("Init advisor: common base/app images are flagged as init-less (with registry/org/tag)")
func initAdvisorFlagsInitlessImages() {
    #expect(MachineImageAdvisor.likelyLacksInit("ubuntu"))
    #expect(MachineImageAdvisor.likelyLacksInit("ubuntu:24.04"))
    #expect(MachineImageAdvisor.likelyLacksInit("docker.io/library/ubuntu:24.04"))
    #expect(MachineImageAdvisor.likelyLacksInit("alpine:3.22"))
    #expect(MachineImageAdvisor.likelyLacksInit("nginx@sha256:abc"))
}

@Test("Init advisor: images mentioning init/systemd are not flagged")
func initAdvisorAllowsInitImages() {
    #expect(!MachineImageAdvisor.likelyLacksInit("geerlingguy/docker-ubuntu2204-ansible"))
    #expect(!MachineImageAdvisor.likelyLacksInit("redhat/ubi9-init"))
    #expect(!MachineImageAdvisor.likelyLacksInit("jrei/systemd-ubuntu"))
}

@Test("Init advisor: an empty or unknown image is not flagged (no false alarm)")
func initAdvisorEmptyAndUnknown() {
    #expect(!MachineImageAdvisor.likelyLacksInit(""))
    #expect(!MachineImageAdvisor.likelyLacksInit("mycorp/custom-appliance:1.0"))
}

// MARK: - MachineImageAdvisor.logsIndicateMissingInit

@Test("Stop diagnosis: the /sbin/init not-found line is recognized (captured from a real machine)")
func stopDiagnosisInitNotFound() {
    let lines = [
        "[  OK  ] Reached target Basic System.",
        "/sbin.machine/init: 74: exec: /sbin/init: not found",
    ]
    #expect(MachineImageAdvisor.logsIndicateMissingInit(lines))
}

@Test("Stop diagnosis: the openrc-missing line is recognized (alpine case)")
func stopDiagnosisOpenrcMissing() {
    #expect(MachineImageAdvisor.logsIndicateMissingInit(["can't run '/sbin/openrc': No such file or directory"]))
}

@Test("Stop diagnosis: healthy systemd boot logs are not flagged")
func stopDiagnosisHealthyBoot() {
    let lines = [
        "systemd 249.11 running in system mode",
        "[  OK  ] Reached target Multi-User System.",
        "[  OK  ] Reached target Graphical Interface.",
    ]
    #expect(!MachineImageAdvisor.logsIndicateMissingInit(lines))
}
