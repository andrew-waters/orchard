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

    /// A CIDR subnet: dotted-quad IPv4 followed by a /0–/32 prefix length.
    static func isValidSubnet(_ subnet: String) -> Bool {
        let regex = "^([0-9]{1,3}\\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: subnet)
    }
}
