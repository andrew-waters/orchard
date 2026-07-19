import AppKit

@MainActor
final class OrchardAppDelegate: NSObject, NSApplicationDelegate {
	weak var startupSequenceService: StartupSequenceService?
	private var terminationCleanupTask: Task<Void, Never>?

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		if terminationCleanupTask != nil { return .terminateLater }
		guard let startupSequenceService,
			!startupSequenceService.sequenceOwnedContainerIDs.isEmpty || startupSequenceService.isRunning else {
			return .terminateNow
		}

		terminationCleanupTask = Task { @MainActor [weak self] in
			await startupSequenceService.stopSequenceOwnedContainers()
			sender.reply(toApplicationShouldTerminate: true)
			self?.terminationCleanupTask = nil
		}
		return .terminateLater
	}
}
