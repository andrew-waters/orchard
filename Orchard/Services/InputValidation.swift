import Foundation

/// Pure input validators used by the Add/Run forms. Kept out of the views so they can be
/// unit-tested and reused. (Container-name validation lives on `ContainerConfigForm` since
/// it also needs the existing container list.)
enum InputValidation {
    /// A DNS domain: dot-separated labels, each 1–63 chars, alphanumeric with internal dashes.
    static func isValidDomainName(_ domain: String) -> Bool {
        let regex = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: domain)
    }

    /// A network name: a single label, 1–63 chars, alphanumeric with internal dashes.
    static func isValidNetworkName(_ name: String) -> Bool {
        let regex = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: name)
    }

    /// A volume name as the runtime accepts it: a letter or digit, then letters, digits, `_`,
    /// `.` or `-`, at most 255 characters in all.
    static func isValidVolumeName(_ name: String) -> Bool {
        name.count <= 255 && name.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]*$", options: .regularExpression) != nil
    }

    /// The bytes in a volume size written as `container volume create -s` takes it: a number
    /// and an optional binary unit (`512M`, `10G`, `1.5gib`; no unit is bytes). Nil when it
    /// isn't one, or is under the runtime's 1 MiB minimum.
    static func volumeSizeBytes(_ size: String) -> UInt64? {
        let trimmed = size.trimmingCharacters(in: .whitespaces).lowercased()
        let unitStart = trimmed.firstIndex { !"0123456789.".contains($0) } ?? trimmed.endIndex
        guard let value = Double(trimmed[..<unitStart].trimmingCharacters(in: .whitespaces)), value.isFinite else {
            return nil
        }
        let unit = trimmed[unitStart...].trimmingCharacters(in: .whitespaces)
        let exponents: [Character: Double] = ["b": 0, "k": 1, "m": 2, "g": 3, "t": 4, "p": 5]
        guard let exponent = exponents[unit.first ?? "b"], ["", "b", "ib"].contains(unit.dropFirst()) else {
            return nil
        }
        let bytes = value * pow(1024, exponent)
        guard bytes >= 1_048_576, bytes < Double(UInt64.max) else { return nil }
        return UInt64(bytes)
    }

    static let invalidVolumeNameMessage =
        "Use letters, digits, underscores, dots and hyphens, starting with a letter or digit."

    static let invalidVolumeSizeMessage =
        "Enter a size such as 512M or 10G, at least 1M."

    /// A dotted-quad IPv4 address, each octet 0-255.
    static func isValidIPv4(_ address: String) -> Bool {
        let octet = "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"
        let regex = "^(\(octet)\\.){3}\(octet)$"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: address)
    }

    /// A CIDR subnet: dotted-quad IPv4 (each octet 0–255) followed by a /0–/32 prefix length.
    static func isValidSubnet(_ subnet: String) -> Bool {
        let octet = "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"
        let regex = "^(\(octet)\\.){3}\(octet)/([0-9]|[1-2][0-9]|3[0-2])$"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: subnet)
    }

    /// An image name to build or commit to. An optional registry host (which may carry a
    /// :port), then the lowercase repository path, then an optional mixed-case :tag - so a
    /// local registry form like localhost:5000/myapp:v1 validates.
    static func isValidImageReference(_ reference: String) -> Bool {
        let pattern = "^([a-z0-9][a-z0-9.-]*(:[0-9]+)?/)?[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9._-]+)?$"
        return reference.range(of: pattern, options: .regularExpression) != nil
    }

    static let invalidImageReferenceMessage =
        "Invalid image name. Use lowercase letters, digits, separators, and an optional :tag."
}
