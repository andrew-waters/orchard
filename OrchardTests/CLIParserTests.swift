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

@Test("System properties: flattens nesting, remaps ids, and types bool/null")
func systemPropertiesParsed() {
    let json = """
    {
      "build": { "image": "ghcr.io/example/builder:latest" },
      "dns": { "domain": "test" },
      "kernel": { "binary": null },
      "network": { "enabled": true }
    }
    """
    let props = parseSystemProperties(json: json)
    func prop(_ id: String) -> SystemProperty? { props.first { $0.id == id } }

    // build.image is remapped to image.builder
    #expect(prop("image.builder")?.value == "ghcr.io/example/builder:latest")
    #expect(prop("build.image") == nil)
    // nested string key is flattened with a dotted path
    #expect(prop("dns.domain")?.value == "test")
    // null becomes the *undefined* sentinel
    #expect(prop("kernel.binary")?.value == "*undefined*")
    // bool is typed as .bool
    #expect(prop("network.enabled")?.type == .bool)
    #expect(prop("network.enabled")?.value == "true")
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
