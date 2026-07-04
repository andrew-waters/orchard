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

    /// Look up an element by accessibility identifier regardless of element type — the
    /// sidebar rows are tap-gesture HStacks, not `.buttons`, so a typed query would miss them.
    private func element(_ app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Selecting another sidebar row renders that resource list.
    @MainActor
    func testSidebarNavigationRendersLists() throws {
        let app = launchedApp()
        XCTAssertTrue(app.staticTexts["uitest-web"].waitForExistence(timeout: 20))

        let imagesRow = element(app, id: "sidebar-images")
        XCTAssertTrue(imagesRow.waitForExistence(timeout: 10), "Images sidebar row should be present")
        imagesRow.click()
        XCTAssertTrue(
            app.staticTexts["uitest-nginx"].waitForExistence(timeout: 10),
            "Images list should render the seeded image"
        )

        let containersRow = element(app, id: "sidebar-containers")
        XCTAssertTrue(containersRow.waitForExistence(timeout: 10), "Containers sidebar row should be present")
        containersRow.click()
        XCTAssertTrue(app.staticTexts["uitest-web"].waitForExistence(timeout: 10))
    }
}
