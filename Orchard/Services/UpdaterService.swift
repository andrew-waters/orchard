import Combine
import Sparkle
import SwiftUI

/// Wraps Sparkle's updater so SwiftUI views can trigger update checks and
/// observe whether a check is currently allowed.
///
/// Sparkle is configured via `Info.plist` (`SUFeedURL`, `SUPublicEDKey`). With
/// `startingUpdater: true` and no `SUEnableAutomaticChecks` value set, Sparkle
/// prompts the user on first launch to ask whether it may check automatically,
/// then performs periodic background checks thereafter.
final class UpdaterService: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    /// Mirrors Sparkle's `canCheckForUpdates` so menu items can disable
    /// themselves while a check is already in flight.
    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Presents Sparkle's standard "Check for Updates" flow.
    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
}

/// A menu item that triggers a Sparkle update check and disables itself while
/// one is already running.
struct CheckForUpdatesView: View {
    @ObservedObject var updater: UpdaterService

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
