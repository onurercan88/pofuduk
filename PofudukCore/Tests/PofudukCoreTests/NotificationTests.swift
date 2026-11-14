import XCTest
@testable import PofudukCore

final class RainNotificationEngineTests: XCTestCase {
    let engine = RainNotificationEngine()
    let now = TestClock.date(hour: 13, minute: 30)
    var prefs: NotificationPreferences = {
        var p = NotificationPreferences()
        p.isEnabled = true
        return p
    }()

    private func rainAt(_ hour: Int, mm: Double = 1.2, prob: Int = 80, condition: WeatherCondition = .rain,
                        retrievedAt: Date? = nil) -> WeatherSnapshot {
        let hourly = TestClock.hours { i, t in
            HourlyForecast(time: t, temperature: 18, condition: i == hour ? condition : .cloudy,
                           precipitationProbability: i == hour ? prob : 5, precipitationMm: i == hour ? mm : 0, windSpeedKmh: 10)
        }
        return TestClock.snapshot(hourly: hourly, now: now, retrievedAt: retrievedAt)
    }

    func testRainExpectedWithin30Minutes() throws {
        let plan = engine.plan(snapshot: rainAt(14), preferences: prefs, log: InMemoryNotificationLog(), now: now)
        let n = try XCTUnwrap(plan.first)
        XCTAssertEqual(n.category, .rainSoon)
        XCTAssertEqual(n.fireDate, now.addingTimeInterval(60), "Lead time already passed → notify right away")
        XCTAssertTrue(n.body.hasPrefix("Yaklaşık 30 dakika içinde İstanbul'da yağmur bekleniyor"), n.body)
        XCTAssertTrue(n.body.contains("Kaynak: Open-Meteo.com tahmini"), "Source must be stated")
    }

    func testLeadTimeIsRespected() throws {
        let plan = engine.plan(snapshot: rainAt(17), preferences: prefs, log: InMemoryNotificationLog(), now: now)
        XCTAssertEqual(plan.first?.fireDate, TestClock.date(hour: 16, minute: 30))
    }

    func testBelowUserThresholdNoNotification() {
        var p = prefs
        p.rainProbabilityThreshold = 90
        XCTAssertTrue(engine.plan(snapshot: rainAt(15), preferences: p, log: InMemoryNotificationLog(), now: now).isEmpty)
    }

    func testDuplicateNotificationsAreSuppressed() {
        let log = InMemoryNotificationLog()
        let first = engine.plan(snapshot: rainAt(14), preferences: prefs, log: log, now: now)
        first.forEach { log.record($0.id, fireDate: $0.fireDate) }
        let later = now.addingTimeInterval(5 * 60)   // already delivered
        XCTAssertTrue(engine.plan(snapshot: rainAt(14, retrievedAt: later), preferences: prefs, log: log, now: later).isEmpty)
    }

    func testRescheduleBeforeDeliveryIsAllowed() {
        let log = InMemoryNotificationLog()
        let first = engine.plan(snapshot: rainAt(17), preferences: prefs, log: log, now: now)
        first.forEach { log.record($0.id, fireDate: $0.fireDate) }
        XCTAssertEqual(engine.plan(snapshot: rainAt(17), preferences: prefs, log: log, now: now).count, 1,
                       "Not yet fired → may be replaced with the latest forecast")
    }

    func testQuietHours() {
        let night = TestClock.date(hour: 22, minute: 30)
        let snap = TestClock.snapshot(hourly: TestClock.hours { i, t in
            HourlyForecast(time: t, temperature: 12, condition: i == 23 ? .rain : .cloudy,
                           precipitationProbability: i == 23 ? 90 : 0, precipitationMm: i == 23 ? 2 : 0)
        }, now: night)
        XCTAssertTrue(engine.plan(snapshot: snap, preferences: prefs, log: InMemoryNotificationLog(), now: night).isEmpty)
        var p = prefs
        p.quietHours.enabled = false
        XCTAssertEqual(engine.plan(snapshot: snap, preferences: p, log: InMemoryNotificationLog(), now: night).count, 1)
    }

    func testStaleForecastNeverNotifies() {
        let old = now.addingTimeInterval(-2 * 3600)
        let snap = rainAt(14, retrievedAt: old)
        XCTAssertTrue(snap.isStale(at: now))
        XCTAssertTrue(engine.plan(snapshot: snap, preferences: prefs, log: InMemoryNotificationLog(), now: now).isEmpty)
    }

