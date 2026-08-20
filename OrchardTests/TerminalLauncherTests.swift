import Foundation
import Testing
@testable import Orchard

@Test("TerminalLauncher: automation refusal points at System Settings")
func terminalLauncherNotAuthorizedMessage() {
    let error: NSDictionary = [
        NSAppleScript.errorNumber: -1743,
        NSAppleScript.errorAppName: "Terminal",
        NSAppleScript.errorBriefMessage: "Not authorized to send Apple events to Terminal.",
    ]
    let message = TerminalLauncher.userMessage(for: error)
    #expect(message.contains("Terminal"))
    #expect(message.contains("Privacy & Security"))
    #expect(message.contains("Automation"))
}

@Test("TerminalLauncher: privilege error is treated as an automation refusal")
func terminalLauncherPrivilegeErrorMessage() {
    let error: NSDictionary = [
        NSAppleScript.errorNumber: -10004,
        NSAppleScript.errorAppName: "iTerm2",
    ]
    let message = TerminalLauncher.userMessage(for: error)
    #expect(message.contains("iTerm2"))
    #expect(message.contains("Automation"))
}

@Test("TerminalLauncher: app-not-running errors suggest opening the app")
func terminalLauncherAppNotRunningMessage() {
    let error: NSDictionary = [
        NSAppleScript.errorNumber: -600,
        NSAppleScript.errorAppName: "iTerm2",
    ]
    let message = TerminalLauncher.userMessage(for: error)
    #expect(message.contains("iTerm2"))
    #expect(message.contains("isn't running"))
}

@Test("TerminalLauncher: unknown errors fall back to the brief message")
func terminalLauncherUnknownErrorMessage() {
    let error: NSDictionary = [
        NSAppleScript.errorNumber: -2700,
        NSAppleScript.errorBriefMessage: "Some other failure.",
    ]
    let message = TerminalLauncher.userMessage(for: error)
    #expect(message.contains("Failed to open terminal"))
    #expect(message.contains("Some other failure."))
}

@Test("TerminalLauncher: missing error fields still produce a usable message")
func terminalLauncherMissingFieldsMessage() {
    let message = TerminalLauncher.userMessage(for: [:])
    #expect(message.contains("Failed to open terminal"))
}
