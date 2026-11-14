import XCTest
@testable import PofudukCore

final class MorningBriefingTests: XCTestCase {
    let engine = MorningBriefingEngine()
    let tz = TestClock.istanbul

    func testShouldGreetWindowAndOncePerDay() {
        var s = MorningBriefingSettings()            // 07:30
        XCTAssertFalse(engine.shouldGreet(now: TestClock.date(hour: 7, minute: 10), settings: s, timeZone: tz))
        XCTAssertTrue(engine.shouldGreet(now: TestClock.date(hour: 7, minute: 45), settings: s, timeZone: tz))
        XCTAssertFalse(engine.shouldGreet(now: TestClock.date(hour: 12, minute: 5), settings: s, timeZone: tz))
        s.lastGreetedDay = MorningBriefingEngine.dayKey(TestClock.date(hour: 8), timeZone: tz)
        XCTAssertFalse(engine.shouldGreet(now: TestClock.date(hour: 9), settings: s, timeZone: tz), "Once per day")
        XCTAssertTrue(engine.shouldGreet(now: TestClock.date(hour: 9, day: 15), settings: s, timeZone: tz), "Next day again")
        s.isEnabled = false
        XCTAssertFalse(engine.shouldGreet(now: TestClock.date(hour: 9, day: 15), settings: s, timeZone: tz))
    }

    func testCustomTime() {
        var s = MorningBriefingSettings()
        s.minuteOfDay = 6 * 60 + 15
        XCTAssertTrue(engine.shouldGreet(now: TestClock.date(hour: 6, minute: 20), settings: s, timeZone: tz))
    }

    private func briefing(_ scenario: MockWeatherData.Scenario, at hour: Int, warnings: [OfficialWarning] = []) -> Briefing {
        let now = TestClock.date(hour: hour)
        var snap = MockWeatherData.snapshot(scenario, now: now)
        snap.source = .openMeteo
        let a = WeatherSummaryEngine().analyze(snap, now: now)
        let c = ClothingRecommendationEngine().recommend(for: snap, now: now)
        return engine.briefing(snapshot: snap, analysis: a, warnings: warnings, clothing: c, now: now)
    }

    func testMorningArcRainAndUmbrella() {
        let b = briefing(.rainyAfternoon, at: 8)
        XCTAssertEqual(b.sentences.first, "Günaydın!")
        XCTAssertTrue(b.fullText.contains("sabah"), b.fullText)
        XCTAssertTrue(b.fullText.contains("dereceyle başlıyoruz"), b.fullText)
        XCTAssertTrue(b.fullText.contains("Öğleden sonra sıcaklık"), b.fullText)
        XCTAssertTrue(b.fullText.contains("Ancak öğleden sonra yağmur bekleniyor."), b.fullText)
        XCTAssertEqual(b.sentences.last, "Dışarı çıkacaksan şemsiyeni hazırla!")
    }

    func testSunnyMorningIsCheerfulAndMentionsUV() {
        let b = briefing(.sunny, at: 8)
        XCTAssertTrue(b.fullText.contains("Bugün senin için güzel bir gün olabilir."))
        XCTAssertTrue(b.fullText.contains("Gün boyu yağış beklenmiyor."))
        XCTAssertTrue(b.fullText.contains("UV indeksi 7"))
        XCTAssertEqual(b.restingMood, .happy)
    }

    func testLateMorningUsesCurrentTemperature() {
        XCTAssertTrue(briefing(.cloudy, at: 11).fullText.contains("şu an"))
    }

    func testOfficialWarningComesRightAfterGreetingAndIsSerious() {
        let now = TestClock.date(hour: 8)
        let w = OfficialWarning(id: "1", level: .red, hazard: "Fırtına", description: "", provinces: ["İstanbul"],
                                validFrom: now.addingTimeInterval(-60), validUntil: now.addingTimeInterval(3600),
                                sourceURL: URL(string: "https://www.mgm.gov.tr")!)
        let b = briefing(.sunny, at: 8, warnings: [w])
        XCTAssertEqual(b.sentences[0], "Günaydın.")
        XCTAssertTrue(b.sentences[1].contains("kırmızı seviyede"))
        XCTAssertFalse(b.fullText.contains("güzel bir gün"))
        XCTAssertEqual(b.restingMood, .warning)
    }

    func testClothingIncludedWhenNoteworthy() {
        XCTAssertTrue(briefing(.snowy, at: 8).fullText.contains("mont"))
    }

    // MARK: Notification

    func testNotificationScheduledForNextBriefingTime() throws {
        var s = MorningBriefingSettings()
        s.sendsNotification = true
        let evening = TestClock.date(hour: 21)
        let snap = MockWeatherData.snapshot(.rainyAfternoon, now: evening)
        let n = try XCTUnwrap(engine.notification(snapshot: snap, settings: s, now: evening))
        XCTAssertEqual(n.fireDate, TestClock.date(hour: 7, minute: 30, day: 15))
        XCTAssertEqual(n.id, "morningBriefing-2026-11-15")
        XCTAssertTrue(n.body.contains("Kaynak:"))
        XCTAssertTrue(n.body.contains("Yağış ihtimali"))
    }

    func testNoNotificationWhenOffOrForecastTooOld() {
        var s = MorningBriefingSettings()
        let evening = TestClock.date(hour: 21)
        let snap = MockWeatherData.snapshot(.sunny, now: evening)
        XCTAssertNil(engine.notification(snapshot: snap, settings: s, now: evening), "Text notification is opt-in")
        s.sendsNotification = true
        var old = snap
        old.retrievedAt = TestClock.date(hour: 9)          // ~22.5 h before 07:30 tomorrow
        XCTAssertNil(engine.notification(snapshot: old, settings: s, now: evening))
    }
}