    func testDisabledOrCategoryOffMeansNothing() {
        var off = prefs
        off.isEnabled = false
        XCTAssertTrue(engine.plan(snapshot: rainAt(14), preferences: off, log: InMemoryNotificationLog(), now: now).isEmpty)
        var noRain = prefs
        noRain.enabledCategories.remove(.rainSoon)
        XCTAssertTrue(engine.plan(snapshot: rainAt(14), preferences: noRain, log: InMemoryNotificationLog(), now: now).isEmpty)
    }

    func testHeavyAndThunderCategories() {
        XCTAssertEqual(engine.plan(snapshot: rainAt(15, mm: 10), preferences: prefs, log: InMemoryNotificationLog(), now: now).first?.category, .heavyRain)
        XCTAssertEqual(engine.plan(snapshot: rainAt(15, condition: .thunderstorm), preferences: prefs, log: InMemoryNotificationLog(), now: now).first?.category, .severeWeather)
    }

    func testSevereOfficialWarningHasPriorityAndBreaksQuietHours() throws {
        let night = TestClock.date(hour: 23)
        let snap = TestClock.snapshot(hourly: TestClock.hours { i, t in
            HourlyForecast(time: t, temperature: 12, condition: .rain, precipitationProbability: 90, precipitationMm: 2)
        }, now: night)
        let w = OfficialWarning(id: "w1", level: .orange, hazard: "Kuvvetli yağış", description: "Sel riskine dikkat.",
                                provinces: ["İstanbul"], validFrom: night.addingTimeInterval(-60), validUntil: night.addingTimeInterval(7200),
                                sourceURL: URL(string: "https://www.mgm.gov.tr")!)
        var p = prefs
        p.quietHours.enabled = true
        let plan = engine.plan(snapshot: snap, warnings: [w], preferences: p, log: InMemoryNotificationLog(), now: night)
        let first = try XCTUnwrap(plan.first)
        XCTAssertEqual(first.category, .mgmWarning)
        XCTAssertTrue(first.isTimeSensitive)
        XCTAssertTrue(first.body.contains("Kaynak: MGM (resmi uyarı)"))
        XCTAssertFalse(plan.contains { $0.category == .rainSoon }, "Forecast notifications respect quiet hours")
    }

    func testForecastBeyondHorizonIsNotScheduled() {
        // Rain 8 h after retrieval: outside the 6 h horizon → wait for a fresher forecast.
        let early = TestClock.date(hour: 6)
        let snap = TestClock.snapshot(hourly: TestClock.hours { i, t in
            HourlyForecast(time: t, temperature: 15, condition: i == 14 ? .rain : .clear,
                           precipitationProbability: i == 14 ? 90 : 0, precipitationMm: i == 14 ? 2 : 0)
        }, now: early, expiresIn: 12 * 3600)
        XCTAssertTrue(engine.plan(snapshot: snap, preferences: prefs, log: InMemoryNotificationLog(), now: early).isEmpty)
    }

    func testStrongWindAndTemperatureChange() {
        let snap = TestClock.snapshot(hourly: TestClock.hours { i, t in
            HourlyForecast(time: t, temperature: 15, condition: .cloudy, precipitationProbability: 0, precipitationMm: 0,
                           windSpeedKmh: i == 16 ? 50 : 10, windGustKmh: i == 16 ? 75 : 15)
        }, now: now, daily: [
            DailyForecast(date: TestClock.date(hour: 0), minTemperature: 10, maxTemperature: 22, condition: .cloudy),
            DailyForecast(date: TestClock.date(hour: 0, day: 15), minTemperature: 3, maxTemperature: 11, condition: .cloudy)
        ])
        var p = prefs
        p.enabledCategories.insert(.temperatureChange)
        let plan = engine.plan(snapshot: snap, preferences: p, log: InMemoryNotificationLog(), now: now)
        XCTAssertTrue(plan.contains { $0.category == .strongWind && $0.body.contains("75 kilometreye") })
        let temp = plan.first { $0.category == .temperatureChange }
        XCTAssertEqual(temp?.fireDate, TestClock.date(hour: 19))
        XCTAssertTrue(temp?.body.contains("11 derece daha serin") == true, temp?.body ?? "")
    }

    func testQuietHoursWrapMidnight() {
        let q = QuietHours(enabled: true, startMinute: 22 * 60, endMinute: 7 * 60)
        XCTAssertTrue(q.contains(TestClock.date(hour: 23), timeZone: TestClock.istanbul))
        XCTAssertTrue(q.contains(TestClock.date(hour: 6, minute: 59), timeZone: TestClock.istanbul))
        XCTAssertFalse(q.contains(TestClock.date(hour: 7), timeZone: TestClock.istanbul))
    }
}
