import AppKit

@MainActor
final class OrchardAppDelegate: NSObject, NSApplicationDelegate {
	private enum CleanupOutcome {
		case completed
		case timedOut
	}

	weak var startupSequenceService: StartupSequenceService?
	private var terminationCleanupTask: Task<Void, Never>?

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		if terminationCleanupTask != nil { return .terminateLater }
		guard let startupSequenceService,
			!startupSequenceService.sequenceOwnedContainerIDs.isEmpty || startupSequenceService.isRunning else {
			return .terminateNow
		}

		terminationCleanupTask = Task { @MainActor [weak self] in
			let (completionStream, completionContinuation) = AsyncStream<Void>.makeStream()
			let cleanupTask = Task { @MainActor in
				await startupSequenceService.stopSequenceOwnedContainers()
				completionContinuation.finish()
			}

			let outcome = await withTaskGroup(of: CleanupOutcome.self) { tasks in
				tasks.addTask {
					for await _ in completionStream { }
					return .completed
				}
				tasks.addTask {
					try? await Task.sleep(for: .seconds(5))
					return .timedOut
				}
				let outcome = await tasks.next() ?? .timedOut
				tasks.cancelAll()
				return outcome
			}

			if outcome == .timedOut {
				cleanupTask.cancel()
			}
			sender.reply(toApplicationShouldTerminate: true)
			self?.terminationCleanupTask = nil
		}
		return .terminateLater
	}
}
