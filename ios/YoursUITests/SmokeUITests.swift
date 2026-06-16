import XCTest

final class SmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLandingMockShowsGoogleEntry() throws {
        let app = launch(arguments: ["-YoursMockLanding"])

        XCTAssertTrue(app.buttons["landing-google-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["landing-title"].exists)
    }

    func testChatMockShowsPrimaryControlsAndSettings() throws {
        let app = launch(arguments: ["-YoursMockChat"])

        XCTAssertTrue(app.buttons["send-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["next-day-button"].exists)
        XCTAssertTrue(app.buttons["save-button"].exists)

        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.staticTexts["settings-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-done-button"].exists)
    }

    func testSleepMockMovesFromIntegratingToContinue() throws {
        let app = launch(arguments: ["-YoursMockChat", "-YoursMockSleep"])

        XCTAssertTrue(app.staticTexts["sleep-integrating-label"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sleep-continue-button"].waitForExistence(timeout: 8))
    }

    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }
}
