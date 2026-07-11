import Foundation

/// What a log pane (and the log-viewer window) is showing. `Codable`/`Hashable` so it can be
/// a `WindowGroup` presentation value; it carries the resource id and which service reads its
/// logs, letting one pane serve both containers and machines.
enum LogTarget: Codable, Hashable {
    case container(String)
    case machine(String)

    var id: String {
        switch self {
        case .container(let id), .machine(let id):
            return id
        }
    }

    var isMachine: Bool {
        if case .machine = self { return true }
        return false
    }
}
