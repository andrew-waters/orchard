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
        // Run the blocking Process work on a global-queue thread — not a Swift-concurrency
        // cooperative thread — so several concurrent CLI calls can't starve the pool.
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try SystemCommandRunner.runProcessSync(program: program, arguments: arguments))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func runWithSudo(program: String, arguments: [String]) async throws -> ProcessResult {
        let script = SystemCommandRunner.adminScript(program: program, arguments: arguments)
        return try await run(program: "/usr/bin/osascript", arguments: ["-e", script])
    }

    /// Quote a single token for `/bin/sh` by wrapping it in single quotes (which suppress
    /// all shell interpretation), escaping any embedded single quote as `'\''`.
    static func shellQuote(_ token: String) -> String {
        "'" + token.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Build the AppleScript that runs `program` + `arguments` as an administrator.
    /// Every token is shell-quoted, then the whole command is escaped for the AppleScript
    /// double-quoted string literal — so a space, quote, or `$(…)` in a user-supplied
    /// argument (e.g. a DNS domain) or the binary path is treated as literal text, never
    /// executed. Pure and unit-tested.
    static func adminScript(program: String, arguments: [String]) -> String {
        let command = ([program] + arguments).map(shellQuote).joined(separator: " ")
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    /// Synchronous process execution. Must be called off the main/cooperative threads.
    static func runProcessSync(program: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Drain both pipes concurrently *before* waiting: a child that writes more than
        // the ~64KB pipe buffer would otherwise block forever waiting for us to read,
        // and we'd block forever in waitUntilExit — a mutual deadlock.
        let group = DispatchGroup()
        let lock = NSLock()
        var stdoutData = Data()
        var stderrData = Data()
        for (pipe, isStdout) in [(stdoutPipe, true), (stderrPipe, false)] {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock()
                if isStdout { stdoutData = data } else { stderrData = data }
                lock.unlock()
                group.leave()
            }
        }
        group.wait()
        process.waitUntilExit()

        var stdoutStr = String(data: stdoutData, encoding: .utf8)
        var stderrStr = String(data: stderrData, encoding: .utf8)

        // Strip trailing newline
        if let s = stdoutStr, s.hasSuffix("\n") { stdoutStr = String(s.dropLast()) }
        if let s = stderrStr, s.hasSuffix("\n") { stderrStr = String(s.dropLast()) }

        return ProcessResult(exitCode: process.terminationStatus, stdout: stdoutStr, stderr: stderrStr)
    }
}
