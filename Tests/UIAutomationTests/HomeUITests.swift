import XCTest

final class HomeUITests: XCTestCase {
    func testHomeShowsDemoBadgeAndControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-pofuduk.demoScenario", "rainyAfternoon"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Örnek veri — gerçek tahmin değil"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Durdur"].exists)
        XCTAssertTrue(app.buttons["Tüm metni göster"].exists)
        app.buttons["Tüm metni göster"].tap()
        XCTAssertTrue(app.navigationBars["Pofuduk'un söyledikleri"].waitForExistence(timeout: 3))
    }
}
