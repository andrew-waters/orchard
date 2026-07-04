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

    /// Look up an element by accessibility identifier regardless of element type. The sidebar
    /// tabs are icon-only SwiftUI `.plain` buttons, which macOS surfaces as image/other
    /// elements rather than `.buttons`, so a typed query (`app.buttons[...]`) misses them.
    private func element(_ app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Tab switching renders another resource list.
    @MainActor
    func testTabSwitchingRendersLists() throws {
        let app = launchedApp()
        XCTAssertTrue(app.staticTexts["uitest-web"].waitForExistence(timeout: 20))

        let imagesTab = element(app, id: "tab-images")
        XCTAssertTrue(imagesTab.waitForExistence(timeout: 10), "Images tab should be present")
        imagesTab.click()
        XCTAssertTrue(
            app.staticTexts["uitest-nginx"].waitForExistence(timeout: 10),
            "Images tab should render the seeded image"
        )

        let containersTab = element(app, id: "tab-containers")
        XCTAssertTrue(containersTab.waitForExistence(timeout: 10), "Containers tab should be present")
        containersTab.click()
        XCTAssertTrue(app.staticTexts["uitest-web"].waitForExistence(timeout: 10))
    }
}
