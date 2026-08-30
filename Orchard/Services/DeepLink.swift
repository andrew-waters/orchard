import Foundation

/// Destinations reachable via the `orchard://` URL scheme.
///
/// Forms (host is the noun, the rest of the path is the identifier):
/// - `orchard://<tab>` — any sidebar tab, e.g. `orchard://containers`,
///   `orchard://dashboard`
/// - `orchard://container/<id>`
/// - `orchard://image/<reference>` — the reference may itself contain slashes
///   (`orchard://image/docker.io/library/nginx:latest`)
/// - `orchard://machine/<id>`, `orchard://mount/<id>`, `orchard://network/<id>`,
///   `orchard://dns/<domain>`
enum DeepLink: Equatable {
    case tab(TabSelection)
    case container(String)
    case image(String)
    case mount(String)
    case machine(String)
    case dnsDomain(String)
    case network(String)

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == "orchard", let host = url.host else { return nil }
        // Everything after "orchard://<host>/", undoing percent-encoding but
        // keeping interior slashes (image references contain them).
        let identifier = url.path
            .removingPercentEncoding
            .map { String($0.drop(while: { $0 == "/" })) } ?? ""

        switch host.lowercased() {
        case "container":
            return identifier.isEmpty ? .tab(.containers) : .container(identifier)
        case "image":
            return identifier.isEmpty ? .tab(.images) : .image(identifier)
        case "mount":
            return identifier.isEmpty ? .tab(.mounts) : .mount(identifier)
        case "machine":
            return identifier.isEmpty ? .tab(.machines) : .machine(identifier)
        case "dns":
            return identifier.isEmpty ? .tab(.dns) : .dnsDomain(identifier)
        case "network":
            return identifier.isEmpty ? .tab(.networks) : .network(identifier)
        default:
            // A bare tab link: orchard://images, orchard://dashboard, … URL
            // hosts are case-insensitive (and Foundation may lowercase them),
            // so match tabs case-insensitively too.
            guard let tab = TabSelection.allCases.first(where: { $0.rawValue.lowercased() == host.lowercased() }) else {
                return nil
            }
            return .tab(tab)
        }
    }
}
