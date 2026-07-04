import Foundation

/// One place for human-readable byte sizes, replacing the `ByteCountFormatter().string(...)`
/// calls scattered across the views.
enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }

    static func string(_ bytes: Int) -> String {
        string(Int64(bytes))
    }
}
