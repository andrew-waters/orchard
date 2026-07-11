import Foundation

/// Home-directory mount mode for a container machine (`rw` / `ro` / `none`), shared by the
/// create and edit forms so neither reaches into the other's internals.
enum MachineHomeMount: String, CaseIterable, Identifiable {
    case rw, ro, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rw: return "Read/Write"
        case .ro: return "Read-Only"
        case .none: return "None"
        }
    }
}
