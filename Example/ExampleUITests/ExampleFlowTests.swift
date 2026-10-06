import XCTest

/// End-to-end checks: routing, early configuration, main request, rendering, events, retry and the list page.
@MainActor
final class ExampleFlowTests: XCTestCase {
    private enum Timeout {
        static let load: TimeInterval = 8
        static let short: TimeInterval = 3
    }

    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        app.launch()
    }

    func testPushDetailRendersLoadedStateAndContext() {
        app.buttons["Push Detail"].tap()

        // Route parameters are written to the context in configure, so they are there on first display.
        XCTAssertTrue(app.staticTexts["context: id = 1, source = Optional<UIViewController>"].waitForExistence(timeout: Timeout.short))

        // Once loading finishes, render() refreshes the title and body.
        XCTAssertTrue(app.navigationBars["Item #1"].waitForExistence(timeout: Timeout.load))
        XCTAssertTrue(app.staticTexts["id = 1, price = 19.9"].exists)
    }

    func testPluginReceivesEventAndRetryReloads() {
        app.buttons["Push Detail"].tap()
        XCTAssertTrue(app.navigationBars["Item #1"].waitForExistence(timeout: Timeout.load))

        // The page dispatches an event after parsing; the plugin updates its own view.
        XCTAssertTrue(app.staticTexts["plugin received event: Item #1 loaded 1x"].waitForExistence(timeout: Timeout.short))

        // Retry runs the main request flow again.
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.staticTexts["plugin received event: Item #1 loaded 2x"].waitForExistence(timeout: Timeout.load))
    }

    func testPresentWrapsDetailInNavigation() {
        app.buttons["Present Detail"].tap()
        XCTAssertTrue(app.navigationBars["Item #2"].waitForExistence(timeout: Timeout.load))
    }

    func testListPageLoadsAndPushesDetail() {
        app.buttons["List"].tap()
        let cell = app.staticTexts["Item #3"]
        XCTAssertTrue(cell.waitForExistence(timeout: Timeout.load))

        cell.tap()
        XCTAssertTrue(app.navigationBars["Item #3"].waitForExistence(timeout: Timeout.load))
    }

    func testDeeplinkOpensDetailWithDeeplinkSource() {
        app.buttons["Open Deeplink"].tap()
        XCTAssertTrue(app.staticTexts["context: id = 1, source = deeplink"].waitForExistence(timeout: Timeout.short))
        XCTAssertTrue(app.navigationBars["Item #1"].waitForExistence(timeout: Timeout.load))
    }
}
