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
        app.launchEnvironment["ORCHARD_UITEST_MOCK_BACKEND"] = "1"
        app.launch()
        app.activate()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "App should reach the foreground under the mock backend"
        )
        return app
    }

    /// The app now opens on the Dashboard; the container list lives under the Containers tab.
    /// Every flow below starts here so it doesn't depend on the launch default.
    ///
    /// The sidebar row is a tap-gesture view (not a `Button`), and a synthetic `click()` on it
    /// intermittently fails to register on a cold/slow CI launch — the tab never switches and
    /// the list column never appears. So click until the seeded row actually renders, which is
    /// the real signal that navigation took; re-selecting the Containers tab is idempotent.
    private func openContainersTab(_ app: XCUIApplication) {
        let tab = app.buttons["sidebar-containers"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Containers sidebar tab should exist")
        for _ in 0..<5 {
            tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            if app.staticTexts["uitest-web"].waitForExistence(timeout: 5) { return }
        }
        XCTFail("Containers list did not render after selecting the Containers tab")
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

    /// A long environment key must not push its own row's controls out of the pane: the key
    /// column is capped, so the key wraps and Show/Copy stay reachable. The seeded container
    /// carries `ORCHARD_UI_TEST_LONG_ENVIRONMENT_VARIABLE_KEY` for exactly this.
    @MainActor
    func testLongEnvironmentKeyKeepsItsRowControlsReachable() throws {
        let app = launchedApp()
        openContainersTab(app)
        XCTAssertTrue(app.staticTexts["uitest-web"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Logs"].waitForExistence(timeout: 10))

        // Scroll from a point inside the detail pane rather than querying the SwiftUI
        // ScrollView: resolving that element asks XCTest to snapshot the whole detail
        // hierarchy, which is slow enough to time out. Wheel deltas also avoid the inertia
        // a synthetic swipe adds, and the normalised anchor holds at any window size.
        let detailPane = app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.6))
        let toggle = app.buttons["environment-value-toggle-ORCHARD_UI_TEST_LONG_ENVIRONMENT_VARIABLE_KEY"]

        for _ in 0..<8 where !(toggle.exists && toggle.isHittable) {
            detailPane.scroll(byDeltaX: 0, deltaY: -150)
        }
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "The long environment key's value control should render after scrolling"
        )
        XCTAssertTrue(
            toggle.isHittable,
            "The value control beside a long environment key should remain onscreen and clickable"
        )

        // The label flips only once SwiftUI has re-rendered the row, so wait for it.
        toggle.click()
        let revealed = expectation(for: NSPredicate(format: "label == %@", "Hide"), evaluatedWith: toggle)
        wait(for: [revealed], timeout: 10)
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
