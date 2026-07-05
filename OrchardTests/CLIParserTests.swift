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

@Test("System properties: malformed / non-array JSON yields an empty list, not a crash")
func systemPropertiesMalformed() {
    #expect(parseSystemProperties(json: "not json").isEmpty)
    #expect(parseSystemProperties(json: "{}").isEmpty)
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
