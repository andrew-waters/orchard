import Foundation

enum TabSelection: String, CaseIterable {
    case containers = "containers"
    case images = "images"
    case mounts = "mounts"
    case machines = "machines"
    case dns = "dns"
    case networks = "networks"
    case registries = "registries"
    case systemLogs = "systemLogs"
    case dashboard = "dashboard"

    var icon: String {
        switch self {
        case .containers:
            return "cube"
        case .images:
            return "cube.transparent"
        case .mounts:
            return "externaldrive"
        case .machines:
            return "cpu"
        case .dns:
            return "network"
        case .networks:
            return "arrow.down.left.arrow.up.right"
        case .registries:
            return "server.rack"
        case .systemLogs:
            return "doc.text.below.ecg"
        case .dashboard:
            return "gauge.with.dots.needle.bottom.50percent"
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
        case .machines:
            return "Machines"
        case .dns:
            return "DNS"
        case .networks:
            return "Networks"
        case .registries:
            return "Registries"
        case .systemLogs:
            return "System Logs"
        case .dashboard:
            return "Dashboard"
        }
    }
}
