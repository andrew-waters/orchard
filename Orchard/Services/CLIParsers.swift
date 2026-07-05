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

/// Parses `container system property list --format=json`, which emits a JSON array of
/// `{id, type, value, description}` objects. `type` is "Bool" or "String"; `value` is a
/// JSON bool, string, number, or null (null → the `*undefined*` sentinel).
func parseSystemProperties(json output: String) -> [SystemProperty] {
    guard let data = output.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return []
    }

    // Legacy id aliases, kept in case older daemons emit the pre-rename ids.
    let idMappings: [String: String] = [
        "build.image": "image.builder",
        "vminit.image": "image.init",
    ]

    return array.compactMap { entry in
        guard let rawId = entry["id"] as? String else { return nil }
        let propertyId = idMappings[rawId] ?? rawId

        let type = (entry["type"] as? String)
            .flatMap(SystemProperty.PropertyType.init(rawValue:)) ?? .string

        let rawValue = entry["value"]
        let valueString: String
        if rawValue == nil || rawValue is NSNull {
            valueString = "*undefined*"
        } else if type == .bool, let boolValue = rawValue as? Bool {
            valueString = boolValue ? "true" : "false"
        } else if let stringValue = rawValue as? String {
            valueString = stringValue
        } else if let numberValue = rawValue as? NSNumber {
            valueString = numberValue.stringValue
        } else {
            valueString = String(describing: rawValue!)
        }

        return SystemProperty(
            id: propertyId,
            type: type,
            value: valueString,
            description: entry["description"] as? String ?? ""
        )
    }
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
