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

/// Legacy id aliases, mapping the daemon's category keys to the ids the app looks up.
private let systemPropertyIDAliases: [String: String] = [
    "build.image": "image.builder",
    "vminit.image": "image.init",
]

/// Parses `container system property list --format=json`. As of container 1.0 the daemon
/// emits a nested object keyed by category (`{"build": {"rosetta": true, …}, …}`); pre-1.0
/// daemons emitted a flat array of `{id, type, value, description}`. Both are handled.
func parseSystemProperties(json output: String) -> [SystemProperty] {
    guard let data = output.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) else {
        return []
    }

    // container 1.0+: nested `{category: {key: value}}` object. Checked before the array
    // form because a JSON array does not cast to a dictionary.
    if let categories = root as? [String: Any] {
        return categories.flatMap { category, value -> [SystemProperty] in
            guard let fields = value as? [String: Any] else { return [] }
            return fields.map { key, raw in
                let rawId = "\(category).\(key)"
                let (type, valueString) = normalizeSystemPropertyValue(raw)
                return SystemProperty(
                    id: systemPropertyIDAliases[rawId] ?? rawId,
                    type: type,
                    value: valueString,
                    description: ""
                )
            }
        }
    }

    // Pre-1.0: flat array of `{id, type, value, description}` objects.
    if let array = root as? [[String: Any]] {
        return array.compactMap { entry in
            guard let rawId = entry["id"] as? String else { return nil }
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
                id: systemPropertyIDAliases[rawId] ?? rawId,
                type: type,
                value: valueString,
                description: entry["description"] as? String ?? ""
            )
        }
    }

    return []
}

/// Classifies a raw JSON scalar from the nested property object as a bool or string and
/// renders it to the app's string form. JSON booleans bridge to `NSNumber` (`CFBoolean`),
/// so they are distinguished from numbers by CoreFoundation type rather than `as? Bool`,
/// which also matches 0/1 integers.
private func normalizeSystemPropertyValue(_ raw: Any) -> (SystemProperty.PropertyType, String) {
    if raw is NSNull {
        return (.string, "*undefined*")
    }
    if let string = raw as? String {
        return (.string, string)
    }
    if let number = raw as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return (.bool, number.boolValue ? "true" : "false")
        }
        return (.string, number.stringValue)
    }
    return (.string, String(describing: raw))
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
