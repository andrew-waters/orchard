import XCTest

/// Smoke suite: launches the app against the in-memory stub backend (via the
/// `--uitest-mock-backend` launch argument) and drives a few flows a user would meet.
/// Deliberately capped at a handful of high-signal flows — this is a smoke harness, not a
/// per-feature UI-test suite. Seeded identifiers come from `UITestSeed` in the app target.
final class OrchardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchedApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-mock-backend"] + extraArguments
        app.launch()
        return app
    }

    /// The app now opens on the Dashboard; the container list lives under the Containers tab.
    /// Every flow below starts here so it doesn't depend on the launch default.
    private func openContainersTab(_ app: XCUIApplication) {
        let tab = app.buttons["sidebar-containers"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Containers sidebar tab should exist")
        tab.click()
    }

    /// The "#54 class" of bug: the app is up but everything is broken/empty — invisible to
    /// service unit tests. If the seeded container renders in the Containers list, launch +
    /// system-status + container list + the per-service environment injection all worked.
    @MainActor
    func testLaunchesAndRendersSeededContainers() throws {
        let app = launchedApp()
        openContainersTab(app)
        XCTAssertTrue(
            app.staticTexts["uitest-web"].waitForExistence(timeout: 20),
            "Seeded container should render in the Containers list"
        )
    }

    /// The auto-selected container's detail pane renders alongside the list — exercising
    /// ContainerDetail and its sub-services (stats/image sections, header actions). The detail
    /// header's Logs button is a stable element unique to the detail pane.
    @MainActor
    func testContainerDetailRenders() throws {
        let app = launchedApp()
        openContainersTab(app)
        XCTAssertTrue(app.staticTexts["uitest-web"].waitForExistence(timeout: 20))
        XCTAssertTrue(
            app.buttons["Logs"].waitForExistence(timeout: 10),
            "The selected container's detail pane (with its header actions) should render"
        )
    }

    /// The #54 class: a failed user action must be visible. With the stub set to fail
    /// `stopContainer`, stopping the running container should surface the error alert.
    @MainActor
    func testFailedActionPresentsErrorAlert() throws {
        let app = launchedApp(extraArguments: ["--uitest-fail-stop"])
        openContainersTab(app)
        XCTAssertTrue(app.staticTexts["uitest-web"].waitForExistence(timeout: 20))

        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "The running container's Stop button should render")
        stop.click()

        XCTAssertTrue(
            app.staticTexts["Something Went Wrong"].waitForExistence(timeout: 10),
            "A failed action should present the error alert"
        )
    }
}
