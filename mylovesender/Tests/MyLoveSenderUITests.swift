#if DEBUG && canImport(XCTest)
import XCTest

final class MyLoveSenderUITests: XCTestCase {
    func testCreateAndReopenDraft() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launchEnvironment["MYLOVE_UI_TESTING"] = "1"
        app.launch()

        app.tabBars.buttons["Neu"].tap()
        app.textFields["Titel"].tap()
        app.textFields["Titel"].typeText("Fuer Bella")
        app.textViews.firstMatch.tap()
        app.textViews.firstMatch.typeText("Ein kleiner Testbrief.")
        app.buttons["Als Entwurf speichern"].tap()
        app.tabBars.buttons["Briefe"].tap()
        XCTAssertTrue(app.staticTexts["Fuer Bella"].waitForExistence(timeout: 2))
        app.staticTexts["Fuer Bella"].tap()
        XCTAssertTrue(app.navigationBars["Brief"].exists || app.navigationBars["Fuer Bella"].exists)
    }
}
#endif
