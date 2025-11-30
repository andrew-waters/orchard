import Foundation

enum TabSelection: String, CaseIterable {
    case containers = "containers"
    case images = "images"
    case mounts = "mounts"
    case dns = "dns"
    case networks = "networks"
    case registries = "registries"
    case systemLogs = "systemLogs"

    var icon: String {
        switch self {
        case .containers:
            return "cube"
        case .images:
            return "cube.transparent"
        case .mounts:
            return "externaldrive"
        case .dns:
            return "network"
        case .networks:
            return "wifi"
        case .registries:
            return "server.rack"
        case .systemLogs:
            return "doc.text.below.ecg"
        }
    }

    var title: String {
        switch self {
        case .containers:
            return "Containers"
        case .images:
            return "Images"
        case .mounts:
            return "Mounts"
        case .dns:
            return "DNS"
        case .networks:
            return "Networks"
        case .registries:
            return "Registries"
        case .systemLogs:
            return "System Logs"
        }
    }
}
