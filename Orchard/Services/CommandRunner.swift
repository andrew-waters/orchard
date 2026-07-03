import Foundation

/// Result of running an external process.
struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String?
    let stderr: String?
    var failed: Bool { exitCode != 0 }
}

/// Abstraction over running external CLI commands, so callers can be driven with a
/// mock in tests. `run` is `async` and executes off the main actor.
protocol CommandRunner: Sendable {
    func run(program: String, arguments: [String]) async throws -> ProcessResult
    func runWithSudo(program: String, arguments: [String]) async throws -> ProcessResult
}

/// The production `CommandRunner`: spawns real processes.
struct SystemCommandRunner: CommandRunner {
    func run(program: String, arguments: [String]) async throws -> ProcessResult {
        // Run the blocking Process work on a background thread so the caller's
        // executor (typically the main actor) is never blocked.
        try await Task.detached(priority: .userInitiated) {
            try SystemCommandRunner.runProcessSync(program: program, arguments: arguments)
        }.value
    }

    func runWithSudo(program: String, arguments: [String]) async throws -> ProcessResult {
        let fullCommand = "\(program) \(arguments.joined(separator: " "))"
        let script = """
        do shell script "\(fullCommand)" with administrator privileges
        """
        return try await run(program: "/usr/bin/osascript", arguments: ["-e", script])
    }

    /// Synchronous process execution.
    static func runProcessSync(program: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        var stdoutStr = String(data: stdoutData, encoding: .utf8)
        var stderrStr = String(data: stderrData, encoding: .utf8)

        // Strip trailing newline
        if let s = stdoutStr, s.hasSuffix("\n") { stdoutStr = String(s.dropLast()) }
        if let s = stderrStr, s.hasSuffix("\n") { stderrStr = String(s.dropLast()) }

        return ProcessResult(exitCode: process.terminationStatus, stdout: stdoutStr, stderr: stderrStr)
    }
}
