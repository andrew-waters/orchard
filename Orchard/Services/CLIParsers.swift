import Foundation

// Pure parsing of CLI / HTTP output. These functions depend only on their inputs and
// the app's domain models, so they can be unit-tested directly. They are lenient:
// malformed input yields an empty / no-op result rather than throwing.

// MARK: - Builder status

/// Outcome of parsing `container builder status --format json` stdout.
enum BuilderParseResult {
    /// No builder present — plain-text "not running", or empty / `null` / `[]` JSON.
    case notRunning
    /// One or more builders decoded from JSON (single object or array).
    case builders([Builder])
    /// JSON was present but could not be decoded; carries a short preview for logging.
    case decodeFailure(preview: String)
}

func parseBuilderStatus(stdout: String) -> BuilderParseResult {
    let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()

    // Known non-JSON "not running" output.
    if lower.hasPrefix("builder is not running") || lower.hasPrefix("no builder") {
        return .notRunning
    }

    // Empty or explicit empty JSON.
    if trimmed.isEmpty || trimmed == "null" || trimmed == "[]" {
        return .notRunning
    }

    // Try decoding JSON (single object or array).
    let data = Data(trimmed.utf8)
    if let single = try? JSONDecoder().decode(Builder.self, from: data) {
        return .builders([single])
    }
    if let array = try? JSONDecoder().decode([Builder].self, from: data) {
        return .builders(array)
    }
    return .decodeFailure(preview: String(trimmed.prefix(200)))
}

// MARK: - DNS domains

func parseDNSDomains(json output: String, defaultDomain: String?) -> [DNSDomain] {
    var domains: [DNSDomain] = []
    guard let data = output.data(using: .utf8) else { return domains }

    // Parse JSON array of domain strings.
    if let domainArray = try? JSONSerialization.jsonObject(with: data) as? [String] {
        for domainName in domainArray {
            domains.append(DNSDomain(domain: domainName, isDefault: domainName == defaultDomain))
        }
    }
    return domains
}

// MARK: - System properties

func parseSystemProperties(json output: String) -> [SystemProperty] {
    guard let data = output.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return []
    }

    var properties: [SystemProperty] = []

    let idMappings: [String: String] = [
        "build.image": "image.builder",
        "vminit.image": "image.init",
    ]

    func flatten(_ dict: [String: Any], prefix: String = "") {
        for (key, value) in dict {
            let dotKey = prefix.isEmpty ? key : "\(prefix).\(key)"
            if let nestedDict = value as? [String: Any] {
                flatten(nestedDict, prefix: dotKey)
            } else {
                let propertyId = idMappings[dotKey] ?? dotKey
                let valueString: String
                let type: SystemProperty.PropertyType

                if value is NSNull {
                    valueString = "*undefined*"
                    type = .string
                } else if let boolValue = value as? Bool {
                    valueString = boolValue ? "true" : "false"
                    type = .bool
                } else if let stringValue = value as? String {
                    valueString = stringValue
                    type = .string
                } else if let numberValue = value as? NSNumber {
                    valueString = numberValue.stringValue
                    type = .string
                } else {
                    valueString = String(describing: value)
                    type = .string
                }

                properties.append(SystemProperty(
                    id: propertyId,
                    type: type,
                    value: valueString,
                    description: ""
                ))
            }
        }
    }

    flatten(json)
    return properties
}

// MARK: - Docker Hub search

func parseDockerHubSearch(data: Data) -> [RegistrySearchResult] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let results = json["results"] as? [[String: Any]] else {
        return []
    }

    return results.compactMap { result in
        guard let name = result["repo_name"] as? String else { return nil }

        // Build full image name with registry.
        let fullName = name.contains("/") ? "docker.io/\(name)" : "docker.io/library/\(name)"

        return RegistrySearchResult(
            name: fullName,
            description: result["short_description"] as? String,
            isOfficial: (result["is_official"] as? Bool) ?? false,
            starCount: result["star_count"] as? Int
        )
    }
}
