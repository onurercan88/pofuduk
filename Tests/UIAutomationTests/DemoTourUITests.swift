import XCTest

/// A slow, guided walk through the app for the CI screen recording (pofuduk-tour.mp4).
/// Skipped in normal test runs; CI enables it with TEST_RUNNER_POFUDUK_TOUR=1 while recording.
/// Steps are "soft": a missing element is skipped so the recording always completes.
final class DemoTourUITests: XCTestCase {
    private var app: XCUIApplication!

    private func pause(_ seconds: UInt32) { sleep(seconds) }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 5) {
        var n = 0
        while !element.isHittable && n < maxSwipes { app.swipeUp(); n += 1 }
    }

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 4) {
        if element.waitForExistence(timeout: timeout), element.isHittable { element.tap() }
    }

    private func ask(_ question: String, wait: UInt32) {
        let field = app.textFields["Soru"]
        guard field.waitForExistence(timeout: 4) else { return }
        field.tap()
        field.typeText(question + "\n")
        pause(wait)
    }

    func testGuidedTour() throws {
        guard ProcessInfo.processInfo.environment["POFUDUK_TOUR"] == "1" else {
            throw XCTSkip("Guided tour runs only while CI records the video.")
        }
        app = XCUIApplication()
        app.launchArguments = ["-pofuduk.demoScenario", "rainyAfternoon"]
        app.launch()

        // 1. Rainy afternoon briefing: speech, subtitles, umbrella.
        pause(14)

        // 2. Different weather looks via the demo picker.
        for scenario in ["Fırtına", "Karlı", "Güneşli"] {
            let chip = app.buttons[scenario]
            scrollTo(chip)
            tap(chip)
            app.swipeDown(); app.swipeDown()
            pause(8)
        }

        // 3. Questions, including a follow-up.
        ask("Yarın hava nasıl?", wait: 9)
        ask("Peki yağmur var mı?", wait: 7)
        ask("Bugün ne giysem?", wait: 8)

        // 4. "Bugün Ne Giysem?" screen.
        let clothing = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Bugün Ne Giysem'")).firstMatch
        scrollTo(clothing)
        tap(clothing)
        pause(5)
        tap(app.buttons["Yarın"])
        pause(4)
        tap(app.buttons["Kapat"])
        pause(1)

        // 5. Travel weather to Antalya.
        let travel = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Seyahat Hava Durumu'")).firstMatch
        scrollTo(travel)
        tap(travel)
        let destination = app.textFields["Şehir veya ilçe"]
        if destination.waitForExistence(timeout: 4) {
            destination.tap()
            destination.typeText("Antalya")
            pause(2)
            tap(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Antalya'")).firstMatch)
            tap(app.buttons["Hava durumunu göster"])
            pause(5)
            app.swipeUp()
            pause(4)
        }
        tap(app.buttons["Kapat"])
        pause(1)

        // 6. Settings.
        app.swipeDown(); app.swipeDown()
        tap(app.buttons["Ayarlar"])
        pause(3)
        app.swipeUp()
        pause(3)
        tap(app.buttons["Bitti"])
        pause(3)
    }
}
