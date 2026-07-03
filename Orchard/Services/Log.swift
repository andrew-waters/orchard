import OSLog

/// Categorized loggers. Filter in Console.app by subsystem `dev.andon.orchard`.
enum Log {
    private static let subsystem = "dev.andon.orchard"

    static let cli = Logger(subsystem: subsystem, category: "cli")
    static let xpc = Logger(subsystem: subsystem, category: "xpc")
    static let containers = Logger(subsystem: subsystem, category: "containers")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
