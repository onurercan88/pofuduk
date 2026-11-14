import XCTest

final class HomeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchDemo(_ scenario: String = "rainyAfternoon", soundOff: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-pofuduk.demoScenario", scenario]
        if soundOff { app.launchArguments += ["-pofuduk.soundOn", "NO"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["Örnek veri — gerçek tahmin değil"].waitForExistence(timeout: 8))
        return app
    }

    func testHomeShowsDemoBadgeAndControls() {
        let app = launchDemo(soundOff: false)
        XCTAssertTrue(app.buttons["Durdur"].exists)
        XCTAssertTrue(app.buttons["Tüm metni göster"].exists)
        XCTAssertTrue(app.buttons["Ayarlar"].exists)
        app.buttons["Tüm metni göster"].tap()
        XCTAssertTrue(app.navigationBars["Pofuduk'un söyledikleri"].waitForExistence(timeout: 3))
    }

    func testTypedQuestionIsAnswered() {
        let app = launchDemo()
        let field = app.textFields["Soru"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Yarın hava nasıl?\n")
        app.buttons["Tüm metni göster"].tap()
        let answer = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Yarın İstanbul'")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
    }

    func testSettingsOpensWithPrivacyAndDeleteOption() {
        let app = launchDemo()
        app.buttons["Ayarlar"].tap()
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 3))
        let delete = app.buttons["Verilerimi sil"]
        for _ in 0..<6 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.exists)
    }

    func testClothingAndTravelScreensOpen() {
        let app = launchDemo()
        let clothing = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Bugün Ne Giysem'")).firstMatch
        for _ in 0..<4 where !clothing.isHittable { app.swipeUp() }
        clothing.tap()
        XCTAssertTrue(app.navigationBars["Bugün Ne Giysem?"].waitForExistence(timeout: 3))
        app.buttons["Kapat"].tap()

        let travel = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Seyahat Hava Durumu'")).firstMatch
        for _ in 0..<4 where !travel.isHittable { app.swipeUp() }
        travel.tap()
        XCTAssertTrue(app.navigationBars["Seyahat Hava Durumu"].waitForExistence(timeout: 3))
    }

    /// Apple's automated accessibility audit (iOS 17+) on the home screen.
    func testHomeAccessibilityAudit() throws {
        let app = launchDemo("sunny")
        let askBarTop = app.textFields["Soru"].frame.minY - 24
        try app.performAccessibilityAudit { issue in
            let label = issue.element?.label ?? "-"
            // Only exception: contrast of scroll content currently covered by the fixed ask bar
            // (the audit samples the bar's background, not what the user can see).
            if issue.auditType == .contrast, let frame = issue.element?.frame, frame.maxY > askBarTop {
                print("AUDIT-SKIPPED (covered by ask bar): \(label) \(frame)")
                return true
            }
            print("AUDIT: \(issue.auditType) | \(issue.compactDescription) | \(label) | \(issue.element?.elementType.rawValue ?? 0)")
            return false
        }
    }
}
