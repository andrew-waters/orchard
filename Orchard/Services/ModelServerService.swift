import Foundation

/// Owns the model servers Orchard has started and supervises their processes. Complements
/// `ModelService` (which only *detects* running servers): this one *runs* them. Follows the
/// house service template - `@Published` state, `AlertCenter` for user-facing failures.
///
/// A managed server never exits on its own, so lifecycle is driven by the process's
/// termination handler: a user Stop is expected (remove quietly); any other exit is a crash
/// (mark failed + alert).
@MainActor
final class ModelServerService: ObservableObject {
    @Published var servers: [ManagedModelServer] = []
    /// Whether the engine binary is installed; drives the create affordance and guidance.
    @Published var engineAvailable: Bool

    private let engine: ModelServerEngine
    private let alertCenter: AlertCenter
    private var processes: [String: ServerProcess] = [:]
    /// Ids the user asked to stop, so the termination handler can tell an intended stop
    /// from a crash.
    private var stopping: Set<String> = []

    init(engine: ModelServerEngine = MLXServerEngine(), alertCenter: AlertCenter) {
        self.engine = engine
        self.alertCenter = alertCenter
        self.engineAvailable = engine.locateBinary() != nil
    }

    /// Ports currently bound by managed servers, so the detected-provider list can hide the
    /// duplicates they would otherwise appear as.
    var managedPorts: Set<UInt16> { Set(servers.map(\.port)) }

    private static func serverID(model: String, port: UInt16) -> String { "\(model)@\(port)" }

    private static func logURL(for id: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("orchard-model-servers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = id.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return dir.appendingPathComponent("\(safe).log")
    }

    @discardableResult
    func start(model: String, host: String, port: UInt16) -> Bool {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alertCenter.error("Enter a model to serve (e.g. mlx-community/Llama-3.2-1B-Instruct-4bit).")
            return false
        }
        let id = Self.serverID(model: trimmed, port: port)
        guard processes[id] == nil else {
            alertCenter.error("A server for \(trimmed) on port \(port) is already running.")
            return false
        }

        let logURL = Self.logURL(for: id)
        do {
            let process = try engine.launch(model: trimmed, host: host, port: port, logURL: logURL)
            // The process abstraction guarantees this fires on the main thread, so we can
            // run the main-actor handler synchronously (and deterministically in tests).
            process.terminationHandler = { [weak self] code in
                MainActor.assumeIsolated { self?.handleTermination(id: id, code: code) }
            }
            processes[id] = process
            servers.append(ManagedModelServer(id: id, model: trimmed, host: host, port: port, status: .running, logPath: logURL.path))
            return true
        } catch {
            alertCenter.error("Failed to start server: \(error.localizedDescription)")
            return false
        }
    }

    func stop(_ id: String) {
        guard let process = processes[id] else { return }
        stopping.insert(id)
        process.terminate()
    }

    private func handleTermination(id: String, code: Int32) {
        processes[id] = nil
        let wasIntentional = stopping.remove(id) != nil

        if wasIntentional {
            servers.removeAll { $0.id == id }
        } else if let index = servers.firstIndex(where: { $0.id == id }) {
            // Unexpected exit - keep it visible as failed so the user can read its log.
            servers[index].status = .failed
            alertCenter.error("Model server \(servers[index].model) stopped unexpectedly (exit \(code)). Check its log.")
        }
    }
}
