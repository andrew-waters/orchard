import XCTest

/// Smoke suite: launches the app against the in-memory stub backend (via the
/// `--uitest-mock-backend` launch argument) and drives a few flows a user would meet.
/// Deliberately capped at a handful of high-signal flows — this is a smoke harness, not a
/// per-feature UI-test suite. Seeded identifiers come from `UITestSeed` in the app target.
final class OrchardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-mock-backend"]
        app.launch()
        return app
    }

    /// The "#54 class" of bug: the app is up but everything is broken/empty — invisible to
    /// service unit tests. If the seeded container renders, launch + system-status +
    /// container list + the per-service environment injection all worked end-to-end.
    @MainActor
    func testLaunchesAndRendersSeededContainers() throws {
        let app = launchedApp()
        XCTAssertTrue(
            app.staticTexts["uitest-web"].waitForExistence(timeout: 20),
            "Seeded container should render in the list on launch"
        )
    }

    /// The auto-selected container's detail pane renders alongside the list — exercising
    /// ContainerDetail and its sub-services (stats/image sections, header actions), not just
    /// the list. The detail tab bar's buttons match reliably by label.
    @MainActor
    func testContainerDetailRenders() throws {
        let app = launchedApp()
        XCTAssertTrue(app.staticTexts["uitest-web"].waitForExistence(timeout: 20))
        XCTAssertTrue(
            app.buttons["Overview"].waitForExistence(timeout: 10),
            "The selected container's detail pane (with its tab bar) should render"
        )
    }
}
